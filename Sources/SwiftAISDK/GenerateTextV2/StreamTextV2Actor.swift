import AISDKProvider
import AISDKProviderUtils
import Foundation

actor StreamTextV2Actor {
    private let source: AsyncThrowingStream<LanguageModelV3StreamPart, Error>
    private let model: any LanguageModelV3
    private var initialMessages: [ModelMessage]
    private let initialSystem: String?
    private let stopConditions: [StopCondition]
    private let tools: ToolSet?

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
    private var recordedContent: [ContentPart] = []
    private var activeTextContent: [String: ActiveTextContent] = [:]
    private var activeReasoningContent: [String: ActiveReasoningContent] = [:]
    private var recordedResponseMessages: [ResponseMessage] = []
    private var currentToolCalls: [TypedToolCall] = []
    private var currentToolOutputs: [ToolOutput] = []
    private var recordedRequest: LanguageModelRequestMetadata = LanguageModelRequestMetadata()
    private var recordedSteps: [StepResult] = []
    private var accumulatedUsage: LanguageModelUsage = LanguageModelUsage()
    private var recordedFinishReason: FinishReason? = nil
    private var externalStopRequested = false
    private var abortEmitted = false
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
        tools: ToolSet?,
        totalUsagePromise: DelayedPromise<LanguageModelUsage>,
        finishReasonPromise: DelayedPromise<FinishReason>,
        stepsPromise: DelayedPromise<[StepResult]>
    ) {
        self.source = source
        self.model = model
        self.initialMessages = initialMessages
        self.initialSystem = system
        self.stopConditions = stopConditions
        self.tools = tools
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
        // Emit `.abort` immediately to notify consumers, but keep streams open
        // until the provider finishes so we can still publish a final `.finish`.
        if !terminated && !abortEmitted {
            abortEmitted = true
            await fullBroadcaster.send(.abort)
        }
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
                let continueStreaming = await shouldStartAnotherStep()
                if !continueStreaming { break }
                let nextMessages = makeConversationMessagesForContinuation()
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

    private func shouldStartAnotherStep() async -> Bool {
        guard let lastStep = recordedSteps.last else { return false }
        guard lastStep.finishReason == .toolCalls else { return false }
        let clientToolCalls = clientToolCalls(in: lastStep)
        if clientToolCalls.isEmpty { return false }
        let clientToolOutputs = clientToolOutputs(in: lastStep)
        if clientToolOutputs.count != clientToolCalls.count { return false }
        let stopMet = await isStopConditionMet(stopConditions: stopConditions, steps: recordedSteps)
        return !stopMet
    }

    private func makeConversationMessagesForContinuation() -> [ModelMessage] {
        if recordedResponseMessages.isEmpty {
            return initialMessages
        }
        let responseMessages = recordedResponseMessages
        let converted = convertResponseMessagesToModelMessagesV2(responseMessages)
        return initialMessages + converted
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
        recordedContent.removeAll()
        activeTextContent.removeAll()
        activeReasoningContent.removeAll()
        currentToolCalls.removeAll()
        currentToolOutputs.removeAll()
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
            if Task.isCancelled {
                await finishAll(
                    response: nil,
                    usage: nil,
                    finishReason: nil,
                    providerMetadata: nil,
                    error: nil
                )
                return
            }
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
                    if !warnings.isEmpty {
                        // Surface warnings early for observers
                        logWarnings(warnings.map { .languageModel($0) })
                    }
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
                let index = recordedContent.count
                recordedContent.append(.text(text: "", providerMetadata: providerMetadata))
                activeTextContent[id] = ActiveTextContent(
                    index: index,
                    text: "",
                    providerMetadata: providerMetadata
                )
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
                    let index = recordedContent.count
                    recordedContent.append(.text(text: "", providerMetadata: providerMetadata))
                    activeTextContent[id] = ActiveTextContent(
                        index: index,
                        text: "",
                        providerMetadata: providerMetadata
                    )
                    await fullBroadcaster.send(
                        .textStart(id: id, providerMetadata: providerMetadata))
                }
                if var active = activeTextContent[id] {
                    active.text += delta
                    if let providerMetadata {
                        active.providerMetadata = providerMetadata
                    }
                    activeTextContent[id] = active
                    recordedContent[active.index] = .text(
                        text: active.text,
                        providerMetadata: active.providerMetadata
                    )
                } else {
                    let index = recordedContent.count
                    recordedContent.append(.text(text: delta, providerMetadata: providerMetadata))
                    activeTextContent[id] = ActiveTextContent(
                        index: index,
                        text: delta,
                        providerMetadata: providerMetadata
                    )
                }
                await fullBroadcaster.send(
                    .textDelta(id: id, text: delta, providerMetadata: providerMetadata))
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
                if var active = activeTextContent[id] {
                    if let providerMetadata {
                        active.providerMetadata = providerMetadata
                    }
                    activeTextContent.removeValue(forKey: id)
                    recordedContent[active.index] = .text(
                        text: active.text,
                        providerMetadata: active.providerMetadata
                    )
                }
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
                let index = recordedContent.count
                let reasoning = ReasoningOutput(text: "", providerMetadata: providerMetadata)
                recordedContent.append(.reasoning(reasoning))
                activeReasoningContent[id] = ActiveReasoningContent(
                    index: index,
                    text: "",
                    providerMetadata: providerMetadata
                )
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
                    let index = recordedContent.count
                    let reasoning = ReasoningOutput(text: "", providerMetadata: providerMetadata)
                    recordedContent.append(.reasoning(reasoning))
                    activeReasoningContent[id] = ActiveReasoningContent(
                        index: index,
                        text: "",
                        providerMetadata: providerMetadata
                    )
                    await fullBroadcaster.send(
                        .reasoningStart(id: id, providerMetadata: providerMetadata)
                    )
                }
                if var active = activeReasoningContent[id] {
                    active.text += delta
                    if let providerMetadata {
                        active.providerMetadata = providerMetadata
                    }
                    activeReasoningContent[id] = active
                    let reasoning = ReasoningOutput(
                        text: active.text,
                        providerMetadata: active.providerMetadata
                    )
                    recordedContent[active.index] = .reasoning(reasoning)
                } else {
                    let reasoning = ReasoningOutput(text: delta, providerMetadata: providerMetadata)
                    let index = recordedContent.count
                    recordedContent.append(.reasoning(reasoning))
                    activeReasoningContent[id] = ActiveReasoningContent(
                        index: index,
                        text: delta,
                        providerMetadata: providerMetadata
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
                if var active = activeReasoningContent[id] {
                    if let providerMetadata {
                        active.providerMetadata = providerMetadata
                    }
                    activeReasoningContent.removeValue(forKey: id)
                    let reasoning = ReasoningOutput(
                        text: active.text,
                        providerMetadata: active.providerMetadata
                    )
                    recordedContent[active.index] = .reasoning(reasoning)
                }
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
                let parsed = await safeParseJSON(ParseJSONOptions(text: call.input))
                let inputValue: JSONValue
                let parseError: Error?
                switch parsed {
                case .success(let value, _):
                    inputValue = value
                    parseError = nil
                case .failure(let error, _):
                    inputValue = .string(call.input)
                    parseError = error
                }
                activeToolInputs[call.toolCallId] = inputValue
                activeToolNames[call.toolCallId] = call.toolName
                let typed: TypedToolCall
                if parseError == nil, tools?[call.toolName] != nil {
                    let staticCall = StaticToolCall(
                        toolCallId: call.toolCallId,
                        toolName: call.toolName,
                        input: inputValue,
                        providerExecuted: call.providerExecuted,
                        providerMetadata: call.providerMetadata
                    )
                    typed = .static(staticCall)
                } else {
                    let dynamicCall = DynamicToolCall(
                        toolCallId: call.toolCallId,
                        toolName: call.toolName,
                        input: inputValue,
                        providerExecuted: call.providerExecuted,
                        providerMetadata: call.providerMetadata,
                        invalid: parseError == nil ? nil : true,
                        error: parseError
                    )
                    typed = .dynamic(dynamicCall)
                }
                recordedContent.append(.toolCall(typed, providerMetadata: call.providerMetadata))
                currentToolCalls.append(typed)
                await fullBroadcaster.send(.toolCall(typed))
            case .toolResult(let result):
                let input = activeToolInputs[result.toolCallId] ?? .null
                let typed: TypedToolResult
                if tools?[result.toolName] != nil {
                    let staticResult = StaticToolResult(
                        toolCallId: result.toolCallId,
                        toolName: result.toolName,
                        input: input,
                        output: result.result,
                        providerExecuted: result.providerExecuted,
                        preliminary: result.preliminary,
                        providerMetadata: result.providerMetadata
                    )
                    typed = .static(staticResult)
                } else {
                    let dynamicResult = DynamicToolResult(
                        toolCallId: result.toolCallId,
                        toolName: result.toolName,
                        input: input,
                        output: result.result,
                        providerExecuted: result.providerExecuted,
                        preliminary: result.preliminary,
                        providerMetadata: result.providerMetadata
                    )
                    typed = .dynamic(dynamicResult)
                }
                let isPreliminary = result.preliminary == true
                await fullBroadcaster.send(.toolResult(typed))
                if !isPreliminary {
                    recordedContent.append(.toolResult(typed, providerMetadata: result.providerMetadata))
                    currentToolOutputs.append(.result(typed))
                    activeToolInputs.removeValue(forKey: result.toolCallId)
                    activeToolNames.removeValue(forKey: result.toolCallId)
                }
            case let .finish(finishReason, usage, providerMetadata):
                for id in openTextIds {
                    await fullBroadcaster.send(.textEnd(id: id, providerMetadata: nil))
                    if let active = activeTextContent[id] {
                        activeTextContent.removeValue(forKey: id)
                        recordedContent[active.index] = .text(
                            text: active.text,
                            providerMetadata: active.providerMetadata
                        )
                    }
                }
                openTextIds.removeAll()
                for id in openReasoningIds {
                    await fullBroadcaster.send(.reasoningEnd(id: id, providerMetadata: nil))
                    if let active = activeReasoningContent[id] {
                        activeReasoningContent.removeValue(forKey: id)
                        let reasoning = ReasoningOutput(
                            text: active.text,
                            providerMetadata: active.providerMetadata
                        )
                        recordedContent[active.index] = .reasoning(reasoning)
                    }
                }
                openReasoningIds.removeAll()
                finalizePendingContent()
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
                let contentSnapshot = recordedContent
                let modelMessages = toResponseMessages(content: contentSnapshot, tools: tools)
                let responseMessages = convertModelMessagesToResponseMessagesV2(modelMessages)
                let mergedMessages = recordedResponseMessages + responseMessages
                let stepResult = DefaultStepResult(
                    content: contentSnapshot, finishReason: finishReason, usage: usage,
                    warnings: capturedWarnings, request: recordedRequest,
                    response: StepResultResponse(
                        from: response, messages: mergedMessages, body: nil),
                    providerMetadata: providerMetadata)
                recordedSteps.append(stepResult)
                recordedResponseMessages.append(contentsOf: responseMessages)
                accumulatedUsage = addLanguageModelUsage(accumulatedUsage, usage)
                currentToolCalls.removeAll()
                currentToolOutputs.removeAll()
                // Do not resolve `finishReasonPromise` here; session-level finish
                // will resolve it with the last step's reason to mirror upstream.
                // Keep the last seen reason in `recordedFinishReason`.
                recordedFinishReason = finishReason
            case .file(let file):
                let genFile = toGeneratedFile(file)
                recordedContent.append(.file(file: genFile, providerMetadata: nil))
                await fullBroadcaster.send(.file(genFile))
            case .source(let source):
                recordedContent.append(.source(type: "source", source: source))
                await fullBroadcaster.send(.source(source))
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
            @unknown default:
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
        // If the provider supplied a tail step via `response/usage/finishReason`,
        // record it before resolving the promises or emitting the terminal `.finish`.
        finalizePendingContent()
        if let usage, let finishReason, let resp = response {
            let contentSnapshot = recordedContent
            let modelMessages = toResponseMessages(content: contentSnapshot, tools: tools)
            let responseMessages = convertModelMessagesToResponseMessagesV2(modelMessages)
            let mergedMessages = recordedResponseMessages + responseMessages
            let stepResult = DefaultStepResult(
                content: contentSnapshot, finishReason: finishReason, usage: usage,
                warnings: capturedWarnings, request: recordedRequest,
                response: StepResultResponse(from: resp, messages: mergedMessages, body: nil),
                providerMetadata: providerMetadata)
            recordedSteps.append(stepResult)
            recordedResponseMessages.append(contentsOf: responseMessages)
            accumulatedUsage = addLanguageModelUsage(accumulatedUsage, usage)
            currentToolCalls.removeAll()
            currentToolOutputs.removeAll()
            recordedFinishReason = finishReason
        }
        // Resolve promises BEFORE publishing the terminal `.finish` event.
        // This guarantees observers that await promises in response to `.finish`
        // can read stable values without timing races.
        totalUsagePromise.resolve(accumulatedUsage)
        stepsPromise.resolve(recordedSteps)
        // Resolve finish reason with the last recorded one (or unknown if none).
        finishReasonPromise.resolve(recordedFinishReason ?? .unknown)

        if let error {
            // Error path: finish streams with the error, do not emit terminal `.finish` part.
            await textBroadcaster.finish(error: error)
            await fullBroadcaster.finish(error: error)
        } else {
            // Success path: optionally emit `.abort` if an external stop was requested,
            // then emit session-level `.finish` before closing the broadcasters.
            if externalStopRequested && !abortEmitted {
                abortEmitted = true
                await fullBroadcaster.send(.abort)
            }
            let finalReason = recordedFinishReason ?? .unknown
            await fullBroadcaster.send(
                .finish(finishReason: finalReason, totalUsage: accumulatedUsage)
            )
            await textBroadcaster.finish()
            await fullBroadcaster.finish()
        }
        onTerminate?()
        onTerminate = nil
    }

    private func clientToolCalls(in step: StepResult) -> [TypedToolCall] {
        step.toolCalls.filter { $0.providerExecuted != true }
    }

    private func clientToolOutputs(in step: StepResult) -> [TypedToolResult] {
        step.toolResults.filter { $0.providerExecuted != true }
    }

    private func finalizePendingContent() {
        for (_, active) in activeTextContent {
            recordedContent[active.index] = .text(
                text: active.text,
                providerMetadata: active.providerMetadata
            )
        }
        activeTextContent.removeAll()
        for (_, active) in activeReasoningContent {
            let reasoning = ReasoningOutput(
                text: active.text,
                providerMetadata: active.providerMetadata
            )
            recordedContent[active.index] = .reasoning(reasoning)
        }
        activeReasoningContent.removeAll()
    }

    // MARK: - Conversions

    private func toGeneratedFile(_ file: LanguageModelV3File) -> GeneratedFile {
        switch file.data {
        case .base64(let b64):
            return DefaultGeneratedFileWithType(base64: b64, mediaType: file.mediaType)
        case .binary(let data):
            return DefaultGeneratedFileWithType(data: data, mediaType: file.mediaType)
        }
    }

    func setOnTerminate(_ cb: @escaping @Sendable () -> Void) { onTerminate = cb }
    func setInitialRequest(_ info: LanguageModelV3RequestInfo?) {
        guard let body = info?.body else { return }
        if let value = try? jsonValue(from: body) {
            recordedRequest = LanguageModelRequestMetadata(body: value)
        }
    }

    // Observability helpers for consumers that need step snapshots.
    func getRecordedSteps() -> [StepResult] { recordedSteps }
    func getLastStep() -> StepResult? { recordedSteps.last }

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

enum StreamTextV2Error: Error { case providerError(JSONValue) }
