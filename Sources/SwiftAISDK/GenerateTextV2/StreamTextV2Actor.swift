import AISDKProvider
import AISDKProviderUtils
import Foundation

actor StreamTextV2Actor {
    private let source: AsyncThrowingStream<LanguageModelV3StreamPart, Error>
    private let model: any LanguageModelV3
    private var initialMessages: [ModelMessage]
    private let initialSystem: String?
    private let stopConditions: [StopCondition]

    private let textBroadcaster = AsyncStreamBroadcaster<String>()
    private let fullBroadcaster = AsyncStreamBroadcaster<TextStreamPart>()

    private var started = false
    // Session-level framing: `.start` must be emitted exactly once per session
    private var framingEmitted = false
    private var terminated = false
    private var onTerminate: (@Sendable () -> Void)? = nil

    private var capturedWarnings: [LanguageModelV3CallWarning] = []
    private var capturedResponseId: String?
    private var capturedModelId: String?
    private var capturedTimestamp: Date?
    private var openTextIds = Set<String>()
    private var openReasoningIds = Set<String>()
    private var aggregatedText: String = ""
    private var recordedRequest: LanguageModelRequestMetadata = LanguageModelRequestMetadata()
    private var recordedSteps: [StepResult] = []
    private var accumulatedUsage: LanguageModelUsage = LanguageModelUsage()
    private var recordedFinishReason: FinishReason? = nil
    private var externalStopRequested = false
    // Tool tracking for the current step
    private var activeToolInputs: [String: JSONValue] = [:] // toolCallId -> parsed input
    private var activeToolNames: [String: String] = [:]     // toolCallId -> tool name

    private let totalUsagePromise: DelayedPromise<LanguageModelUsage>
    private let finishReasonPromise: DelayedPromise<FinishReason>
    private let stepsPromise: DelayedPromise<[StepResult]>

    init(
        source: AsyncThrowingStream<LanguageModelV3StreamPart, Error>,
        model: any LanguageModelV3,
        initialMessages: [ModelMessage],
        system: String?,
        stopConditions: [StopCondition],
        totalUsagePromise: DelayedPromise<LanguageModelUsage>,
        finishReasonPromise: DelayedPromise<FinishReason>,
        stepsPromise: DelayedPromise<[StepResult]>
    ) {
        self.source = source
        self.model = model
        self.initialMessages = initialMessages
        self.initialSystem = system
        self.stopConditions = stopConditions
        self.totalUsagePromise = totalUsagePromise
        self.finishReasonPromise = finishReasonPromise
        self.stepsPromise = stepsPromise
    }

    func textStream() async -> AsyncThrowingStream<String, Error> {
        await ensureStarted()
        return await textBroadcaster.register()
    }

    func fullStream() async -> AsyncThrowingStream<TextStreamPart, Error> {
        await ensureStarted()
        return await fullBroadcaster.register()
    }

    // External request to stop the current and subsequent provider streams.
    // This mirrors the upstream `stopStream` hook used by transforms.
    func requestStop() async {
        externalStopRequested = true
    }

    private func ensureStarted() async {
        guard !started else { return }
        started = true
        Task { [weak self] in await self?.run() }
    }

    private func run() async {
        do {
            try await consumeProviderStream(stream: source, emitStartStep: true)
            while !terminated {
                if externalStopRequested { break }
                let shouldStop = await isStopConditionMet(
                    stopConditions: stopConditions, steps: recordedSteps)
                if shouldStop { break }
                guard let last = recordedSteps.last else { break }
                // Build next step prompt: initial messages + assistant response
                let responseMessages = convertModelMessagesToResponseMessagesV2(
                    toResponseMessages(content: last.content, tools: nil)
                )
                let nextMessages =
                    initialMessages + convertResponseMessagesToModelMessagesV2(responseMessages)
                let lmPrompt = try await buildLanguageModelPrompt(messages: nextMessages)
                let options = LanguageModelV3CallOptions(prompt: lmPrompt)
                let result = try await model.doStream(options: options)
                setInitialRequest(result.request)
                try await consumeProviderStream(stream: result.stream, emitStartStep: true)
            }
            await finishAll(response: nil, usage: nil, finishReason: nil, providerMetadata: nil)
        } catch is CancellationError {
            await finishAll(response: nil, usage: nil, finishReason: nil, providerMetadata: nil)
        } catch {
            await finishAll(
                response: nil, usage: nil, finishReason: nil, providerMetadata: nil, error: error)
        }
    }

    // MARK: - Prompt Construction (Upstream parity)

    /// Builds a provider prompt using the full conversion pipeline:
    /// - Captures the initial system prompt
    /// - Uses `convertToLanguageModelPrompt` to map content parts and assets
    /// - Respects provider `supportedUrls` (URLs left as references when supported)
    /// - Parameter messages: Conversation messages to include (system is injected automatically)
    /// - Returns: A LanguageModelV3Prompt ready for `doStream`
    private func buildLanguageModelPrompt(messages: [ModelMessage]) async throws -> LanguageModelV3Prompt {
        let standardized = StandardizedPrompt(system: initialSystem, messages: messages)
        let supported = try await model.supportedUrls
        let prompt = try await convertToLanguageModelPrompt(
            prompt: standardized,
            supportedUrls: supported,
            download: nil
        )
        return prompt
    }

    private func consumeProviderStream(
        stream: AsyncThrowingStream<LanguageModelV3StreamPart, Error>,
        emitStartStep: Bool
    ) async throws {
        // Reset per-step state
        aggregatedText = ""
        capturedWarnings = []
        openTextIds.removeAll()
        openReasoningIds.removeAll()
        activeToolInputs.removeAll()
        activeToolNames.removeAll()
        if externalStopRequested { return }

        // Per-step framing is emitted after we have seen `.streamStart(warnings)`
        // to ensure warnings are populated. If provider skips `.streamStart`,
        // we will emit framing before the first content part with empty warnings.
        let shouldEmitStartStep = emitStartStep
        var didEmitStartStep = false
        var sawStreamStart = false
        for try await part in stream {
            if externalStopRequested { break }
            switch part {
            case .streamStart(let warnings):
                capturedWarnings = warnings
                sawStreamStart = true
                if !framingEmitted {
                    framingEmitted = true
                    await fullBroadcaster.send(.start)
                }
                if shouldEmitStartStep && !didEmitStartStep {
                    didEmitStartStep = true
                    await fullBroadcaster.send(
                        .startStep(request: recordedRequest, warnings: warnings)
                    )
                }
            case let .responseMetadata(id, modelId, timestamp):
                capturedResponseId = id ?? capturedResponseId
                capturedModelId = modelId ?? capturedModelId
                capturedTimestamp = timestamp ?? capturedTimestamp
            case let .textStart(id, providerMetadata):
                if !didEmitStartStep {
                    if !framingEmitted {
                        framingEmitted = true
                        await fullBroadcaster.send(.start)
                    }
                    if shouldEmitStartStep {
                        didEmitStartStep = true
                        await fullBroadcaster.send(
                            .startStep(
                                request: recordedRequest,
                                warnings: sawStreamStart ? capturedWarnings : []
                            )
                        )
                    }
                }
                openTextIds.insert(id)
                await fullBroadcaster.send(.textStart(id: id, providerMetadata: providerMetadata))
            case let .textDelta(id, delta, providerMetadata):
                if !didEmitStartStep {
                    if !framingEmitted {
                        framingEmitted = true
                        await fullBroadcaster.send(.start)
                    }
                    if shouldEmitStartStep {
                        didEmitStartStep = true
                        await fullBroadcaster.send(
                            .startStep(
                                request: recordedRequest,
                                warnings: sawStreamStart ? capturedWarnings : []
                            )
                        )
                    }
                }
                await textBroadcaster.send(delta)
                if !openTextIds.contains(id) {
                    openTextIds.insert(id)
                    await fullBroadcaster.send(
                        .textStart(id: id, providerMetadata: providerMetadata))
                }
                await fullBroadcaster.send(
                    .textDelta(id: id, text: delta, providerMetadata: providerMetadata))
                aggregatedText.append(delta)
            case let .textEnd(id, providerMetadata):
                if !didEmitStartStep {
                    if !framingEmitted {
                        framingEmitted = true
                        await fullBroadcaster.send(.start)
                    }
                    if shouldEmitStartStep {
                        didEmitStartStep = true
                        await fullBroadcaster.send(
                            .startStep(
                                request: recordedRequest,
                                warnings: sawStreamStart ? capturedWarnings : []
                            )
                        )
                    }
                }
                openTextIds.remove(id)
                await fullBroadcaster.send(.textEnd(id: id, providerMetadata: providerMetadata))
            case let .reasoningStart(id, providerMetadata):
                if !didEmitStartStep {
                    if !framingEmitted {
                        framingEmitted = true
                        await fullBroadcaster.send(.start)
                    }
                    if shouldEmitStartStep {
                        didEmitStartStep = true
                        await fullBroadcaster.send(
                            .startStep(
                                request: recordedRequest,
                                warnings: sawStreamStart ? capturedWarnings : []
                            )
                        )
                    }
                }
                openReasoningIds.insert(id)
                await fullBroadcaster.send(
                    .reasoningStart(id: id, providerMetadata: providerMetadata)
                )
            case let .reasoningDelta(id, delta, providerMetadata):
                if !didEmitStartStep {
                    if !framingEmitted {
                        framingEmitted = true
                        await fullBroadcaster.send(.start)
                    }
                    if shouldEmitStartStep {
                        didEmitStartStep = true
                        await fullBroadcaster.send(
                            .startStep(
                                request: recordedRequest,
                                warnings: sawStreamStart ? capturedWarnings : []
                            )
                        )
                    }
                }
                if !openReasoningIds.contains(id) {
                    openReasoningIds.insert(id)
                    await fullBroadcaster.send(
                        .reasoningStart(id: id, providerMetadata: providerMetadata)
                    )
                }
                await fullBroadcaster.send(
                    .reasoningDelta(id: id, text: delta, providerMetadata: providerMetadata)
                )
            case let .reasoningEnd(id, providerMetadata):
                if !didEmitStartStep {
                    if !framingEmitted {
                        framingEmitted = true
                        await fullBroadcaster.send(.start)
                    }
                    if shouldEmitStartStep {
                        didEmitStartStep = true
                        await fullBroadcaster.send(
                            .startStep(
                                request: recordedRequest,
                                warnings: sawStreamStart ? capturedWarnings : []
                            )
                        )
                    }
                }
                openReasoningIds.remove(id)
                await fullBroadcaster.send(
                    .reasoningEnd(id: id, providerMetadata: providerMetadata)
                )
            case let .toolInputStart(id, toolName, providerMetadata, providerExecuted):
                if !didEmitStartStep {
                    if !framingEmitted {
                        framingEmitted = true
                        await fullBroadcaster.send(.start)
                    }
                    if shouldEmitStartStep {
                        didEmitStartStep = true
                        await fullBroadcaster.send(
                            .startStep(
                                request: recordedRequest,
                                warnings: sawStreamStart ? capturedWarnings : []
                            )
                        )
                    }
                }
                await fullBroadcaster.send(
                    .toolInputStart(
                        id: id, toolName: toolName, providerMetadata: providerMetadata,
                        providerExecuted: providerExecuted, dynamic: nil))
            case let .toolInputDelta(id, delta, providerMetadata):
                if !didEmitStartStep {
                    if !framingEmitted {
                        framingEmitted = true
                        await fullBroadcaster.send(.start)
                    }
                    if shouldEmitStartStep {
                        didEmitStartStep = true
                        await fullBroadcaster.send(
                            .startStep(
                                request: recordedRequest,
                                warnings: sawStreamStart ? capturedWarnings : []
                            )
                        )
                    }
                }
                await fullBroadcaster.send(
                    .toolInputDelta(id: id, delta: delta, providerMetadata: providerMetadata))
            case let .toolInputEnd(id, providerMetadata):
                if !didEmitStartStep {
                    if !framingEmitted {
                        framingEmitted = true
                        await fullBroadcaster.send(.start)
                    }
                    if shouldEmitStartStep {
                        didEmitStartStep = true
                        await fullBroadcaster.send(
                            .startStep(
                                request: recordedRequest,
                                warnings: sawStreamStart ? capturedWarnings : []
                            )
                        )
                    }
                }
                await fullBroadcaster.send(
                    .toolInputEnd(id: id, providerMetadata: providerMetadata))
            case .toolCall(let call):
                // Parse JSON input (best-effort); fall back to raw string
                let parsed = await safeParseJSON(ParseJSONOptions(text: call.input))
                let inputValue: JSONValue
                switch parsed {
                case .success(let v, _): inputValue = v
                case .failure:
                    inputValue = .string(call.input)
                }
                activeToolInputs[call.toolCallId] = inputValue
                activeToolNames[call.toolCallId] = call.toolName
                let typed = TypedToolCall.dynamic(
                    DynamicToolCall(
                        toolCallId: call.toolCallId,
                        toolName: call.toolName,
                        input: inputValue,
                        providerExecuted: call.providerExecuted,
                        providerMetadata: call.providerMetadata,
                        invalid: false,
                        error: nil
                    )
                )
                await fullBroadcaster.send(.toolCall(typed))
            case .toolResult(let result):
                let input = activeToolInputs[result.toolCallId] ?? .null
                let typed: TypedToolResult = .dynamic(
                    DynamicToolResult(
                        toolCallId: result.toolCallId,
                        toolName: result.toolName,
                        input: input,
                        output: result.result,
                        providerExecuted: result.providerExecuted,
                        preliminary: result.preliminary,
                        providerMetadata: result.providerMetadata
                    )
                )
                await fullBroadcaster.send(.toolResult(typed))
            case let .finish(finishReason, usage, providerMetadata):
                for id in openTextIds {
                    await fullBroadcaster.send(.textEnd(id: id, providerMetadata: nil))
                }
                openTextIds.removeAll()
                for id in openReasoningIds {
                    await fullBroadcaster.send(.reasoningEnd(id: id, providerMetadata: nil))
                }
                openReasoningIds.removeAll()
                let response = LanguageModelResponseMetadata(
                    id: capturedResponseId ?? "unknown",
                    timestamp: capturedTimestamp ?? Date(timeIntervalSince1970: 0),
                    modelId: capturedModelId ?? "unknown",
                    headers: nil
                )
                await fullBroadcaster.send(
                    .finishStep(
                        response: response, usage: usage, finishReason: finishReason,
                        providerMetadata: providerMetadata))
                let contentParts: [ContentPart] =
                    aggregatedText.isEmpty
                    ? [] : [.text(text: aggregatedText, providerMetadata: nil)]
                let modelMessages = toResponseMessages(content: contentParts, tools: nil)
                let responseMessages = convertModelMessagesToResponseMessagesV2(modelMessages)
                let stepResult = DefaultStepResult(
                    content: contentParts, finishReason: finishReason, usage: usage,
                    warnings: capturedWarnings, request: recordedRequest,
                    response: StepResultResponse(
                        from: response, messages: responseMessages, body: nil),
                    providerMetadata: providerMetadata)
                recordedSteps.append(stepResult)
                accumulatedUsage = addLanguageModelUsage(accumulatedUsage, usage)
                // Do not resolve `finishReasonPromise` here; session-level finish
                // will resolve it with the last step's reason to mirror upstream.
                // Keep the last seen reason in `recordedFinishReason`.
                recordedFinishReason = finishReason
            case .raw(let raw):
                if !didEmitStartStep {
                    if !framingEmitted {
                        framingEmitted = true
                        await fullBroadcaster.send(.start)
                    }
                    if shouldEmitStartStep {
                        didEmitStartStep = true
                        await fullBroadcaster.send(
                            .startStep(
                                request: recordedRequest,
                                warnings: sawStreamStart ? capturedWarnings : []
                            )
                        )
                    }
                }
                await fullBroadcaster.send(.raw(rawValue: raw))
            case .error(let err):
                // Provider surfaced an error as a stream part. Terminate session
                // through the single terminal path to keep promises/broadcasters consistent.
                await finishAll(
                    response: nil,
                    usage: nil,
                    finishReason: nil,
                    providerMetadata: nil,
                    error: StreamTextV2Error.providerError(err)
                )
                return
            default:
                break
            }
        }
    }

    private func finishAll(
        response: LanguageModelResponseMetadata?,
        usage: LanguageModelUsage?,
        finishReason: FinishReason?,
        providerMetadata: ProviderMetadata?,
        error: Error? = nil
    ) async {
        guard !terminated else { return }
        terminated = true
        if let error {
            // Error path: finish streams with the error, do not emit terminal `.finish` part.
            await textBroadcaster.finish(error: error)
            await fullBroadcaster.finish(error: error)
        } else {
            // Success path: optionally emit `.abort` if an external stop was requested,
            // then emit session-level `.finish` before closing the broadcasters.
            if externalStopRequested {
                await fullBroadcaster.send(.abort)
            }
            let finalReason = recordedFinishReason ?? .unknown
            await fullBroadcaster.send(
                .finish(finishReason: finalReason, totalUsage: accumulatedUsage)
            )
            await textBroadcaster.finish()
            await fullBroadcaster.finish()
        }
        if let usage, let finishReason, let resp = response {
            let contentParts: [ContentPart] =
                aggregatedText.isEmpty ? [] : [.text(text: aggregatedText, providerMetadata: nil)]
            let modelMessages = toResponseMessages(content: contentParts, tools: nil)
            let responseMessages = convertModelMessagesToResponseMessagesV2(modelMessages)
            let stepResult = DefaultStepResult(
                content: contentParts, finishReason: finishReason, usage: usage,
                warnings: capturedWarnings, request: recordedRequest,
                response: StepResultResponse(from: resp, messages: responseMessages, body: nil),
                providerMetadata: providerMetadata)
            recordedSteps.append(stepResult)
            accumulatedUsage = addLanguageModelUsage(accumulatedUsage, usage)
            recordedFinishReason = finishReason
        }
        totalUsagePromise.resolve(accumulatedUsage)
        stepsPromise.resolve(recordedSteps)
        // Resolve finish reason with the last recorded one (or unknown if none).
        finishReasonPromise.resolve(recordedFinishReason ?? .unknown)
        onTerminate?()
        onTerminate = nil
    }

    func setOnTerminate(_ cb: @escaping @Sendable () -> Void) { onTerminate = cb }
    func setInitialRequest(_ info: LanguageModelV3RequestInfo?) {
        guard let body = info?.body else { return }
        if let value = try? jsonValue(from: body) {
            recordedRequest = LanguageModelRequestMetadata(body: value)
        }
    }

    private func convertModelMessagesToResponseMessagesV2(_ messages: [ModelMessage])
        -> [ResponseMessage]
    {
        messages.compactMap { message in
            switch message {
            case .assistant(let a): return .assistant(a)
            case .tool(let t): return .tool(t)
            case .system, .user: return nil
            }
        }
    }
    private func convertResponseMessagesToModelMessagesV2(_ messages: [ResponseMessage])
        -> [ModelMessage]
    {
        messages.map { m in
            switch m {
            case .assistant(let a): return .assistant(a)
            case .tool(let t): return .tool(t)
            }
        }
    }
}

enum StreamTextV2Error: Error { case providerError(JSONValue) }
