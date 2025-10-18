import AISDKProvider
import AISDKProviderUtils
import Foundation

// MARK: - Public API (Milestone 1)

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public typealias StreamTextOnChunk = @Sendable (TextStreamPart) -> Void
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public typealias StreamTextOnError = @Sendable (Error) -> Void
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public typealias StreamTextOnStepFinish = @Sendable (StepResult) -> Void
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public typealias StreamTextOnFinish = @Sendable (
    _ finalStep: StepResult,
    _ steps: [StepResult],
    _ totalUsage: LanguageModelUsage,
    _ finishReason: FinishReason
) -> Void
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public typealias StreamTextOnAbort = @Sendable (_ steps: [StepResult]) -> Void

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
    experimentalOutput output: Output.Specification<OutputValue, PartialOutputValue>? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    experimentalApprove approve: (@Sendable (ToolApprovalRequestOutput) async -> ApprovalAction)? = nil,
    experimentalTransform transforms: [StreamTextTransform] = [],
    experimentalDownload download: DownloadFunction? = nil,
    experimentalRepairToolCall repairToolCall: ToolCallRepairFunction? = nil,
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
    private let totalUsagePromise = DelayedPromise<LanguageModelUsage>()
    private let finishReasonPromise = DelayedPromise<FinishReason>()
    private let stepsPromise = DelayedPromise<[StepResult]>()
    private var observerTask: Task<Void, Never>? = nil
    private var onFinishTask: Task<Void, Never>? = nil

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
        configuration: StreamTextActorConfiguration,
        onChunk: StreamTextOnChunk?,
        onStepFinish: StreamTextOnStepFinish? = nil,
        onFinish: StreamTextOnFinish? = nil,
        onAbort: StreamTextOnAbort? = nil,
        onError: StreamTextOnError? = nil
    ) {
        self.stopConditions = stopConditions.isEmpty ? [stepCountIs(1)] : stopConditions
        self.actor = StreamTextActor(
            source: providerStream,
            model: model,
            initialMessages: initialMessages,
            system: system,
            stopConditions: self.stopConditions,
            tools: tools,
            approvalResolver: approve,
            experimentalApprovalContext: nil,
            configuration: configuration,
            totalUsagePromise: totalUsagePromise,
            finishReasonPromise: finishReasonPromise,
            stepsPromise: stepsPromise
        )
        self.transforms = transforms
        self.tools = tools
        _ = self.actor  // keep strong reference

        if onChunk != nil || onStepFinish != nil || onAbort != nil || onError != nil || onFinish != nil {
            self.observerTask = Task { [actor] in
                let stream = await actor.fullStream()
                do {
                    for try await part in stream {
                        if let onChunk {
                            switch part {
                            case .textDelta, .reasoningDelta, .source, .toolCall,
                                 .toolInputStart, .toolInputDelta, .toolResult, .raw:
                                onChunk(part)
                            default:
                                break
                            }
                        }
                        if let onStepFinish, case .finishStep = part, let last = await actor.getLastStep() {
                            onStepFinish(last)
                        }
                        if let onAbort, case .abort = part {
                            onAbort(await actor.getRecordedSteps())
                        }
                        if let onFinish, case .finish = part {
                            // Promises already resolved before `.finish` is published by the actor.
                            // Await them here to deliver `onFinish` deterministically from the stream observer.
                            do {
                                async let reason = finishReasonPromise.task.value
                                async let usage = totalUsagePromise.task.value
                                async let stepList = stepsPromise.task.value
                                let (r, u, s) = try await (reason, usage, stepList)
                                if let final = s.last { onFinish(final, s, u, r) }
                            } catch {
                                // If promises failed, surface via onError if present.
                                if let onError { onError(error) }
                            }
                        }
                    }
                } catch {
                    if let onError { onError(error) }
                }
            }
        }

        if let onFinish {
            self.onFinishTask = Task {
                do {
                    async let reason = finishReasonPromise.task.value
                    async let usage = totalUsagePromise.task.value
                    async let stepList = stepsPromise.task.value
                    let (r, u, s) = try await (reason, usage, stepList)
                    if let final = s.last { onFinish(final, s, u, r) }
                } catch { }
            }
        }
    }

    // Internal: forward provider request info into actor state
    func _setRequestInfo(_ info: LanguageModelV3RequestInfo?) async {
        await actor.setInitialRequest(info)
    }

    // Internal: install provider cancel callback so actor can cancel upstream if it finishes earlier
    func _setProviderCancel(_ cancel: @escaping @Sendable () -> Void) async {
        await actor.setOnTerminate(cancel)
    }

    func _appendInitialResponseMessages(_ messages: [ResponseMessage]) async {
        await actor.appendInitialResponseMessages(messages)
    }

    func _publishPreludeEvents(_ parts: [TextStreamPart]) async {
        await actor.publishPreludeEvents(parts)
    }

    public var textStream: AsyncThrowingStream<String, Error> {
        // Bridge async actor method into a non-async property via forwarding stream
        AsyncThrowingStream { continuation in
            let task = Task {
                let inner = await actor.textStream()
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
    }

    public var fullStream: AsyncThrowingStream<TextStreamPart, Error> {
        // Build base full stream from actor
        let baseStream = AsyncThrowingStream<TextStreamPart, Error> { continuation in
            let task = Task {
                let inner = await actor.fullStream()
                do {
                    for try await value in inner { continuation.yield(value) }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }

        // Convert to AsyncIterableStream for transforms
        let iterable = createAsyncIterableStream(source: baseStream)

        // Build transform pipeline. Approval is handled inside the actor, so only caller-supplied transforms run here.
        let pipeline = transforms

        let options = StreamTextTransformOptions(
            tools: tools,
            stopStream: { Task { await self.actor.requestStop() } }
        )
        let transformedIterable = pipeline.reduce(iterable) { acc, t in t(acc, options) }
        let transformedStream = AsyncThrowingStream<TextStreamPart, Error> { continuation in
            let task = Task {
                var iterator = transformedIterable.makeAsyncIterator()
                do {
                    while let part = try await iterator.next() {
                        continuation.yield(part)
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }

        return transformedStream
    }

    // MARK: - Convenience collectors (useful for tests and simple consumers)

    /// Collects all text deltas from `textStream` into a single concatenated string.
    public func collectText() async throws -> String {
        var buffer = ""
        for try await chunk in textStream { buffer.append(chunk) }
        return buffer
    }

    /// Waits for stream completion and returns the final tuple (finalStep, steps, totalUsage, finishReason).
    /// Promises are awaited directly to avoid any ordering races with `.finish` event delivery.
    public func waitForFinish() async throws -> (
        finalStep: StepResult,
        steps: [StepResult],
        totalUsage: LanguageModelUsage,
        finishReason: FinishReason
    ) {
        async let reason = finishReasonPromise.task.value
        async let usage = totalUsagePromise.task.value
        async let stepList = stepsPromise.task.value
        let (r, u, s) = try await (reason, usage, stepList)
        guard let last = s.last else { throw NoOutputGeneratedError() }
        return (last, s, u, r)
    }

    // MARK: - Accessors (Milestone 3)

    private var finalStep: StepResult {
        get async throws {
            let steps = try await stepsPromise.task.value
            guard let last = steps.last else { throw NoOutputGeneratedError() }
            return last
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
        get async throws { try await finishReasonPromise.task.value }
    }

    public var usage: LanguageModelUsage {
        get async throws { try await finalStep.usage }
    }

    public var totalUsage: LanguageModelUsage {
        get async throws { try await totalUsagePromise.task.value }
    }

    public var warnings: [CallWarning]? {
        get async throws { try await finalStep.warnings }
    }

    public var steps: [StepResult] {
        get async throws { try await stepsPromise.task.value }
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

// MARK: - Responses (minimal)

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

// MARK: - UI Message Stream (minimal)

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

        // Start from plain text stream and transform into UI chunks
        let base = transformTextToUIMessageStream(stream: textStream)

        // Handle finish, id injection, and final onFinish
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

    // MARK: - Control

    /// Requests to stop the underlying stream as soon as possible.
    /// This mirrors the upstream `stopStream` hook and is useful for
    /// transforms or consumers that want to abort further steps.
    public func stop() {
        // Do not cancel observer/onFinish tasks here — they must remain alive
        // to deliver `.abort` and `.finish` callbacks deterministically.
        Task { await actor.requestStop() }
    }

    // MARK: - Convenience

    /// Returns the full stream as an AsyncIterableStream wrapper, which is sometimes
    /// more ergonomic for consumers that want a cancellable async sequence abstraction.
    public var fullStreamIterable: AsyncIterableStream<TextStreamPart> {
        createAsyncIterableStream(source: fullStream)
    }

    /// Returns the text delta stream wrapped as `AsyncIterableStream`.
    public var textStreamIterable: AsyncIterableStream<String> {
        createAsyncIterableStream(source: textStream)
    }

    /// Reads the entire `textStream` and returns the concatenated text.
    /// This is a convenience for simple, non-streaming use-cases.
    public func readAllText() async throws -> String {
        var buffer = ""
        for try await delta in textStream {
            buffer += delta
        }
        return buffer
    }

    /// Collects the entire `fullStream` into an in-memory array.
    /// Useful for tests or debugging to assert on precise event ordering.
    public func collectFullStream() async throws -> [TextStreamPart] {
        var parts: [TextStreamPart] = []
        for try await part in fullStream {
            parts.append(part)
        }
        return parts
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
    experimentalOutput output: Output.Specification<OutputValue, PartialOutputValue>? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    experimentalApprove approve: (@Sendable (ToolApprovalRequestOutput) async -> ApprovalAction)? = nil,
    experimentalTransform transforms: [StreamTextTransform] = [],
    experimentalDownload download: DownloadFunction? = nil,
    experimentalRepairToolCall repairToolCall: ToolCallRepairFunction? = nil,
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
    // TODO: integrate telemetry/output/repairToolCall/experimentalContext parity.
    _ = telemetry
    _ = repairToolCall
    _ = experimentalContext

    _ = _internal
    let resolvedModel = try resolveLanguageModel(modelArg)
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
        model: TelemetryModelInfo(modelId: resolvedModel.modelId, provider: resolvedModel.provider),
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
        baseTelemetryAttributes: baseTelemetryAttributes
    )

    // Bridge provider async stream acquisition without blocking the caller.
    let (bridgeStream, continuation) = AsyncThrowingStream.makeStream(
        of: LanguageModelV3StreamPart.self
    )

    let result = DefaultStreamTextResult<OutputValue, PartialOutputValue>(
        baseModel: modelArg,
        model: resolvedModel,
        providerStream: bridgeStream,
        transforms: transforms,
        stopConditions: stopConditions,
        initialMessages: normalizedMessages,
        system: standardizedPrompt.system,
        tools: tools,
        approve: approve,
        configuration: actorConfig,
        onChunk: onChunk,
        onStepFinish: onStepFinish,
        onFinish: onFinish,
        onAbort: onAbort,
        onError: onError
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
                        await result._publishPreludeEvents([.toolOutputDenied(deniedEvent)])

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
                                        await result._publishPreludeEvents([.toolResult(typed)])
                                    }
                                }
                            )

                            guard let output else { continue }

                            switch output {
                            case .result(let typed):
                                await result._publishPreludeEvents([.toolResult(typed)])
                            case .error(let error):
                                await result._publishPreludeEvents([.toolError(error)])
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

                let promptForProvider = StandardizedPrompt(
                    system: standardizedPrompt.system,
                    messages: conversationMessages
                )

                let supported = try await resolvedModel.supportedUrls
                let lmPrompt = try await convertToLanguageModelPrompt(
                    prompt: promptForProvider,
                    supportedUrls: supported,
                    download: download
                )

                let toolPreparation = try await prepareToolsAndToolChoice(
                    tools: tools,
                    toolChoice: toolChoice,
                    activeTools: effectiveActiveTools
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

                let providerResult = try await actorConfig.preparedRetries.retry.call {
                    try await resolvedModel.doStream(options: callOptions)
                }

                await result._setRequestInfo(providerResult.request)
                for try await part in providerResult.stream {
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
            } catch {
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
    experimentalOutput output: Output.Specification<OutputValue, PartialOutputValue>? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    experimentalApprove approve: (@Sendable (ToolApprovalRequestOutput) async -> ApprovalAction)? = nil,
    experimentalTransform transforms: [StreamTextTransform] = [],
    experimentalDownload download: DownloadFunction? = nil,
    experimentalRepairToolCall repairToolCall: ToolCallRepairFunction? = nil,
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
