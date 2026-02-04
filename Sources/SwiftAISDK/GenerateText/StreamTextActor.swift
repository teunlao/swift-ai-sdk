import AISDKProvider
import AISDKProviderUtils
import Foundation

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
actor StreamTextActor {
    private let source: AsyncThrowingStream<LanguageModelV3StreamPart, Error>
    private var model: any LanguageModelV3
    private var initialMessages: [ModelMessage]
    private let initialSystem: String?
    private let stopConditions: [StopCondition]
    private let tools: ToolSet?
    private let configuration: StreamTextActorConfiguration

    private let textBroadcaster = AsyncStreamBroadcaster<String>()
    private let fullBroadcaster = AsyncStreamBroadcaster<TextStreamPart>()

    private var started = false
    // Session-level framing: `.start` must be emitted exactly once per session
    private var framingEmitted = false
    private var terminated = false
    private var onTerminate: (@Sendable () -> Void)? = nil

    private var capturedWarnings: [SharedV3Warning] = []
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
    private var currentToolCallsById: [String: TypedToolCall] = [:]
    private var currentToolOutputs: [ToolOutput] = []
    private var recordedRequest: LanguageModelRequestMetadata = LanguageModelRequestMetadata()
    private var recordedSteps: [StepResult] = []
    private var accumulatedUsage: LanguageModelUsage = LanguageModelUsage()
    private var recordedFinishReason: FinishReason? = nil
    private var recordedRawFinishReason: String? = nil
    private var externalStopRequested = false
    private var abortEmitted = false
    // Tool tracking for the current step
    private var activeToolInputs: [String: JSONValue] = [:] // toolCallId -> parsed input
    private var activeToolNames: [String: String] = [:]     // toolCallId -> tool name

    private let approvalResolver: (@Sendable (ToolApprovalRequestOutput) async -> ApprovalAction)?
    private var experimentalContext: JSONValue?

    private struct PendingApproval: Sendable {
        let toolCallId: String
        let toolName: String
        let input: JSONValue
        let typedCall: TypedToolCall
        let tool: Tool
        let providerMetadata: ProviderMetadata?
    }

    private var pendingApprovals: [PendingApproval] = []

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
        approvalResolver: (@Sendable (ToolApprovalRequestOutput) async -> ApprovalAction)?,
        experimentalApprovalContext: JSONValue?,
        configuration: StreamTextActorConfiguration,
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
        self.configuration = configuration
        self.approvalResolver = approvalResolver
        self.experimentalContext = experimentalApprovalContext
        self.totalUsagePromise = totalUsagePromise
        self.finishReasonPromise = finishReasonPromise
        self.stepsPromise = stepsPromise
    }

    func setExperimentalContext(_ value: JSONValue?) {
        experimentalContext = value
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
            await fullBroadcaster.send(.abort(reason: nil))
        }
    }

    private func emitStreamError(_ message: String) async {
        await fullBroadcaster.send(.error(StreamTextInvariantError(message: message)))
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
                let stepInputMessages = makeConversationMessagesForContinuation()
                let stepNumber = recordedSteps.count

                var stepModelArg: LanguageModel = configuration.baseModel
                var stepSystem = initialSystem
                var stepMessages = stepInputMessages
                var stepToolChoice = configuration.toolChoice
                var stepActiveTools = configuration.activeTools
                var stepProviderOptions = configuration.providerOptions

                if let prepareStep = configuration.prepareStep {
                    let options = PrepareStepOptions(
                        steps: recordedSteps,
                        stepNumber: stepNumber,
                        model: configuration.baseModel,
                        messages: stepInputMessages,
                        experimentalContext: experimentalContext
                    )

                    if let result = try await prepareStep(options) {
                        experimentalContext = result.experimentalContext ?? experimentalContext
                        stepModelArg = result.model ?? stepModelArg
                        stepSystem = result.system ?? stepSystem
                        stepMessages = result.messages ?? stepMessages
                        stepToolChoice = result.toolChoice ?? stepToolChoice
                        stepActiveTools = result.activeTools ?? stepActiveTools
                        stepProviderOptions = mergeProviderOptions(stepProviderOptions, result.providerOptions)
                    }
                }

                self.model = try resolveLanguageModel(stepModelArg)
                let lmPrompt = try await buildLanguageModelPrompt(system: stepSystem, messages: stepMessages)
                let toolPreparation = try await prepareToolsAndToolChoice(
                    tools: tools,
                    toolChoice: stepToolChoice,
                    activeTools: stepActiveTools
                )
                let options = try await makeCallOptions(
                    prompt: lmPrompt,
                    tools: toolPreparation.tools,
                    toolChoice: toolPreparation.toolChoice,
                    providerOptions: stepProviderOptions
                )
                let result = try await configuration.preparedRetries.retry.call { [self] in
                    try await self.model.doStream(options: options)
                }
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
        let converted = convertResponseMessagesToModelMessages(responseMessages)
        return initialMessages + converted
    }

    private func currentMessagesForApproval() -> [ModelMessage] {
        if recordedResponseMessages.isEmpty {
            return initialMessages
        }
        let responseMessages = recordedResponseMessages
        let converted = convertResponseMessagesToModelMessages(responseMessages)
        return initialMessages + converted
    }

    private func requiresApproval(for tool: Tool, callId: String, input: JSONValue) async -> Bool {
        guard let needsApproval = tool.needsApproval else { return false }
        switch needsApproval {
        case .always:
            return true
        case .never:
            return false
        case .conditional(let predicate):
            do {
                return try await predicate(
                    input,
                    ToolCallApprovalOptions(
                        toolCallId: callId,
                        messages: currentMessagesForApproval(),
                        experimentalContext: experimentalContext
                    )
                )
            } catch {
                return true
            }
        }
    }

    private func removePendingApproval(toolCallId: String) {
        pendingApprovals.removeAll { $0.toolCallId == toolCallId }
    }

    private func makeTypedToolResult(
        tool: Tool,
        callId: String,
        toolName: String,
        input: JSONValue,
        output: JSONValue,
        preliminary: Bool,
        providerMetadata: ProviderMetadata?
    ) -> TypedToolResult {
        if tool.type == nil || tool.type == .function {
            return .static(
                StaticToolResult(
                    toolCallId: callId,
                    toolName: toolName,
                    input: input,
                    output: output,
                    providerExecuted: false,
                    preliminary: preliminary,
                    providerMetadata: providerMetadata
                )
            )
        } else {
            return .dynamic(
                DynamicToolResult(
                    toolCallId: callId,
                    toolName: toolName,
                    input: input,
                    output: output,
                    providerExecuted: false,
                    preliminary: preliminary,
                    providerMetadata: providerMetadata
                )
            )
        }
    }

    private func makeTypedToolError(
        tool: Tool,
        callId: String,
        toolName: String,
        input: JSONValue,
        error: Error
    ) -> TypedToolError {
        if tool.type == nil || tool.type == .function {
            return .static(
                StaticToolError(
                    toolCallId: callId,
                    toolName: toolName,
                    input: input,
                    error: error,
                    providerExecuted: false
                )
            )
        } else {
            return .dynamic(
                DynamicToolError(
                    toolCallId: callId,
                    toolName: toolName,
                    input: input,
                    error: error,
                    providerExecuted: false
                )
            )
        }
    }

    private func emitToolResult(_ result: TypedToolResult, preliminary: Bool) async {
        await fullBroadcaster.send(.toolResult(result))
        if !preliminary {
            recordedContent.append(.toolResult(result, providerMetadata: nil))
            currentToolOutputs.append(.result(result))
            activeToolInputs.removeValue(forKey: result.toolCallId)
            activeToolNames.removeValue(forKey: result.toolCallId)
            removePendingApproval(toolCallId: result.toolCallId)
        }
    }

    private func emitToolError(_ error: TypedToolError) async {
        await fullBroadcaster.send(.toolError(error))
        recordedContent.append(.toolError(error, providerMetadata: nil))
        currentToolOutputs.append(.error(error))
        activeToolInputs.removeValue(forKey: error.toolCallId)
        activeToolNames.removeValue(forKey: error.toolCallId)
        removePendingApproval(toolCallId: error.toolCallId)
    }

    private func emitToolOutputDenied(callId: String, toolName: String) async {
        await fullBroadcaster.send(.toolOutputDenied(ToolOutputDenied(toolCallId: callId, toolName: toolName)))
        activeToolInputs.removeValue(forKey: callId)
        activeToolNames.removeValue(forKey: callId)
        removePendingApproval(toolCallId: callId)
    }

    private func handleExecutionResult(_ execution: ToolExecutionResult<JSONValue>, pending: PendingApproval) async {
        switch execution {
        case .value(let value):
            let typed = makeTypedToolResult(
                tool: pending.tool,
                callId: pending.toolCallId,
                toolName: pending.toolName,
                input: pending.input,
                output: value,
                preliminary: false,
                providerMetadata: pending.providerMetadata
            )
            await emitToolResult(typed, preliminary: false)
        case .future(let future):
            do {
                let value = try await future()
                let typed = makeTypedToolResult(
                    tool: pending.tool,
                    callId: pending.toolCallId,
                    toolName: pending.toolName,
                    input: pending.input,
                    output: value,
                    preliminary: false,
                    providerMetadata: pending.providerMetadata
                )
                await emitToolResult(typed, preliminary: false)
            } catch {
                let typedError = makeTypedToolError(
                    tool: pending.tool,
                    callId: pending.toolCallId,
                    toolName: pending.toolName,
                    input: pending.input,
                    error: error
                )
                await emitToolError(typedError)
            }
        case .stream(let stream):
            var last: JSONValue = .null
            do {
                for try await chunk in stream {
                    if Task.isCancelled { return }
                    last = chunk
                    let prelim = makeTypedToolResult(
                        tool: pending.tool,
                        callId: pending.toolCallId,
                        toolName: pending.toolName,
                        input: pending.input,
                        output: chunk,
                        preliminary: true,
                        providerMetadata: pending.providerMetadata
                    )
                    await emitToolResult(prelim, preliminary: true)
                }
            } catch {
                let typedError = makeTypedToolError(
                    tool: pending.tool,
                    callId: pending.toolCallId,
                    toolName: pending.toolName,
                    input: pending.input,
                    error: error
                )
                await emitToolError(typedError)
                return
            }
            let finalResult = makeTypedToolResult(
                tool: pending.tool,
                callId: pending.toolCallId,
                toolName: pending.toolName,
                input: pending.input,
                output: last,
                preliminary: false,
                providerMetadata: pending.providerMetadata
            )
            await emitToolResult(finalResult, preliminary: false)
        }
    }

    private func resolvePendingApprovals() async {
        if pendingApprovals.isEmpty { return }
        let approvals = pendingApprovals
        pendingApprovals.removeAll()
        for pending in approvals {
            if Task.isCancelled { break }
            let approval = ToolApprovalRequestOutput(approvalId: pending.toolCallId, toolCall: pending.typedCall)
            if let resolver = approvalResolver {
                let decision = await resolver(approval)
                if Task.isCancelled { break }
                switch decision {
                case .approve:
                    await executeToolAfterApproval(pending)
                case .deny:
                    await emitToolOutputDenied(callId: pending.toolCallId, toolName: pending.toolName)
                }
            } else {
                await fullBroadcaster.send(.toolApprovalRequest(approval))
                recordedContent.append(.toolApprovalRequest(approval))
                activeToolInputs.removeValue(forKey: pending.toolCallId)
                activeToolNames.removeValue(forKey: pending.toolCallId)
            }
        }
    }

    private func executeToolAfterApproval(_ pending: PendingApproval) async {
        guard let execute = pending.tool.execute else {
            await emitToolOutputDenied(callId: pending.toolCallId, toolName: pending.toolName)
            return
        }
        let options = ToolCallOptions(
            toolCallId: pending.toolCallId,
            messages: currentMessagesForApproval(),
            abortSignal: nil,
            experimentalContext: experimentalContext
        )
        do {
            let result = try await execute(pending.input, options)
            await handleExecutionResult(result, pending: pending)
        } catch {
            let typedError = makeTypedToolError(
                tool: pending.tool,
                callId: pending.toolCallId,
                toolName: pending.toolName,
                input: pending.input,
                error: error
            )
            await emitToolError(typedError)
        }
    }

    // MARK: - Prompt Construction (Upstream parity)

    /// Builds a provider prompt using the full conversion pipeline:
    /// - Captures the initial system prompt
    /// - Uses `convertToLanguageModelPrompt` to map content parts and assets
    /// - Respects provider `supportedUrls` (URLs left as references when supported)
    /// - Parameter messages: Conversation messages to include (system is injected automatically)
    /// - Returns: A LanguageModelV3Prompt ready for `doStream`
    private func buildLanguageModelPrompt(system: String?, messages: [ModelMessage]) async throws -> LanguageModelV3Prompt {
        let standardized = StandardizedPrompt(system: system, messages: messages)
        let supported = try await model.supportedUrls
        let prompt = try await convertToLanguageModelPrompt(
            prompt: standardized,
            supportedUrls: supported,
            download: configuration.download
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
        currentToolCallsById.removeAll()
        currentToolOutputs.removeAll()
        capturedWarnings = []
        openTextIds.removeAll()
        openReasoningIds.removeAll()
        activeToolInputs.removeAll()
        activeToolNames.removeAll()
        capturedResponseId = configuration.generateId()
        capturedModelId = model.modelId
        capturedTimestamp = configuration.currentDate()
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
                // Upstream tolerance: if a textDelta appears before textStart for an id,
                // implicitly open the text span and emit a matching .textStart.
                if !openTextIds.contains(id) || activeTextContent[id] == nil {
                    openTextIds.insert(id)
                    let index = recordedContent.count
                    recordedContent.append(.text(text: "", providerMetadata: providerMetadata))
                    activeTextContent[id] = ActiveTextContent(
                        index: index,
                        text: "",
                        providerMetadata: providerMetadata
                    )
                    await fullBroadcaster.send(.textStart(id: id, providerMetadata: providerMetadata))
                }
                guard let stored = activeTextContent[id] else { break }
                await textBroadcaster.send(delta)
                var active = stored
                active.text += delta
                if let providerMetadata {
                    active.providerMetadata = providerMetadata
                }
                activeTextContent[id] = active
                recordedContent[active.index] = .text(
                    text: active.text,
                    providerMetadata: active.providerMetadata
                )
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
                guard openTextIds.contains(id), let stored = activeTextContent[id] else {
                    await emitStreamError("text part \(id) not found")
                    continue
                }
                openTextIds.remove(id)
                var active = stored
                if let providerMetadata {
                    active.providerMetadata = providerMetadata
                }
                activeTextContent.removeValue(forKey: id)
                recordedContent[active.index] = .text(
                    text: active.text,
                    providerMetadata: active.providerMetadata
                )
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
                // Same tolerance for reasoning deltas: auto-open if needed.
                if !openReasoningIds.contains(id) || activeReasoningContent[id] == nil {
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
                guard let stored = activeReasoningContent[id] else { break }
                var active = stored
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
                guard openReasoningIds.contains(id), let stored = activeReasoningContent[id] else {
                    await emitStreamError("reasoning part \(id) not found")
                    continue
                }
                openReasoningIds.remove(id)
                var active = stored
                if let providerMetadata {
                    active.providerMetadata = providerMetadata
                }
                activeReasoningContent.removeValue(forKey: id)
                let reasoning = ReasoningOutput(
                    text: active.text,
                    providerMetadata: active.providerMetadata
                )
                recordedContent[active.index] = .reasoning(reasoning)
                await fullBroadcaster.send(
                    .reasoningEnd(id: id, providerMetadata: providerMetadata)
                )

case let .toolInputStart(id, toolName, providerMetadata, providerExecuted, dynamicFlag, title):
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
                let messagesForInput = currentMessagesForApproval()
                activeToolNames[id] = toolName
                let tool = tools?[toolName]
                if let onInputStart = tool?.onInputStart {
                    let options = ToolCallOptions(
                        toolCallId: id,
                        messages: messagesForInput,
                        abortSignal: configuration.abortSignal,
                        experimentalContext: experimentalContext
                    )
                    try await onInputStart(options)
                }
                await fullBroadcaster.send(
                    .toolInputStart(
                        id: id,
                        toolName: toolName,
                        providerMetadata: providerMetadata,
                        providerExecuted: providerExecuted,
                        dynamic: dynamicFlag ?? (tool?.type == .dynamic ? true : nil),
                        title: title
                    )
                )
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
                guard activeToolNames[id] != nil else {
                    await emitStreamError("tool input \(id) not found")
                    continue
                }
                if let toolName = activeToolNames[id], let tool = tools?[toolName], let onInputDelta = tool.onInputDelta {
                    let options = ToolCallDeltaOptions(
                        inputTextDelta: delta,
                        toolCallId: id,
                        messages: currentMessagesForApproval(),
                        abortSignal: configuration.abortSignal,
                        experimentalContext: experimentalContext
                    )
                    try await onInputDelta(options)
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
                guard activeToolNames.removeValue(forKey: id) != nil else {
                    await emitStreamError("tool input \(id) not found")
                    continue
                }
                await fullBroadcaster.send(
                    .toolInputEnd(id: id, providerMetadata: providerMetadata))
            case .toolCall(let call):
                let approvalMessages = currentMessagesForApproval()
                let typed = await parseToolCall(
                    toolCall: call,
                    tools: tools,
                    repairToolCall: configuration.repairToolCall,
                    system: initialSystem,
                    messages: approvalMessages
                )

                activeToolInputs[typed.toolCallId] = typed.input
                activeToolNames[typed.toolCallId] = typed.toolName

                recordedContent.append(.toolCall(typed, providerMetadata: typed.providerMetadata))
                currentToolCalls.append(typed)
                currentToolCallsById[typed.toolCallId] = typed
                await fullBroadcaster.send(.toolCall(typed))

                if typed.invalid == true {
                    let error = makeInvalidToolCallError(from: typed)
                    await emitToolError(error)
                    continue
                }

                guard let tool = tools?[typed.toolName], typed.providerExecuted != true else {
                    continue
                }

                if let onInputAvailable = tool.onInputAvailable {
                    let options = ToolCallInputOptions(
                        input: typed.input,
                        toolCallId: typed.toolCallId,
                        messages: approvalMessages,
                        abortSignal: configuration.abortSignal,
                        experimentalContext: experimentalContext
                    )
                    do {
                        try await onInputAvailable(options)
                    } catch {
                        let typedError = makeTypedToolError(
                            tool: tool,
                            callId: typed.toolCallId,
                            toolName: typed.toolName,
                            input: typed.input,
                            error: error
                        )
                        await emitToolError(typedError)
                        continue
                    }
                }

                if await requiresApproval(for: tool, callId: typed.toolCallId, input: typed.input) {
                    pendingApprovals.append(PendingApproval(
                        toolCallId: typed.toolCallId,
                        toolName: typed.toolName,
                        input: typed.input,
                        typedCall: typed,
                        tool: tool,
                        providerMetadata: typed.providerMetadata
                    ))
                } else {
                    let pending = PendingApproval(
                        toolCallId: typed.toolCallId,
                        toolName: typed.toolName,
                        input: typed.input,
                        typedCall: typed,
                        tool: tool,
                        providerMetadata: typed.providerMetadata
                    )
                    await executeToolAfterApproval(pending)
                }

            case .toolApprovalRequest(let request):
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

                guard let toolCall = currentToolCallsById[request.toolCallId] else {
                    await emitStreamError("tool call \(request.toolCallId) not found for approval \(request.approvalId)")
                    continue
                }

                let approval = ToolApprovalRequestOutput(
                    approvalId: request.approvalId,
                    toolCall: toolCall
                )
                await fullBroadcaster.send(.toolApprovalRequest(approval))
                recordedContent.append(.toolApprovalRequest(approval))

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
                    removePendingApproval(toolCallId: result.toolCallId)
                }
            case let .finish(finishReason, usage, providerMetadata):
                let stepUsage = asLanguageModelUsage(usage)
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
                await resolvePendingApprovals()
                let response = LanguageModelResponseMetadata(
                    id: capturedResponseId ?? configuration.generateId(),
                    timestamp: capturedTimestamp ?? configuration.currentDate(),
                    modelId: capturedModelId ?? model.modelId,
                    headers: nil
                )
                await fullBroadcaster.send(
                    .finishStep(
                        response: response,
                        usage: stepUsage,
                        finishReason: finishReason,
                        rawFinishReason: finishReason.rawValue,
                        providerMetadata: providerMetadata
                    )
                )
                let contentSnapshot = recordedContent
                let modelMessages = toResponseMessages(content: contentSnapshot, tools: tools)
                let responseMessages = convertModelMessagesToResponseMessages(modelMessages)
                let mergedMessages = recordedResponseMessages + responseMessages
                let stepResult = DefaultStepResult(
                    content: contentSnapshot,
                    finishReason: finishReason,
                    rawFinishReason: finishReason.rawValue,
                    usage: stepUsage,
                    warnings: capturedWarnings, request: recordedRequest,
                    response: StepResultResponse(
                        from: response, messages: mergedMessages, body: nil),
                    providerMetadata: providerMetadata)
                recordedSteps.append(stepResult)
                recordedResponseMessages.append(contentsOf: responseMessages)
                accumulatedUsage = addLanguageModelUsage(accumulatedUsage, stepUsage)
                currentToolCalls.removeAll()
                currentToolCallsById.removeAll()
                currentToolOutputs.removeAll()
                // Do not resolve `finishReasonPromise` here; session-level finish
                // will resolve it with the last step's reason to mirror upstream.
                // Keep the last seen reason in `recordedFinishReason`.
                recordedFinishReason = finishReason
                recordedRawFinishReason = finishReason.rawValue
            case .file(let file):
                let genFile = toGeneratedFile(file)
                recordedContent.append(.file(file: genFile, providerMetadata: nil))
                await fullBroadcaster.send(.file(genFile))
            case .source(let source):
                recordedContent.append(.source(type: "source", source: source))
                await fullBroadcaster.send(.source(source))
            case .raw(let raw):
                guard configuration.includeRawChunks else { break }
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
                    error: StreamTextError.providerError(err)
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
        await resolvePendingApprovals()
        if let usage, let finishReason, let resp = response {
            let contentSnapshot = recordedContent
            let modelMessages = toResponseMessages(content: contentSnapshot, tools: tools)
            let responseMessages = convertModelMessagesToResponseMessages(modelMessages)
            let mergedMessages = recordedResponseMessages + responseMessages
            let stepResult = DefaultStepResult(
                content: contentSnapshot,
                finishReason: finishReason,
                rawFinishReason: finishReason.rawValue,
                usage: usage,
                warnings: capturedWarnings, request: recordedRequest,
                response: StepResultResponse(from: resp, messages: mergedMessages, body: nil),
                providerMetadata: providerMetadata)
            recordedSteps.append(stepResult)
            recordedResponseMessages.append(contentsOf: responseMessages)
            accumulatedUsage = addLanguageModelUsage(accumulatedUsage, usage)
            currentToolCalls.removeAll()
            currentToolCallsById.removeAll()
            currentToolOutputs.removeAll()
            recordedFinishReason = finishReason
            recordedRawFinishReason = finishReason.rawValue
        }
        // Resolve promises BEFORE publishing the terminal `.finish` event.
        // This guarantees observers that await promises in response to `.finish`
        // can read stable values without timing races.
        totalUsagePromise.resolve(accumulatedUsage)
        stepsPromise.resolve(recordedSteps)
        // Resolve finish reason with the last recorded one (or unknown if none).
        finishReasonPromise.resolve(recordedFinishReason ?? .unknown)

        if let error {
            // Error path: emit a .error part for downstream observers,
            // then finish streams with the error (no terminal `.finish`).
            await fullBroadcaster.send(.error(error))
            await textBroadcaster.finish(error: error)
            await fullBroadcaster.finish(error: error)
        } else {
            // Success path: optionally emit `.abort` if an external stop was requested,
            // then emit session-level `.finish` before closing the broadcasters.
            if externalStopRequested && !abortEmitted {
                abortEmitted = true
                await fullBroadcaster.send(.abort(reason: nil))
            }
            let finalReason = recordedFinishReason ?? .unknown
            await fullBroadcaster.send(
                .finish(
                    finishReason: finalReason,
                    rawFinishReason: recordedRawFinishReason ?? finalReason.rawValue,
                    totalUsage: accumulatedUsage
                )
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

    func appendInitialResponseMessages(_ messages: [ResponseMessage]) {
        guard !messages.isEmpty else { return }
        recordedResponseMessages.append(contentsOf: messages)
    }

    func publishPreludeEvents(_ parts: [TextStreamPart]) async {
        guard !parts.isEmpty else { return }
        for part in parts {
            await fullBroadcaster.send(part)
        }
    }

    // Observability helpers for consumers that need step snapshots.
    func getRecordedSteps() -> [StepResult] { recordedSteps }
    func getLastStep() -> StepResult? { recordedSteps.last }

    private func makeCallOptions(
        prompt: LanguageModelV3Prompt,
        tools: [LanguageModelV3Tool]?,
        toolChoice: LanguageModelV3ToolChoice?,
        providerOptions: ProviderOptions?
    ) async throws -> LanguageModelV3CallOptions {
        let responseFormat = try await configuration.responseFormatProvider?()
        return LanguageModelV3CallOptions(
            prompt: prompt,
            maxOutputTokens: configuration.callSettings.maxOutputTokens,
            temperature: configuration.callSettings.temperature,
            stopSequences: configuration.callSettings.stopSequences,
            topP: configuration.callSettings.topP,
            topK: configuration.callSettings.topK,
            presencePenalty: configuration.callSettings.presencePenalty,
            frequencyPenalty: configuration.callSettings.frequencyPenalty,
            responseFormat: responseFormat,
            seed: configuration.callSettings.seed,
            tools: tools,
            toolChoice: toolChoice,
            includeRawChunks: configuration.includeRawChunks ? true : nil,
            abortSignal: configuration.abortSignal,
            headers: configuration.headers,
            providerOptions: providerOptions ?? configuration.providerOptions
        )
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

private struct StreamTextInvariantError: LocalizedError, CustomStringConvertible, Sendable {
    let message: String

    var errorDescription: String? { message }
    var description: String { message }
}

enum StreamTextError: Error { case providerError(JSONValue) }
