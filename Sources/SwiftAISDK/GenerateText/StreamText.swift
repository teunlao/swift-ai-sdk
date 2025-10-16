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

private struct ToolCallDescription {
    let toolCallId: String
    let toolName: String
    let input: JSONValue
    let providerExecuted: Bool?
    let providerMetadata: ProviderMetadata?
    let invalid: Bool
    let error: Any?
}

private extension TypedToolCall {
    func details() -> ToolCallDescription {
        switch self {
        case .static(let call):
            return ToolCallDescription(
                toolCallId: call.toolCallId,
                toolName: call.toolName,
                input: call.input,
                providerExecuted: call.providerExecuted,
                providerMetadata: call.providerMetadata,
                invalid: call.invalid ?? false,
                error: nil
            )
        case .dynamic(let call):
            return ToolCallDescription(
                toolCallId: call.toolCallId,
                toolName: call.toolName,
                input: call.input,
                providerExecuted: call.providerExecuted,
                providerMetadata: call.providerMetadata,
                invalid: call.invalid ?? false,
                error: call.error
            )
        }
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

private actor StreamTextToolNameStore {
    private var names: [String: String] = [:]

    func set(_ id: String, name: String?) {
        if let name {
            names[id] = name
        } else {
            names[id] = nil
        }
    }

    func toolName(for id: String) -> String? {
        names[id]
    }
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
    var currentToolCalls: [TypedToolCall] = []
    var currentToolOutputs: [ToolOutput] = []
    var lastClientToolCalls: [TypedToolCall] = []
    var lastClientToolOutputs: [ToolOutput] = []

    func resetForNewStep(request: LanguageModelRequestMetadata, warnings: [CallWarning]) {
        recordedContent = []
        activeTextContent = [:]
        activeReasoningContent = [:]
        recordedRequest = request
        recordedWarnings = warnings
        currentToolCalls = []
        currentToolOutputs = []
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
private func convertResponseMessagesToModelMessages(
    _ messages: [ResponseMessage]
) -> [ModelMessage] {
    messages.map { message in
        switch message {
        case .assistant(let assistant):
            return .assistant(assistant)
        case .tool(let tool):
            return .tool(tool)
        }
    }
}

private func makeRequestMetadata(
    from info: LanguageModelV3RequestInfo?
) -> LanguageModelRequestMetadata {
    guard let body = info?.body else {
        return LanguageModelRequestMetadata()
    }

    let json = jsonValue(fromAny: body)
    return LanguageModelRequestMetadata(body: json)
}

private func jsonValue(fromAny value: Any) -> JSONValue? {
    if let json = value as? JSONValue {
        return json
    }

    return try? jsonValue(from: value)
}

private func makeExecutionDeniedContent(_ approval: CollectedToolApproval) -> ContentPart {
    let reasonValue: JSONValue
    if let reason = approval.approvalResponse.reason {
        reasonValue = .string(reason)
    } else {
        reasonValue = .null
    }

    let payload = JSONValue.object([
        "type": .string("execution-denied"),
        "reason": reasonValue
    ])

    switch approval.toolCall {
    case .static(let call):
        let result = StaticToolResult(
            toolCallId: call.toolCallId,
            toolName: call.toolName,
            input: call.input,
            output: payload,
            providerExecuted: call.providerExecuted,
            preliminary: nil
        )
        return .toolResult(.static(result), providerMetadata: call.providerMetadata)
    case .dynamic(let call):
        let result = DynamicToolResult(
            toolCallId: call.toolCallId,
            toolName: call.toolName,
            input: call.input,
            output: payload,
            providerExecuted: call.providerExecuted,
            preliminary: nil
        )
        return .toolResult(.dynamic(result), providerMetadata: call.providerMetadata)
    }
}

private func toolOutputToContentPart(_ output: ToolOutput) -> ContentPart {
    switch output {
    case .result(let result):
        return .toolResult(result, providerMetadata: nil)
    case .error(let error):
        return .toolError(error, providerMetadata: nil)
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

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public final class DefaultStreamTextResult<OutputValue: Sendable, PartialOutputValue: Sendable>: StreamTextResult {
    public typealias PartialOutput = PartialOutputValue

    private let totalUsagePromise = DelayedPromise<LanguageModelUsage>()
    private let finishReasonPromise = DelayedPromise<FinishReason>()
    private let stepsPromise = DelayedPromise<[StepResult]>()

    private let stitchable: StitchableStream<TextStreamPart>
    private let addStream: @Sendable (AsyncIterableStream<TextStreamPart>) async throws -> Void
    private let closeStream: @Sendable () -> Void
    private let terminateStream: @Sendable () -> Void
    private var baseStream: AsyncIterableStream<EnrichedStreamPart<PartialOutputValue>>

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
    private let callHeaders: [String: String]
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
        let headersWithUserAgent = withUserAgentSuffix(settings.headers ?? [:], "ai/\(VERSION)")
        var normalizedSettings = settings
        normalizedSettings.headers = headersWithUserAgent

        self.tools = tools
        self.onChunk = onChunk
        self.onError = onError
        self.onFinish = onFinish
        self.onAbort = onAbort
        self.onStepFinish = onStepFinish
        self.internalOptions = internalOptions
        self.model = model
        self.telemetry = telemetry
        self.settings = normalizedSettings
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
        self.callHeaders = headersWithUserAgent

        let stitchable: StitchableStream<TextStreamPart> = createStitchableStream()
        self.stitchable = stitchable
        self.addStream = stitchable.addStream
        self.closeStream = stitchable.close
        self.terminateStream = stitchable.terminate
        self.baseStream = createAsyncIterableStream(
            source: AsyncThrowingStream { continuation in
                continuation.finish()
            }
        )
        self.baseStream = makeBaseStream()

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
        let stream = teeBaseStream()

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await part in stream {
                        if case let .textDelta(_, text, _) = part.part, !text.isEmpty {
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
        let stream = teeBaseStream()

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await part in stream {
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

        let stream = teeBaseStream()

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await part in stream {
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
        let streamOptions = options ?? UIMessageStreamOptions<Message>()
        let responseMessageId: String?
        if let generator = streamOptions.generateMessageId {
            responseMessageId = getResponseUIMessageId(
                originalMessages: streamOptions.originalMessages,
                responseMessageId: generator
            )
        } else {
            responseMessageId = nil
        }

        func mapErrorMessage(_ value: Any?) -> String {
            if let error = value as? Error {
                return streamOptions.onError?(error) ?? AISDKProvider.getErrorMessage(error)
            }
            let message = AISDKProvider.getErrorMessage(value)
            if let onError = streamOptions.onError {
                let synthetic = NSError(
                    domain: "ai.streamText",
                    code: 0,
                    userInfo: [NSLocalizedDescriptionKey: message]
                )
                return onError(synthetic)
            }
            return message
        }

        let baseStream = teeBaseStream()

        let toolNameStore = StreamTextToolNameStore()

        func resolvedDynamicFlag(for id: String) async -> Bool? {
            guard let toolName = await toolNameStore.toolName(for: id),
                  let tool = tools?[toolName] else {
                return nil
            }
            if tool.type == .some(.dynamic) {
                return true
            }
            return nil
        }

        let chunkStream = AsyncThrowingStream<AnyUIMessageChunk, Error> { continuation in
            Task {
                do {
                    for try await enriched in baseStream {
                        let part = enriched.part
                        let metadataValue = streamOptions.messageMetadata?(part)

                        switch part {
                        case let .textStart(id, metadata):
                            continuation.yield(.textStart(id: id, providerMetadata: metadata))

                        case let .textDelta(id, text, metadata):
                            continuation.yield(.textDelta(id: id, delta: text, providerMetadata: metadata))

                        case let .textEnd(id, metadata):
                            continuation.yield(.textEnd(id: id, providerMetadata: metadata))

                        case let .reasoningStart(id, metadata):
                            continuation.yield(.reasoningStart(id: id, providerMetadata: metadata))

                        case let .reasoningDelta(id, text, metadata):
                            if streamOptions.sendReasoning {
                                continuation.yield(.reasoningDelta(id: id, delta: text, providerMetadata: metadata))
                            }

                        case let .reasoningEnd(id, metadata):
                            continuation.yield(.reasoningEnd(id: id, providerMetadata: metadata))

                        case let .file(file):
                            continuation.yield(.file(
                                url: "data:\(file.mediaType);base64,\(file.base64)",
                                mediaType: file.mediaType,
                                providerMetadata: nil
                            ))

                        case let .source(source):
                            guard streamOptions.sendSources else { break }
                            switch source {
                            case let .url(id, url, title, providerMetadata):
                                continuation.yield(.sourceUrl(
                                    sourceId: id,
                                    url: url,
                                    title: title,
                                    providerMetadata: providerMetadata
                                ))
                            case let .document(id, mediaType, title, filename, providerMetadata):
                                continuation.yield(.sourceDocument(
                                    sourceId: id,
                                    mediaType: mediaType,
                                    title: title,
                                    filename: filename,
                                    providerMetadata: providerMetadata
                                ))
                            }

                        case let .toolInputStart(id, toolName, _, providerExecuted, dynamic):
                            await toolNameStore.set(id, name: toolName)
                            let resolvedDynamic: Bool?
                            if let dynamic {
                                resolvedDynamic = dynamic
                            } else {
                                resolvedDynamic = await resolvedDynamicFlag(for: id)
                            }
                            continuation.yield(.toolInputStart(
                                toolCallId: id,
                                toolName: toolName,
                                providerExecuted: providerExecuted,
                                dynamic: resolvedDynamic
                            ))

                        case let .toolInputDelta(id, delta, _):
                            continuation.yield(.toolInputDelta(toolCallId: id, inputTextDelta: delta))

                        case let .toolInputEnd(id, _):
                            await toolNameStore.set(id, name: nil)

                        case let .toolCall(toolCall):
                            let details = toolCall.details()
                            await toolNameStore.set(details.toolCallId, name: details.toolName)
                            let resolvedDynamic = await resolvedDynamicFlag(for: details.toolCallId)

                            if details.invalid {
                                let errorText = mapErrorMessage(details.error)

                                continuation.yield(.toolInputError(
                                    toolCallId: details.toolCallId,
                                    toolName: details.toolName,
                                    input: details.input,
                                    providerExecuted: details.providerExecuted,
                                    providerMetadata: details.providerMetadata,
                                    dynamic: resolvedDynamic,
                                    errorText: errorText
                                ))
                            } else {
                                continuation.yield(.toolInputAvailable(
                                    toolCallId: details.toolCallId,
                                    toolName: details.toolName,
                                    input: details.input,
                                    providerExecuted: details.providerExecuted,
                                    providerMetadata: details.providerMetadata,
                                    dynamic: resolvedDynamic
                                ))
                            }

                        case let .toolResult(result):
                            let resolvedDynamic = await resolvedDynamicFlag(for: result.toolCallId)
                            continuation.yield(.toolOutputAvailable(
                                toolCallId: result.toolCallId,
                                output: result.output,
                                providerExecuted: result.providerExecuted,
                                dynamic: resolvedDynamic,
                                preliminary: result.preliminary
                            ))

                        case let .toolError(error):
                            let resolvedDynamic = await resolvedDynamicFlag(for: error.toolCallId)
                            let errorText = mapErrorMessage(error.error)
                            continuation.yield(.toolOutputError(
                                toolCallId: error.toolCallId,
                                errorText: errorText,
                                providerExecuted: error.providerExecuted,
                                dynamic: resolvedDynamic
                            ))

                        case let .toolApprovalRequest(request):
                            continuation.yield(.toolApprovalRequest(approvalId: request.approvalId, toolCallId: request.toolCall.toolCallId))

                        case let .toolOutputDenied(denied):
                            continuation.yield(.toolOutputDenied(toolCallId: denied.toolCallId))

                        case .startStep:
                            continuation.yield(.startStep)

                        case .finishStep:
                            continuation.yield(.finishStep)

                        case .start:
                            if streamOptions.sendStart {
                                continuation.yield(.start(
                                    messageId: responseMessageId,
                                    messageMetadata: metadataValue
                                ))
                            }

                        case .finish:
                            if streamOptions.sendFinish {
                                continuation.yield(.finish(messageMetadata: metadataValue))
                            }

                        case .abort:
                            continuation.yield(.abort)

                        case let .error(error):
                            let errorText = mapErrorMessage(error)
                            continuation.yield(.error(errorText: errorText))

                        case .raw:
                            break
                        }

                        if let metadataValue = metadataValue {
                            switch part {
                            case .start where !streamOptions.sendStart:
                                continuation.yield(.messageMetadata(metadataValue))
                            case .finish where !streamOptions.sendFinish:
                                continuation.yield(.messageMetadata(metadataValue))
                            case .start, .finish:
                                break
                            default:
                                continuation.yield(.messageMetadata(metadataValue))
                            }
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }

        let handledStream = handleUIMessageStreamFinish(
            stream: chunkStream,
            messageId: responseMessageId,
            originalMessages: streamOptions.originalMessages ?? [],
            onFinish: streamOptions.onFinish,
            onError: { error in
                _ = streamOptions.onError?(error)
            }
        )

        return handledStream
    }

    public func pipeUIMessageStreamToResponse<Message: UIMessageConvertible>(
        _ response: any StreamTextResponseWriter,
        options: StreamTextUIResponseOptions<Message>?
    ) {
        let stream = toUIMessageStream(options: options?.streamOptions)
        SwiftAISDK.pipeUIMessageStreamToResponse(
            response: response,
            stream: stream,
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
        let stream = toUIMessageStream(options: options?.streamOptions)
        return SwiftAISDK.createUIMessageStreamResponse(
            stream: stream,
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
            state.currentToolCalls.append(toolCall)
            state.recordedContent.append(.toolCall(toolCall, providerMetadata: toolCall.providerMetadata))

        case let .toolResult(result):
            guard !result.isPreliminary else { break }
            state.currentToolOutputs.append(.result(result))
            state.recordedContent.append(.toolResult(result, providerMetadata: result.providerMetadata))

        case let .toolError(errorValue):
            state.currentToolOutputs.append(.error(errorValue))
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
            let wrapped = wrapGatewayError(errorValue)
            if let error = wrapped as? Error {
                await onError(StreamTextOnErrorEvent(error: error))
            } else {
                let message = AISDKProvider.getErrorMessage(wrapped ?? errorValue)
                let fallback = NSError(
                    domain: "ai.streamText",
                    code: 0,
                    userInfo: [NSLocalizedDescriptionKey: message]
                )
                await onError(StreamTextOnErrorEvent(error: fallback))
            }

        case .start,
             .abort,
             .raw:
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

        continuation.finish()
    }

    private func teeBaseStream() -> AsyncThrowingStream<EnrichedStreamPart<PartialOutputValue>, Error> {
        let (primary, secondary) = teeAsyncThrowingStream(baseStream.asAsyncThrowingStream())
        baseStream = createAsyncIterableStream(source: secondary)
        return primary
    }

    private func makeBaseStream() -> AsyncIterableStream<EnrichedStreamPart<PartialOutputValue>> {
        var transformedStream = stitchable.stream

        if !transforms.isEmpty {
            for transform in transforms {
                transformedStream = transform(
                    transformedStream,
                    StreamTextTransformOptions(
                        tools: tools,
                        stopStream: terminateStream
                    )
                )
            }
        }

        let outputStream = createOutputTransformStream(
            stream: transformedStream,
            output: output
        )

        return createAsyncIterableStream(
            source: AsyncThrowingStream<EnrichedStreamPart<PartialOutputValue>, Error> { continuation in
                _ = Task { [weak self] in
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

        let clientToolCalls = state.currentToolCalls.filter { $0.providerExecuted != true }
        let clientToolOutputs = state.currentToolOutputs.filter { $0.providerExecuted != true }
        state.lastClientToolCalls = clientToolCalls
        state.lastClientToolOutputs = clientToolOutputs
        state.currentToolCalls = []
        state.currentToolOutputs = []

        state.stepFinish?.resolve(())

        if let onStepFinish {
            await onStepFinish(stepResult)
        }
    }

    private func runStreamPipeline() async {
        do {
            let preparedRetries = try prepareRetries(
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
            let initialMessages = standardizedPrompt.messages

            let tracer = getTracer(
                isEnabled: telemetry?.isEnabled ?? false,
                tracer: telemetry?.tracer
            )

            var responseMessages: [ResponseMessage] = []
            var accumulatedUsage = LanguageModelUsage()

            var initialResponseMessages: [ResponseMessage] = []

            let approvals = collectToolApprovals(messages: initialMessages)

            if !approvals.approvedToolApprovals.isEmpty || !approvals.deniedToolApprovals.isEmpty {
                var approvalTask: Task<[ContentPart], Never>?

                let approvalStream = createAsyncIterableStream(
                    source: AsyncThrowingStream<TextStreamPart, Error>(bufferingPolicy: .unbounded) { continuation in
                        approvalTask = Task { [weak self] in
                            guard let self else {
                                continuation.finish()
                                return []
                            }

                            var content: [ContentPart] = []

                            for denied in approvals.deniedToolApprovals {
                                let deniedEvent = ToolOutputDenied(
                                    toolCallId: denied.toolCall.toolCallId,
                                    toolName: denied.toolCall.toolName,
                                    providerExecuted: denied.toolCall.providerExecuted
                                )
                                continuation.yield(.toolOutputDenied(deniedEvent))
                                content.append(makeExecutionDeniedContent(denied))
                            }

                            if !approvals.approvedToolApprovals.isEmpty {
                                await withTaskGroup(of: ToolOutput?.self) { group in
                                    for approved in approvals.approvedToolApprovals {
                                        group.addTask {
                                            await executeToolCall(
                                                toolCall: approved.toolCall,
                                                tools: self.tools,
                                                tracer: tracer,
                                                telemetry: self.telemetry,
                                                messages: initialMessages,
                                                abortSignal: self.settings.abortSignal,
                                                experimentalContext: self.experimentalContext,
                                                onPreliminaryToolResult: { result in
                                                    continuation.yield(.toolResult(result))
                                                }
                                            )
                                        }
                                    }

                                    for await output in group {
                                        guard let output else { continue }

                                        switch output {
                                        case .result(let result):
                                            continuation.yield(.toolResult(result))
                                        case .error(let error):
                                            continuation.yield(.toolError(error))
                                        }

                                        content.append(toolOutputToContentPart(output))
                                    }
                                }
                            }

                            continuation.finish()
                            return content
                        }
                    }
                )

                try await addStream(approvalStream)

                let approvalContent = await approvalTask?.value ?? []
                if !approvalContent.isEmpty {
                    let modelMessages = toResponseMessages(content: approvalContent, tools: tools)
                    let approvalResponses = convertModelMessagesToResponseMessages(modelMessages)
                    initialResponseMessages.append(contentsOf: approvalResponses)
                }
            }

            responseMessages = initialResponseMessages

            state.recordedResponseMessages = []

            try await executeStep(
                stepNumber: 0,
                standardizedPrompt: standardizedPrompt,
                initialMessages: initialMessages,
                responseMessages: &responseMessages,
                accumulatedUsage: &accumulatedUsage,
                retries: preparedRetries,
                preparedCallSettings: preparedCallSettings,
                tracer: tracer
            )
        } catch {
            await emitStreamError(error)
        }
    }

    private func executeStep(
        stepNumber: Int,
        standardizedPrompt: StandardizedPrompt,
        initialMessages: [ModelMessage],
        responseMessages: inout [ResponseMessage],
        accumulatedUsage: inout LanguageModelUsage,
        retries: PreparedRetries,
        preparedCallSettings: PreparedCallSettings,
        tracer: any Tracer
    ) async throws {
        let responseModelMessages = convertResponseMessagesToModelMessages(responseMessages)
        let stepInputMessages = initialMessages + responseModelMessages

        let prepareOptions = PrepareStepOptions(
            steps: state.recordedSteps,
            stepNumber: stepNumber,
            model: baseModel,
            messages: stepInputMessages
        )

        let prepareResult = try await prepareStep?(prepareOptions)

        let stepModelSource = prepareResult?.model ?? baseModel
        let stepModel = try resolveLanguageModel(stepModelSource)

        let stepSystem = prepareResult?.system ?? standardizedPrompt.system
        let stepMessages = prepareResult?.messages ?? stepInputMessages
        let stepToolChoice = prepareResult?.toolChoice ?? toolChoice
        let stepActiveTools = prepareResult?.activeTools ?? activeTools

        let stepPrompt = StandardizedPrompt(system: stepSystem, messages: stepMessages)
        let supportedUrls = try await stepModel.supportedUrls
        let promptForModel = try await convertToLanguageModelPrompt(
            prompt: stepPrompt,
            supportedUrls: supportedUrls,
            download: download
        )

        let toolPreparation = try await prepareToolsAndToolChoice(
            tools: tools,
            toolChoice: stepToolChoice,
            activeTools: stepActiveTools
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
            tools: toolPreparation.tools,
            toolChoice: toolPreparation.toolChoice,
            includeRawChunks: includeRawChunks,
            abortSignal: settings.abortSignal,
            headers: callHeaders,
            providerOptions: providerOptions
        )

        let streamResult = try await retries.retry.call {
            try await stepModel.doStream(options: callOptions)
        }

        let streamWithToolResults = runToolsTransformation(
            tools: tools,
            generatorStream: streamResult.stream,
            tracer: tracer,
            telemetry: telemetry,
            system: stepSystem,
            messages: stepMessages,
            abortSignal: settings.abortSignal,
            repairToolCall: repairToolCall,
            experimentalContext: experimentalContext,
            generateId: internalOptions.generateId
        )

        state.stepFinish = DelayedPromise<Void>()
        state.recordedResponseMessages = responseMessages
        state.currentToolCalls = []
        state.currentToolOutputs = []
        state.lastClientToolCalls = []
        state.lastClientToolOutputs = []

        let requestMetadata = makeRequestMetadata(from: streamResult.request)

        let stepStream = createAsyncIterableStream(
            source: AsyncThrowingStream<TextStreamPart, Error>(bufferingPolicy: .unbounded) { continuation in
                _ = Task { [weak self] in
                    guard let self else {
                        continuation.finish()
                        return
                    }

                    continuation.yield(.start)

                    var pendingWarnings: [CallWarning] = []
                    var firstChunk = true
                    var stepFinishReason: FinishReason = .unknown
                    var stepUsage = LanguageModelUsage()
                    var stepProviderMetadata: ProviderMetadata?
                    var stepResponseId = self.internalOptions.generateId()
                    var stepResponseTimestamp = self.internalOptions.currentDate()
                    var stepResponseModelId = stepModel.modelId

                    do {
                        for try await part in streamWithToolResults {
                            if let abortSignal = self.settings.abortSignal, abortSignal() {
                                if let onAbort = self.onAbort {
                                    await onAbort(StreamTextOnAbortEvent(steps: self.state.recordedSteps))
                                }
                                continuation.yield(.abort)
                                continuation.finish()
                                return
                            }

                            switch part {
                            case .streamStart(let warnings):
                                pendingWarnings = warnings
                                continue
                            case let .textStart(id, providerMetadata):
                                if firstChunk {
                                    firstChunk = false
                                    continuation.yield(.startStep(request: requestMetadata, warnings: pendingWarnings))
                                }
                                continuation.yield(.textStart(id: id, providerMetadata: providerMetadata))
                            case let .textDelta(id, delta, providerMetadata):
                                if firstChunk {
                                    firstChunk = false
                                    continuation.yield(.startStep(request: requestMetadata, warnings: pendingWarnings))
                                }
                                continuation.yield(.textDelta(id: id, text: delta, providerMetadata: providerMetadata))
                            case let .textEnd(id, providerMetadata):
                                if firstChunk {
                                    firstChunk = false
                                    continuation.yield(.startStep(request: requestMetadata, warnings: pendingWarnings))
                                }
                                continuation.yield(.textEnd(id: id, providerMetadata: providerMetadata))
                            case let .reasoningStart(id, providerMetadata):
                                if firstChunk {
                                    firstChunk = false
                                    continuation.yield(.startStep(request: requestMetadata, warnings: pendingWarnings))
                                }
                                continuation.yield(.reasoningStart(id: id, providerMetadata: providerMetadata))
                            case let .reasoningDelta(id, delta, providerMetadata):
                                if firstChunk {
                                    firstChunk = false
                                    continuation.yield(.startStep(request: requestMetadata, warnings: pendingWarnings))
                                }
                                continuation.yield(.reasoningDelta(id: id, text: delta, providerMetadata: providerMetadata))
                            case let .reasoningEnd(id, providerMetadata):
                                if firstChunk {
                                    firstChunk = false
                                    continuation.yield(.startStep(request: requestMetadata, warnings: pendingWarnings))
                                }
                                continuation.yield(.reasoningEnd(id: id, providerMetadata: providerMetadata))
                            case let .toolInputStart(id, toolName, providerMetadata, providerExecuted):
                                if firstChunk {
                                    firstChunk = false
                                    continuation.yield(.startStep(request: requestMetadata, warnings: pendingWarnings))
                                }
                                let dynamicFlag: Bool? = {
                                    guard let tool = self.tools?[toolName] else { return nil }
                                    return tool.type == .dynamic ? true : nil
                                }()
                                continuation.yield(.toolInputStart(
                                    id: id,
                                    toolName: toolName,
                                    providerMetadata: providerMetadata,
                                    providerExecuted: providerExecuted,
                                    dynamic: dynamicFlag
                                ))
                            case let .toolInputDelta(id, delta, providerMetadata):
                                if firstChunk {
                                    firstChunk = false
                                    continuation.yield(.startStep(request: requestMetadata, warnings: pendingWarnings))
                                }
                                continuation.yield(.toolInputDelta(id: id, delta: delta, providerMetadata: providerMetadata))
                            case let .toolInputEnd(id, providerMetadata):
                                if firstChunk {
                                    firstChunk = false
                                    continuation.yield(.startStep(request: requestMetadata, warnings: pendingWarnings))
                                }
                                continuation.yield(.toolInputEnd(id: id, providerMetadata: providerMetadata))
                            case let .toolCall(toolCall):
                                if firstChunk {
                                    firstChunk = false
                                    continuation.yield(.startStep(request: requestMetadata, warnings: pendingWarnings))
                                }
                                continuation.yield(.toolCall(toolCall))
                            case let .toolResult(result):
                                if firstChunk {
                                    firstChunk = false
                                    continuation.yield(.startStep(request: requestMetadata, warnings: pendingWarnings))
                                }
                                continuation.yield(.toolResult(result))
                            case let .toolError(error):
                                if firstChunk {
                                    firstChunk = false
                                    continuation.yield(.startStep(request: requestMetadata, warnings: pendingWarnings))
                                }
                                continuation.yield(.toolError(error))
                            case let .toolApprovalRequest(request):
                                if firstChunk {
                                    firstChunk = false
                                    continuation.yield(.startStep(request: requestMetadata, warnings: pendingWarnings))
                                }
                                continuation.yield(.toolApprovalRequest(request))
                            case let .source(source):
                                if firstChunk {
                                    firstChunk = false
                                    continuation.yield(.startStep(request: requestMetadata, warnings: pendingWarnings))
                                }
                                continuation.yield(.source(source))
                            case let .file(file):
                                if firstChunk {
                                    firstChunk = false
                                    continuation.yield(.startStep(request: requestMetadata, warnings: pendingWarnings))
                                }
                                continuation.yield(.file(file))
                            case let .finish(finishReason, usage, providerMetadata):
                                stepFinishReason = finishReason
                                stepUsage = usage
                                stepProviderMetadata = providerMetadata
                            case let .responseMetadata(id, timestamp, modelId):
                                if let id { stepResponseId = id }
                                if let timestamp { stepResponseTimestamp = timestamp }
                                if let modelId { stepResponseModelId = modelId }
                            case let .raw(rawValue):
                                if includeRawChunks {
                                    if firstChunk {
                                        firstChunk = false
                                        continuation.yield(.startStep(request: requestMetadata, warnings: pendingWarnings))
                                    }
                                    continuation.yield(.raw(rawValue: rawValue))
                                }
                            case let .error(error):
                                if firstChunk {
                                    firstChunk = false
                                    continuation.yield(.startStep(request: requestMetadata, warnings: pendingWarnings))
                                }
                                continuation.yield(.error(error))
                            }
                        }

                        if firstChunk {
                            continuation.yield(.startStep(request: requestMetadata, warnings: pendingWarnings))
                        }

                        let responseMetadata = LanguageModelResponseMetadata(
                            id: stepResponseId,
                            timestamp: stepResponseTimestamp,
                            modelId: stepResponseModelId,
                            headers: streamResult.response?.headers
                        )

                        continuation.yield(.finishStep(
                            response: responseMetadata,
                            usage: stepUsage,
                            finishReason: stepFinishReason,
                            providerMetadata: stepProviderMetadata
                        ))

                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
        )

        try await addStream(stepStream)
        if let stepFinish = state.stepFinish {
            _ = try await stepFinish.task.value
        }

        responseMessages = state.recordedResponseMessages

        guard let stepResult = state.recordedSteps.last else {
            return
        }

        accumulatedUsage = addLanguageModelUsage(accumulatedUsage, stepResult.usage)

        let clientToolCalls = state.lastClientToolCalls
        let clientToolOutputs = state.lastClientToolOutputs

        let shouldContinue: Bool
        if !clientToolCalls.isEmpty,
           clientToolOutputs.count == clientToolCalls.count {
            let stopMet = await isStopConditionMet(
                stopConditions: stopConditions,
                steps: state.recordedSteps
            )
            shouldContinue = !stopMet
        } else {
            shouldContinue = false
        }

        if shouldContinue {
            try await executeStep(
                stepNumber: stepNumber + 1,
                standardizedPrompt: standardizedPrompt,
                initialMessages: initialMessages,
                responseMessages: &responseMessages,
                accumulatedUsage: &accumulatedUsage,
                retries: retries,
                preparedCallSettings: preparedCallSettings,
                tracer: tracer
            )
            return
        }

        let finishReason = stepResult.finishReason
        let finishStream = createAsyncIterableStream(
            source: AsyncThrowingStream<TextStreamPart, Error> { continuation in
                continuation.yield(.finish(finishReason: finishReason, totalUsage: accumulatedUsage))
                continuation.finish()
            }
        )

        try await addStream(finishStream)
        closeStream()
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

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension DefaultStreamTextResult: @unchecked Sendable {}
