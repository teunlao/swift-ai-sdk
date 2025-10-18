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

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func streamTextV2<OutputValue: Sendable, PartialOutputValue: Sendable>(
    model modelArg: LanguageModel,
    prompt: String,
    experimentalTransform transforms: [StreamTextTransform] = [],
    stopWhen stopConditions: [StopCondition] = [stepCountIs(1)],
    onChunk: StreamTextOnChunk? = nil,
    onStepFinish: StreamTextOnStepFinish? = nil,
    onFinish: StreamTextOnFinish? = nil,
    onAbort: StreamTextOnAbort? = nil,
    onError: StreamTextOnError? = nil
) throws -> DefaultStreamTextV2Result<OutputValue, PartialOutputValue> {
    // Resolve LanguageModel to a v3 model; for milestone 1 only v3 path is supported.
    _ = try resolveLanguageModel(modelArg)

    return try streamTextV2(
        model: modelArg,
        system: nil,
        messages: [.user(UserModelMessage(content: .text(prompt), providerOptions: nil))],
        experimentalTransform: transforms,
        stopWhen: stopConditions,
        onChunk: onChunk,
        onStepFinish: onStepFinish,
        onFinish: onFinish,
        onAbort: onAbort,
        onError: onError
    )
}

// MARK: - Result Type (Milestone 1)

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public final class DefaultStreamTextV2Result<OutputValue: Sendable, PartialOutputValue: Sendable>:
    @unchecked Sendable
{
    public typealias Output = OutputValue
    public typealias PartialOutput = PartialOutputValue

    private let actor: StreamTextV2Actor
    private let transforms: [StreamTextTransform]
    private let stopConditions: [StopCondition]
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
        onChunk: StreamTextOnChunk?,
        onStepFinish: StreamTextOnStepFinish? = nil,
        onFinish: StreamTextOnFinish? = nil,
        onAbort: StreamTextOnAbort? = nil,
        onError: StreamTextOnError? = nil
    ) {
        self.stopConditions = stopConditions.isEmpty ? [stepCountIs(1)] : stopConditions
        self.actor = StreamTextV2Actor(
            source: providerStream,
            model: model,
            initialMessages: initialMessages,
            system: system,
            stopConditions: self.stopConditions,
            totalUsagePromise: totalUsagePromise,
            finishReasonPromise: finishReasonPromise,
            stepsPromise: stepsPromise
        )
        self.transforms = transforms
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
        let options = StreamTextTransformOptions(
            tools: nil,
            stopStream: { Task { await self.actor.requestStop() } }
        )
        let transformed = transforms.reduce(iterable) { acc, t in t(acc, options) }

        // Convert back to AsyncThrowingStream for public API
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await part in transformed { continuation.yield(part) }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
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

    // MARK: - Responses (V2 minimal)

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

    // MARK: - UI Message Stream (minimal V2)

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
                    domain: "ai.streamTextV2",
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

// MARK: - Helpers (none needed for milestone 1)

// MARK: - Overload: system/messages prompt (Upstream parity)

/// Creates a V2 text stream using an initial system/message prompt, matching the upstream stream-text.ts
/// surface. This overload allows callers to pass structured messages instead of a simple text prompt.
///
/// - Parameters:
///   - model: The language model to use.
///   - system: Optional system instruction to prepend to the prompt.
///   - messages: Initial conversation messages (required; must be non-empty).
///   - experimentalTransform: Transforms applied to the full stream (map/tee semantics).
///   - stopWhen: Stop conditions to halt multi-step generation.
///
/// - Returns: DefaultStreamTextV2Result exposing text/full/UI streams and accessors.
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func streamTextV2<OutputValue: Sendable, PartialOutputValue: Sendable>(
    model modelArg: LanguageModel,
    system: String?,
    messages initialMessages: [ModelMessage],
    experimentalTransform transforms: [StreamTextTransform] = [],
    stopWhen stopConditions: [StopCondition] = [stepCountIs(1)],
    onChunk: StreamTextOnChunk? = nil,
    onStepFinish: StreamTextOnStepFinish? = nil,
    onFinish: StreamTextOnFinish? = nil,
    onAbort: StreamTextOnAbort? = nil,
    onError: StreamTextOnError? = nil
) throws -> DefaultStreamTextV2Result<OutputValue, PartialOutputValue> {
    // Resolve LanguageModel to a v3 model.
    let resolved: any LanguageModelV3 = try resolveLanguageModel(modelArg)

    // Bridge provider async stream acquisition without blocking the caller.
    // We will build the provider prompt inside the task using supportedUrls
    // and the full `convertToLanguageModelPrompt` pipeline.
    let (bridgeStream, continuation) = AsyncThrowingStream.makeStream(
        of: LanguageModelV3StreamPart.self)

    let result = DefaultStreamTextV2Result<OutputValue, PartialOutputValue>(
        baseModel: modelArg,
        model: resolved,
        providerStream: bridgeStream,
        transforms: transforms,
        stopConditions: stopConditions,
        initialMessages: initialMessages,
        system: system,
        onChunk: onChunk,
        onStepFinish: onStepFinish,
        onFinish: onFinish,
        onAbort: onAbort,
        onError: onError
    )

    // Start producer task to fetch provider stream and forward its parts.
    let providerTask = Task {
        do {
            // Build the provider prompt via full conversion path (upstream parity)
            let standardized = StandardizedPrompt(system: system, messages: initialMessages)
            let supported = try await resolved.supportedUrls
            let lmPrompt = try await convertToLanguageModelPrompt(
                prompt: standardized,
                supportedUrls: supported,
                download: nil
            )
            let options = LanguageModelV3CallOptions(prompt: lmPrompt)

            let providerResult = try await resolved.doStream(options: options)
            await result._setRequestInfo(providerResult.request)
            for try await part in providerResult.stream {
                continuation.yield(part)
            }
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }
    continuation.onTermination = { _ in providerTask.cancel() }

    // Allow actor to cancel provider task on early finish
    Task { await result._setProviderCancel { providerTask.cancel() } }

    return result
}
// MARK: - Overload: Prompt object

/// Starts a V2 text stream from a `Prompt` value (system + prompt/messages),
/// matching the upstream ergonomics while using the full prompt conversion path.
///
/// - Parameters:
///   - model: The language model to use
///   - prompt: A prompt value containing system and content/messages
///   - experimentalTransform: Optional transforms
///   - stopWhen: Stop conditions to halt multi-step generation
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func streamTextV2<OutputValue: Sendable, PartialOutputValue: Sendable>(
    model: LanguageModel,
    prompt: Prompt,
    experimentalTransform transforms: [StreamTextTransform] = [],
    stopWhen stopConditions: [StopCondition] = [stepCountIs(1)],
    onChunk: StreamTextOnChunk? = nil,
    onStepFinish: StreamTextOnStepFinish? = nil,
    onFinish: StreamTextOnFinish? = nil,
    onAbort: StreamTextOnAbort? = nil,
    onError: StreamTextOnError? = nil
) throws -> DefaultStreamTextV2Result<OutputValue, PartialOutputValue> {
    let standardized = try standardizePrompt(prompt)
    return try streamTextV2(
        model: model,
        system: standardized.system,
        messages: standardized.messages,
        experimentalTransform: transforms,
        stopWhen: stopConditions,
        onChunk: onChunk,
        onStepFinish: onStepFinish,
        onFinish: onFinish,
        onAbort: onAbort,
        onError: onError
    )
}
