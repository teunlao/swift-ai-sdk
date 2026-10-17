import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Parts flowing through a streaming step, between the provider and the step
 output: public stream parts plus the model-call and tool-execution events the
 step consumes.

 Port of `LanguageModelStreamPart` from
 `@ai-sdk/ai/src/generate-text/stream-language-model-call.ts`, the
 `tool-execution-end` part of `execute-tools-from-stream.ts` and the retry
 attempt boundary of `stream-retry-attempt-boundary.ts`.
 */
enum StepStreamPart: Sendable {
    case part(TextStreamPart)
    case modelCallStart(warnings: [CallWarning])
    case modelCallEnd(
        finishReason: FinishReason,
        rawFinishReason: String?,
        usage: LanguageModelUsage,
        providerMetadata: ProviderMetadata?,
        performance: LanguageModelCallPerformance
    )
    case modelCallResponseMetadata(id: String?, timestamp: Date?, modelId: String?)
    case toolExecutionEnd(toolCallId: String, toolExecutionMs: Double)
    case retryAttemptBoundary(warnings: [CallWarning])

    /**
     Whether the part is semantic model output: non-empty text, reasoning or
     tool input deltas, files and tool calls.

     Port of `@ai-sdk/ai/src/generate-text/is-output-chunk.ts`.
     */
    var isOutputChunk: Bool {
        guard case .part(let part) = self else { return false }
        switch part {
        case .textDelta(_, let text, _), .reasoningDelta(_, let text, _):
            return !text.isEmpty
        case .toolInputDelta(_, let delta, _):
            return !delta.isEmpty
        case .file, .reasoningFile, .toolCall:
            return true
        default:
            return false
        }
    }
}

/// The started provider stream of a step.
struct LanguageModelCallStream: Sendable {
    let stream: AsyncThrowingStream<StepStreamPart, Error>
    let request: LanguageModelV4RequestInfo?
    let response: LanguageModelV4StreamResponseInfo?
    /// Cancels the provider stream, ending its request.
    let cancel: @Sendable () async -> Void
}

/**
 Starts one provider streaming call and converts its parts.

 Port of `streamLanguageModelCall` from
 `@ai-sdk/ai/src/generate-text/stream-language-model-call.ts`: converts the
 prompt, notifies the step start (once per step, via `onStart`) and the model
 call start, calls `doStream` inside the telemetry model-call context, and
 transforms provider parts: tool calls are parsed, provider errors normalized,
 performance measured, and an enforced tool choice checked at `finish`.
 */
func streamLanguageModelCall(
    model: any LanguageModelV4,
    tools: ToolSet?,
    modelTools: ToolSet?,
    toolOrder: [String]?,
    responseFormat: LanguageModelV4ResponseFormat?,
    toolChoice: ToolChoice?,
    instructions: Instructions?,
    messages: [ModelMessage],
    download: DownloadFunction?,
    abortSignal: (@Sendable () -> Bool)?,
    headers: [String: String],
    includeRawChunks: Bool,
    providerOptions: ProviderOptions?,
    repairToolCall: ToolCallRepairFunction?,
    refineToolInput: ToolInputRefinement?,
    callId: String,
    toolsContext: ToolsContext,
    callOptions: LanguageModelCallOptions,
    telemetry: TelemetryDispatcher,
    generateId: @escaping IDGenerator,
    now: @escaping @Sendable () -> Double,
    onStart: @escaping @Sendable (_ promptMessages: LanguageModelV4Prompt, _ stepTools: [LanguageModelV4Tool]?, _ stepToolChoice: LanguageModelV4ToolChoice) async -> Void,
    onLanguageModelCallStart: OnLanguageModelCallStartCallback?,
    onLanguageModelCallEnd: OnLanguageModelCallEndCallback?
) async throws -> LanguageModelCallStream {
    let promptMessages = try await convertToLanguageModelPrompt(
        prompt: StandardizedPrompt(instructions: instructions, messages: messages),
        supportedUrls: try await model.supportedUrls,
        download: download,
        abortSignal: abortSignal
    )

    let stepTools = try await prepareTools(tools: modelTools, toolOrder: toolOrder, toolsContext: toolsContext)
    let stepToolChoice = prepareToolChoice(toolChoice)

    await onStart(promptMessages, stepTools, stepToolChoice)

    let startEvent = LanguageModelCallStartEvent(
        callId: callId,
        provider: model.provider,
        modelId: model.modelId,
        instructions: instructions,
        messages: messages,
        tools: stepTools,
        callOptions: callOptions
    )
    await notify(
        invoke(onLanguageModelCallStart, with: startEvent),
        { await telemetry.onLanguageModelCallStart(startEvent) }
    )

    let callStartTimestampMs = now()

    let result = try await telemetry.executeLanguageModelCall(startEvent) {
        try await model.doStream(options: LanguageModelV4CallOptions(
            prompt: promptMessages,
            maxOutputTokens: callOptions.maxOutputTokens,
            temperature: callOptions.temperature,
            stopSequences: callOptions.stopSequences,
            topP: callOptions.topP,
            topK: callOptions.topK,
            presencePenalty: callOptions.presencePenalty,
            frequencyPenalty: callOptions.frequencyPenalty,
            responseFormat: responseFormat,
            seed: callOptions.seed,
            tools: stepTools,
            toolChoice: stepToolChoice,
            includeRawChunks: includeRawChunks,
            abortSignal: abortSignal,
            headers: headers,
            reasoning: callOptions.reasoning,
            providerOptions: providerOptions
        ))
    }

    let state = LanguageModelStreamState(
        tools: tools,
        instructions: instructions,
        messages: messages,
        repairToolCall: repairToolCall,
        refineToolInput: refineToolInput,
        abortSignal: abortSignal,
        callId: callId,
        provider: model.provider,
        modelId: model.modelId,
        toolChoice: stepToolChoice,
        responseId: generateId(),
        now: now,
        callStartTimestampMs: callStartTimestampMs,
        telemetry: telemetry,
        onLanguageModelCallEnd: onLanguageModelCallEnd
    )

    let providerStream = result.stream
    return LanguageModelCallStream(
        stream: pullTransform(providerStream) { chunk in try await state.transform(chunk) },
        request: result.request,
        response: result.response,
        cancel: { await cancelStream(providerStream) }
    )
}

/// State of the provider part conversion of one model call.
private final class LanguageModelStreamState: @unchecked Sendable {
    let tools: ToolSet?
    let instructions: Instructions?
    let messages: [ModelMessage]
    let repairToolCall: ToolCallRepairFunction?
    let refineToolInput: ToolInputRefinement?
    let abortSignal: (@Sendable () -> Bool)?
    let callId: String
    let provider: String
    let modelId: String
    let toolChoice: LanguageModelV4ToolChoice
    let now: @Sendable () -> Double
    let callStartTimestampMs: Double
    let telemetry: TelemetryDispatcher
    let onLanguageModelCallEnd: OnLanguageModelCallEndCallback?

    var responseId: String
    var responseModelId: String
    var toolCallsById: [String: TypedToolCall] = [:]
    var modelCallContent: [ContentPart] = []
    var rawModelCallContent: [LanguageModelV4Content] = []
    var textPartIndexes: [String: Int] = [:]
    var reasoningPartIndexes: [String: Int] = [:]
    var rawTextPartIndexes: [String: Int] = [:]
    var rawReasoningPartIndexes: [String: Int] = [:]
    var timeToFirstOutputMs: Double?
    var previousOutputChunkTimestampMs: Double?
    var timeBetweenOutputChunksMs: [Double] = []

    init(
        tools: ToolSet?,
        instructions: Instructions?,
        messages: [ModelMessage],
        repairToolCall: ToolCallRepairFunction?,
        refineToolInput: ToolInputRefinement?,
        abortSignal: (@Sendable () -> Bool)?,
        callId: String,
        provider: String,
        modelId: String,
        toolChoice: LanguageModelV4ToolChoice,
        responseId: String,
        now: @escaping @Sendable () -> Double,
        callStartTimestampMs: Double,
        telemetry: TelemetryDispatcher,
        onLanguageModelCallEnd: OnLanguageModelCallEndCallback?
    ) {
        self.tools = tools
        self.instructions = instructions
        self.messages = messages
        self.repairToolCall = repairToolCall
        self.refineToolInput = refineToolInput
        self.abortSignal = abortSignal
        self.callId = callId
        self.provider = provider
        self.modelId = modelId
        self.toolChoice = toolChoice
        self.responseId = responseId
        self.responseModelId = modelId
        self.now = now
        self.callStartTimestampMs = callStartTimestampMs
        self.telemetry = telemetry
        self.onLanguageModelCallEnd = onLanguageModelCallEnd
    }

    private func isOutputChunk(_ chunk: LanguageModelV4StreamPart) -> Bool {
        switch chunk {
        case .textDelta(_, let delta, _), .reasoningDelta(_, let delta, _), .toolInputDelta(_, let delta, _):
            return !delta.isEmpty
        case .file, .reasoningFile, .toolCall:
            return true
        default:
            return false
        }
    }

    func transform(_ chunk: LanguageModelV4StreamPart) async throws -> [StepStreamPart] {
        if isOutputChunk(chunk) {
            let timestamp = now()
            if timeToFirstOutputMs == nil {
                timeToFirstOutputMs = timestamp - callStartTimestampMs
            } else if let previous = previousOutputChunkTimestampMs {
                timeBetweenOutputChunksMs.append(timestamp - previous)
            }
            previousOutputChunkTimestampMs = timestamp
        }

        switch chunk {
        case .error(let error):
            return [.part(.error(normalizeStreamProviderError(error)))]

        case .textStart(let id, let metadata):
            upsertText(id: id, reasoning: false, delta: nil, providerMetadata: metadata)
            return [.part(.textStart(id: id, providerMetadata: metadata))]

        case .textDelta(let id, let delta, let metadata):
            upsertText(id: id, reasoning: false, delta: delta, providerMetadata: metadata)
            return [.part(.textDelta(id: id, text: delta, providerMetadata: metadata))]

        case .textEnd(let id, let metadata, let citations):
            upsertText(id: id, reasoning: false, delta: nil, providerMetadata: metadata)
            textPartIndexes[id] = nil
            rawTextPartIndexes[id] = nil
            return [.part(.textEnd(id: id, providerMetadata: metadata, citations: citations))]

        case .reasoningStart(let id, let metadata):
            upsertText(id: id, reasoning: true, delta: nil, providerMetadata: metadata)
            return [.part(.reasoningStart(id: id, providerMetadata: metadata))]

        case .reasoningDelta(let id, let delta, let metadata):
            upsertText(id: id, reasoning: true, delta: delta, providerMetadata: metadata)
            return [.part(.reasoningDelta(id: id, text: delta, providerMetadata: metadata))]

        case .reasoningEnd(let id, let metadata):
            upsertText(id: id, reasoning: true, delta: nil, providerMetadata: metadata)
            reasoningPartIndexes[id] = nil
            rawReasoningPartIndexes[id] = nil
            return [.part(.reasoningEnd(id: id, providerMetadata: metadata))]

        case .file(let file):
            let generated = try await resolveGeneratedFile(
                data: file.data, mediaType: file.mediaType, abortSignal: abortSignal, cache: nil
            )
            modelCallContent.append(.file(file: generated, providerMetadata: file.providerMetadata))
            rawModelCallContent.append(.file(file))
            return [.part(.file(file: generated, providerMetadata: file.providerMetadata))]

        case .reasoningFile(let file):
            let generated = try await resolveGeneratedFile(
                data: file.data, mediaType: file.mediaType, abortSignal: abortSignal, cache: nil
            )
            modelCallContent.append(.reasoningFile(file: generated, providerMetadata: file.providerMetadata))
            rawModelCallContent.append(.reasoningFile(file))
            return [.part(.reasoningFile(file: generated, providerMetadata: file.providerMetadata))]

        case .finish(let finishReason, let rawUsage, let providerMetadata):
            return await finish(finishReason: finishReason, rawUsage: rawUsage, providerMetadata: providerMetadata)

        case .toolCall(let toolCallPart):
            rawModelCallContent.append(.toolCall(toolCallPart))
            do {
                let toolCall = try await parseToolCall(
                    toolCall: toolCallPart,
                    tools: tools,
                    repairToolCall: repairToolCall,
                    refineToolInput: refineToolInput,
                    instructions: instructions,
                    messages: messages,
                    abortSignal: abortSignal
                )
                toolCallsById[toolCall.toolCallId] = toolCall
                modelCallContent.append(.toolCall(toolCall, providerMetadata: toolCall.providerMetadata))

                var parts: [StepStreamPart] = [.part(.toolCall(toolCall))]
                if toolCall.invalid == true, toolCall.providerExecuted != true {
                    parts.append(.part(.toolError(.dynamic(DynamicToolError(
                        toolCallId: toolCall.toolCallId,
                        toolName: toolCall.toolName,
                        title: toolCall.title,
                        input: toolCall.input,
                        error: InvalidToolCallMessageError(message: AISDKProvider.getErrorMessage(toolCall.error)),
                        toolMetadata: toolCall.toolMetadata
                    )))))
                }
                return parts
            } catch {
                return [.part(.error(error))]
            }

        case .toolApprovalRequest(let request):
            rawModelCallContent.append(.toolApprovalRequest(request))
            guard let toolCall = toolCallsById[request.toolCallId] else {
                return [.part(.error(ToolCallNotFoundForApprovalError(
                    toolCallId: request.toolCallId,
                    approvalId: request.approvalId
                )))]
            }
            let approvalRequest = ToolApprovalRequestOutput(approvalId: request.approvalId, toolCall: toolCall)
            modelCallContent.append(.toolApprovalRequest(approvalRequest))
            return [.part(.toolApprovalRequest(approvalRequest))]

        case .toolResult(let resultPart):
            rawModelCallContent.append(.toolResult(resultPart))
            let toolCall = toolCallsById[resultPart.toolCallId]
            let input = toolCall?.input ?? .null
            let dynamic = resultPart.dynamic == true

            let part: TextStreamPart
            let content: ContentPart
            if resultPart.isError == true {
                let error = ProviderToolExecutionError(value: resultPart.result)
                let typed: TypedToolError = dynamic
                    ? .dynamic(DynamicToolError(
                        toolCallId: resultPart.toolCallId, toolName: resultPart.toolName, input: input,
                        error: error, providerExecuted: true, providerMetadata: resultPart.providerMetadata,
                        toolMetadata: toolCall?.toolMetadata
                    ))
                    : .static(StaticToolError(
                        toolCallId: resultPart.toolCallId, toolName: resultPart.toolName, input: input,
                        error: error, providerExecuted: true, providerMetadata: resultPart.providerMetadata,
                        toolMetadata: toolCall?.toolMetadata
                    ))
                part = .toolError(typed)
                content = .toolError(typed, providerMetadata: resultPart.providerMetadata)
            } else {
                let typed: TypedToolResult = dynamic
                    ? .dynamic(DynamicToolResult(
                        toolCallId: resultPart.toolCallId, toolName: resultPart.toolName, input: input,
                        output: resultPart.result, providerExecuted: true, preliminary: resultPart.preliminary,
                        providerMetadata: resultPart.providerMetadata, toolMetadata: toolCall?.toolMetadata
                    ))
                    : .static(StaticToolResult(
                        toolCallId: resultPart.toolCallId, toolName: resultPart.toolName, input: input,
                        output: resultPart.result, providerExecuted: true, preliminary: resultPart.preliminary,
                        providerMetadata: resultPart.providerMetadata, toolMetadata: toolCall?.toolMetadata
                    ))
                part = .toolResult(typed)
                content = .toolResult(typed, providerMetadata: resultPart.providerMetadata)
            }
            modelCallContent.append(content)
            return [.part(part)]

        case .toolInputStart(let id, let toolName, let metadata, let providerExecuted, let dynamic, _, let inputEncoding):
            let tool = tools?[toolName]
            return [.part(.toolInputStart(
                id: id,
                toolName: toolName,
                providerMetadata: metadata,
                providerExecuted: providerExecuted,
                dynamic: dynamic ?? (tool?.type == .dynamic),
                title: tool?.title,
                inputEncoding: inputEncoding,
                toolMetadata: tool?.metadata
            ))]

        case .toolInputDelta(let id, let delta, let metadata):
            return [.part(.toolInputDelta(id: id, delta: delta, providerMetadata: metadata))]

        case .toolInputEnd(let id, let metadata):
            return [.part(.toolInputEnd(id: id, providerMetadata: metadata))]

        case .streamStart(let warnings):
            return [.modelCallStart(warnings: warnings)]

        case .responseMetadata(let id, let modelId, let timestamp):
            responseId = id ?? responseId
            responseModelId = modelId ?? responseModelId
            return [.modelCallResponseMetadata(id: id, timestamp: timestamp, modelId: modelId)]

        case .custom(let custom):
            modelCallContent.append(.custom(kind: custom.kind, providerMetadata: custom.providerMetadata))
            rawModelCallContent.append(.custom(custom))
            return [.part(.custom(kind: custom.kind, providerMetadata: custom.providerMetadata))]

        case .source(let source):
            modelCallContent.append(.source(type: "source", source: source))
            rawModelCallContent.append(.source(source))
            return [.part(.source(source))]

        case .raw(let rawValue):
            return [.part(.raw(rawValue: rawValue))]
        }
    }

    private func finish(
        finishReason: LanguageModelV4FinishReason,
        rawUsage: LanguageModelV4Usage,
        providerMetadata: ProviderMetadata?
    ) async -> [StepStreamPart] {
        let usage = asLanguageModelUsage(rawUsage)
        let responseTimeMs = now() - callStartTimestampMs
        let performance = LanguageModelCallPerformance(
            responseTimeMs: responseTimeMs,
            effectiveOutputTokensPerSecond: calculateTokensPerSecond(
                tokens: usage.outputTokens, durationMs: responseTimeMs
            ),
            outputTokensPerSecond: timeToFirstOutputMs.map {
                calculateTokensPerSecond(tokens: usage.outputTokens, durationMs: responseTimeMs - $0)
            },
            inputTokensPerSecond: timeToFirstOutputMs.map {
                calculateTokensPerSecond(tokens: usage.inputTokens, durationMs: $0)
            },
            effectiveTotalTokensPerSecond: calculateTokensPerSecond(
                tokens: sumTokenCounts(usage.inputTokens, usage.outputTokens),
                durationMs: responseTimeMs
            ),
            timeToFirstOutputMs: timeToFirstOutputMs,
            timeBetweenOutputChunksMs: timeBetweenOutputChunksMs.isEmpty
                ? nil
                : outputChunkTimingStats(timeBetweenOutputChunksMs)
        )

        let endEvent = LanguageModelCallEndEvent(
            callId: callId,
            provider: provider,
            modelId: responseModelId,
            finishReason: finishReason.unified,
            usage: usage,
            content: modelCallContent,
            responseId: responseId,
            providerMetadata: providerMetadata,
            performance: performance
        )
        await notify(
            invoke(onLanguageModelCallEnd, with: endEvent),
            { await self.telemetry.onLanguageModelCallEnd(endEvent) }
        )

        var violation: ToolChoiceViolationError?
        if let enforced = enforcedToolChoice(toolChoice),
           !toolCallsById.values.contains(where: { toolCall in
               if case .tool(let toolName) = enforced { return toolCall.toolName == toolName }
               return true
           }) {
            violation = ToolChoiceViolationError(
                toolChoice: enforced,
                finishReason: finishReason.unified,
                provider: provider,
                modelId: modelId,
                content: rawModelCallContent
            )
        }

        // The model call result is kept even when the response violates the tool choice;
        // the `error` finish reason prevents executing its tool calls.
        var parts: [StepStreamPart] = [.modelCallEnd(
            finishReason: violation == nil ? finishReason.unified : .error,
            rawFinishReason: finishReason.raw,
            usage: usage,
            providerMetadata: providerMetadata,
            performance: performance
        )]
        if let violation {
            parts.append(.part(.error(violation)))
        }
        return parts
    }

    private func upsertText(id: String, reasoning: Bool, delta: String?, providerMetadata: ProviderMetadata?) {
        let index: Int
        if let existing = reasoning ? reasoningPartIndexes[id] : textPartIndexes[id] {
            index = existing
        } else {
            modelCallContent.append(reasoning
                ? .reasoning(ReasoningOutput(text: "", providerMetadata: providerMetadata))
                : .text(text: "", providerMetadata: providerMetadata))
            index = modelCallContent.count - 1
            if reasoning { reasoningPartIndexes[id] = index } else { textPartIndexes[id] = index }
        }

        let rawIndex: Int
        if let existing = reasoning ? rawReasoningPartIndexes[id] : rawTextPartIndexes[id] {
            rawIndex = existing
        } else {
            rawModelCallContent.append(reasoning
                ? .reasoning(LanguageModelV4Reasoning(text: "", providerMetadata: providerMetadata))
                : .text(LanguageModelV4Text(text: "", providerMetadata: providerMetadata)))
            rawIndex = rawModelCallContent.count - 1
            if reasoning { rawReasoningPartIndexes[id] = rawIndex } else { rawTextPartIndexes[id] = rawIndex }
        }

        switch modelCallContent[index] {
        case .text(let text, let citations, let metadata):
            modelCallContent[index] = .text(
                text: text + (delta ?? ""),
                citations: citations,
                providerMetadata: providerMetadata ?? metadata
            )
        case .reasoning(let output):
            modelCallContent[index] = .reasoning(ReasoningOutput(
                text: output.text + (delta ?? ""),
                providerMetadata: providerMetadata ?? output.providerMetadata
            ))
        default:
            break
        }

        switch rawModelCallContent[rawIndex] {
        case .text(let text):
            rawModelCallContent[rawIndex] = .text(LanguageModelV4Text(
                text: text.text + (delta ?? ""),
                providerMetadata: providerMetadata ?? text.providerMetadata
            ))
        case .reasoning(let text):
            rawModelCallContent[rawIndex] = .reasoning(LanguageModelV4Reasoning(
                text: text.text + (delta ?? ""),
                providerMetadata: providerMetadata ?? text.providerMetadata
            ))
        default:
            break
        }
    }
}

/// Port of `calculateOutputChunkTimingStats` from `@ai-sdk/ai/src/generate-text/stream-language-model-call.ts`.
func outputChunkTimingStats(_ timings: [Double]) -> OutputChunkTimingStats {
    let sorted = timings.sorted()
    func percentile(_ value: Double) -> Double {
        sorted[Int((value * Double(sorted.count)).rounded(.up)) - 1]
    }
    return OutputChunkTimingStats(
        min: sorted[0],
        p10: percentile(0.1),
        median: percentile(0.5),
        avg: timings.reduce(0, +) / Double(timings.count),
        p90: percentile(0.9),
        max: sorted[sorted.count - 1]
    )
}
