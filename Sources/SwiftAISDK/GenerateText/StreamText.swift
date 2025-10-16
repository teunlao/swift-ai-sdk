import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Streaming text generation entry point and result container.

 Port of `@ai-sdk/ai/src/generate-text/stream-text.ts`.

 Mirrors the upstream TypeScript implementation, including multi-step
 execution, tool streaming, telemetry, partial output parsing, and UI
 message stream helpers.
 */

// MARK: - Stream Transform & Callback Types

public struct StreamTextTransformOptions: Sendable {
    public let tools: ToolSet?
    public let stopStream: @Sendable () -> Void

    public init(tools: ToolSet?, stopStream: @escaping @Sendable () -> Void) {
        self.tools = tools
        self.stopStream = stopStream
    }
}

public typealias StreamTextTransform = @Sendable (
    _ stream: AsyncIterableStream<TextStreamPart>,
    _ options: StreamTextTransformOptions
) -> AsyncIterableStream<TextStreamPart>

public struct StreamTextOnErrorEvent: Sendable {
    public let error: Error
}

public struct StreamTextOnChunkEvent: Sendable {
    public let chunk: TextStreamPart
}

public struct StreamTextOnFinishEvent: Sendable {
    public let finishReason: FinishReason
    public let totalUsage: LanguageModelUsage
    public let finalStep: StepResult
    public let steps: [StepResult]
}

public struct StreamTextOnAbortEvent: Sendable {
    public let steps: [StepResult]
}

public typealias StreamTextOnErrorCallback = @Sendable (_ event: StreamTextOnErrorEvent) async -> Void
public typealias StreamTextOnChunkCallback = @Sendable (_ event: StreamTextOnChunkEvent) async -> Void
public typealias StreamTextOnFinishCallback = @Sendable (_ event: StreamTextOnFinishEvent) async -> Void
public typealias StreamTextOnAbortCallback = @Sendable (_ event: StreamTextOnAbortEvent) async -> Void
public typealias StreamTextOnStepFinishCallback = @Sendable (_ stepResult: StepResult) async -> Void

// MARK: - Internal Options

public struct StreamTextInternalOptions: Sendable {
    public var now: @Sendable () -> Double
    public var generateId: IDGenerator
    public var currentDate: @Sendable () -> Date

    public init(
        now: @escaping @Sendable () -> Double = SwiftAISDK.now,
        generateId: IDGenerator? = nil,
        currentDate: @escaping @Sendable () -> Date = Date.init
    ) {
        self.now = now
        if let generateId {
            self.generateId = generateId
        } else {
            self.generateId = try! createIDGenerator(prefix: "aitxt", size: 24)
        }
        self.currentDate = currentDate
    }
}

// MARK: - Enriched Stream Part

struct EnrichedStreamPart<PartialOutput: Sendable>: Sendable {
    let part: TextStreamPart
    let partialOutput: PartialOutput?
}

private struct ActiveTextContent: Sendable {
    var index: Int
    var text: String
    var providerMetadata: ProviderMetadata?
}

private struct ActiveReasoningContent: Sendable {
    var index: Int
    var text: String
    var providerMetadata: ProviderMetadata?
}

private final class StreamPipelineState: @unchecked Sendable {
    var recordedContent: [ContentPart] = []
    var recordedResponseMessages: [ResponseMessage] = []
    var recordedFinishReason: FinishReason?
    var recordedTotalUsage: LanguageModelUsage?
    var recordedRequest: LanguageModelRequestMetadata = LanguageModelRequestMetadata()
    var recordedWarnings: [CallWarning] = []
    var recordedSteps: [StepResult] = []
    var activeTextContent: [String: ActiveTextContent] = [:]
    var activeReasoningContent: [String: ActiveReasoningContent] = [:]
    var toolNamesByCallId: [String: String] = [:]
    var rootSpan: (any Span)?
    var stepFinish: DelayedPromise<Void>?

    func resetForNewStep(request: LanguageModelRequestMetadata, warnings: [CallWarning]) {
        recordedContent = []
        activeTextContent = [:]
        activeReasoningContent = [:]
        recordedRequest = request
        recordedWarnings = warnings
    }
}

private struct StreamTextConsistencyError: LocalizedError, CustomStringConvertible, Sendable {
    let message: String

    var errorDescription: String? { message }
    var description: String { message }
}

private func jsonString(from value: JSONValue) -> String? {
    guard let data = try? JSONEncoder().encode(value) else {
        return nil
    }
    return String(data: data, encoding: .utf8)
}

private func convertModelMessagesToResponseMessages(
    _ messages: [ModelMessage]
) -> [ResponseMessage] {
    messages.compactMap { message in
        switch message {
        case .assistant(let assistant):
            return .assistant(assistant)
        case .tool(let tool):
            return .tool(tool)
        case .system, .user:
            return nil
        }
    }
}

private extension TypedToolResult {
    var isPreliminary: Bool {
        switch self {
        case .static(let result):
            return result.preliminary == true
        case .dynamic(let result):
            return result.preliminary == true
        }
    }

    var providerMetadata: ProviderMetadata? {
        switch self {
        case .static:
            return nil
        case .dynamic:
            return nil
        }
    }
}


// MARK: - Helpers

private func createOutputTransformStream<OutputValue: Sendable, PartialOutput: Sendable>(
    stream: AsyncIterableStream<TextStreamPart>,
    output: Output.Specification<OutputValue, PartialOutput>?
) -> AsyncIterableStream<EnrichedStreamPart<PartialOutput>> {
    guard let output else {
        return stream.map { part in
            EnrichedStreamPart(part: part, partialOutput: nil)
        }
    }

    return createAsyncIterableStream(
        source: AsyncThrowingStream<EnrichedStreamPart<PartialOutput>, Error> { continuation in
            Task {
                var firstTextChunkID: String?
                var accumulatedText = ""
                var currentChunkText = ""
                var lastPublishedRepresentation: String?

                func serializePartial(_ partial: PartialOutput) -> String? {
                    if let jsonValue = partial as? JSONValue {
                        return jsonString(from: jsonValue)
                    }

                    if let convertible = partial as? CustomStringConvertible {
                        return convertible.description
                    }

                    return nil
                }

                func publishCurrentChunk(partial: PartialOutput?) {
                    guard let textID = firstTextChunkID, !currentChunkText.isEmpty else {
                        return
                    }

                    continuation.yield(
                        EnrichedStreamPart(
                            part: .textDelta(id: textID, text: currentChunkText, providerMetadata: nil),
                            partialOutput: partial
                        )
                    )

                    currentChunkText = ""
                }

                do {
                    for try await part in stream {
                        switch part {
                        case let .textStart(id, _):
                            if firstTextChunkID == nil {
                                firstTextChunkID = id
                            } else if id != firstTextChunkID {
                                continuation.yield(.init(part: part, partialOutput: nil))
                                continue
                            }

                            continuation.yield(.init(part: part, partialOutput: nil))

                        case let .textDelta(id, text, _):
                            guard firstTextChunkID == nil || firstTextChunkID == id else {
                                continuation.yield(.init(part: part, partialOutput: nil))
                                continue
                            }

                            if firstTextChunkID == nil {
                                firstTextChunkID = id
                            }

                            accumulatedText.append(text)
                            currentChunkText.append(text)

                            if let partial = try await output.parsePartial(text: accumulatedText) {
                                let representation = serializePartial(partial)
                                if representation != lastPublishedRepresentation {
                                    publishCurrentChunk(partial: partial)
                                    lastPublishedRepresentation = representation
                                }
                            }

                        case let .textEnd(id, _):
                            guard firstTextChunkID == nil || firstTextChunkID == id else {
                                continuation.yield(.init(part: part, partialOutput: nil))
                                continue
                            }

                            if !currentChunkText.isEmpty {
                                publishCurrentChunk(partial: nil)
                            }

                            continuation.yield(.init(part: part, partialOutput: nil))

                        default:
                            continuation.yield(.init(part: part, partialOutput: nil))
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    )
}

// MARK: - Public API

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func streamText<OutputValue: Sendable, PartialOutputValue: Sendable>(
    model modelArg: LanguageModel,
    tools: ToolSet? = nil,
    toolChoice: ToolChoice? = nil,
    system: String? = nil,
    prompt: String? = nil,
    messages: [ModelMessage]? = nil,
    stopWhen: [StopCondition] = [stepCountIs(1)],
    experimentalOutput output: Output.Specification<OutputValue, PartialOutputValue>? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    providerOptions: ProviderOptions? = nil,
    experimentalActiveTools: [String]? = nil,
    activeTools: [String]? = nil,
    experimentalPrepareStep: PrepareStepFunction? = nil,
    prepareStep: PrepareStepFunction? = nil,
    experimentalRepairToolCall repairToolCall: ToolCallRepairFunction? = nil,
    experimentalTransform transforms: [StreamTextTransform] = [],
    experimentalDownload download: DownloadFunction? = nil,
    includeRawChunks: Bool = false,
    onChunk: StreamTextOnChunkCallback? = nil,
    onError rawOnError: StreamTextOnErrorCallback? = nil,
    onFinish: StreamTextOnFinishCallback? = nil,
    onAbort: StreamTextOnAbortCallback? = nil,
    onStepFinish: StreamTextOnStepFinishCallback? = nil,
    experimentalContext: JSONValue? = nil,
    _internal: StreamTextInternalOptions = StreamTextInternalOptions(),
    settings: CallSettings = CallSettings()
) throws -> DefaultStreamTextResult<OutputValue, PartialOutputValue> {
    let resolvedModel = try resolveLanguageModel(modelArg)
    let effectiveActiveTools = activeTools ?? experimentalActiveTools
    let effectivePrepareStep = prepareStep ?? experimentalPrepareStep

    let defaultOnError: StreamTextOnErrorCallback = { event in
        fputs("streamText error: \(event.error)\n", stderr)
    }
    let onError = rawOnError ?? defaultOnError

    guard (prompt == nil) || (messages == nil) else {
        throw InvalidPromptError(
            prompt: "Prompt(system: \(system ?? "nil"), prompt: \(prompt ?? "nil"), messages: provided)",
            message: "Provide either `prompt` or `messages`, not both."
        )
    }

    let promptInput: Prompt
    if let promptText = prompt {
        promptInput = Prompt.text(promptText, system: system)
    } else if let messageList = messages {
        promptInput = Prompt.messages(messageList, system: system)
    } else {
        throw InvalidPromptError(
            prompt: "Prompt(system: \(system ?? "nil"))",
            message: "Either `prompt` or `messages` must be provided."
        )
    }

    let stopConditions = stopWhen.isEmpty ? [stepCountIs(1)] : stopWhen

    return try DefaultStreamTextResult(
        baseModel: modelArg,
        model: resolvedModel,
        telemetry: telemetry,
        settings: settings,
        prompt: promptInput,
        tools: tools,
        toolChoice: toolChoice,
        stopConditions: stopConditions,
        transforms: transforms,
        activeTools: effectiveActiveTools,
        prepareStep: effectivePrepareStep,
        repairToolCall: repairToolCall,
        output: output,
        providerOptions: providerOptions,
        download: download,
        includeRawChunks: includeRawChunks,
        onChunk: onChunk,
        onError: onError,
        onFinish: onFinish,
        onAbort: onAbort,
        onStepFinish: onStepFinish,
        experimentalContext: experimentalContext,
        internalOptions: _internal
    )
}

// MARK: - DefaultStreamTextResult (partial implementation)

public final class DefaultStreamTextResult<OutputValue: Sendable, PartialOutputValue: Sendable>: StreamTextResult {
    public typealias PartialOutput = PartialOutputValue

    private let totalUsagePromise = DelayedPromise<LanguageModelUsage>()
    private let finishReasonPromise = DelayedPromise<FinishReason>()
    private let stepsPromise = DelayedPromise<[StepResult]>()

    private let stitchable: StitchableStream<TextStreamPart>
    private let addStream: @Sendable (AsyncIterableStream<TextStreamPart>) async throws -> Void
    private let closeStream: @Sendable () -> Void
    private let terminateStream: @Sendable () -> Void
    private lazy var baseStream: AsyncIterableStream<EnrichedStreamPart<PartialOutputValue>> = makeBaseStream()

    private let output: Output.Specification<OutputValue, PartialOutputValue>?
    private let includeRawChunks: Bool
    private let tools: ToolSet?
    private let onChunk: StreamTextOnChunkCallback?
    private let onError: StreamTextOnErrorCallback
    private let onFinish: StreamTextOnFinishCallback?
    private let onAbort: StreamTextOnAbortCallback?
    private let onStepFinish: StreamTextOnStepFinishCallback?

    private let internalOptions: StreamTextInternalOptions
    private let baseModel: LanguageModel
    private let model: any LanguageModelV3
    private let telemetry: TelemetrySettings?
    private let settings: CallSettings
    private let prompt: Prompt
    private let toolChoice: ToolChoice?
    private let stopConditions: [StopCondition]
    private let activeTools: [String]?
    private let prepareStep: PrepareStepFunction?
    private let repairToolCall: ToolCallRepairFunction?
    private let providerOptions: ProviderOptions?
    private let download: DownloadFunction?
    private let experimentalContext: JSONValue?
    private let transforms: [StreamTextTransform]
    private let state = StreamPipelineState()

    init(
        baseModel: LanguageModel,
        model: any LanguageModelV3,
        telemetry: TelemetrySettings?,
        settings: CallSettings,
        prompt: Prompt,
        tools: ToolSet?,
        toolChoice: ToolChoice?,
        stopConditions: [StopCondition],
        transforms: [StreamTextTransform],
        activeTools: [String]?,
        prepareStep: PrepareStepFunction?,
        repairToolCall: ToolCallRepairFunction?,
        output: Output.Specification<OutputValue, PartialOutputValue>?,
        providerOptions: ProviderOptions?,
        download: DownloadFunction?,
        includeRawChunks: Bool,
        onChunk: StreamTextOnChunkCallback?,
        onError: @escaping StreamTextOnErrorCallback,
        onFinish: StreamTextOnFinishCallback?,
        onAbort: StreamTextOnAbortCallback?,
        onStepFinish: StreamTextOnStepFinishCallback?,
        experimentalContext: JSONValue?,
        internalOptions: StreamTextInternalOptions
    ) throws {
        self.baseModel = baseModel
        self.output = output
        self.includeRawChunks = includeRawChunks
        self.tools = tools
        self.onChunk = onChunk
        self.onError = onError
        self.onFinish = onFinish
        self.onAbort = onAbort
        self.onStepFinish = onStepFinish
        self.internalOptions = internalOptions
        self.model = model
        self.telemetry = telemetry
        self.settings = settings
        self.prompt = prompt
        self.toolChoice = toolChoice
        self.stopConditions = stopConditions
        self.activeTools = activeTools
        self.prepareStep = prepareStep
        self.repairToolCall = repairToolCall
        self.providerOptions = providerOptions
        self.download = download
        self.experimentalContext = experimentalContext
        self.transforms = transforms

        let stitchable: StitchableStream<TextStreamPart> = createStitchableStream()
        self.stitchable = stitchable
        self.addStream = stitchable.addStream
        self.closeStream = stitchable.close
        self.terminateStream = stitchable.terminate

        Task { [weak self] in
            guard let self else { return }
            await self.runStreamPipeline()
        }
    }


    // MARK: - StreamTextResult

    public var content: [ContentPart] {
        get async throws {
            let step = try await finalStep
            return step.content
        }
    }

    public var text: String {
        get async throws {
            let step = try await finalStep
            return step.text
        }
    }

    public var reasoning: [ReasoningOutput] {
        get async throws {
            let step = try await finalStep
            return step.reasoning
        }
    }

    public var reasoningText: String? {
        get async throws {
            let step = try await finalStep
            return step.reasoningText
        }
    }

    public var files: [GeneratedFile] {
        get async throws {
            let step = try await finalStep
            return step.files
        }
    }

    public var sources: [Source] {
        get async throws {
            let step = try await finalStep
            return step.sources
        }
    }

    public var toolCalls: [TypedToolCall] {
        get async throws {
            let step = try await finalStep
            return step.toolCalls
        }
    }

    public var staticToolCalls: [StaticToolCall] {
        get async throws {
            let step = try await finalStep
            return step.staticToolCalls
        }
    }

    public var dynamicToolCalls: [DynamicToolCall] {
        get async throws {
            let step = try await finalStep
            return step.dynamicToolCalls
        }
    }

    public var toolResults: [TypedToolResult] {
        get async throws {
            let step = try await finalStep
            return step.toolResults
        }
    }

    public var staticToolResults: [StaticToolResult] {
        get async throws {
            let step = try await finalStep
            return step.staticToolResults
        }
    }

    public var dynamicToolResults: [DynamicToolResult] {
        get async throws {
            let step = try await finalStep
            return step.dynamicToolResults
        }
    }

    public var finishReason: FinishReason {
        get async throws {
            try await finishReasonPromise.task.value
        }
    }

    public var usage: LanguageModelUsage {
        get async throws {
            let step = try await finalStep
            return step.usage
        }
    }

    public var totalUsage: LanguageModelUsage {
        get async throws {
            try await totalUsagePromise.task.value
        }
    }

    public var warnings: [CallWarning]? {
        get async throws {
            let step = try await finalStep
            return step.warnings
        }
    }

    public var steps: [StepResult] {
        get async throws {
            try await stepsPromise.task.value
        }
    }

    public var request: LanguageModelRequestMetadata {
        get async throws {
            let step = try await finalStep
            return step.request
        }
    }

    public var response: StepResultResponse {
        get async throws {
            let step = try await finalStep
            return step.response
        }
    }

    public var providerMetadata: ProviderMetadata? {
        get async throws {
            let step = try await finalStep
            return step.providerMetadata
        }
    }

    public var textStream: AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await part in baseStream.asAsyncThrowingStream() {
                        if case let .textDelta(_, text, _) = part.part {
                            continuation.yield(text)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public var fullStream: AsyncThrowingStream<TextStreamPart, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await part in baseStream.asAsyncThrowingStream() {
                        continuation.yield(part.part)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public var experimentalPartialOutputStream: AsyncThrowingStream<PartialOutputValue, Error> {
        guard output != nil else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: NoOutputSpecifiedError())
            }
        }

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await part in baseStream.asAsyncThrowingStream() {
                        if let partial = part.partialOutput {
                            continuation.yield(partial)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func consumeStream(options: ConsumeStreamOptions?) async {
        await SwiftAISDK.consumeStream(stream: fullStream, onError: options?.onError)
    }

    public func toUIMessageStream<Message: UIMessageConvertible>(
        options: UIMessageStreamOptions<Message>?
    ) -> AsyncThrowingStream<UIMessageStreamChunk<Message>, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    public func pipeUIMessageStreamToResponse<Message: UIMessageConvertible>(
        _ response: any StreamTextResponseWriter,
        options: StreamTextUIResponseOptions<Message>?
    ) {
        let emptyStream = AsyncThrowingStream<AnyUIMessageChunk, Error> { continuation in
            continuation.finish()
        }
        SwiftAISDK.pipeUIMessageStreamToResponse(
            response: response,
            stream: emptyStream,
            options: options
        )
    }

    public func pipeTextStreamToResponse(
        _ response: any StreamTextResponseWriter,
        init initOptions: TextStreamResponseInit?
    ) {
        SwiftAISDK.pipeTextStreamToResponse(
            response: response,
            status: initOptions?.status,
            statusText: initOptions?.statusText,
            headers: initOptions?.headers,
            textStream: textStream
        )
    }

    public func toUIMessageStreamResponse<Message: UIMessageConvertible>(
        options: StreamTextUIResponseOptions<Message>?
    ) -> UIMessageStreamResponse<Message> {
        SwiftAISDK.createUIMessageStreamResponse(
            stream: AsyncThrowingStream<AnyUIMessageChunk, Error> { continuation in
                continuation.finish()
            },
            options: options
        )
    }

    public func toTextStreamResponse(
        init initOptions: TextStreamResponseInit?
    ) -> TextStreamResponse {
        SwiftAISDK.createTextStreamResponse(
            status: initOptions?.status,
            statusText: initOptions?.statusText,
            headers: initOptions?.headers,
            textStream: textStream
        )
    }

    // MARK: - Pipeline

    private func processStreamChunk(
        _ chunk: EnrichedStreamPart<PartialOutputValue>,
        continuation: AsyncThrowingStream<EnrichedStreamPart<PartialOutputValue>, Error>.Continuation
    ) async {
        continuation.yield(chunk)

        let part = chunk.part

        if shouldInvokeOnChunk(part: part), let onChunk {
            await onChunk(StreamTextOnChunkEvent(chunk: part))
        }

        switch part {
        case let .startStep(request, warnings):
            state.resetForNewStep(request: request, warnings: warnings)

        case let .toolInputStart(id, toolName, _, _, _):
            state.toolNamesByCallId[id] = toolName

        case let .toolInputDelta(id, _, _):
            if state.toolNamesByCallId[id] == nil {
                state.toolNamesByCallId[id] = ""
            }

        case let .toolInputEnd(id, _):
            state.toolNamesByCallId.removeValue(forKey: id)

        case let .textStart(id, metadata):
            let index = state.recordedContent.count
            state.activeTextContent[id] = ActiveTextContent(index: index, text: "", providerMetadata: metadata)
            state.recordedContent.append(.text(text: "", providerMetadata: metadata))

        case let .textDelta(id, delta, metadata):
            guard var active = state.activeTextContent[id] else {
                emitConsistencyError(
                    message: "text part \(id) not found",
                    continuation: continuation
                )
                return
            }

            active.text += delta
            if let metadata {
                active.providerMetadata = metadata
            }
            state.activeTextContent[id] = active
            state.recordedContent[active.index] = .text(text: active.text, providerMetadata: active.providerMetadata)

        case let .textEnd(id, metadata):
            guard var active = state.activeTextContent[id] else {
                emitConsistencyError(
                    message: "text part \(id) not found",
                    continuation: continuation
                )
                return
            }

            if let metadata {
                active.providerMetadata = metadata
            }
            state.activeTextContent.removeValue(forKey: id)
            state.recordedContent[active.index] = .text(text: active.text, providerMetadata: active.providerMetadata)

        case let .reasoningStart(id, metadata):
            let index = state.recordedContent.count
            let reasoning = ReasoningOutput(text: "", providerMetadata: metadata)
            state.activeReasoningContent[id] = ActiveReasoningContent(index: index, text: "", providerMetadata: metadata)
            state.recordedContent.append(.reasoning(reasoning))

        case let .reasoningDelta(id, delta, metadata):
            guard var active = state.activeReasoningContent[id] else {
                emitConsistencyError(
                    message: "reasoning part \(id) not found",
                    continuation: continuation
                )
                return
            }

            active.text += delta
            if let metadata {
                active.providerMetadata = metadata
            }
            state.activeReasoningContent[id] = active
            let reasoning = ReasoningOutput(text: active.text, providerMetadata: active.providerMetadata)
            state.recordedContent[active.index] = .reasoning(reasoning)

        case let .reasoningEnd(id, metadata):
            guard var active = state.activeReasoningContent[id] else {
                emitConsistencyError(
                    message: "reasoning part \(id) not found",
                    continuation: continuation
                )
                return
            }

            if let metadata {
                active.providerMetadata = metadata
            }
            state.activeReasoningContent.removeValue(forKey: id)
            let reasoning = ReasoningOutput(text: active.text, providerMetadata: active.providerMetadata)
            state.recordedContent[active.index] = .reasoning(reasoning)

        case let .file(file):
            state.recordedContent.append(.file(file: file, providerMetadata: nil))

        case let .source(source):
            state.recordedContent.append(.source(type: "source", source: source))

        case let .toolCall(toolCall):
            state.recordedContent.append(.toolCall(toolCall, providerMetadata: toolCall.providerMetadata))

        case let .toolResult(result):
            guard !result.isPreliminary else { break }
            state.recordedContent.append(.toolResult(result, providerMetadata: result.providerMetadata))

        case let .toolError(errorValue):
            state.recordedContent.append(.toolError(errorValue, providerMetadata: nil))

        case let .toolApprovalRequest(request):
            state.recordedContent.append(.toolApprovalRequest(request))

        case .toolOutputDenied:
            break

        case let .finishStep(response, usage, finishReason, providerMetadata):
            await completeStep(
                response: response,
                usage: usage,
                finishReason: finishReason,
                providerMetadata: providerMetadata,
                continuation: continuation
            )

        case let .finish(finishReason, totalUsage):
            state.recordedFinishReason = finishReason
            state.recordedTotalUsage = totalUsage

        case let .error(errorValue):
            let wrapped = wrapGatewayError(errorValue) ?? errorValue
            if let error = wrapped as? Error {
                await onError(StreamTextOnErrorEvent(error: error))
            }

        case .start,
             .abort,
             .raw:
            break

        default:
            break
        }
    }

    private func finishProcessedStream(
        continuation: AsyncThrowingStream<EnrichedStreamPart<PartialOutputValue>, Error>.Continuation
    ) async {
        if state.recordedSteps.isEmpty {
            let error = NoOutputGeneratedError(message: "No output generated. Check the stream for errors.")
            finishReasonPromise.reject(error)
            totalUsagePromise.reject(error)
            stepsPromise.reject(error)
            continuation.finish(throwing: error)
            return
        }

        let steps = state.recordedSteps
        let finalStep = steps[steps.count - 1]
        let finishReason = state.recordedFinishReason ?? finalStep.finishReason
        let totalUsage = state.recordedTotalUsage ?? finalStep.usage

        stepsPromise.resolve(steps)
        finishReasonPromise.resolve(finishReason)
        totalUsagePromise.resolve(totalUsage)

        if let onFinish {
            await onFinish(
                StreamTextOnFinishEvent(
                    finishReason: finishReason,
                    totalUsage: totalUsage,
                    finalStep: finalStep,
                    steps: steps
                )
            )
        }

        if let onStepFinish {
            await onStepFinish(finalStep)
        }

        continuation.finish()
    }

    private func makeBaseStream() -> AsyncIterableStream<EnrichedStreamPart<PartialOutputValue>> {
        let outputStream = createOutputTransformStream(
            stream: stitchable.stream,
            output: output
        )

        return createAsyncIterableStream(
            source: AsyncThrowingStream<EnrichedStreamPart<PartialOutputValue>, Error> { continuation in
                Task { [weak self] in
                    guard let self else {
                        continuation.finish()
                        return
                    }

                    do {
                        for try await chunk in outputStream {
                            await self.processStreamChunk(
                                chunk,
                                continuation: continuation
                            )
                        }

                        await self.finishProcessedStream(continuation: continuation)
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
        )
    }

    private func shouldInvokeOnChunk(part: TextStreamPart) -> Bool {
        switch part {
        case .textDelta,
             .reasoningDelta,
             .source,
             .toolCall,
             .toolInputStart,
             .toolInputDelta,
             .toolResult,
             .raw:
            return true
        default:
            return false
        }
    }

    private func emitConsistencyError(
        message: String,
        continuation: AsyncThrowingStream<EnrichedStreamPart<PartialOutputValue>, Error>.Continuation
    ) {
        let errorPart = StreamTextConsistencyError(message: message)
        continuation.yield(
            EnrichedStreamPart(
                part: .error(errorPart),
                partialOutput: nil
            )
        )
    }

    private func completeStep(
        response: LanguageModelResponseMetadata,
        usage: LanguageModelUsage,
        finishReason: FinishReason,
        providerMetadata: ProviderMetadata?,
        continuation: AsyncThrowingStream<EnrichedStreamPart<PartialOutputValue>, Error>.Continuation
    ) async {
        let contentSnapshot = state.recordedContent
        let stepModelMessages = toResponseMessages(
            content: contentSnapshot,
            tools: tools
        )

        let responseMessages = convertModelMessagesToResponseMessages(stepModelMessages)
        let mergedMessages = state.recordedResponseMessages + responseMessages

        let stepResult = DefaultStepResult(
            content: contentSnapshot,
            finishReason: finishReason,
            usage: usage,
            warnings: state.recordedWarnings,
            request: state.recordedRequest,
            response: StepResultResponse(
                from: response,
                messages: mergedMessages,
                body: nil
            ),
            providerMetadata: providerMetadata
        )

        let warnings = state.recordedWarnings.map { Warning.languageModel($0) }
        logWarnings(warnings)
        state.recordedSteps.append(stepResult)
        state.recordedResponseMessages.append(contentsOf: responseMessages)
        state.stepFinish?.resolve(())

        if let onStepFinish {
            await onStepFinish(stepResult)
        }
    }

    private func runStreamPipeline() async {
        do {
            let retries = try prepareRetries(
                maxRetries: settings.maxRetries,
                abortSignal: settings.abortSignal
            )

            let preparedCallSettings = try prepareCallSettings(
                maxOutputTokens: settings.maxOutputTokens,
                temperature: settings.temperature,
                topP: settings.topP,
                topK: settings.topK,
                presencePenalty: settings.presencePenalty,
                frequencyPenalty: settings.frequencyPenalty,
                stopSequences: settings.stopSequences,
                seed: settings.seed
            )

            let standardizedPrompt = try standardizePrompt(prompt)
            let supportedUrls = try await model.supportedUrls
            let promptForModel = try await convertToLanguageModelPrompt(
                prompt: standardizedPrompt,
                supportedUrls: supportedUrls,
                download: download
            )

            let responseFormat = try await output?.responseFormat()

            let callOptions = LanguageModelV3CallOptions(
                prompt: promptForModel,
                maxOutputTokens: preparedCallSettings.maxOutputTokens,
                temperature: preparedCallSettings.temperature,
                stopSequences: preparedCallSettings.stopSequences,
                topP: preparedCallSettings.topP,
                topK: preparedCallSettings.topK,
                presencePenalty: preparedCallSettings.presencePenalty,
                frequencyPenalty: preparedCallSettings.frequencyPenalty,
                responseFormat: responseFormat,
                seed: preparedCallSettings.seed,
                includeRawChunks: includeRawChunks,
                abortSignal: settings.abortSignal,
                headers: settings.headers,
                providerOptions: providerOptions
            )

            let result = try await retries.retry.call {
                try await self.model.doStream(options: callOptions)
            }

            let stream = buildTextStream(from: result)

            var transformed = stream
            for transform in transforms {
                transformed = transform(
                    transformed,
                    StreamTextTransformOptions(
                        tools: tools,
                        stopStream: { [weak self] in self?.terminateStream() }
                    )
                )
            }

            try await addStream(transformed)
            closeStream()
        } catch {
            await emitStreamError(error)
        }
    }

    private func buildTextStream(
        from result: LanguageModelV3StreamResult
    ) -> AsyncIterableStream<TextStreamPart> {
        createAsyncIterableStream(
            source: AsyncThrowingStream<TextStreamPart, Error> { continuation in
                Task { [weak self] in
                    guard let self else {
                        continuation.finish()
                        return
                    }

                    var collectedWarnings: [CallWarning] = []
                    var finishReason: FinishReason = .unknown
                    var totalUsage = LanguageModelUsage()
                    var providerMetadata: ProviderMetadata?

                    do {
                        for try await chunk in result.stream {
                            switch chunk {
                            case let .streamStart(warnings):
                                collectedWarnings = warnings
                            case let .finish(reason, usage, metadata):
                                finishReason = reason
                                totalUsage = usage
                                providerMetadata = metadata
                            default:
                                break
                            }

                            guard let part = self.mapStreamPart(chunk, includeRawChunks: self.includeRawChunks) else {
                                continue
                            }

                            continuation.yield(part)
                        }

                        continuation.finish()

                        await self.finalizeStream(
                            finishReason: finishReason,
                            totalUsage: totalUsage,
                            warnings: collectedWarnings,
                            providerMetadata: providerMetadata,
                            responseInfo: result.response
                        )
                    } catch {
                        continuation.finish(throwing: error)
                        await self.emitStreamError(error)
                    }
                }
            }
        )
    }

    private func finalizeStream(
        finishReason: FinishReason,
        totalUsage: LanguageModelUsage,
        warnings: [CallWarning],
        providerMetadata: ProviderMetadata?,
        responseInfo: LanguageModelV3StreamResponseInfo?
    ) async {
        let stepResult = DefaultStepResult(
            content: [],
            finishReason: finishReason,
            usage: totalUsage,
            warnings: warnings,
            request: LanguageModelRequestMetadata(),
            response: StepResultResponse(
                id: internalOptions.generateId(),
                timestamp: internalOptions.currentDate(),
                modelId: model.modelId,
                headers: responseInfo?.headers,
                messages: [],
                body: nil
            ),
            providerMetadata: providerMetadata
        )

        stepsPromise.resolve([stepResult])
        finishReasonPromise.resolve(finishReason)
        totalUsagePromise.resolve(totalUsage)

        if let onFinish {
            await onFinish(
                StreamTextOnFinishEvent(
                    finishReason: finishReason,
                    totalUsage: totalUsage,
                    finalStep: stepResult,
                    steps: [stepResult]
                )
            )
        }

        if let onStepFinish {
            await onStepFinish(stepResult)
        }
    }

    private func emitStreamError(_ error: Error) async {
        let errorStream = createAsyncIterableStream(
            source: AsyncThrowingStream<TextStreamPart, Error> { continuation in
                continuation.yield(.error(error))
                continuation.finish()
            }
        )

        do {
            try await addStream(errorStream)
        } catch {
            // ignore
        }

        terminateStream()
        finishReasonPromise.reject(error)
        totalUsagePromise.reject(error)
        stepsPromise.reject(error)

        await onError(StreamTextOnErrorEvent(error: error))
    }

    private func mapStreamPart(
        _ part: LanguageModelV3StreamPart,
        includeRawChunks: Bool
    ) -> TextStreamPart? {
        switch part {
        case let .textStart(id, metadata):
            return .textStart(id: id, providerMetadata: metadata)
        case let .textDelta(id, delta, metadata):
            return .textDelta(id: id, text: delta, providerMetadata: metadata)
        case let .textEnd(id, metadata):
            return .textEnd(id: id, providerMetadata: metadata)
        case let .reasoningStart(id, metadata):
            return .reasoningStart(id: id, providerMetadata: metadata)
        case let .reasoningDelta(id, delta, metadata):
            return .reasoningDelta(id: id, text: delta, providerMetadata: metadata)
        case let .reasoningEnd(id, metadata):
            return .reasoningEnd(id: id, providerMetadata: metadata)
        case let .streamStart(warnings):
            return .startStep(request: LanguageModelRequestMetadata(), warnings: warnings)
        case let .finish(reason, usage, _):
            return .finish(finishReason: reason, totalUsage: usage)
        case let .raw(rawValue) where includeRawChunks:
            return .raw(rawValue: rawValue)
        case .raw:
            return nil
        case let .error(errorValue):
            return .error(JSONValueError(value: errorValue))
        default:
            return nil
        }
    }

    private struct JSONValueError: Error, CustomStringConvertible {
        let value: JSONValue

        var description: String {
            "JSON error: \(value)"
        }
    }

    private var finalStep: StepResult {
        get async throws {
            let steps = try await stepsPromise.task.value
            guard let last = steps.last else {
                throw NoOutputGeneratedError(message: "No output generated. Check the stream for errors.")
            }
            return last
        }
    }
}

extension AsyncIterableStream {
    func map<T>(_ transform: @escaping @Sendable (Element) -> T) -> AsyncIterableStream<T> {
        createAsyncIterableStream(
            source: AsyncThrowingStream<T, Error> { continuation in
                Task {
                    do {
                        for try await value in self {
                            continuation.yield(transform(value))
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
        )
    }

    func asAsyncThrowingStream() -> AsyncThrowingStream<Element, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await value in self {
                        continuation.yield(value)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

extension DefaultStreamTextResult: @unchecked Sendable {}
