import AISDKProvider
import AISDKProviderUtils
import Foundation

// MARK: - Public API (Milestone 1)

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public typealias StreamTextOnChunk = @Sendable (TextStreamPart) async -> Void
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public typealias StreamTextOnError = @Sendable (Error) async -> Void
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public typealias StreamTextOnStepFinish = @Sendable (StepResult) async -> Void
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public typealias StreamTextOnFinish = @Sendable (
    _ finalStep: StepResult,
    _ steps: [StepResult],
    _ totalUsage: LanguageModelUsage,
    _ finishReason: FinishReason
) async -> Void
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public typealias StreamTextOnAbort = @Sendable (_ steps: [StepResult]) async -> Void

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

struct StreamTextActorConfiguration: Sendable {
    let callSettings: PreparedCallSettings
    let preparedRetries: PreparedRetries
    let headers: [String: String]
    let providerOptions: ProviderOptions?
    let includeRawChunks: Bool
    let abortSignal: (@Sendable () -> Bool)?
    let toolChoice: ToolChoice?
    let activeTools: [String]?
    let download: DownloadFunction?
    let responseFormatProvider: (@Sendable () async throws -> LanguageModelV3ResponseFormat?)?
    let now: @Sendable () -> Double
    let generateId: IDGenerator
    let currentDate: @Sendable () -> Date
    let telemetry: TelemetrySettings?
    let tracer: any Tracer
    let baseTelemetryAttributes: Attributes
    let baseModel: LanguageModel
    let prepareStep: PrepareStepFunction?
    let repairToolCall: ToolCallRepairFunction?
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
struct StreamTextStepPreparation {
    let modelArg: LanguageModel
    let resolvedModel: any LanguageModelV3
    let system: String?
    let messages: [ModelMessage]
    let toolChoice: ToolChoice?
    let activeTools: [String]?
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private func makeStreamTextStepPreparation(
    prepareStep: PrepareStepFunction?,
    baseModel: LanguageModel,
    defaultResolvedModel: any LanguageModelV3,
    steps: [StepResult],
    stepNumber: Int,
    inputMessages: [ModelMessage]
) async throws -> StreamTextStepPreparation {
    var modelArg = baseModel
    var resolvedModel: any LanguageModelV3 = defaultResolvedModel
    var systemOverride: String? = nil
    var messages = inputMessages
    var toolChoice: ToolChoice? = nil
    var activeTools: [String]? = nil

    if let prepareStep {
        let options = PrepareStepOptions(
            steps: steps,
            stepNumber: stepNumber,
            model: baseModel,
            messages: inputMessages
        )

        if let result = try await prepareStep(options) {
            if let newModel = result.model {
                modelArg = newModel
                resolvedModel = try resolveLanguageModel(newModel)
            }
            if let system = result.system {
                systemOverride = system
            }
            if let overrideMessages = result.messages {
                messages = overrideMessages
            }
            if let overrideToolChoice = result.toolChoice {
                toolChoice = overrideToolChoice
            }
            if let overrideActiveTools = result.activeTools {
                activeTools = overrideActiveTools
            }
        }
    }

    return StreamTextStepPreparation(
        modelArg: modelArg,
        resolvedModel: resolvedModel,
        system: systemOverride,
        messages: messages,
        toolChoice: toolChoice,
        activeTools: activeTools
    )
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

private func providerExecutedFlag(for call: TypedToolCall) -> Bool? {
    switch call {
    case .static(let value):
        return value.providerExecuted
    case .dynamic(let value):
        return value.providerExecuted
    }
}

public struct StreamTextTransformOptions {
    public var tools: ToolSet?
    public var stopStream: @Sendable () -> Void

    public init(tools: ToolSet?, stopStream: @escaping @Sendable () -> Void) {
        self.tools = tools
        self.stopStream = stopStream
    }
}

public typealias StreamTextTransform = @Sendable (
    _ stream: AsyncIterableStream<TextStreamPart>,
    _ options: StreamTextTransformOptions
) -> AsyncIterableStream<TextStreamPart>


@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func streamText<OutputValue: Sendable, PartialOutputValue: Sendable>(
    model modelArg: LanguageModel,
    prompt: String,
    tools: ToolSet? = nil,
    toolChoice: ToolChoice? = nil,
    providerOptions: ProviderOptions? = nil,
    experimentalActiveTools: [String]? = nil,
    activeTools: [String]? = nil,
    experimentalOutput output: SwiftAISDK.Output.Specification<OutputValue, PartialOutputValue>? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    experimentalApprove approve: (@Sendable (ToolApprovalRequestOutput) async -> ApprovalAction)? = nil,
    experimentalTransform transforms: [StreamTextTransform] = [],
    experimentalDownload download: DownloadFunction? = nil,
    experimentalRepairToolCall repairToolCall: ToolCallRepairFunction? = nil,
    prepareStep: PrepareStepFunction? = nil,
    experimentalContext: JSONValue? = nil,
    includeRawChunks: Bool = false,
    stopWhen stopConditions: [StopCondition] = [stepCountIs(1)],
    onChunk: StreamTextOnChunk? = nil,
    onStepFinish: StreamTextOnStepFinish? = nil,
    onFinish: StreamTextOnFinish? = nil,
    onAbort: StreamTextOnAbort? = nil,
    onError: StreamTextOnError? = nil,
    internalOptions _internal: StreamTextInternalOptions = StreamTextInternalOptions(),
    settings: CallSettings = CallSettings()
) throws -> DefaultStreamTextResult<OutputValue, PartialOutputValue> {
    // Resolve LanguageModel to a v3 model; for milestone 1 only v3 path is supported.
    _ = try resolveLanguageModel(modelArg)

    return try streamText(
        model: modelArg,
        system: nil,
        messages: [.user(UserModelMessage(content: .text(prompt), providerOptions: nil))],
        tools: tools,
        toolChoice: toolChoice,
        providerOptions: providerOptions,
        experimentalActiveTools: experimentalActiveTools,
        activeTools: activeTools,
        experimentalOutput: output,
        experimentalTelemetry: telemetry,
        experimentalApprove: approve,
        experimentalTransform: transforms,
        experimentalDownload: download,
        experimentalRepairToolCall: repairToolCall,
        prepareStep: prepareStep,
        experimentalContext: experimentalContext,
        includeRawChunks: includeRawChunks,
        stopWhen: stopConditions,
        onChunk: onChunk,
        onStepFinish: onStepFinish,
        onFinish: onFinish,
        onAbort: onAbort,
        onError: onError,
        internalOptions: _internal,
        settings: settings
    )
}

// MARK: - Convenience: top-level response helpers (Text/UI)

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func streamTextAsResponse(
    model: LanguageModel,
    prompt: String,
    tools: ToolSet? = nil,
    init initOptions: TextStreamResponseInit? = nil,
    experimentalTransform transforms: [StreamTextTransform] = [],
    stopWhen stopConditions: [StopCondition] = [stepCountIs(1)],
    onError: StreamTextOnError? = nil
) throws -> TextStreamResponse {
    let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
        model: model,
        prompt: prompt,
        tools: tools,
        experimentalTransform: transforms,
        stopWhen: stopConditions,
        onError: onError
    )
    return result.toTextStreamResponse(init: initOptions)
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func pipeStreamTextToResponse(
    model: LanguageModel,
    prompt: String,
    tools: ToolSet? = nil,
    response: any StreamTextResponseWriter,
    init initOptions: TextStreamResponseInit? = nil,
    experimentalTransform transforms: [StreamTextTransform] = [],
    stopWhen stopConditions: [StopCondition] = [stepCountIs(1)],
    onError: StreamTextOnError? = nil
) throws {
    let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
        model: model,
        prompt: prompt,
        tools: tools,
        experimentalTransform: transforms,
        stopWhen: stopConditions,
        onError: onError
    )
    result.pipeTextStreamToResponse(response, init: initOptions)
}

// MARK: - Result Type (Milestone 1)

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public final class DefaultStreamTextResult<OutputValue: Sendable, PartialOutputValue: Sendable>:
    @unchecked Sendable
{
    public typealias Output = OutputValue
    public typealias PartialOutput = PartialOutputValue

    private let actor: StreamTextActor
    private let transforms: [StreamTextTransform]
    private let stopConditions: [StopCondition]
    private let tools: ToolSet?
    private let outputSpecification: SwiftAISDK.Output.Specification<OutputValue, PartialOutputValue>?
    private let totalUsagePromise = DelayedPromise<LanguageModelUsage>()
    private let finishReasonPromise = DelayedPromise<FinishReason>()
    private let stepsPromise = DelayedPromise<[StepResult]>()
    private let aggregator: StreamTextPipelineAggregator
    private let fullStreamBroadcaster = AsyncStreamBroadcaster<TextStreamPart>()
    private let textStreamBroadcaster = AsyncStreamBroadcaster<String>()
    private var pipelineTask: Task<Void, Never>!
    private let baseModelId: String

    private actor OutputStorage {
        var parsed = false
        var value: OutputValue? = nil

        func shouldParse() -> Bool {
            if parsed { return false }
            parsed = true
            return true
        }

        func store(_ newValue: OutputValue?) {
            value = newValue
        }

        func snapshot() -> (parsed: Bool, value: OutputValue?) {
            (parsed, value)
        }
    }

    private let outputStorage = OutputStorage()

    @available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
    init(
        baseModel: LanguageModel,
        model: any LanguageModelV3,
        providerStream: AsyncThrowingStream<LanguageModelV3StreamPart, Error>,
        transforms: [StreamTextTransform],
        stopConditions: [StopCondition],
        initialMessages: [ModelMessage],
        system: String?,
        tools: ToolSet?,
        approve: (@Sendable (ToolApprovalRequestOutput) async -> ApprovalAction)? = nil,
        approvalContext: JSONValue?,
        outputSpecification: SwiftAISDK.Output.Specification<OutputValue, PartialOutputValue>?,
        configuration: StreamTextActorConfiguration,
        onChunk: StreamTextOnChunk?,
        onStepFinish: StreamTextOnStepFinish? = nil,
        onFinish: StreamTextOnFinish? = nil,
        onAbort: StreamTextOnAbort? = nil,
        onError: StreamTextOnError? = nil
    ) {
        self.stopConditions = stopConditions.isEmpty ? [stepCountIs(1)] : stopConditions
        self.baseModelId = model.modelId
        self.actor = StreamTextActor(
            source: providerStream,
            model: model,
            initialMessages: initialMessages,
            system: system,
            stopConditions: self.stopConditions,
            tools: tools,
            approvalResolver: approve,
            experimentalApprovalContext: approvalContext,
            configuration: configuration,
            totalUsagePromise: totalUsagePromise,
            finishReasonPromise: finishReasonPromise,
            stepsPromise: stepsPromise
        )
        self.transforms = transforms
        self.outputSpecification = outputSpecification
        self.tools = tools

        self.aggregator = StreamTextPipelineAggregator(
            tools: tools,
            baseModelId: model.modelId,
            onChunk: onChunk,
            onStepFinish: onStepFinish,
            onFinish: onFinish,
            onAbort: onAbort,
            onError: onError,
            includeRawChunks: configuration.includeRawChunks
        )

        let actor = self.actor
        let aggregator = self.aggregator
        let transforms = self.transforms
        let tools = self.tools

        self.pipelineTask = Task {
            let baseStream = AsyncThrowingStream<TextStreamPart, Error> { continuation in
                let task = Task {
                    let inner = await actor.fullStream()
                    do {
                        for try await value in inner {
                            continuation.yield(value)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }

            let iterable = createAsyncIterableStream(source: baseStream)

            let transformOptions = StreamTextTransformOptions(
                tools: tools,
                stopStream: {
                    Task { await actor.requestStop() }
                }
            )

            let transformedIterable = transforms.reduce(iterable) { current, transform in
                transform(current, transformOptions)
            }

            let transformedStream = AsyncThrowingStream<TextStreamPart, Error> { continuation in
                let task = Task {
                    var iterator = transformedIterable.makeAsyncIterator()
                    do {
                        while let part = try await iterator.next() {
                            continuation.yield(part)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }

            do {
                for try await part in transformedStream {
                    await aggregator.process(part: part)
                    if case .textDelta(_, let delta, _) = part {
                        await self.textStreamBroadcaster.send(delta)
                    }
                    await self.fullStreamBroadcaster.send(part)
                }
                await aggregator.finish(error: nil)
                await self.textStreamBroadcaster.finish()
                await self.fullStreamBroadcaster.finish()
            } catch {
                await aggregator.finish(error: error)
                await self.textStreamBroadcaster.finish(error: error)
                await self.fullStreamBroadcaster.finish(error: error)
            }
        }
    }

    deinit {
        pipelineTask.cancel()
    }

    public var textStream: AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let stream = await textStreamBroadcaster.register()
                do {
                    for try await value in stream {
                        continuation.yield(value)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public var fullStream: AsyncThrowingStream<TextStreamPart, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let stream = await fullStreamBroadcaster.register()
                do {
                    for try await value in stream {
                        continuation.yield(value)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public var experimentalPartialOutputStream: AsyncThrowingStream<PartialOutputValue, Error> {
        guard let outputSpecification else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: NoOutputSpecifiedError())
            }
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                let stream = await fullStreamBroadcaster.register()
                var firstTextId: String? = nil
                var accumulated = ""
                var lastRepresentation: String? = nil

                func flushCurrent() async throws {
                    guard let _ = firstTextId, !accumulated.isEmpty else { return }
                    if let partial = try await outputSpecification.parsePartial(text: accumulated) {
                        let representation = partialRepresentation(partial)
                        if representation != lastRepresentation {
                            continuation.yield(partial)
                            lastRepresentation = representation
                        }
                    }
                }

                do {
                    for try await part in stream {
                        switch part {
                        case .textStart(let id, _):
                            firstTextId = id
                            accumulated = ""
                            lastRepresentation = nil
                        case .textDelta(let id, let delta, _):
                            if firstTextId == nil {
                                firstTextId = id
                                accumulated = ""
                                lastRepresentation = nil
                            }
                            guard id == firstTextId else { continue }
                            accumulated += delta
                            try await flushCurrent()
                        case .textEnd(let id, _):
                            if id == firstTextId {
                                try await flushCurrent()
                                firstTextId = nil
                                accumulated = ""
                                lastRepresentation = nil
                            }
                        case .finishStep, .finish:
                            try await flushCurrent()
                            firstTextId = nil
                            accumulated = ""
                            lastRepresentation = nil
                        default:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public var experimentalOutput: OutputValue {
        get async throws {
            guard outputSpecification != nil else { throw NoOutputSpecifiedError() }
            let (final, _, _, reason) = try await waitForFinish()
            var snapshot = await outputStorage.snapshot()
            if !snapshot.parsed {
                try await parseOutputIfNeeded(finalStep: final, finishReason: reason)
                snapshot = await outputStorage.snapshot()
            }
            guard snapshot.parsed, let value = snapshot.value else { throw NoOutputSpecifiedError() }
            return value
        }
    }

    public func collectText() async throws -> String {
        var buffer = ""
        for try await delta in textStream { buffer.append(delta) }
        return buffer
    }

    public func waitForFinish() async throws -> (
        finalStep: StepResult,
        steps: [StepResult],
        totalUsage: LanguageModelUsage,
        finishReason: FinishReason
    ) {
        try await aggregator.waitForCompletion()
        let steps = try await aggregator.stepsList()
        guard let final = steps.last else { throw NoOutputGeneratedError() }
        let finishReason = try await aggregator.finishReasonValue()
        let usage = try await aggregator.totalUsageValue()
        try await parseOutputIfNeeded(finalStep: final, finishReason: finishReason)
        return (final, steps, usage, finishReason)
    }

    private var finalStep: StepResult {
        get async throws {
            try await aggregator.finalStepValue()
        }
    }

    public var content: [ContentPart] {
        get async throws { try await finalStep.content }
    }

    public var text: String {
        get async throws { try await finalStep.text }
    }

    public var reasoning: [ReasoningOutput] {
        get async throws { try await finalStep.reasoning }
    }

    public var reasoningText: String? {
        get async throws { try await finalStep.reasoningText }
    }

    public var files: [GeneratedFile] {
        get async throws { try await finalStep.files }
    }

    public var sources: [Source] {
        get async throws { try await finalStep.sources }
    }

    public var toolCalls: [TypedToolCall] {
        get async throws { try await finalStep.toolCalls }
    }

    public var staticToolCalls: [StaticToolCall] {
        get async throws { try await finalStep.staticToolCalls }
    }

    public var dynamicToolCalls: [DynamicToolCall] {
        get async throws { try await finalStep.dynamicToolCalls }
    }

    public var toolResults: [TypedToolResult] {
        get async throws { try await finalStep.toolResults }
    }

    public var staticToolResults: [StaticToolResult] {
        get async throws { try await finalStep.staticToolResults }
    }

    public var dynamicToolResults: [DynamicToolResult] {
        get async throws { try await finalStep.dynamicToolResults }
    }

    public var finishReason: FinishReason {
        get async throws { try await aggregator.finishReasonValue() }
    }

    public var usage: LanguageModelUsage {
        get async throws { try await finalStep.usage }
    }

    public var totalUsage: LanguageModelUsage {
        get async throws { try await aggregator.totalUsageValue() }
    }

    public var warnings: [CallWarning]? {
        get async throws { try await finalStep.warnings }
    }

    public var steps: [StepResult] {
        get async throws { try await aggregator.stepsList() }
    }

    public var request: LanguageModelRequestMetadata {
        get async throws { try await finalStep.request }
    }

    public var response: StepResultResponse {
        get async throws { try await finalStep.response }
    }

    public var providerMetadata: ProviderMetadata? {
        get async throws { try await finalStep.providerMetadata }
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

    public func toSSEStream(includeUsage: Bool) -> AsyncThrowingStream<String, Error> {
        makeStreamTextSSEStream(from: fullStream, includeUsage: includeUsage)
    }

    public func toUIMessageStream<Message: UIMessageConvertible>(
        options: UIMessageStreamOptions<Message>?
    ) -> AsyncThrowingStream<AnyUIMessageChunk, Error> {
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

        @Sendable func mapErrorMessage(_ value: Any?) -> String {
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

        let base: AsyncThrowingStream<AnyUIMessageChunk, Error> = transformFullToUIMessageStream(
            stream: fullStream,
            options: UIMessageTransformOptions(
                sendStart: streamOptions.sendStart,
                sendFinish: streamOptions.sendFinish,
                sendReasoning: streamOptions.sendReasoning,
                sendSources: streamOptions.sendSources,
                messageMetadata: streamOptions.messageMetadata
            )
        )

        let handled = handleUIMessageStreamFinish(
            stream: base,
            messageId: responseMessageId,
            originalMessages: streamOptions.originalMessages ?? [],
            onFinish: streamOptions.onFinish,
            onError: { error in _ = mapErrorMessage(error) }
        )

        return handled
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

    public func toUIMessageStreamResponse<Message: UIMessageConvertible>(
        options: StreamTextUIResponseOptions<Message>?
    ) -> UIMessageStreamResponse<Message> {
        let stream = toUIMessageStream(options: options?.streamOptions)
        return SwiftAISDK.createUIMessageStreamResponse(
            stream: stream,
            options: options
        )
    }

    public func consumeStream(options: ConsumeStreamOptions? = nil) async {
        await SwiftAISDK.consumeStream(stream: fullStream, onError: options?.onError)
    }

    public func stop() {
        Task { await actor.requestStop() }
    }

    public var fullStreamIterable: AsyncIterableStream<TextStreamPart> {
        createAsyncIterableStream(source: fullStream)
    }

    public var textStreamIterable: AsyncIterableStream<String> {
        createAsyncIterableStream(source: textStream)
    }

    public func readAllText() async throws -> String {
        var buffer = ""
        for try await chunk in textStream { buffer.append(chunk) }
        return buffer
    }

    public func collectFullStream() async throws -> [TextStreamPart] {
        var parts: [TextStreamPart] = []
        for try await part in fullStream {
            parts.append(part)
        }
        return parts
    }


    func _setRequestInfo(_ info: LanguageModelV3RequestInfo?) async {
        await actor.setInitialRequest(info)
    }

    func _setProviderCancel(_ cancel: @escaping @Sendable () -> Void) async {
        await actor.setOnTerminate(cancel)
    }

    func _appendInitialResponseMessages(_ messages: [ResponseMessage]) async {
        await aggregator.appendInitialResponseMessages(messages)
    }

    func _notifyThrownError(_ error: Error) async {
        await aggregator.notifyThrownError(error)
    }

    func _publishPreludeEvents(_ parts: [TextStreamPart]) async {
        guard !parts.isEmpty else { return }
        for part in parts {
            await aggregator.deliverChunkEvent(part)
            if case .textDelta(_, let delta, _) = part {
                await textStreamBroadcaster.send(delta)
            }
            await fullStreamBroadcaster.send(part)
        }
    }

    private func parseOutputIfNeeded(finalStep: StepResult, finishReason: FinishReason) async throws {
        guard let outputSpecification else { return }
        let shouldParse = await outputStorage.shouldParse()
        if !shouldParse { return }

        if finishReason == .toolCalls {
            await outputStorage.store(nil)
            return
        }

        let responseMetadata = LanguageModelResponseMetadata(
            id: finalStep.response.id,
            timestamp: finalStep.response.timestamp,
            modelId: finalStep.response.modelId,
            headers: finalStep.response.headers
        )

        let parsed = try await outputSpecification.parseOutput(
            text: finalStep.text,
            response: responseMetadata,
            usage: finalStep.usage,
            finishReason: finishReason
        )

        await outputStorage.store(parsed)
    }

    private func partialRepresentation(_ value: PartialOutputValue) -> String {
        if let json = value as? JSONValue, let encoded = jsonString(from: json) {
            return encoded
        }
        if let string = value as? String {
            return string
        }
        if let convertible = value as? CustomStringConvertible {
            return convertible.description
        }
        return String(describing: value)
    }
}



private struct AggregatedTextContent {
    var index: Int
    var text: String
    var providerMetadata: ProviderMetadata?
}

private struct AggregatedReasoningContent {
    var index: Int
    var text: String
    var providerMetadata: ProviderMetadata?
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private actor StreamTextPipelineAggregator {
    private let tools: ToolSet?
    private let baseModelId: String
    private let onChunk: StreamTextOnChunk?
    private let onStepFinish: StreamTextOnStepFinish?
    private let onFinish: StreamTextOnFinish?
    private let onAbort: StreamTextOnAbort?
    private let onError: StreamTextOnError?
    private let includeRawChunks: Bool

    private var recordedSteps: [DefaultStepResult] = []
    private var recordedContent: [ContentPart] = []
    private var recordedResponseMessages: [ResponseMessage] = []
    private var currentWarnings: [CallWarning] = []
    private var currentRequest = LanguageModelRequestMetadata()
    private var currentResponseId: String?
    private var currentModelId: String?
    private var currentTimestamp: Date?
    private var openTextIds = Set<String>()
    private var activeTextContent: [String: AggregatedTextContent] = [:]
    private var openReasoningIds = Set<String>()
    private var activeReasoningContent: [String: AggregatedReasoningContent] = [:]
    private var activeToolInputs: [String: JSONValue] = [:]
    private var activeToolNames: [String: String] = [:]
    private var finishReason: FinishReason? = nil
    private var totalUsage: LanguageModelUsage? = nil
    private var finalStep: DefaultStepResult? = nil
    private var finishError: Error? = nil
    private var finished = false
    private var waiters: [CheckedContinuation<Void, Error>] = []

    init(
        tools: ToolSet?,
        baseModelId: String,
        onChunk: StreamTextOnChunk?,
        onStepFinish: StreamTextOnStepFinish?,
        onFinish: StreamTextOnFinish?,
        onAbort: StreamTextOnAbort?,
        onError: StreamTextOnError?,
        includeRawChunks: Bool
    ) {
        self.tools = tools
        self.baseModelId = baseModelId
        self.onChunk = onChunk
        self.onStepFinish = onStepFinish
        self.onFinish = onFinish
        self.onAbort = onAbort
        self.onError = onError
        self.includeRawChunks = includeRawChunks
    }


    func deliverChunkEvent(_ part: TextStreamPart) async {
        await deliverOnChunkIfNeeded(part)
    }
    func process(part: TextStreamPart) async {
        await deliverOnChunkIfNeeded(part)

        switch part {
        case .start:
            return
        case .abort:
            await handleAbort()
        case .startStep(let request, let warnings):
            await startStep(request: request, warnings: warnings)
        case .textStart(let id, let providerMetadata):
            await handleTextStart(id: id, providerMetadata: providerMetadata)
        case .textDelta(let id, let delta, let providerMetadata):
            await handleTextDelta(id: id, delta: delta, providerMetadata: providerMetadata)
        case .textEnd(let id, let providerMetadata):
            await handleTextEnd(id: id, providerMetadata: providerMetadata)
        case .reasoningStart(let id, let providerMetadata):
            await handleReasoningStart(id: id, providerMetadata: providerMetadata)
        case .reasoningDelta(let id, let delta, let providerMetadata):
            await handleReasoningDelta(id: id, delta: delta, providerMetadata: providerMetadata)
        case .reasoningEnd(let id, let providerMetadata):
            await handleReasoningEnd(id: id, providerMetadata: providerMetadata)
        case .toolInputStart(let id, let toolName, _, _, _):
            activeToolNames[id] = toolName
        case .toolInputDelta(let id, _, _):
            if activeToolNames[id] != nil { /* callbacks handled in actor */ }
        case .toolInputEnd(let id, _):
            activeToolNames.removeValue(forKey: id)
        case .toolCall(let call):
            await handleToolCall(call)
        case .toolResult(let result):
            await handleToolResult(result)
        case .toolError(let error):
            recordedContent.append(.toolError(error, providerMetadata: nil))
        case .toolApprovalRequest(let approval):
            recordedContent.append(.toolApprovalRequest(approval))
        case .toolOutputDenied:
            return
        case .source(let source):
            recordedContent.append(.source(type: "source", source: source))
        case .file(let file):
            recordedContent.append(.file(file: file, providerMetadata: nil))
        case .raw:
            return
        case .finishStep(let response, let usage, let finishReason, let providerMetadata):
            await finalizeStep(
                response: response,
                usage: usage,
                finishReason: finishReason,
                providerMetadata: providerMetadata
            )
        case .finish(let finishReason, let usage):
            await handleFinish(finishReason: finishReason, usage: usage)
        case .error(let errorValue):
            let normalized = (wrapGatewayError(errorValue) as? Error) ?? errorValue
            await deliverError(normalized)
        }
    }

    func finish(error: Error?) async {
        guard !finished else { return }
        finished = true
        if let _ = error {
            // На ошибке провайдера для ожидателей финала возвращаем
            // NoOutputGeneratedError (стрим уже завершён с ошибкой отдельно).
            finishError = NoOutputGeneratedError()
        } else if finishReason == nil || totalUsage == nil || recordedSteps.isEmpty {
            finishError = NoOutputGeneratedError()
        }
        resumeWaiters()
    }

    func waitForCompletion() async throws {
        if finished {
            if let error = finishError { throw error }
            return
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            waiters.append(continuation)
        }
    }

    func stepsList() async throws -> [StepResult] {
        try await waitForCompletion()
        return recordedSteps
    }

    func finalStepValue() async throws -> StepResult {
        try await waitForCompletion()
        guard let finalStep else { throw NoOutputGeneratedError() }
        return finalStep
    }

    func totalUsageValue() async throws -> LanguageModelUsage {
        try await waitForCompletion()
        guard let usage = totalUsage else { throw NoOutputGeneratedError() }
        return usage
    }

    func finishReasonValue() async throws -> FinishReason {
        try await waitForCompletion()
        guard let reason = finishReason else { throw NoOutputGeneratedError() }
        return reason
    }

    func appendInitialResponseMessages(_ messages: [ResponseMessage]) {
        guard !messages.isEmpty else { return }
        recordedResponseMessages.append(contentsOf: messages)
    }

    private func resumeWaiters() {
        let continuations = waiters
        waiters.removeAll()
        if let error = finishError {
            for continuation in continuations {
                continuation.resume(throwing: error)
            }
        } else {
            for continuation in continuations {
                continuation.resume(returning: ())
            }
        }
    }

    private func deliverOnChunkIfNeeded(_ part: TextStreamPart) async {
        guard let onChunk else { return }
        switch part {
        case .textDelta, .reasoningDelta, .source, .toolCall, .toolInputStart, .toolInputDelta, .toolResult:
            await onChunk(part)
        case .raw:
            if includeRawChunks { await onChunk(part) }
        default:
            break
        }
    }

    private func deliverError(_ error: Error) async {
        // Сообщаем об ошибке, но не сохраняем её как финальную:
        // waitForFinish должен бросать NoOutputGeneratedError.
        if let onError {
            await onError(error)
        }
    }

    // Ошибка пришла как исключение из стрима (а не .error часть)
    func notifyThrownError(_ error: Error) async {
        await deliverError(error)
    }

    private func handleAbort() async {
        await onAbort?(recordedSteps)
        finishError = NoOutputGeneratedError()
    }

    private func startStep(request: LanguageModelRequestMetadata, warnings: [CallWarning]) async {
        recordedContent.removeAll()
        activeTextContent.removeAll()
        activeReasoningContent.removeAll()
        activeToolInputs.removeAll()
        activeToolNames.removeAll()
        openTextIds.removeAll()
        openReasoningIds.removeAll()
        currentWarnings = warnings
        currentRequest = request
        currentResponseId = nil
        currentModelId = nil
        currentTimestamp = nil
    }

    private func handleTextStart(id: String, providerMetadata: ProviderMetadata?) async {
        openTextIds.insert(id)
        let index = recordedContent.count
        recordedContent.append(.text(text: "", providerMetadata: providerMetadata))
        activeTextContent[id] = AggregatedTextContent(index: index, text: "", providerMetadata: providerMetadata)
    }

    private func handleTextDelta(id: String, delta: String, providerMetadata: ProviderMetadata?) async {
        if !openTextIds.contains(id) {
            await handleTextStart(id: id, providerMetadata: providerMetadata)
        }
        guard var active = activeTextContent[id] else { return }
        active.text += delta
        if let providerMetadata {
            active.providerMetadata = providerMetadata
        }
        activeTextContent[id] = active
        recordedContent[active.index] = .text(text: active.text, providerMetadata: active.providerMetadata)
    }

    private func handleTextEnd(id: String, providerMetadata: ProviderMetadata?) async {
        openTextIds.remove(id)
        guard var active = activeTextContent[id] else { return }
        if let providerMetadata {
            active.providerMetadata = providerMetadata
        }
        activeTextContent.removeValue(forKey: id)
        recordedContent[active.index] = .text(text: active.text, providerMetadata: active.providerMetadata)
    }

    private func handleReasoningStart(id: String, providerMetadata: ProviderMetadata?) async {
        openReasoningIds.insert(id)
        let index = recordedContent.count
        let reasoning = ReasoningOutput(text: "", providerMetadata: providerMetadata)
        recordedContent.append(.reasoning(reasoning))
        activeReasoningContent[id] = AggregatedReasoningContent(index: index, text: "", providerMetadata: providerMetadata)
    }

    private func handleReasoningDelta(id: String, delta: String, providerMetadata: ProviderMetadata?) async {
        if !openReasoningIds.contains(id) {
            await handleReasoningStart(id: id, providerMetadata: providerMetadata)
        }
        guard var active = activeReasoningContent[id] else { return }
        active.text += delta
        if let providerMetadata {
            active.providerMetadata = providerMetadata
        }
        activeReasoningContent[id] = active
        let reasoning = ReasoningOutput(text: active.text, providerMetadata: active.providerMetadata)
        recordedContent[active.index] = .reasoning(reasoning)
    }

    private func handleReasoningEnd(id: String, providerMetadata: ProviderMetadata?) async {
        openReasoningIds.remove(id)
        guard var active = activeReasoningContent[id] else { return }
        if let providerMetadata {
            active.providerMetadata = providerMetadata
        }
        activeReasoningContent.removeValue(forKey: id)
        let reasoning = ReasoningOutput(text: active.text, providerMetadata: active.providerMetadata)
        recordedContent[active.index] = .reasoning(reasoning)
    }

    private func handleToolCall(_ call: TypedToolCall) async {
        activeToolInputs[call.toolCallId] = call.input
        activeToolNames[call.toolCallId] = call.toolName
        recordedContent.append(.toolCall(call, providerMetadata: call.providerMetadata))
    }

    private func handleToolResult(_ result: TypedToolResult) async {
        if result.preliminary == true { return }
        recordedContent.append(.toolResult(result, providerMetadata: result.providerMetadata))
        activeToolInputs.removeValue(forKey: result.toolCallId)
        activeToolNames.removeValue(forKey: result.toolCallId)
    }

    private func finalizePendingContent() {
        for (id, active) in activeTextContent {
            recordedContent[active.index] = .text(text: active.text, providerMetadata: active.providerMetadata)
            openTextIds.remove(id)
        }
        activeTextContent.removeAll()
        openTextIds.removeAll()

        for (id, active) in activeReasoningContent {
            let reasoning = ReasoningOutput(text: active.text, providerMetadata: active.providerMetadata)
            recordedContent[active.index] = .reasoning(reasoning)
            openReasoningIds.remove(id)
        }
        activeReasoningContent.removeAll()
        openReasoningIds.removeAll()
    }

    private func finalizeStep(
        response: LanguageModelResponseMetadata,
        usage: LanguageModelUsage,
        finishReason: FinishReason,
        providerMetadata: ProviderMetadata?
    ) async {
        finalizePendingContent()

        let contentSnapshot = recordedContent
        let modelMessages = toResponseMessages(content: contentSnapshot, tools: tools)
        let responseMessages = convertModelMessagesToResponseMessages(modelMessages)
        let mergedMessages = recordedResponseMessages + responseMessages

        let responseMetadata = LanguageModelResponseMetadata(
            id: response.id,
            timestamp: response.timestamp,
            modelId: response.modelId,
            headers: response.headers
        )

        let stepResult = DefaultStepResult(
            content: contentSnapshot,
            finishReason: finishReason,
            usage: usage,
            warnings: currentWarnings,
            request: currentRequest,
            response: StepResultResponse(from: responseMetadata, messages: mergedMessages, body: nil),
            providerMetadata: providerMetadata
        )

        recordedSteps.append(stepResult)
        recordedResponseMessages.append(contentsOf: responseMessages)

        if let onStepFinish {
            await onStepFinish(stepResult)
        }

        currentWarnings.removeAll()
        currentRequest = LanguageModelRequestMetadata()
        currentResponseId = nil
        currentModelId = nil
        currentTimestamp = nil
    }

    private func handleFinish(finishReason: FinishReason, usage: LanguageModelUsage) async {
        totalUsage = usage
        self.finishReason = finishReason
        if let step = recordedSteps.last {
            finalStep = step
            if let onFinish {
                await onFinish(step, recordedSteps, usage, finishReason)
            }
        }
    }
}

private func toGeneratedFile(_ file: LanguageModelV3File) -> GeneratedFile {
    switch file.data {
    case .base64(let base64):
        return DefaultGeneratedFileWithType(base64: base64, mediaType: file.mediaType)
    case .binary(let data):
        return DefaultGeneratedFileWithType(data: data, mediaType: file.mediaType)
    }
}

private func convertModelMessagesToResponseMessages(_ messages: [ModelMessage]) -> [ResponseMessage] {
    messages.compactMap { message in
        switch message {
        case .assistant(let value):
            return .assistant(value)
        case .tool(let value):
            return .tool(value)
        case .system, .user:
            return nil
        }
    }
}

// MARK: - Internal helpers

// MARK: - Helpers (none needed for milestone 1)

// MARK: - Overload: system/messages prompt (Upstream parity)

/// Creates a text stream using an initial system/message prompt, matching the upstream stream-text.ts
/// surface. This overload allows callers to pass structured messages instead of a simple text prompt.
///
/// - Parameters:
///   - model: The language model to use.
///   - system: Optional system instruction to prepend to the prompt.
///   - messages: Initial conversation messages (required; must be non-empty).
///   - experimentalTransform: Transforms applied to the full stream (map/tee semantics).
///   - stopWhen: Stop conditions to halt multi-step generation.
///
/// - Returns: DefaultStreamTextResult exposing text/full/UI streams and accessors.
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func streamText<OutputValue: Sendable, PartialOutputValue: Sendable>(
    model modelArg: LanguageModel,
    system: String?,
    messages initialMessages: [ModelMessage],
    tools: ToolSet? = nil,
    toolChoice: ToolChoice? = nil,
    providerOptions: ProviderOptions? = nil,
    experimentalActiveTools: [String]? = nil,
    activeTools: [String]? = nil,
    experimentalOutput output: SwiftAISDK.Output.Specification<OutputValue, PartialOutputValue>? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    experimentalApprove approve: (@Sendable (ToolApprovalRequestOutput) async -> ApprovalAction)? = nil,
    experimentalTransform transforms: [StreamTextTransform] = [],
    experimentalDownload download: DownloadFunction? = nil,
    experimentalRepairToolCall repairToolCall: ToolCallRepairFunction? = nil,
    prepareStep: PrepareStepFunction? = nil,
    experimentalContext: JSONValue? = nil,
    includeRawChunks: Bool = false,
    stopWhen stopConditions: [StopCondition] = [stepCountIs(1)],
    onChunk: StreamTextOnChunk? = nil,
    onStepFinish: StreamTextOnStepFinish? = nil,
    onFinish: StreamTextOnFinish? = nil,
    onAbort: StreamTextOnAbort? = nil,
    onError: StreamTextOnError? = nil,
    internalOptions _internal: StreamTextInternalOptions = StreamTextInternalOptions(),
    settings: CallSettings = CallSettings()
) throws -> DefaultStreamTextResult<OutputValue, PartialOutputValue> {

    _ = _internal
    let defaultResolvedModel = try resolveLanguageModel(modelArg)
    let standardizedPrompt = StandardizedPrompt(system: system, messages: initialMessages)
    let normalizedMessages = standardizedPrompt.messages
    let effectiveActiveTools = activeTools ?? experimentalActiveTools

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

    let headersWithUserAgent = withUserAgentSuffix(
        settings.headers ?? [:],
        "ai/\(VERSION)"
    )

    var telemetryCallSettings = settings
    telemetryCallSettings.maxRetries = preparedRetries.maxRetries

    let tracer = getTracer(
        isEnabled: telemetry?.isEnabled ?? false,
        tracer: telemetry?.tracer
    )

    let baseTelemetryAttributes = getBaseTelemetryAttributes(
        model: TelemetryModelInfo(modelId: defaultResolvedModel.modelId, provider: defaultResolvedModel.provider),
        settings: telemetryCallSettings,
        telemetry: telemetry,
        headers: headersWithUserAgent
    )

    let responseFormatProvider: (@Sendable () async throws -> LanguageModelV3ResponseFormat?)?
    if let output {
        responseFormatProvider = { try await output.responseFormat() }
    } else {
        responseFormatProvider = nil
    }

    let actorConfig = StreamTextActorConfiguration(
        callSettings: preparedCallSettings,
        preparedRetries: preparedRetries,
        headers: headersWithUserAgent,
        providerOptions: providerOptions,
        includeRawChunks: includeRawChunks,
        abortSignal: settings.abortSignal,
        toolChoice: toolChoice,
        activeTools: effectiveActiveTools,
        download: download,
        responseFormatProvider: responseFormatProvider,
        now: _internal.now,
        generateId: _internal.generateId,
        currentDate: _internal.currentDate,
        telemetry: telemetry,
        tracer: tracer,
        baseTelemetryAttributes: baseTelemetryAttributes,
        baseModel: modelArg,
        prepareStep: prepareStep,
        repairToolCall: repairToolCall
    )

    // Bridge provider async stream acquisition without blocking the caller.
    let (bridgeStream, continuation) = AsyncThrowingStream.makeStream(
        of: LanguageModelV3StreamPart.self
    )

    let errorHandler: StreamTextOnError = onError ?? { error in
        fputs("streamText error: \\(error)\n", stderr)
    }

    let result = DefaultStreamTextResult<OutputValue, PartialOutputValue>(
        baseModel: modelArg,
        model: defaultResolvedModel,
        providerStream: bridgeStream,
        transforms: transforms,
        stopConditions: stopConditions,
        initialMessages: normalizedMessages,
        system: standardizedPrompt.system,
        tools: tools,
        approve: approve,
        approvalContext: experimentalContext,
        outputSpecification: output,
        configuration: actorConfig,
        onChunk: onChunk,
        onStepFinish: onStepFinish,
        onFinish: onFinish,
        onAbort: onAbort,
        onError: errorHandler
    )

    let providerTask = Task {
        let outerAttributeInputs = buildStreamTextOuterTelemetryAttributes(
            telemetry: actorConfig.telemetry,
            baseAttributes: actorConfig.baseTelemetryAttributes,
            system: standardizedPrompt.system,
            prompt: nil,
            messages: standardizedPrompt.messages
        )

        let outerSpanAttributes: Attributes
        do {
            outerSpanAttributes = try await selectTelemetryAttributes(
                telemetry: actorConfig.telemetry,
                attributes: outerAttributeInputs
            )
        } catch {
            outerSpanAttributes = resolvedAttributesFromValues(outerAttributeInputs)
        }

        try await recordSpan(
            name: "ai.streamText",
            tracer: actorConfig.tracer,
            attributes: outerSpanAttributes
        ) { span in
            var activeDoStreamSpan: (any Span)? = nil
            do {
                var responseMessagesHistory: [ResponseMessage] = []
                let approvals = collectToolApprovals(messages: normalizedMessages)
                let tracer: any Tracer = actorConfig.tracer

                if !approvals.deniedToolApprovals.isEmpty || !approvals.approvedToolApprovals.isEmpty {
                    var toolContentParts: [ToolContentPart] = []

                    for denied in approvals.deniedToolApprovals {
                        let providerExecuted = providerExecutedFlag(for: denied.toolCall)
                        let deniedEvent = ToolOutputDenied(
                            toolCallId: denied.toolCall.toolCallId,
                            toolName: denied.toolCall.toolName,
                            providerExecuted: providerExecuted
                        )
                        await result._publishPreludeEvents([TextStreamPart.toolOutputDenied(deniedEvent)])

                        let deniedPart = ToolResultPart(
                            toolCallId: denied.toolCall.toolCallId,
                            toolName: denied.toolCall.toolName,
                            output: .executionDenied(reason: denied.approvalResponse.reason)
                        )
                        toolContentParts.append(.toolResult(deniedPart))
                    }

                    if let tools, !approvals.approvedToolApprovals.isEmpty {
                        for approval in approvals.approvedToolApprovals {
                            let output = await executeToolCall(
                                toolCall: approval.toolCall,
                                tools: tools,
                                tracer: tracer,
                                telemetry: actorConfig.telemetry,
                                messages: normalizedMessages,
                                abortSignal: settings.abortSignal,
                                experimentalContext: experimentalContext,
                                onPreliminaryToolResult: { typed in
                                    Task {
                                        await result._publishPreludeEvents([TextStreamPart.toolResult(typed)])
                                    }
                                }
                            )

                            guard let output else { continue }

                            switch output {
                            case .result(let typed):
                                await result._publishPreludeEvents([TextStreamPart.toolResult(typed)])
                            case .error(let error):
                                await result._publishPreludeEvents([TextStreamPart.toolError(error)])
                            }

                            toolContentParts.append(makeToolContentPart(output: output, tools: tools))
                        }
                    }

                    if !toolContentParts.isEmpty {
                        let toolMessage = ToolModelMessage(content: toolContentParts)
                        let responseMessage = ResponseMessage.tool(toolMessage)
                        responseMessagesHistory.append(responseMessage)
                        await result._appendInitialResponseMessages([responseMessage])
                    }
                }

                let conversationMessages: [ModelMessage]
                if responseMessagesHistory.isEmpty {
                    conversationMessages = normalizedMessages
                } else {
                    conversationMessages = normalizedMessages + convertResponseMessagesToModelMessages(responseMessagesHistory)
                }

                let stepPreparation = try await makeStreamTextStepPreparation(
                    prepareStep: prepareStep,
                    baseModel: modelArg,
                    defaultResolvedModel: defaultResolvedModel,
                    steps: [],
                    stepNumber: 0,
                    inputMessages: conversationMessages
                )

                let promptForProvider = StandardizedPrompt(
                    system: stepPreparation.system ?? standardizedPrompt.system,
                    messages: stepPreparation.messages
                )

                let supported = try await stepPreparation.resolvedModel.supportedUrls
                let lmPrompt = try await convertToLanguageModelPrompt(
                    prompt: promptForProvider,
                    supportedUrls: supported,
                    download: download
                )

                let toolPreparation = try await prepareToolsAndToolChoice(
                    tools: tools,
                    toolChoice: stepPreparation.toolChoice ?? toolChoice,
                    activeTools: stepPreparation.activeTools ?? effectiveActiveTools
                )

                let responseFormat = try await actorConfig.responseFormatProvider?()

                let callOptions = LanguageModelV3CallOptions(
                    prompt: lmPrompt,
                    maxOutputTokens: actorConfig.callSettings.maxOutputTokens,
                    temperature: actorConfig.callSettings.temperature,
                    stopSequences: actorConfig.callSettings.stopSequences,
                    topP: actorConfig.callSettings.topP,
                    topK: actorConfig.callSettings.topK,
                    presencePenalty: actorConfig.callSettings.presencePenalty,
                    frequencyPenalty: actorConfig.callSettings.frequencyPenalty,
                    responseFormat: responseFormat,
                    seed: actorConfig.callSettings.seed,
                    tools: toolPreparation.tools,
                    toolChoice: toolPreparation.toolChoice,
                    includeRawChunks: actorConfig.includeRawChunks ? true : nil,
                    abortSignal: actorConfig.abortSignal,
                    headers: actorConfig.headers,
                    providerOptions: actorConfig.providerOptions
                )

                let doStreamAttributeInputs = buildStreamTextDoStreamTelemetryAttributes(
                    telemetry: actorConfig.telemetry,
                    baseAttributes: actorConfig.baseTelemetryAttributes,
                    prompt: lmPrompt,
                    tools: toolPreparation.tools,
                    toolChoice: toolPreparation.toolChoice,
                    settings: actorConfig.callSettings,
                    model: stepPreparation.resolvedModel
                )

                let resolvedDoStreamAttributes: Attributes
                do {
                    resolvedDoStreamAttributes = try await selectTelemetryAttributes(
                        telemetry: actorConfig.telemetry,
                        attributes: doStreamAttributeInputs
                    )
                } catch {
                    resolvedDoStreamAttributes = resolvedAttributesFromValues(doStreamAttributeInputs)
                }

                let (providerResult, doStreamSpanAny, doStreamStartTimestamp): (LanguageModelV3StreamResult, any Span, Double) = try await recordSpan(
                    name: "ai.streamText.doStream",
                    tracer: actorConfig.tracer,
                    attributes: resolvedDoStreamAttributes,
                    fn: { span in
                        let startTimestamp = actorConfig.now()
                        let result = try await actorConfig.preparedRetries.retry.call {
                            try await stepPreparation.resolvedModel.doStream(options: callOptions)
                        }
                        return (result, span, startTimestamp)
                    },
                    endWhenDone: false
                )

                let doStreamSpan = doStreamSpanAny
                activeDoStreamSpan = doStreamSpan
                defer { doStreamSpan.end() }

                await result._setRequestInfo(providerResult.request)

                var sawFirstChunk = false
                for try await part in providerResult.stream {
                    if !sawFirstChunk {
                        switch part {
                        case .streamStart:
                            break
                        default:
                            sawFirstChunk = true
                            let elapsed = max(actorConfig.now() - doStreamStartTimestamp, 0)
                            let firstAttrs: Attributes = ["ai.response.msToFirstChunk": .double(elapsed)]
                            doStreamSpan.addEvent("ai.stream.firstChunk", attributes: firstAttrs)
                            doStreamSpan.setAttributes(firstAttrs)
                        }
                    }
                    continuation.yield(part)
                }
                continuation.finish()

                let finish = try await result.waitForFinish()
                let rootAttributeInputs = buildStreamTextRootTelemetryAttributes(
                    telemetry: actorConfig.telemetry,
                    finishReason: finish.finishReason,
                    finalStep: finish.finalStep,
                    totalUsage: finish.totalUsage
                )
                let resolvedRootAttributes: Attributes
                do {
                    resolvedRootAttributes = try await selectTelemetryAttributes(
                        telemetry: actorConfig.telemetry,
                        attributes: rootAttributeInputs
                    )
                } catch {
                    resolvedRootAttributes = resolvedAttributesFromValues(rootAttributeInputs)
                }
                span.setAttributes(resolvedRootAttributes)

                let msToFinish = max(actorConfig.now() - doStreamStartTimestamp, 0)
                var finishAttrs: Attributes = ["ai.response.msToFinish": .double(msToFinish)]
                if let outputTokens = finish.totalUsage.outputTokens, msToFinish > 0 {
                    let avg = (1000.0 * Double(outputTokens)) / msToFinish
                    finishAttrs["ai.response.avgOutputTokensPerSecond"] = .double(avg)
                }
                doStreamSpan.addEvent("ai.stream.finish", attributes: finishAttrs)
                doStreamSpan.setAttributes(finishAttrs)
            } catch {
                if let span = activeDoStreamSpan {
                    recordErrorOnSpan(span, error: error)
                }
                continuation.finish(throwing: error)
                throw error
            }
        }
    }

    continuation.onTermination = { _ in providerTask.cancel() }
    Task { await result._setProviderCancel { providerTask.cancel() } }

    return result
}

private func buildStreamTextOuterTelemetryAttributes(
    telemetry: TelemetrySettings?,
    baseAttributes: Attributes,
    system: String?,
    prompt: String?,
    messages: [ModelMessage]
) -> [String: ResolvableAttributeValue?] {
    var attributes: [String: ResolvableAttributeValue?] = [:]

    for (key, value) in assembleOperationName(operationId: "ai.streamText", telemetry: telemetry) {
        attributes[key] = .value(value)
    }

    for (key, value) in baseAttributes {
        attributes[key] = .value(value)
    }

    attributes["ai.prompt"] = .input {
        guard let summary = summarizePromptForTelemetry(system: system, prompt: prompt, messages: messages) else {
            return nil
        }
        return .string(summary)
    }

    return attributes
}

private func buildStreamTextDoStreamTelemetryAttributes(
    telemetry: TelemetrySettings?,
    baseAttributes: Attributes,
    prompt: LanguageModelV3Prompt,
    tools: [LanguageModelV3Tool]?,
    toolChoice: LanguageModelV3ToolChoice?,
    settings: PreparedCallSettings,
    model: any LanguageModelV3
) -> [String: ResolvableAttributeValue?] {
    var attributes: [String: ResolvableAttributeValue?] = [:]

    for (key, value) in assembleOperationName(operationId: "ai.streamText.doStream", telemetry: telemetry) {
        attributes[key] = .value(value)
    }

    for (key, value) in baseAttributes {
        attributes[key] = .value(value)
    }

    attributes["ai.model.provider"] = .value(.string(model.provider))
    attributes["ai.model.id"] = .value(.string(model.modelId))

    attributes["ai.prompt.messages"] = .input {
        guard let serialized = try? stringifyForTelemetry(prompt) else {
            return nil
        }
        return .string(serialized)
    }

    attributes["ai.prompt.tools"] = .input {
        guard let encoded = encodeToolsForTelemetry(tools) else {
            return nil
        }
        return .string(encoded)
    }

    attributes["ai.prompt.toolChoice"] = .input {
        guard let encoded = encodeToolChoiceForTelemetry(toolChoice) else {
            return nil
        }
        return .string(encoded)
    }

    attributes["gen_ai.system"] = .value(.string(model.provider))
    attributes["gen_ai.request.model"] = .value(.string(model.modelId))

    if let frequencyPenalty = settings.frequencyPenalty {
        attributes["gen_ai.request.frequency_penalty"] = .value(.double(frequencyPenalty))
    }
    if let maxTokens = settings.maxOutputTokens {
        attributes["gen_ai.request.max_tokens"] = .value(.int(maxTokens))
    }
    if let presencePenalty = settings.presencePenalty {
        attributes["gen_ai.request.presence_penalty"] = .value(.double(presencePenalty))
    }
    if let stopSequences = settings.stopSequences, !stopSequences.isEmpty {
        attributes["gen_ai.request.stop_sequences"] = .value(.stringArray(stopSequences))
    }
    if let temperature = settings.temperature {
        attributes["gen_ai.request.temperature"] = .value(.double(temperature))
    }
    if let topK = settings.topK {
        attributes["gen_ai.request.top_k"] = .value(.int(topK))
    }
    if let topP = settings.topP {
        attributes["gen_ai.request.top_p"] = .value(.double(topP))
    }

    return attributes
}

private func buildStreamTextRootTelemetryAttributes(
    telemetry: TelemetrySettings?,
    finishReason: FinishReason,
    finalStep: StepResult,
    totalUsage: LanguageModelUsage
) -> [String: ResolvableAttributeValue?] {
    var attributes: [String: ResolvableAttributeValue?] = [:]

    attributes["ai.response.finishReason"] = .value(.string(finishReason.rawValue))

    attributes["ai.response.text"] = .output {
        .string(finalStep.text)
    }

    if let toolCallsString = encodeToolCallsForTelemetry(finalStep.toolCalls) {
        attributes["ai.response.toolCalls"] = .output { .string(toolCallsString) }
    }

    if let providerMetadata = finalStep.providerMetadata,
       let metadataString = jsonString(from: providerMetadataToJSON(providerMetadata)) {
        attributes["ai.response.providerMetadata"] = .output { .string(metadataString) }
    }

    if let inputTokens = totalUsage.inputTokens {
        attributes["ai.usage.inputTokens"] = .value(.int(inputTokens))
    }
    if let outputTokens = totalUsage.outputTokens {
        attributes["ai.usage.outputTokens"] = .value(.int(outputTokens))
    }
    if let totalTokens = totalUsage.totalTokens {
        attributes["ai.usage.totalTokens"] = .value(.int(totalTokens))
    }
    if let reasoningTokens = totalUsage.reasoningTokens {
        attributes["ai.usage.reasoningTokens"] = .value(.int(reasoningTokens))
    }
    if let cachedInputTokens = totalUsage.cachedInputTokens {
        attributes["ai.usage.cachedInputTokens"] = .value(.int(cachedInputTokens))
    }

    attributes["gen_ai.response.finish_reasons"] = .value(.stringArray([finishReason.rawValue]))

    return attributes
}

private func encodeToolsForTelemetry(_ tools: [LanguageModelV3Tool]?) -> String? {
    guard let tools else { return nil }
    return jsonString(from: tools)
}

private func encodeToolChoiceForTelemetry(_ toolChoice: LanguageModelV3ToolChoice?) -> String? {
    guard let toolChoice else { return nil }
    return jsonString(from: toolChoice)
}

private func encodeToolCallsForTelemetry(_ toolCalls: [TypedToolCall]) -> String? {
    guard !toolCalls.isEmpty else { return nil }

    let encodedCalls: [JSONValue] = toolCalls.map { call in
        var object: [String: JSONValue] = [
            "toolCallId": .string(call.toolCallId),
            "toolName": .string(call.toolName),
            "input": call.input
        ]

        if let providerExecuted = call.providerExecuted {
            object["providerExecuted"] = .bool(providerExecuted)
        }

        if call.isDynamic {
            object["dynamic"] = .bool(true)
        }

        if let metadata = call.providerMetadata {
            object["providerMetadata"] = providerMetadataToJSON(metadata)
        }

        return .object(object)
    }

    return jsonString(from: .array(encodedCalls))
}

private func providerMetadataToJSON(_ metadata: ProviderMetadata) -> JSONValue {
    let nested = metadata.mapValues { JSONValue.object($0) }
    return .object(nested)
}

private func jsonString<T: Encodable>(from value: T) -> String? {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    guard let data = try? encoder.encode(value) else {
        return nil
    }
    return String(data: data, encoding: .utf8)
}

private func jsonString(from jsonValue: JSONValue) -> String? {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    guard let data = try? encoder.encode(jsonValue) else {
        return nil
    }
    return String(data: data, encoding: .utf8)
}

private func summarizePromptForTelemetry(
    system: String?,
    prompt: String?,
    messages: [ModelMessage]
) -> String? {
    var payload: [String: Any] = [:]

    if let system {
        payload["system"] = system
    }
    if let prompt {
        payload["prompt"] = prompt
    }

    payload["messagesRoles"] = messages.map { message -> String in
        switch message {
        case .system: return "system"
        case .user: return "user"
        case .assistant: return "assistant"
        case .tool: return "tool"
        }
    }
    payload["messagesCount"] = messages.count

    guard JSONSerialization.isValidJSONObject(payload),
          let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
        return nil
    }
    return String(data: data, encoding: .utf8)
}

private func resolvedAttributesFromValues(
    _ inputs: [String: ResolvableAttributeValue?]
) -> Attributes {
    var resolved: Attributes = [:]
    for (key, value) in inputs {
        if case let .value(attribute)? = value {
            resolved[key] = attribute
        }
    }
    return resolved
}

// MARK: - Overload: Prompt object

/// Starts a text stream from a `Prompt` value (system + prompt/messages),
/// matching the upstream ergonomics while using the full prompt conversion path.
///
/// - Parameters:
///   - model: The language model to use
///   - prompt: A prompt value containing system and content/messages
///   - experimentalTransform: Optional transforms
///   - stopWhen: Stop conditions to halt multi-step generation
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func streamText<OutputValue: Sendable, PartialOutputValue: Sendable>(
    model: LanguageModel,
    prompt: Prompt,
    tools: ToolSet? = nil,
    toolChoice: ToolChoice? = nil,
    providerOptions: ProviderOptions? = nil,
    experimentalActiveTools: [String]? = nil,
    activeTools: [String]? = nil,
    experimentalOutput output: SwiftAISDK.Output.Specification<OutputValue, PartialOutputValue>? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    experimentalApprove approve: (@Sendable (ToolApprovalRequestOutput) async -> ApprovalAction)? = nil,
    experimentalTransform transforms: [StreamTextTransform] = [],
    experimentalDownload download: DownloadFunction? = nil,
    experimentalRepairToolCall repairToolCall: ToolCallRepairFunction? = nil,
    prepareStep: PrepareStepFunction? = nil,
    experimentalContext: JSONValue? = nil,
    includeRawChunks: Bool = false,
    stopWhen stopConditions: [StopCondition] = [stepCountIs(1)],
    onChunk: StreamTextOnChunk? = nil,
    onStepFinish: StreamTextOnStepFinish? = nil,
    onFinish: StreamTextOnFinish? = nil,
    onAbort: StreamTextOnAbort? = nil,
    onError: StreamTextOnError? = nil,
    internalOptions _internal: StreamTextInternalOptions = StreamTextInternalOptions(),
    settings: CallSettings = CallSettings()
) throws -> DefaultStreamTextResult<OutputValue, PartialOutputValue> {
    let standardized = try standardizePrompt(prompt)
    return try streamText(
        model: model,
        system: standardized.system,
        messages: standardized.messages,
        tools: tools,
        toolChoice: toolChoice,
        providerOptions: providerOptions,
        experimentalActiveTools: experimentalActiveTools,
        activeTools: activeTools,
        experimentalOutput: output,
        experimentalTelemetry: telemetry,
        experimentalApprove: approve,
        experimentalTransform: transforms,
        experimentalDownload: download,
        experimentalRepairToolCall: repairToolCall,
        prepareStep: prepareStep,
        experimentalContext: experimentalContext,
        includeRawChunks: includeRawChunks,
        stopWhen: stopConditions,
        onChunk: onChunk,
        onStepFinish: onStepFinish,
        onFinish: onFinish,
        onAbort: onAbort,
        onError: onError,
        internalOptions: _internal,
        settings: settings
    )
}
