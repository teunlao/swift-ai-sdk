import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Main non-streaming text generation entry point.

 Port of `@ai-sdk/ai/src/generate-text/generate-text.ts`.

 Orchestrates multi-step language model execution with optional tool calls,
 retries, telemetry, structured output parsing, and result aggregation.
 */
public struct GenerateTextInternalOptions: Sendable {
    /// Generator used for creating unique IDs (tool approvals, responses, etc.).
    public var generateId: IDGenerator

    /// Clock function used when synthesising response timestamps.
    public var currentDate: @Sendable () -> Date

    /**
     Create internal options.

     - Parameters:
       - generateId: Custom ID generator (defaults to `createIDGenerator(prefix:size:)` with prefix `aitxt` and size `24`).
       - currentDate: Clock provider (defaults to `Date.init`).
     */
    public init(
        generateId: IDGenerator? = nil,
        currentDate: @escaping @Sendable () -> Date = Date.init
    ) {
        if let generateId {
            self.generateId = generateId
        } else {
            // Upstream default: createIdGenerator({ prefix: 'aitxt', size: 24 })
            self.generateId = try! createIDGenerator(prefix: "aitxt", size: 24)
        }
        self.currentDate = currentDate
    }
}

// MARK: - Helpers

private actor ResponseMessageStore {
    private var messages: [ResponseMessage] = []

    func all() -> [ResponseMessage] {
        messages
    }

    func append(contentsOf newMessages: [ResponseMessage]) {
        messages.append(contentsOf: newMessages)
    }
}

private struct GenerateStepIntermediate {
    let content: [LanguageModelV3Content]
    let finishReason: FinishReason
    let usage: LanguageModelUsage
    let warnings: [CallWarning]
    let providerMetadata: ProviderMetadata?
    let requestInfo: LanguageModelV3RequestInfo?
    let responseMetadata: LanguageModelResponseMetadata
    let responseBody: JSONValue?
}

private struct ToolCallUnknownError: LocalizedError {
    let toolName: String

    var errorDescription: String? {
        "Tool call \"\(toolName)\" could not be parsed."
    }
}

extension ToolCallUnknownError: CustomStringConvertible {
    var description: String {
        errorDescription ?? "Tool call \"\(toolName)\" could not be parsed."
    }
}

private struct ProviderToolExecutionError: LocalizedError, CustomStringConvertible {
    let value: JSONValue

    var errorDescription: String? {
        "Provider tool execution error."
    }

    var description: String {
        if let json = jsonString(from: value) {
            return json
        }
        return String(describing: value)
    }
}

private func executeTools(
    toolCalls: [TypedToolCall],
    tools: ToolSet?,
    tracer: any Tracer,
    telemetry: TelemetrySettings?,
    messages: [ModelMessage],
    abortSignal: (@Sendable () -> Bool)?,
    experimentalContext: JSONValue?
) async throws -> [ToolOutput] {
    guard let tools, !toolCalls.isEmpty else {
        return []
    }

    return try await withThrowingTaskGroup(of: ToolOutput?.self) { group in
        for toolCall in toolCalls {
            group.addTask {
                await executeToolCall(
                    toolCall: toolCall,
                    tools: tools,
                    tracer: tracer,
                    telemetry: telemetry,
                    messages: messages,
                    abortSignal: abortSignal,
                    experimentalContext: experimentalContext
                )
            }
        }

        var outputs: [ToolOutput] = []
        for try await output in group {
            if let output {
                outputs.append(output)
            }
        }
        return outputs
    }
}

private func makeToolContentPart(
    output: ToolOutput,
    tools: ToolSet?
) -> ToolContentPart {
    switch output {
    case .result(let result):
        let modelOutput = createToolModelOutput(
            output: result.output,
            tool: tools?[result.toolName],
            errorMode: .none
        )
        let part = ToolResultPart(
            toolCallId: result.toolCallId,
            toolName: result.toolName,
            output: modelOutput,
            providerOptions: nil
        )
        return .toolResult(part)

    case .error(let error):
        let modelOutput = createToolModelOutput(
            output: error.error,
            tool: tools?[error.toolName],
            errorMode: .json
        )
        let part = ToolResultPart(
            toolCallId: error.toolCallId,
            toolName: error.toolName,
            output: modelOutput,
            providerOptions: nil
        )
        return .toolResult(part)
    }
}

private func buildOuterTelemetryAttributes(
    telemetry: TelemetrySettings?,
    baseAttributes: Attributes,
    operationId: String,
    system: String?,
    prompt: String?,
    messages: [ModelMessage]?
) -> [String: ResolvableAttributeValue?] {
    var attributes: [String: ResolvableAttributeValue?] = [:]

    for (key, value) in assembleOperationName(operationId: operationId, telemetry: telemetry) {
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

private func buildInnerTelemetryAttributes(
    telemetry: TelemetrySettings?,
    baseAttributes: Attributes,
    operationId: String,
    prompt: LanguageModelV3Prompt,
    tools: [LanguageModelV3Tool]?,
    toolChoice: LanguageModelV3ToolChoice?,
    settings: PreparedCallSettings,
    model: any LanguageModelV3
) -> [String: ResolvableAttributeValue?] {
    var attributes: [String: ResolvableAttributeValue?] = [:]

    for (key, value) in assembleOperationName(operationId: operationId, telemetry: telemetry) {
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

private func buildResponseTelemetryAttributes(
    telemetry: TelemetrySettings?,
    finishReason: FinishReason,
    content: [LanguageModelV3Content],
    providerMetadata: ProviderMetadata?,
    usage: LanguageModelUsage,
    responseId: String,
    responseModelId: String,
    responseTimestamp: Date
) -> [String: ResolvableAttributeValue?] {
    var attributes: [String: ResolvableAttributeValue?] = [:]

    attributes["ai.response.finishReason"] = .value(.string(finishReason.rawValue))

    attributes["ai.response.text"] = .output {
        guard let text = extractTextContent(content: content) else {
            return nil
        }
        return .string(text)
    }

    attributes["ai.response.toolCalls"] = .output {
        guard let calls = asToolCalls(content),
              let encoded = jsonString(from: calls) else {
            return nil
        }
        return .string(encoded)
    }

    attributes["ai.response.providerMetadata"] = .output {
        guard let providerMetadata,
              let encoded = jsonString(from: providerMetadata) else {
            return nil
        }
        return .string(encoded)
    }

    attributes["gen_ai.response.finish_reasons"] = .value(.stringArray([finishReason.rawValue]))
    attributes["gen_ai.response.id"] = .value(.string(responseId))
    attributes["gen_ai.response.model"] = .value(.string(responseModelId))

    if let inputTokens = usage.inputTokens {
        attributes["ai.usage.promptTokens"] = .value(.int(inputTokens))
        attributes["gen_ai.usage.input_tokens"] = .value(.int(inputTokens))
    } else {
        attributes["ai.usage.promptTokens"] = nil
        attributes["gen_ai.usage.input_tokens"] = nil
    }

    if let outputTokens = usage.outputTokens {
        attributes["ai.usage.completionTokens"] = .value(.int(outputTokens))
        attributes["gen_ai.usage.output_tokens"] = .value(.int(outputTokens))
    } else {
        attributes["ai.usage.completionTokens"] = nil
        attributes["gen_ai.usage.output_tokens"] = nil
    }

    attributes["ai.response.id"] = .value(.string(responseId))
    attributes["ai.response.model"] = .value(.string(responseModelId))
    attributes["ai.response.timestamp"] = .value(.string(responseTimestamp.iso8601String))

    return attributes
}

private func summarizePromptForTelemetry(
    system: String?,
    prompt: String?,
    messages: [ModelMessage]?
) -> String? {
    var payload: [String: Any] = [:]
    if let system {
        payload["system"] = system
    }
    if let prompt {
        payload["prompt"] = prompt
    }
    if let messages {
        payload["messagesRoles"] = messages.map { message in
            switch message {
            case .system: return "system"
            case .user: return "user"
            case .assistant: return "assistant"
            case .tool: return "tool"
            }
        }
    }
    payload["messagesCount"] = messages?.count ?? 0

    guard JSONSerialization.isValidJSONObject(payload),
          let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
        return nil
    }
    return String(data: data, encoding: .utf8)
}

private func encodeToolsForTelemetry(
    _ tools: [LanguageModelV3Tool]?
) -> String? {
    guard let tools else { return nil }
    return jsonString(from: tools)
}

private func encodeToolChoiceForTelemetry(
    _ toolChoice: LanguageModelV3ToolChoice?
) -> String? {
    guard let toolChoice else { return nil }
    return jsonString(from: toolChoice)
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
    jsonString(from: jsonValue, using: JSONEncoder())
}

private func jsonString(from jsonValue: JSONValue, using encoder: JSONEncoder) -> String? {
    guard let data = try? encoder.encode(jsonValue) else {
        return nil
    }
    return String(data: data, encoding: .utf8)
}

private struct ToolCallTelemetry: Encodable {
    let toolCallId: String
    let toolName: String
    let input: JSONValue
}

private func asToolCalls(
    _ content: [LanguageModelV3Content]
) -> [ToolCallTelemetry]? {
    let calls = content.compactMap { part -> ToolCallTelemetry? in
        switch part {
        case .toolCall(let toolCall):
            let inputJSON: JSONValue
            if let data = toolCall.input.data(using: .utf8),
               let parsed = try? JSONDecoder().decode(JSONValue.self, from: data) {
                inputJSON = parsed
            } else if let parsed = try? parseJSONString(toolCall.input) {
                inputJSON = parsed
            } else {
                inputJSON = .string(toolCall.input)
            }
            return ToolCallTelemetry(
                toolCallId: toolCall.toolCallId,
                toolName: toolCall.toolName,
                input: inputJSON
            )
        default:
            return nil
        }
    }
    return calls.isEmpty ? nil : calls
}

private func parseToolCalls(
    from content: [LanguageModelV3Content],
    tools: ToolSet?,
    repairToolCall: ToolCallRepairFunction?,
    system: String?,
    messages: [ModelMessage]
) async -> [TypedToolCall] {
    var toolCalls: [TypedToolCall] = []
    for part in content {
        if case .toolCall(let toolCall) = part {
            let parsed = await parseToolCall(
                toolCall: toolCall,
                tools: tools,
                repairToolCall: repairToolCall,
                system: system,
                messages: messages
            )
            toolCalls.append(parsed)
        }
    }
    return toolCalls
}

private func collectInvalidToolOutputs(
    from toolCalls: [TypedToolCall]
) -> [ToolOutput] {
    var outputs: [ToolOutput] = []
    for toolCall in toolCalls {
        switch toolCall {
        case .dynamic(let dynamicCall):
            if dynamicCall.invalid == true {
                let error = dynamicCall.error ?? ToolCallUnknownError(toolName: dynamicCall.toolName)
                let typedError = TypedToolError.dynamic(
                    DynamicToolError(
                        toolCallId: dynamicCall.toolCallId,
                        toolName: dynamicCall.toolName,
                        input: dynamicCall.input,
                        error: error,
                        providerExecuted: dynamicCall.providerExecuted
                    )
                )
                outputs.append(.error(typedError))
            }
        case .static:
            continue
        }
    }
    return outputs
}

private func convertResponseBody(_ body: Any?) -> JSONValue? {
    guard let body else { return nil }
    return try? jsonValue(from: body)
}

private func makeRequestMetadata(
    from info: LanguageModelV3RequestInfo?
) -> LanguageModelRequestMetadata {
    guard let info else { return LanguageModelRequestMetadata() }
    let body: JSONValue?
    if let rawBody = info.body {
        body = try? jsonValue(from: rawBody)
    } else {
        body = nil
    }
    return LanguageModelRequestMetadata(body: body)
}

private func asContent(
    content languageModelContent: [LanguageModelV3Content],
    toolCalls: [TypedToolCall],
    toolOutputs: [ToolOutput],
    toolApprovalRequests: [ToolApprovalRequestOutput]
) -> [ContentPart] {
    var contentParts: [ContentPart] = []

    var toolCallsById: [String: TypedToolCall] = [:]
    for toolCall in toolCalls {
        toolCallsById[toolCall.toolCallId] = toolCall
    }

    for part in languageModelContent {
        switch part {
        case .text(let textPart):
            contentParts.append(
                .text(text: textPart.text, providerMetadata: textPart.providerMetadata)
            )

        case .reasoning(let reasoningPart):
            contentParts.append(
                .reasoning(
                    ReasoningOutput(
                        text: reasoningPart.text,
                        providerMetadata: reasoningPart.providerMetadata
                    )
                )
            )

        case .file(let filePart):
            let generatedFile: GeneratedFile
            switch filePart.data {
            case .base64(let base64):
                generatedFile = DefaultGeneratedFileWithType(base64: base64, mediaType: filePart.mediaType)
            case .binary(let data):
                generatedFile = DefaultGeneratedFileWithType(data: data, mediaType: filePart.mediaType)
            }
            contentParts.append(.file(file: generatedFile, providerMetadata: nil))

        case .source(let sourcePart):
            contentParts.append(.source(type: "source", source: sourcePart))

        case .toolCall(let toolCallPart):
            if let typedCall = toolCallsById[toolCallPart.toolCallId] {
                contentParts.append(.toolCall(typedCall, providerMetadata: toolCallPart.providerMetadata))
            } else {
                let parsedInput = (try? parseJSONString(toolCallPart.input)) ?? .string(toolCallPart.input)
                let dynamicCall = DynamicToolCall(
                    toolCallId: toolCallPart.toolCallId,
                    toolName: toolCallPart.toolName,
                    input: parsedInput,
                    providerExecuted: toolCallPart.providerExecuted,
                    providerMetadata: toolCallPart.providerMetadata,
                    invalid: false,
                    error: nil
                )
                contentParts.append(.toolCall(.dynamic(dynamicCall), providerMetadata: toolCallPart.providerMetadata))
            }

        case .toolResult(let toolResultPart):
            guard let toolCall = toolCallsById[toolResultPart.toolCallId] else {
                continue
            }

            if toolResultPart.isError == true {
                let errorValue = ProviderToolExecutionError(value: toolResultPart.result)
                let typedError: TypedToolError
                switch toolCall {
                case .static(let call):
                    typedError = .static(
                        StaticToolError(
                            toolCallId: call.toolCallId,
                            toolName: call.toolName,
                            input: call.input,
                            error: errorValue,
                            providerExecuted: true
                        )
                    )
                case .dynamic(let call):
                    typedError = .dynamic(
                        DynamicToolError(
                            toolCallId: call.toolCallId,
                            toolName: call.toolName,
                            input: call.input,
                            error: errorValue,
                            providerExecuted: true
                        )
                    )
                }
                contentParts.append(.toolError(typedError, providerMetadata: toolResultPart.providerMetadata))
            } else {
                let typedResult: TypedToolResult
                switch toolCall {
                case .static(let call):
                    typedResult = .static(
                        StaticToolResult(
                            toolCallId: call.toolCallId,
                            toolName: call.toolName,
                            input: call.input,
                            output: toolResultPart.result,
                            providerExecuted: true,
                            preliminary: toolResultPart.preliminary
                        )
                    )
                case .dynamic(let call):
                    typedResult = .dynamic(
                        DynamicToolResult(
                            toolCallId: call.toolCallId,
                            toolName: call.toolName,
                            input: call.input,
                            output: toolResultPart.result,
                            providerExecuted: true,
                            preliminary: toolResultPart.preliminary
                        )
                    )
                }
                contentParts.append(.toolResult(typedResult, providerMetadata: toolResultPart.providerMetadata))
            }
        }
    }

    for output in toolOutputs {
        contentParts.append(toolOutputToContentPart(output))
    }

    for approval in toolApprovalRequests {
        contentParts.append(.toolApprovalRequest(approval))
    }

    return contentParts
}

private func toolOutputToContentPart(_ output: ToolOutput) -> ContentPart {
    switch output {
    case .result(let result):
        return .toolResult(result, providerMetadata: nil)
    case .error(let error):
        return .toolError(error, providerMetadata: nil)
    }
}

private func cloneResponseMessages(
    _ messages: [ResponseMessage]
) -> [ResponseMessage] {
    Array(messages)
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

private extension Date {
    var iso8601String: String {
        ISO8601DateFormatter().string(from: self)
    }
}

private struct JSONParsingError: Error {}

private func parseJSONString(_ text: String) throws -> JSONValue {
    guard let data = text.data(using: .utf8) else {
        throw JSONParsingError()
    }

    let raw = try JSONSerialization.jsonObject(with: data, options: [])
    return try jsonValue(from: raw)
}

/**
 Callback invoked when a generation step completes.

 Matches upstream `GenerateTextOnStepFinishCallback`.
 */
public typealias GenerateTextOnStepFinishCallback = @Sendable (_ stepResult: StepResult) async throws -> Void

/**
 Callback invoked after generation finishes (all steps completed).

 Matches upstream `GenerateTextOnFinishCallback`.
 */
public typealias GenerateTextOnFinishCallback = @Sendable (_ event: GenerateTextFinishEvent) async throws -> Void

/**
 Event payload passed to `onFinish` callback.
 */
public struct GenerateTextFinishEvent: Sendable {
    public let finishReason: FinishReason
    public let usage: LanguageModelUsage
    public let content: [ContentPart]
    public let text: String
    public let reasoningText: String?
    public let reasoning: [ReasoningOutput]
    public let files: [GeneratedFile]
    public let sources: [Source]
    public let toolCalls: [TypedToolCall]
    public let staticToolCalls: [StaticToolCall]
    public let dynamicToolCalls: [DynamicToolCall]
    public let toolResults: [TypedToolResult]
    public let staticToolResults: [StaticToolResult]
    public let dynamicToolResults: [DynamicToolResult]
    public let request: LanguageModelRequestMetadata
    public let response: StepResultResponse
    public let warnings: [CallWarning]?
    public let providerMetadata: ProviderMetadata?
    public let steps: [StepResult]
    public let totalUsage: LanguageModelUsage
}

/**
 Generate a text response (non-streaming) with optional tool usage.

 - Parameters:
   - model: Language model identifier or implementation.
   - tools: Tool set accessible to the model.
   - toolChoice: Tool selection directive (`auto`, `none`, `required`, or specific tool).
   - system: Optional system instruction.
   - prompt: Optional simple text prompt (mutually exclusive with `messages`).
   - messages: Optional array of prompt messages (mutually exclusive with `prompt`).
   - stopWhen: Stop conditions evaluated after each step (default: single-step).
   - experimentalOutput: Structured output parser (mirrors upstream `experimental_output`).
   - experimentalTelemetry: Telemetry configuration.
   - providerOptions: Provider-specific call options.
   - experimentalActiveTools: Deprecated tool filter (forwarded for parity).
   - activeTools: Active tool whitelist.
   - experimentalPrepareStep: Deprecated step preparation hook.
   - prepareStep: Step preparation hook (defaults to `experimentalPrepareStep` when provided).
   - experimentalRepairToolCall: Tool call repair function.
   - experimentalDownload: Custom download implementation for URL media.
   - experimentalContext: Arbitrary JSON context passed to tool execution.
   - internalOptions: Internal knobs (ID generator, clock) used for testing.
   - onStepFinish: Callback executed after each completed step.
   - onFinish: Callback executed after the full generation completes.
   - settings: Call configuration (temperature, topP, retries, headers, etc.).

 - Returns: `DefaultGenerateTextResult` containing aggregated step information.
 */
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func generateText<OutputValue: Sendable>(
    model modelArg: LanguageModel,
    tools: ToolSet? = nil,
    toolChoice: ToolChoice? = nil,
    system: String? = nil,
    prompt: String? = nil,
    messages: [ModelMessage]? = nil,
    stopWhen: [StopCondition] = [stepCountIs(1)],
    experimentalOutput output: Output.Specification<OutputValue, JSONValue>? = nil,
    experimentalTelemetry telemetry: TelemetrySettings? = nil,
    providerOptions: ProviderOptions? = nil,
    experimentalActiveTools: [String]? = nil,
    activeTools: [String]? = nil,
    experimentalPrepareStep: PrepareStepFunction? = nil,
    prepareStep: PrepareStepFunction? = nil,
    experimentalRepairToolCall repairToolCall: ToolCallRepairFunction? = nil,
    experimentalDownload download: DownloadFunction? = nil,
    experimentalContext: JSONValue? = nil,
    internalOptions _internal: GenerateTextInternalOptions = GenerateTextInternalOptions(),
    onStepFinish: GenerateTextOnStepFinishCallback? = nil,
    onFinish: GenerateTextOnFinishCallback? = nil,
    settings: CallSettings = CallSettings()
) async throws -> DefaultGenerateTextResult<OutputValue> {
    let resolvedModel = try resolveLanguageModel(modelArg)
    let defaultLanguageModel: LanguageModel = .v3(resolvedModel)
    let effectiveActiveTools = activeTools ?? experimentalActiveTools
    let effectivePrepareStep = prepareStep ?? experimentalPrepareStep
    let downloadHandler = download

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

    let baseTelemetryAttributes = getBaseTelemetryAttributes(
        model: TelemetryModelInfo(modelId: resolvedModel.modelId, provider: resolvedModel.provider),
        settings: telemetryCallSettings,
        telemetry: telemetry,
        headers: headersWithUserAgent
    )

    let promptInput: Prompt
    if let promptText = prompt {
        if messages != nil {
            throw InvalidPromptError(
                prompt: "Prompt(system: \(system ?? "nil"), prompt: \(promptText), messages: provided)",
                message: "Provide either `prompt` or `messages`, not both."
            )
        }
        promptInput = Prompt.text(promptText, system: system)
    } else if let messageList = messages {
        promptInput = Prompt.messages(messageList, system: system)
    } else {
        throw InvalidPromptError(
            prompt: "Prompt(system: \(system ?? "nil"))",
            message: "Either `prompt` or `messages` must be provided."
        )
    }

    let standardizedPrompt = try standardizePrompt(promptInput)
    let initialMessages = standardizedPrompt.messages
    let responseMessageStore = ResponseMessageStore()

    let tracer = getTracer(
        isEnabled: telemetry?.isEnabled ?? false,
        tracer: telemetry?.tracer
    )

    // Execute approved tool approvals before entering the main loop.
    let approvals = collectToolApprovals(messages: initialMessages)
    if !approvals.approvedToolApprovals.isEmpty || !approvals.deniedToolApprovals.isEmpty {
        let executedOutputs = try await executeTools(
            toolCalls: approvals.approvedToolApprovals.map { $0.toolCall },
            tools: tools,
            tracer: tracer,
            telemetry: telemetry,
            messages: initialMessages,
            abortSignal: settings.abortSignal,
            experimentalContext: experimentalContext
        )

        var toolContent: [ToolContentPart] = executedOutputs.map {
            makeToolContentPart(output: $0, tools: tools)
        }

        for denied in approvals.deniedToolApprovals {
            let deniedPart = ToolResultPart(
                toolCallId: denied.toolCall.toolCallId,
                toolName: denied.toolCall.toolName,
                output: .executionDenied(reason: denied.approvalResponse.reason),
                providerOptions: nil
            )
            toolContent.append(.toolResult(deniedPart))
        }

        if !toolContent.isEmpty {
            await responseMessageStore.append(contentsOf: [
                .tool(ToolModelMessage(content: toolContent))
            ])
        }
    }

    let outerAttributes = try await selectTelemetryAttributes(
        telemetry: telemetry,
        attributes: buildOuterTelemetryAttributes(
            telemetry: telemetry,
            baseAttributes: baseTelemetryAttributes,
            operationId: "ai.generateText",
            system: system,
            prompt: prompt,
            messages: messages
        )
    )

    do {
        return try await recordSpan(
            name: "ai.generateText",
            tracer: tracer,
            attributes: outerAttributes
        ) { span in
            var steps: [StepResult] = []
            var clientToolCalls: [TypedToolCall] = []
            var clientToolOutputs: [ToolOutput] = []
            var currentModelResult: GenerateStepIntermediate?
            var continueLoop = false

            repeat {
                let currentResponseMessages = await responseMessageStore.all()
                let stepInputMessages = initialMessages + convertResponseMessagesToModelMessages(currentResponseMessages)

                let prepareOptions = PrepareStepOptions(
                    steps: steps,
                    stepNumber: steps.count,
                    model: defaultLanguageModel,
                    messages: stepInputMessages
                )
                let prepareStepResult = try await effectivePrepareStep?(prepareOptions)

                let stepModelSource = prepareStepResult?.model ?? defaultLanguageModel
                let stepModel = try resolveLanguageModel(stepModelSource)

                let stepSystem = prepareStepResult?.system ?? standardizedPrompt.system
                let stepMessages = prepareStepResult?.messages ?? stepInputMessages

                let promptForModel = try await convertToLanguageModelPrompt(
                    prompt: StandardizedPrompt(system: stepSystem, messages: stepMessages),
                    supportedUrls: try await stepModel.supportedUrls,
                    download: downloadHandler
                )

                let toolPreparation = try await prepareToolsAndToolChoice(
                    tools: tools,
                    toolChoice: prepareStepResult?.toolChoice ?? toolChoice,
                    activeTools: prepareStepResult?.activeTools ?? effectiveActiveTools
                )

                let responseFormat = try await output?.responseFormat()

                let innerAttributes = try await selectTelemetryAttributes(
                    telemetry: telemetry,
                    attributes: buildInnerTelemetryAttributes(
                        telemetry: telemetry,
                        baseAttributes: baseTelemetryAttributes,
                        operationId: "ai.generateText.doGenerate",
                        prompt: promptForModel,
                        tools: toolPreparation.tools,
                        toolChoice: toolPreparation.toolChoice,
                        settings: preparedCallSettings,
                        model: stepModel
                    )
                )

                let stepResult = try await preparedRetries.retry.call {
                    try await recordSpan(
                        name: "ai.generateText.doGenerate",
                        tracer: tracer,
                        attributes: innerAttributes
                    ) { span in
                        let result = try await stepModel.doGenerate(
                            options: LanguageModelV3CallOptions(
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
                                includeRawChunks: nil,
                                abortSignal: settings.abortSignal,
                                headers: headersWithUserAgent,
                                providerOptions: providerOptions
                            )
                        )

                        let responseId = result.response?.id ?? _internal.generateId()
                        let responseTimestamp = result.response?.timestamp ?? _internal.currentDate()
                        let responseModelId = result.response?.modelId ?? stepModel.modelId
                        let responseHeaders = result.response?.headers
                        let responseBody = convertResponseBody(result.response?.body)

                        span.setAttributes(
                            try await selectTelemetryAttributes(
                                telemetry: telemetry,
                                attributes: buildResponseTelemetryAttributes(
                                    telemetry: telemetry,
                                    finishReason: result.finishReason,
                                    content: result.content,
                                    providerMetadata: result.providerMetadata,
                                    usage: result.usage,
                                    responseId: responseId,
                                    responseModelId: responseModelId,
                                    responseTimestamp: responseTimestamp
                                )
                            )
                        )

                        return GenerateStepIntermediate(
                            content: result.content,
                            finishReason: result.finishReason,
                            usage: result.usage,
                            warnings: result.warnings,
                            providerMetadata: result.providerMetadata,
                            requestInfo: result.request,
                            responseMetadata: LanguageModelResponseMetadata(
                                id: responseId,
                                timestamp: responseTimestamp,
                                modelId: responseModelId,
                                headers: responseHeaders
                            ),
                            responseBody: responseBody
                        )
                    }
                }

                currentModelResult = stepResult

                let stepToolCalls = await parseToolCalls(
                    from: stepResult.content,
                    tools: tools,
                    repairToolCall: repairToolCall,
                    system: stepSystem,
                    messages: stepInputMessages
                )

                var toolApprovalRequests: [String: ToolApprovalRequestOutput] = [:]

                clientToolOutputs = collectInvalidToolOutputs(from: stepToolCalls)

                for toolCall in stepToolCalls {
                    guard toolCall.invalid != true, let tool = tools?[toolCall.toolName] else {
                        continue
                    }

                    if let onInputAvailable = tool.onInputAvailable {
                        try await onInputAvailable(
                            ToolCallInputOptions(
                                input: toolCall.input,
                                toolCallId: toolCall.toolCallId,
                                messages: stepInputMessages,
                                abortSignal: settings.abortSignal,
                                experimentalContext: experimentalContext
                            )
                        )
                    }

                    if await isApprovalNeeded(
                        tool: tool,
                        toolCall: toolCall,
                        messages: stepInputMessages,
                        experimentalContext: experimentalContext
                    ) {
                        let approval = ToolApprovalRequestOutput(
                            approvalId: _internal.generateId(),
                            toolCall: toolCall
                        )
                        toolApprovalRequests[toolCall.toolCallId] = approval
                    }
                }

                clientToolCalls = stepToolCalls.filter { toolCall in
                    toolCall.providerExecuted != true
                }

                if let tools = tools {
                    let pendingToolCalls = clientToolCalls.filter { toolCall in
                        toolCall.invalid != true &&
                        toolApprovalRequests[toolCall.toolCallId] == nil
                    }

                    let executedOutputs = try await executeTools(
                        toolCalls: pendingToolCalls,
                        tools: tools,
                        tracer: tracer,
                        telemetry: telemetry,
                        messages: stepInputMessages,
                        abortSignal: settings.abortSignal,
                        experimentalContext: experimentalContext
                    )

                    clientToolOutputs.append(contentsOf: executedOutputs)
                }

                let stepContent = asContent(
                    content: stepResult.content,
                    toolCalls: stepToolCalls,
                    toolOutputs: clientToolOutputs,
                    toolApprovalRequests: Array(toolApprovalRequests.values)
                )

                let newMessages = convertModelMessagesToResponseMessages(
                    toResponseMessages(
                        content: stepContent,
                        tools: tools
                    )
                )
                await responseMessageStore.append(contentsOf: newMessages)

                let requestMetadata = makeRequestMetadata(from: stepResult.requestInfo)

                let responseMessagesSnapshot = await responseMessageStore.all()
                let stepResponse = StepResultResponse(
                    from: stepResult.responseMetadata,
                    messages: cloneResponseMessages(responseMessagesSnapshot),
                    body: stepResult.responseBody
                )

                let currentStepResult = DefaultStepResult(
                    content: stepContent,
                    finishReason: stepResult.finishReason,
                    usage: stepResult.usage,
                    warnings: stepResult.warnings,
                    request: requestMetadata,
                    response: stepResponse,
                    providerMetadata: stepResult.providerMetadata
                )

                let languageModelWarnings = stepResult.warnings.map { Warning.languageModel($0) }
                if !languageModelWarnings.isEmpty {
                    logWarnings(languageModelWarnings)
                }
                steps.append(currentStepResult)
                if let onStepFinish {
                    try await onStepFinish(currentStepResult)
                }

                let hasPendingToolCalls = !clientToolCalls.isEmpty
                let allToolCallsHaveOutputs = clientToolOutputs.count == clientToolCalls.count
                let stopConditionMet = await isStopConditionMet(stopConditions: stopWhen, steps: steps)
                continueLoop = hasPendingToolCalls && allToolCallsHaveOutputs && !stopConditionMet
            } while continueLoop

            if let finalResult = currentModelResult {
                span.setAttributes(
                    try await selectTelemetryAttributes(
                        telemetry: telemetry,
                        attributes: buildResponseTelemetryAttributes(
                            telemetry: telemetry,
                            finishReason: finalResult.finishReason,
                            content: finalResult.content,
                            providerMetadata: finalResult.providerMetadata,
                            usage: finalResult.usage,
                            responseId: finalResult.responseMetadata.id,
                            responseModelId: finalResult.responseMetadata.modelId,
                            responseTimestamp: finalResult.responseMetadata.timestamp
                        )
                    )
                )
            }

            guard let lastStep = steps.last else {
                return DefaultGenerateTextResult(
                    steps: [],
                    totalUsage: LanguageModelUsage(),
                    resolvedOutput: nil
                )
            }

            var totalUsage = LanguageModelUsage()
            for step in steps {
                totalUsage = addLanguageModelUsage(totalUsage, step.usage)
            }

            if let onFinish {
                let finishEvent = GenerateTextFinishEvent(
                    finishReason: lastStep.finishReason,
                    usage: lastStep.usage,
                    content: lastStep.content,
                    text: lastStep.text,
                    reasoningText: lastStep.reasoningText,
                    reasoning: lastStep.reasoning,
                    files: lastStep.files,
                    sources: lastStep.sources,
                    toolCalls: lastStep.toolCalls,
                    staticToolCalls: lastStep.staticToolCalls,
                    dynamicToolCalls: lastStep.dynamicToolCalls,
                    toolResults: lastStep.toolResults,
                    staticToolResults: lastStep.staticToolResults,
                    dynamicToolResults: lastStep.dynamicToolResults,
                    request: lastStep.request,
                    response: lastStep.response,
                    warnings: lastStep.warnings,
                    providerMetadata: lastStep.providerMetadata,
                    steps: steps,
                    totalUsage: totalUsage
                )
                try await onFinish(finishEvent)
            }

            var resolvedOutput: OutputValue?
            if let output, lastStep.finishReason == .stop {
                let metadata = LanguageModelResponseMetadata(
                    id: lastStep.response.id,
                    timestamp: lastStep.response.timestamp,
                    modelId: lastStep.response.modelId,
                    headers: lastStep.response.headers
                )
                resolvedOutput = try await output.parseOutput(
                    text: lastStep.text,
                    response: metadata,
                    usage: lastStep.usage,
                    finishReason: lastStep.finishReason
                )
            }

            return DefaultGenerateTextResult(
                steps: steps,
                totalUsage: totalUsage,
                resolvedOutput: resolvedOutput
            )
        }
    } catch {
        throw (wrapGatewayError(error) as? Error) ?? error
    }
}
