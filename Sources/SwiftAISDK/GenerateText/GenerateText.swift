import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Internal knobs for tests: id generators and clocks.
public struct GenerateTextInternalOptions: Sendable {
    /// Generates response and approval ids (default prefix `aitxt`, size 24).
    public var generateId: IDGenerator

    /// Generates the call id of the operation (default prefix `call`, size 24).
    public var generateCallId: IDGenerator

    /// Clock used for response timestamps when the provider sends none.
    public var currentDate: @Sendable () -> Date

    /// Millisecond clock used for performance measurements.
    public var now: @Sendable () -> Double

    public init(
        generateId: IDGenerator? = nil,
        generateCallId: IDGenerator? = nil,
        currentDate: @escaping @Sendable () -> Date = Date.init,
        now: @escaping @Sendable () -> Double = { SwiftAISDK.now() }
    ) {
        self.generateId = generateId ?? (try! createIDGenerator(prefix: "aitxt", size: 24))
        self.generateCallId = generateCallId ?? (try! createIDGenerator(prefix: "call", size: 24))
        self.currentDate = currentDate
        self.now = now
    }
}

/**
 What step results retain. Retaining bodies and messages can use a lot of memory
 for large payloads such as images.

 Port of `GenerateTextInclude` from `@ai-sdk/ai/src/generate-text/generate-text.ts`.
 Everything defaults to `false`.
 */
public struct GenerateTextInclude: Sendable {
    /// Retain the request body in step results.
    public var requestBody: Bool?

    /// Retain the request messages in step results.
    public var requestMessages: Bool?

    /// Retain the response body in step results.
    public var responseBody: Bool?

    public init(requestBody: Bool? = nil, requestMessages: Bool? = nil, responseBody: Bool? = nil) {
        self.requestBody = requestBody
        self.requestMessages = requestMessages
        self.responseBody = responseBody
    }
}

/// Port of `@ai-sdk/ai/src/generate-text/calculate-tokens-per-second.ts`.
func calculateTokensPerSecond(tokens: Int?, durationMs: Double?) -> Double {
    let rate = 1000 * Double(tokens ?? 0) / (durationMs ?? 0)
    return rate.isFinite ? rate : 0
}

/// Port of `@ai-sdk/ai/src/generate-text/sum-token-counts.ts`.
func sumTokenCounts(_ first: Int?, _ second: Int?) -> Int? {
    first == nil && second == nil ? nil : (first ?? 0) + (second ?? 0)
}

/// Port of `@ai-sdk/ai/src/generate-text/is-tool-execution-allowed-finish-reason.ts`.
func isToolExecutionAllowedFinishReason(_ finishReason: FinishReason) -> Bool {
    finishReason == .stop || finishReason == .toolCalls
}

/// The tool choice the model response must satisfy, if any.
func enforcedToolChoice(_ toolChoice: LanguageModelV4ToolChoice) -> EnforcedToolChoice? {
    switch toolChoice {
    case .required: return .required
    case .tool(let toolName): return .tool(toolName: toolName)
    default: return nil
    }
}

/// A step timeout that is armed per step.
final class StepAbortTimeout: @unchecked Sendable {
    private let lock = NSLock()
    private var deadline: Double?

    func start(_ timeoutMs: Int?) {
        lock.lock()
        deadline = timeoutMs.map { now() + Double($0) }
        lock.unlock()
    }

    func clear() {
        lock.lock()
        deadline = nil
        lock.unlock()
    }

    var isAborted: Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let deadline else { return false }
        return now() >= deadline
    }
}

/**
 Generates text and calls tools with a language model, without streaming.

 Port of `@ai-sdk/ai/src/generate-text/generate-text.ts`. Each step calls the
 model, executes client tool calls, and continues while all client tool calls
 have outputs and no stop condition is met.

 Callbacks run concurrently with the telemetry integrations; errors thrown by
 callbacks are ignored.
 */
public func generateText<OutputValue: Sendable, PartialOutput: Sendable>(
    model modelArg: LanguageModel,
    tools: ToolSet? = nil,
    toolChoice: ToolChoice? = nil,
    instructions: Instructions? = nil,
    system: Instructions? = nil,
    prompt: String? = nil,
    messages: [ModelMessage]? = nil,
    allowSystemInMessages: Bool? = nil,
    stopWhen: [StopCondition] = [isStepCount(1)],
    output: Output.Specification<OutputValue, PartialOutput>,
    toolApproval: ToolApprovalConfiguration? = nil,
    telemetry: TelemetryOptions? = nil,
    providerOptions: ProviderOptions? = nil,
    activeTools: [String]? = nil,
    toolOrder: [String]? = nil,
    toolCallConcurrency: Int? = nil,
    prepareStep: PrepareStepFunction? = nil,
    repairToolCall: ToolCallRepairFunction? = nil,
    refineToolInput: ToolInputRefinement? = nil,
    download: DownloadFunction? = nil,
    runtimeContext initialRuntimeContext: Context = [:],
    toolsContext initialToolsContext: ToolsContext = [:],
    include includeOptions: GenerateTextInclude? = nil,
    internalOptions _internal: GenerateTextInternalOptions = GenerateTextInternalOptions(),
    onStart: GenerateTextOnStartCallback? = nil,
    onStepStart: GenerateTextOnStepStartCallback? = nil,
    onLanguageModelCallStart: OnLanguageModelCallStartCallback? = nil,
    onLanguageModelCallEnd: OnLanguageModelCallEndCallback? = nil,
    onToolExecutionStart: OnToolExecutionStartCallback? = nil,
    onToolExecutionEnd: OnToolExecutionEndCallback? = nil,
    onStepEnd: GenerateTextOnStepEndCallback? = nil,
    onEnd: GenerateTextOnEndCallback? = nil,
    settings: CallSettings = CallSettings()
) async throws -> DefaultGenerateTextResult<OutputValue> {
    let includeRequestBody = includeOptions?.requestBody ?? false
    let includeRequestMessages = includeOptions?.requestMessages ?? false
    let includeResponseBody = includeOptions?.responseBody ?? false

    let resolvedToolCallConcurrency = try prepareToolCallConcurrency(toolCallConcurrency)
    let model = try resolveLanguageModelV4(modelArg)
    let now = _internal.now

    var unsupportedTimeoutWarnings: [Warning] = []
    if getFirstChunkTimeoutMs(settings.timeout) != nil {
        unsupportedTimeoutWarnings.append(.languageModel(.unsupported(
            feature: "timeout.firstChunkMs",
            details: "The firstChunkMs timeout is only supported by streaming functions."
        )))
    }
    if getChunkTimeoutMs(settings.timeout) != nil {
        unsupportedTimeoutWarnings.append(.languageModel(.unsupported(
            feature: "timeout.chunkMs",
            details: "The chunkMs timeout is only supported by streaming functions."
        )))
    }
    if !unsupportedTimeoutWarnings.isEmpty {
        logWarnings(unsupportedTimeoutWarnings)
    }

    let stepTimeoutMs = getStepTimeoutMs(settings.timeout)
    let stepTimeout = StepAbortTimeout()
    let stepAbortSignal: (@Sendable () -> Bool)? = stepTimeoutMs != nil ? { @Sendable in stepTimeout.isAborted } : nil
    let mergedAbortSignal = mergeAbortSignals(
        settings.abortSignal,
        deadlineAbortSignal(getTotalTimeoutMs(settings.timeout)),
        stepAbortSignal
    )

    let preparedRetries = try prepareRetries(maxRetries: settings.maxRetries, abortSignal: mergedAbortSignal)
    let callSettings = try settings.languageModelCallOptions.prepared()
    let headersWithUserAgent = withUserAgentSuffix(settings.headers ?? [:], "ai/\(VERSION)")

    let initialPrompt = try standardizePrompt(Prompt(
        instructions: instructions,
        system: system,
        allowSystemInMessages: allowSystemInMessages,
        prompt: prompt.map(PromptContent.text),
        messages: messages
    ))

    let callId = _internal.generateCallId()
    let dispatcher = TelemetryDispatcher(telemetry: telemetry)

    let startEvent = GenerateTextStartEvent(
        callId: callId,
        operationId: "ai.generateText",
        provider: model.provider,
        modelId: model.modelId,
        instructions: initialPrompt.instructions,
        messages: initialPrompt.messages,
        tools: tools,
        toolChoice: toolChoice,
        activeTools: activeTools,
        toolOrder: toolOrder,
        callOptions: callSettings,
        maxRetries: preparedRetries.maxRetries,
        timeout: settings.timeout,
        headers: headersWithUserAgent,
        providerOptions: providerOptions,
        output: output,
        toolsContext: initialToolsContext,
        runtimeContext: initialRuntimeContext
    )

    await notify(
        invoke(onStart, with: startEvent),
        { await dispatcher.onStart(.generateText(startEvent)) }
    )

    do {
        var runtimeContext = initialRuntimeContext
        var toolsContext = initialToolsContext
        let initialMessages = initialPrompt.messages
        var initialResponseMessages: [ResponseMessage] = []

        let collected = try collectToolApprovals(messages: initialMessages)
        let validated = try await validateApprovedToolApprovals(
            collected.approvedToolApprovals.filter { $0.toolCall.providerExecuted != true },
            tools: tools,
            toolApproval: toolApproval,
            messages: initialMessages,
            toolsContext: toolsContext,
            runtimeContext: runtimeContext,
            refineToolInput: refineToolInput
        )

        let deniedToolApprovals = collected.deniedToolApprovals + validated.denied
        let deniedWithoutResults = deniedToolApprovals.filter { $0.existingToolResult == nil }

        if !deniedWithoutResults.isEmpty || !validated.approved.isEmpty || !validated.invalid.isEmpty {
            let toolResults = try await executeToolCalls(
                validated.approved.map(\.toolCall),
                tools: tools,
                toolsContext: toolsContext,
                callId: callId,
                messages: initialMessages,
                abortSignal: mergedAbortSignal,
                timeout: settings.timeout,
                telemetry: dispatcher,
                toolCallConcurrency: resolvedToolCallConcurrency,
                onToolExecutionStart: onToolExecutionStart,
                onToolExecutionEnd: onToolExecutionEnd
            )

            var toolContent: [ToolContentPart] = []

            for result in toolResults {
                let output = result.output
                let isError: Bool
                let value: Any?
                switch output {
                case .result(let toolResult):
                    isError = false
                    value = toolResult.output
                case .error(let toolError):
                    isError = true
                    value = toolError.error
                }
                toolContent.append(.toolResult(ToolResultPart(
                    toolCallId: output.toolCallId,
                    toolName: output.toolName,
                    output: try await createToolModelOutput(
                        toolCallId: output.toolCallId,
                        input: output.input,
                        output: value,
                        tool: tools?[output.toolName],
                        errorMode: isError ? .text : .none
                    )
                )))
            }

            // Invalid approved calls are reported to the model without executing them:
            // repairing the input after approval would change the authorized operation.
            for invalid in validated.invalid {
                let toolCall = invalid.approval.toolCall
                toolContent.append(.toolResult(ToolResultPart(
                    toolCallId: toolCall.toolCallId,
                    toolName: toolCall.toolName,
                    output: try await createToolModelOutput(
                        toolCallId: toolCall.toolCallId,
                        input: toolCall.input,
                        output: invalid.error,
                        tool: tools?[toolCall.toolName],
                        errorMode: .text
                    )
                )))
            }

            for denied in deniedWithoutResults {
                let outputProviderOptions: ProviderOptions? = denied.toolCall.providerExecuted == true
                    ? ["openai": ["approvalId": .string(denied.approvalResponse.approvalId)]]
                    : nil
                toolContent.append(.toolResult(ToolResultPart(
                    toolCallId: denied.toolCall.toolCallId,
                    toolName: denied.toolCall.toolName,
                    output: .executionDenied(reason: denied.approvalResponse.reason, providerOptions: outputProviderOptions)
                )))
            }

            initialResponseMessages.append(.tool(ToolModelMessage(content: toolContent)))
        }

        var steps: [StepResult] = []
        var clientToolCalls: [TypedToolCall] = []
        var clientToolOutputs: [ToolOutput] = []
        var deniedToolApprovalResponses: [ToolApprovalResponseOutput] = []
        var instructionsForNextStep = initialPrompt.instructions
        var messagesForNextStep = initialMessages + initialResponseMessages.map { $0.modelMessage }
        var pendingDeferredToolCalls: [String: String] = [:]

        while true {
            if !steps.isEmpty {
                try checkAbort(mergedAbortSignal)
            }

            stepTimeout.start(stepTimeoutMs)
            defer { stepTimeout.clear() }

            let stepNumber = steps.count
            let accumulatedResponseMessages = initialResponseMessages + steps.flatMap(\.response.messages)
            let stepInputMessages = messagesForNextStep

            let prepareStepResult = try await prepareStep?(PrepareStepOptions(
                steps: steps,
                stepNumber: stepNumber,
                model: .v4(model),
                instructions: instructionsForNextStep,
                initialInstructions: initialPrompt.instructions,
                messages: stepInputMessages,
                initialMessages: initialMessages,
                responseMessages: accumulatedResponseMessages,
                toolsContext: toolsContext,
                runtimeContext: runtimeContext
            ))

            let stepModel = try prepareStepResult?.model.map(resolveLanguageModelV4) ?? model
            let stepInstructions = prepareStepResult?.resolvedInstructions ?? instructionsForNextStep
            runtimeContext = prepareStepResult?.runtimeContext ?? runtimeContext
            toolsContext = prepareStepResult?.toolsContext ?? toolsContext

            let stepActiveTools = prepareStepResult?.activeTools ?? activeTools
            let stepExecutionTools = filterActiveTools(tools, activeTools: stepActiveTools)
            let stepToolOrder = prepareStepResult?.toolOrder ?? toolOrder
            let stepTools = try await prepareTools(
                tools: stepExecutionTools,
                toolOrder: stepToolOrder,
                toolsContext: toolsContext
            )
            let stepToolChoiceSetting = prepareStepResult?.toolChoice ?? toolChoice
            let stepToolChoice = prepareToolChoice(stepToolChoiceSetting)
            let stepMessages = prepareStepResult?.messages ?? stepInputMessages

            let promptMessages = try await convertToLanguageModelV4Prompt(
                prompt: StandardizedPrompt(instructions: stepInstructions, messages: stepMessages),
                supportedUrls: try await stepModel.supportedUrls,
                download: download
            )

            let stepProviderOptions = mergeProviderOptions(providerOptions, prepareStepResult?.providerOptions)
            let stepCallSettings = try callSettings.overridden(by: prepareStepResult?.callOptions)

            let stepStartEvent = GenerateTextStepStartEvent(
                callId: callId,
                provider: stepModel.provider,
                modelId: stepModel.modelId,
                stepNumber: stepNumber,
                instructions: stepInstructions,
                messages: stepMessages,
                tools: tools,
                toolChoice: stepToolChoiceSetting,
                activeTools: stepActiveTools,
                toolOrder: stepToolOrder,
                steps: steps,
                providerOptions: stepProviderOptions,
                output: output,
                runtimeContext: runtimeContext,
                toolsContext: toolsContext,
                promptMessages: promptMessages,
                stepTools: stepTools,
                stepToolChoice: stepToolChoice
            )
            await notify(
                invoke(onStepStart, with: stepStartEvent),
                { await dispatcher.onStepStart(stepStartEvent) }
            )

            let languageModelCallStartEvent = LanguageModelCallStartEvent(
                callId: callId,
                provider: stepModel.provider,
                modelId: stepModel.modelId,
                instructions: stepInstructions,
                messages: stepMessages,
                tools: stepTools,
                callOptions: stepCallSettings
            )

            let stepStartTimestampMs = now()

            await notify(
                invoke(onLanguageModelCallStart, with: languageModelCallStartEvent),
                { await dispatcher.onLanguageModelCallStart(languageModelCallStartEvent) }
            )

            let responseFormat = try await output.responseFormat()
            let modelResponse: ModelGenerateResponse = try await preparedRetries.retry.call {
                let result = try await dispatcher.executeLanguageModelCall(languageModelCallStartEvent) {
                    try await stepModel.doGenerate(options: LanguageModelV4CallOptions(
                        prompt: promptMessages,
                        maxOutputTokens: stepCallSettings.maxOutputTokens,
                        temperature: stepCallSettings.temperature,
                        stopSequences: stepCallSettings.stopSequences,
                        topP: stepCallSettings.topP,
                        topK: stepCallSettings.topK,
                        presencePenalty: stepCallSettings.presencePenalty,
                        frequencyPenalty: stepCallSettings.frequencyPenalty,
                        responseFormat: responseFormat,
                        seed: stepCallSettings.seed,
                        tools: stepTools,
                        toolChoice: stepToolChoice,
                        abortSignal: mergedAbortSignal,
                        headers: headersWithUserAgent,
                        reasoning: stepCallSettings.reasoning,
                        providerOptions: stepProviderOptions
                    ))
                }
                return ModelGenerateResponse(
                    result: result,
                    metadata: LanguageModelResponseMetadata(
                        id: result.response?.id ?? _internal.generateId(),
                        timestamp: result.response?.timestamp ?? _internal.currentDate(),
                        modelId: result.response?.modelId ?? stepModel.modelId,
                        headers: result.response?.headers
                    )
                )
            }
            let currentModelResponse = modelResponse.result
            let responseTimeMs = now() - stepStartTimestampMs
            let stepUsage = asLanguageModelUsage(currentModelResponse.usage)
            let finishReason = currentModelResponse.finishReason.unified

            var stepToolCalls: [TypedToolCall] = []
            for part in currentModelResponse.content {
                guard case .toolCall(let toolCall) = part else { continue }
                stepToolCalls.append(try await parseToolCall(
                    toolCall: toolCall,
                    tools: stepExecutionTools,
                    repairToolCall: repairToolCall,
                    refineToolInput: refineToolInput,
                    instructions: stepInstructions,
                    messages: stepMessages,
                    abortSignal: mergedAbortSignal
                ))
            }

            let generatedFileDataCache = GeneratedFileDataCache()
            let modelCallContent = try await convertLanguageModelContent(
                content: currentModelResponse.content,
                toolCalls: stepToolCalls,
                toolOutputs: [],
                toolApprovalRequests: [],
                toolApprovalResponses: [],
                tools: tools,
                abortSignal: mergedAbortSignal,
                generatedFileDataCache: generatedFileDataCache
            )

            let languageModelCallEndEvent = LanguageModelCallEndEvent(
                callId: callId,
                provider: stepModel.provider,
                modelId: modelResponse.metadata.modelId,
                finishReason: finishReason,
                usage: stepUsage,
                content: modelCallContent,
                responseId: modelResponse.metadata.id,
                providerMetadata: currentModelResponse.providerMetadata,
                performance: LanguageModelCallPerformance(
                    responseTimeMs: responseTimeMs,
                    effectiveOutputTokensPerSecond: calculateTokensPerSecond(
                        tokens: stepUsage.outputTokens, durationMs: responseTimeMs
                    ),
                    effectiveTotalTokensPerSecond: calculateTokensPerSecond(
                        tokens: sumTokenCounts(stepUsage.inputTokens, stepUsage.outputTokens),
                        durationMs: responseTimeMs
                    )
                )
            )
            await notify(
                invoke(onLanguageModelCallEnd, with: languageModelCallEndEvent),
                { await dispatcher.onLanguageModelCallEnd(languageModelCallEndEvent) }
            )

            if let enforced = enforcedToolChoice(stepToolChoice),
               !stepToolCalls.contains(where: { toolCall in
                   if case .tool(let toolName) = enforced { return toolCall.toolName == toolName }
                   return true
               }) {
                throw ToolChoiceViolationError(
                    toolChoice: enforced,
                    finishReason: finishReason,
                    provider: stepModel.provider,
                    modelId: stepModel.modelId,
                    content: currentModelResponse.content
                )
            }

            var toolApprovalRequests: [String: ToolApprovalRequestOutput] = [:]
            var stepToolApprovalResponses: [String: ToolApprovalResponseOutput] = [:]
            var approvalOrder: [String] = []
            var blockedToolCallIds: Set<String> = []

            for toolCall in stepToolCalls {
                if toolCall.invalid == true { continue }

                // Tool calls for unavailable tools (e.g. provider-executed dynamic tools) are skipped.
                guard let tool = stepExecutionTools?[toolCall.toolName] else { continue }

                if tool.onInputStart != nil || tool.onInputAvailable != nil {
                    let context = try await validateToolContext(
                        toolName: toolCall.toolName,
                        context: toolsContext[toolCall.toolName],
                        contextSchema: tool.contextSchema
                    )
                    if let onInputStart = tool.onInputStart {
                        try await onInputStart(ToolExecutionOptions(
                            toolCallId: toolCall.toolCallId,
                            messages: stepMessages,
                            abortSignal: mergedAbortSignal,
                            context: context
                        ))
                    }
                    if let onInputAvailable = tool.onInputAvailable {
                        try await onInputAvailable(ToolCallInputOptions(
                            input: toolCall.input,
                            toolCallId: toolCall.toolCallId,
                            messages: stepMessages,
                            abortSignal: mergedAbortSignal,
                            context: context
                        ))
                    }
                }

                let status = try await resolveToolApproval(
                    tools: stepExecutionTools,
                    toolCall: toolCall,
                    toolApproval: toolApproval,
                    messages: stepMessages,
                    toolsContext: toolsContext,
                    runtimeContext: runtimeContext
                )

                // Tools without approval must not consume an approval id, keeping id sequences stable.
                if status == .notApplicable { continue }

                let approvalId = _internal.generateId()
                approvalOrder.append(toolCall.toolCallId)

                switch status {
                case .userApproval(let reason):
                    toolApprovalRequests[toolCall.toolCallId] = ToolApprovalRequestOutput(
                        approvalId: approvalId,
                        toolCall: toolCall,
                        reason: reason
                    )
                    blockedToolCallIds.insert(toolCall.toolCallId)

                case .approved(let reason):
                    toolApprovalRequests[toolCall.toolCallId] = ToolApprovalRequestOutput(
                        approvalId: approvalId,
                        toolCall: toolCall,
                        isAutomatic: true
                    )
                    stepToolApprovalResponses[toolCall.toolCallId] = ToolApprovalResponseOutput(
                        approvalId: approvalId,
                        toolCall: toolCall,
                        approved: true,
                        reason: reason,
                        providerExecuted: toolCall.providerExecuted
                    )

                case .denied(let reason):
                    toolApprovalRequests[toolCall.toolCallId] = ToolApprovalRequestOutput(
                        approvalId: approvalId,
                        toolCall: toolCall,
                        isAutomatic: true
                    )
                    stepToolApprovalResponses[toolCall.toolCallId] = ToolApprovalResponseOutput(
                        approvalId: approvalId,
                        toolCall: toolCall,
                        approved: false,
                        reason: reason,
                        providerExecuted: toolCall.providerExecuted
                    )
                    blockedToolCallIds.insert(toolCall.toolCallId)

                case .notApplicable:
                    break
                }
            }

            // Invalid dynamic client tool calls get error outputs.
            clientToolOutputs = stepToolCalls
                .filter { $0.invalid == true && $0.isDynamic && $0.providerExecuted != true }
                .map { toolCall in
                    .error(.dynamic(DynamicToolError(
                        toolCallId: toolCall.toolCallId,
                        toolName: toolCall.toolName,
                        input: toolCall.input,
                        error: InvalidToolCallMessageError(message: AISDKProvider.getErrorMessage(toolCall.error))
                    )))
                }

            clientToolCalls = stepToolCalls.filter { $0.providerExecuted != true }
            let toolApprovalResponses = approvalOrder.compactMap { stepToolApprovalResponses[$0] }
            deniedToolApprovalResponses = toolApprovalResponses.filter { !$0.approved }
            var toolExecutionMs: [String: Double] = [:]

            if stepExecutionTools != nil, isToolExecutionAllowedFinishReason(finishReason) {
                let results = try await executeToolCalls(
                    clientToolCalls.filter { $0.invalid != true && !blockedToolCallIds.contains($0.toolCallId) },
                    tools: stepExecutionTools,
                    toolsContext: toolsContext,
                    callId: callId,
                    messages: stepMessages,
                    abortSignal: mergedAbortSignal,
                    timeout: settings.timeout,
                    telemetry: dispatcher,
                    toolCallConcurrency: resolvedToolCallConcurrency,
                    onToolExecutionStart: onToolExecutionStart,
                    onToolExecutionEnd: onToolExecutionEnd
                )
                for result in results {
                    toolExecutionMs[result.output.toolCallId] = result.toolExecutionMs
                    clientToolOutputs.append(result.output)
                }
            }

            let stepPerformance = StepResultPerformance(
                effectiveOutputTokensPerSecond: calculateTokensPerSecond(
                    tokens: stepUsage.outputTokens, durationMs: responseTimeMs
                ),
                effectiveTotalTokensPerSecond: calculateTokensPerSecond(
                    tokens: sumTokenCounts(stepUsage.inputTokens, stepUsage.outputTokens),
                    durationMs: responseTimeMs
                ),
                stepTimeMs: now() - stepStartTimestampMs,
                responseTimeMs: responseTimeMs,
                toolExecutionMs: toolExecutionMs
            )

            // Provider-executed tools with deferred results may return their result in a later step.
            for toolCall in stepToolCalls where toolCall.providerExecuted == true {
                guard let tool = stepExecutionTools?[toolCall.toolName],
                      tool.type == .provider, tool.supportsDeferredResults == true else { continue }
                let hasResultInResponse = currentModelResponse.content.contains { part in
                    if case .toolResult(let result) = part { return result.toolCallId == toolCall.toolCallId }
                    return false
                }
                if !hasResultInResponse {
                    pendingDeferredToolCalls[toolCall.toolCallId] = toolCall.toolName
                }
            }
            for part in currentModelResponse.content {
                if case .toolResult(let result) = part {
                    pendingDeferredToolCalls.removeValue(forKey: result.toolCallId)
                }
            }

            let stepContent = try await convertLanguageModelContent(
                content: currentModelResponse.content,
                toolCalls: stepToolCalls,
                toolOutputs: clientToolOutputs,
                toolApprovalRequests: approvalOrder.compactMap { toolApprovalRequests[$0] },
                toolApprovalResponses: toolApprovalResponses,
                tools: tools,
                abortSignal: mergedAbortSignal,
                generatedFileDataCache: generatedFileDataCache
            )

            let stepResponseMessages = try await toResponseMessages(content: stepContent, tools: tools)

            let stepRequest = LanguageModelRequestMetadata(
                messages: includeRequestMessages ? stepMessages : nil,
                body: includeRequestBody ? currentModelResponse.request?.body.flatMap { try? jsonValue(from: $0) } : nil
            )
            let stepResponse = StepResultResponse(
                from: modelResponse.metadata,
                messages: stepResponseMessages,
                body: includeResponseBody ? currentModelResponse.response?.body.flatMap { try? jsonValue(from: $0) } : nil
            )

            let currentStepResult = DefaultStepResult(
                callId: callId,
                stepNumber: stepNumber,
                model: ModelInfo(provider: stepModel.provider, modelId: stepModel.modelId),
                toolsContext: toolsContext,
                runtimeContext: runtimeContext,
                content: stepContent,
                finishReason: finishReason,
                rawFinishReason: currentModelResponse.finishReason.raw,
                usage: stepUsage,
                performance: stepPerformance,
                warnings: currentModelResponse.warnings,
                request: stepRequest,
                response: stepResponse,
                providerMetadata: currentModelResponse.providerMetadata
            )

            if !currentModelResponse.warnings.isEmpty {
                logWarnings(currentModelResponse.warnings.map(Warning.languageModel))
            }

            steps.append(currentStepResult)
            instructionsForNextStep = stepInstructions
            messagesForNextStep = stepMessages + stepResponseMessages.map { $0.modelMessage }

            await notify(
                invoke(onStepEnd, with: currentStepResult as StepResult),
                { await dispatcher.onStepEnd(currentStepResult) }
            )

            // Continue only when every client tool call has an output or a denial,
            // there is something to continue with, and no stop condition is met.
            guard clientToolOutputs.count + deniedToolApprovalResponses.count == clientToolCalls.count,
                  !clientToolCalls.isEmpty || !pendingDeferredToolCalls.isEmpty,
                  try await !isStopConditionMet(stopConditions: stopWhen, steps: steps) else {
                break
            }
        }

        let totalUsage = steps.reduce(LanguageModelUsage()) { addLanguageModelUsage($0, $1.usage) }
        let lastStep = steps[steps.count - 1]

        let endEvent = GenerateTextEndEvent(
            callId: callId,
            steps: steps,
            initialResponseMessages: initialResponseMessages,
            totalUsage: totalUsage
        )
        await notify(
            invoke(onEnd, with: endEvent),
            { await dispatcher.onEnd(.generateText(endEvent)) }
        )

        // Parse the output for stop responses and for non-empty responses without tool calls.
        var resolvedOutput: OutputValue?
        if lastStep.finishReason == .stop || (lastStep.finishReason != .toolCalls && !lastStep.text.isEmpty) {
            resolvedOutput = try await output.parseOutput(
                text: lastStep.text,
                response: lastStep.response.metadata,
                usage: lastStep.usage,
                finishReason: lastStep.finishReason
            )
        }

        return DefaultGenerateTextResult(
            initialResponseMessages: initialResponseMessages,
            steps: steps,
            totalUsage: totalUsage,
            resolvedOutput: resolvedOutput
        )
    } catch {
        await dispatcher.onError(callId: callId, error: error)
        throw (wrapGatewayError(error) as? Error) ?? error
    }
}

/**
 Generates text without a structured output; `result.output` is the final text.

 Same as `generateText(model:output:…)` with `Output.text()`.
 */
public func generateText(
    model: LanguageModel,
    tools: ToolSet? = nil,
    toolChoice: ToolChoice? = nil,
    instructions: Instructions? = nil,
    system: Instructions? = nil,
    prompt: String? = nil,
    messages: [ModelMessage]? = nil,
    allowSystemInMessages: Bool? = nil,
    stopWhen: [StopCondition] = [isStepCount(1)],
    toolApproval: ToolApprovalConfiguration? = nil,
    telemetry: TelemetryOptions? = nil,
    providerOptions: ProviderOptions? = nil,
    activeTools: [String]? = nil,
    toolOrder: [String]? = nil,
    toolCallConcurrency: Int? = nil,
    prepareStep: PrepareStepFunction? = nil,
    repairToolCall: ToolCallRepairFunction? = nil,
    refineToolInput: ToolInputRefinement? = nil,
    download: DownloadFunction? = nil,
    runtimeContext: Context = [:],
    toolsContext: ToolsContext = [:],
    include: GenerateTextInclude? = nil,
    internalOptions: GenerateTextInternalOptions = GenerateTextInternalOptions(),
    onStart: GenerateTextOnStartCallback? = nil,
    onStepStart: GenerateTextOnStepStartCallback? = nil,
    onLanguageModelCallStart: OnLanguageModelCallStartCallback? = nil,
    onLanguageModelCallEnd: OnLanguageModelCallEndCallback? = nil,
    onToolExecutionStart: OnToolExecutionStartCallback? = nil,
    onToolExecutionEnd: OnToolExecutionEndCallback? = nil,
    onStepEnd: GenerateTextOnStepEndCallback? = nil,
    onEnd: GenerateTextOnEndCallback? = nil,
    settings: CallSettings = CallSettings()
) async throws -> DefaultGenerateTextResult<String> {
    try await generateText(
        model: model,
        tools: tools,
        toolChoice: toolChoice,
        instructions: instructions,
        system: system,
        prompt: prompt,
        messages: messages,
        allowSystemInMessages: allowSystemInMessages,
        stopWhen: stopWhen,
        output: Output.text(),
        toolApproval: toolApproval,
        telemetry: telemetry,
        providerOptions: providerOptions,
        activeTools: activeTools,
        toolOrder: toolOrder,
        toolCallConcurrency: toolCallConcurrency,
        prepareStep: prepareStep,
        repairToolCall: repairToolCall,
        refineToolInput: refineToolInput,
        download: download,
        runtimeContext: runtimeContext,
        toolsContext: toolsContext,
        include: include,
        internalOptions: internalOptions,
        onStart: onStart,
        onStepStart: onStepStart,
        onLanguageModelCallStart: onLanguageModelCallStart,
        onLanguageModelCallEnd: onLanguageModelCallEnd,
        onToolExecutionStart: onToolExecutionStart,
        onToolExecutionEnd: onToolExecutionEnd,
        onStepEnd: onStepEnd,
        onEnd: onEnd,
        settings: settings
    )
}

/// A model response with the normalized response metadata.
private struct ModelGenerateResponse: @unchecked Sendable {
    let result: LanguageModelV4GenerateResult
    let metadata: LanguageModelResponseMetadata
}

/// Error output of an invalid dynamic tool call: the message of the parse error.
struct InvalidToolCallMessageError: LocalizedError, CustomStringConvertible, Sendable {
    let message: String
    var errorDescription: String? { message }
    var description: String { message }
}

extension ResponseMessage {
    /// The response message as a model message.
    var modelMessage: ModelMessage {
        switch self {
        case .assistant(let message): return .assistant(message)
        case .tool(let message): return .tool(message)
        }
    }
}
