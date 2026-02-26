import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/amazon-bedrock/src/bedrock-chat-language-model.ts
// Upstream commit: 73d5c5920
//===----------------------------------------------------------------------===//

private let bedrockGenerateFailedResponseHandler: ResponseHandler<APICallError> = createJsonErrorResponseHandler(
    errorSchema: BedrockErrorSchema,
    errorToMessage: { error in
        error.message.isEmpty ? "Unknown error" : error.message
    }
)

private func parseHTTPDate(_ headerValue: String?) -> Date? {
    guard let headerValue else { return nil }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    formatter.timeZone = TimeZone(abbreviation: "GMT")
    return formatter.date(from: headerValue)
}

public final class BedrockChatLanguageModel: LanguageModelV3 {
    struct Config: Sendable {
        let baseURL: @Sendable () -> String
        let headers: @Sendable () -> [String: String?]
        let fetch: FetchFunction?
        let generateId: @Sendable () -> String
    }

    private struct PreparedRequest {
        let command: [String: JSONValue]
        let warnings: [SharedV3Warning]
        let usesJsonResponseTool: Bool
    }

    private let modelIdentifier: BedrockChatModelId
    private let config: Config

    init(modelId: BedrockChatModelId, config: Config) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var specificationVersion: String { "v3" }
    public var provider: String { "amazon-bedrock" }
    public var modelId: String { modelIdentifier.rawValue }

    public var supportedUrls: [String: [NSRegularExpression]] {
        [:]
    }

    public func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult {
        let prepared = try await prepareRequest(options: options)
        let url = chatURL(for: modelIdentifier.rawValue, path: "converse")
        let response = try await postJsonToAPI(
            url: url,
            headers: mergeHeaders(overrides: options.headers),
            body: JSONValue.object(prepared.command),
            failedResponseHandler: bedrockGenerateFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: bedrockGenerateResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let isMistral = isMistralModel(modelIdentifier.rawValue)
        let mapped = mapGenerateContent(
            response: response.value,
            usesJsonResponseTool: prepared.usesJsonResponseTool,
            isMistral: isMistral
        )

        let stopSequence = response.value.additionalModelResponseFields?.delta?.stop_sequence
        let providerMetadata = buildGenerateProviderMetadata(
            response: response.value,
            isJsonResponseFromTool: mapped.isJsonResponseFromTool,
            stopSequence: stopSequence
        )

        let responseHeaders = response.responseHeaders
        let result = LanguageModelV3GenerateResult(
            content: mapped.content,
            finishReason: LanguageModelV3FinishReason(
                unified: mapBedrockFinishReason(
                    response.value.stopReason,
                    isJsonResponseFromTool: mapped.isJsonResponseFromTool
                ),
                raw: response.value.stopReason
            ),
            usage: convertBedrockUsage(response.value.usage),
            providerMetadata: providerMetadata,
            request: LanguageModelV3RequestInfo(body: prepared.command),
            response: LanguageModelV3ResponseInfo(
                id: responseHeaders["x-amzn-requestid"],
                timestamp: parseHTTPDate(responseHeaders["date"]),
                modelId: modelIdentifier.rawValue,
                headers: responseHeaders,
                body: response.rawValue
            ),
            warnings: prepared.warnings
        )

        return result
    }

    public func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult {
        let prepared = try await prepareRequest(options: options)
        let url = chatURL(for: modelIdentifier.rawValue, path: "converse-stream")
        let streamResponse = try await postJsonToAPI(
            url: url,
            headers: mergeHeaders(overrides: options.headers),
            body: JSONValue.object(prepared.command),
            failedResponseHandler: bedrockFailedResponseHandler,
            successfulResponseHandler: createBedrockEventStreamResponseHandler(chunkSchema: bedrockStreamSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let responseHeaders = streamResponse.responseHeaders
        let responseId = responseHeaders["x-amzn-requestid"]
        let responseTimestamp = parseHTTPDate(responseHeaders["date"])
        let modelId = modelIdentifier.rawValue
        let isMistral = isMistralModel(modelId)

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error>(bufferingPolicy: .unbounded) { continuation in
            continuation.yield(.streamStart(warnings: prepared.warnings))
            continuation.yield(.responseMetadata(id: responseId, modelId: modelId, timestamp: responseTimestamp))

            Task {
                var finishReason = LanguageModelV3FinishReason(unified: .other, raw: nil)
                var usageMetrics: BedrockStreamEnvelope.Metadata.Usage?
                var providerMetadata: SharedV3ProviderMetadata?
                var isJsonResponseFromTool = false
                var stopSequence: String?
                var contentBlocks: [Int: StreamContentBlockState] = [:]

                do {
                    for try await chunkResult in streamResponse.value {
                        if options.includeRawChunks == true, let raw = chunkResult.rawJSONValue {
                            continuation.yield(.raw(rawValue: raw))
                        }

                        switch chunkResult {
                        case .failure(let error, let raw):
                            finishReason = LanguageModelV3FinishReason(unified: .error, raw: nil)
                            let errorJSON = raw.flatMap { try? jsonValue(from: $0) } ?? .string(String(describing: error))
                            continuation.yield(.error(error: errorJSON))
                            continue

                        case .success(let chunk, _):
                            if let errorPayload = chunk.firstError {
                                finishReason = LanguageModelV3FinishReason(unified: .error, raw: nil)
                                continuation.yield(.error(error: .object(errorPayload)))
                                continue
                            }

                            if let messageStop = chunk.messageStop {
                                finishReason = LanguageModelV3FinishReason(
                                    unified: mapBedrockFinishReason(
                                        messageStop.stopReason,
                                        isJsonResponseFromTool: isJsonResponseFromTool
                                    ),
                                    raw: messageStop.stopReason
                                )
                                stopSequence = messageStop.additionalModelResponseFields?.delta?.stop_sequence
                            }

                            if let metadata = chunk.metadata {
                                if let usage = metadata.usage {
                                    usageMetrics = usage
                                }

                                let hasCacheUsage = metadata.usage?.cacheWriteInputTokens != nil || metadata.usage?.cacheDetails != nil
                                let traceValue = metadata.trace
                                let traceIsObject: Bool
                                if let traceValue, case .object = traceValue {
                                    traceIsObject = true
                                } else {
                                    traceIsObject = false
                                }

                                if hasCacheUsage || traceIsObject || metadata.performanceConfig != nil || metadata.serviceTier != nil {
                                    var payload: [String: JSONValue] = [:]

                                    if hasCacheUsage, let usage = metadata.usage {
                                        var usagePayload: [String: JSONValue] = [:]
                                        if let cacheWrite = usage.cacheWriteInputTokens {
                                            usagePayload["cacheWriteInputTokens"] = .number(Double(cacheWrite))
                                        }
                                        if let cacheDetails = usage.cacheDetails {
                                            usagePayload["cacheDetails"] = cacheDetails
                                        }
                                        payload["usage"] = .object(usagePayload)
                                    }

                                    if traceIsObject, let traceValue {
                                        payload["trace"] = traceValue
                                    }

                                    if let performanceConfig = metadata.performanceConfig {
                                        payload["performanceConfig"] = performanceConfig
                                    }

                                    if let serviceTier = metadata.serviceTier {
                                        payload["serviceTier"] = serviceTier
                                    }

                                    providerMetadata = ["bedrock": payload]
                                }
                            }

                            if let contentStart = chunk.contentBlockStart,
                               contentStart.start?.toolUse == nil {
                                let blockIndex = contentStart.contentBlockIndex
                                contentBlocks[blockIndex] = .text
                                continuation.yield(.textStart(id: String(blockIndex), providerMetadata: nil))
                            }

                            if let contentDelta = chunk.contentBlockDelta,
                               let delta = contentDelta.delta,
                               let textDelta = delta.text,
                               !textDelta.isEmpty {
                                let blockIndex = contentDelta.contentBlockIndex
                                if contentBlocks[blockIndex] == nil {
                                    contentBlocks[blockIndex] = .text
                                    continuation.yield(.textStart(id: String(blockIndex), providerMetadata: nil))
                                }
                                continuation.yield(.textDelta(id: String(blockIndex), delta: textDelta, providerMetadata: nil))
                            }

                            if let stop = chunk.contentBlockStop {
                                let blockIndex = stop.contentBlockIndex
                                if let state = contentBlocks.removeValue(forKey: blockIndex) {
                                    switch state {
                                    case .reasoning:
                                        continuation.yield(.reasoningEnd(id: String(blockIndex), providerMetadata: nil))
                                    case .text:
                                        continuation.yield(.textEnd(id: String(blockIndex), providerMetadata: nil))
                                    case .toolCall(let toolState):
                                        if toolState.isJsonResponseTool {
                                            isJsonResponseFromTool = true
                                            continuation.yield(.textStart(id: String(blockIndex), providerMetadata: nil))
                                            continuation.yield(.textDelta(id: String(blockIndex), delta: toolState.jsonText, providerMetadata: nil))
                                            continuation.yield(.textEnd(id: String(blockIndex), providerMetadata: nil))
                                        } else {
                                            continuation.yield(.toolInputEnd(id: toolState.toolCallId, providerMetadata: nil))
                                            continuation.yield(.toolCall(LanguageModelV3ToolCall(
                                                toolCallId: toolState.toolCallId,
                                                toolName: toolState.toolName,
                                                input: toolState.jsonText.isEmpty ? "{}" : toolState.jsonText
                                            )))
                                        }
                                    }
                                }
                            }

                            if let contentDelta = chunk.contentBlockDelta,
                               let reasoningContent = contentDelta.delta?.reasoningContent {
                                let blockIndex = contentDelta.contentBlockIndex
                                if let text = reasoningContent.text, !text.isEmpty {
                                    if contentBlocks[blockIndex] == nil {
                                        contentBlocks[blockIndex] = .reasoning
                                        continuation.yield(.reasoningStart(id: String(blockIndex), providerMetadata: nil))
                                    }
                                    continuation.yield(.reasoningDelta(id: String(blockIndex), delta: text, providerMetadata: nil))
                                } else if let signature = reasoningContent.signature, !signature.isEmpty {
                                    continuation.yield(.reasoningDelta(
                                        id: String(blockIndex),
                                        delta: "",
                                        providerMetadata: ["bedrock": ["signature": .string(signature)]]
                                    ))
                                } else if let data = reasoningContent.data, !data.isEmpty {
                                    continuation.yield(.reasoningDelta(
                                        id: String(blockIndex),
                                        delta: "",
                                        providerMetadata: ["bedrock": ["redactedData": .string(data)]]
                                    ))
                                }
                            }

                            if let contentStart = chunk.contentBlockStart,
                               let toolUse = contentStart.start?.toolUse {
                                let blockIndex = contentStart.contentBlockIndex
                                let isJsonResponseTool = prepared.usesJsonResponseTool && toolUse.name == "json"

                                let normalizedId = normalizeToolCallId(toolUse.toolUseId, isMistral: isMistral)
                                contentBlocks[blockIndex] = .toolCall(.init(
                                    toolCallId: normalizedId,
                                    toolName: toolUse.name,
                                    jsonText: "",
                                    isJsonResponseTool: isJsonResponseTool
                                ))

                                if !isJsonResponseTool {
                                    continuation.yield(.toolInputStart(
                                        id: normalizedId,
                                        toolName: toolUse.name,
                                        providerMetadata: nil,
                                        providerExecuted: nil,
                                        dynamic: nil,
                                        title: nil
                                    ))
                                }
                            }

                            if let contentDelta = chunk.contentBlockDelta,
                               let toolUseDelta = contentDelta.delta?.toolUse {
                                let blockIndex = contentDelta.contentBlockIndex
                                if case .toolCall(var toolState) = contentBlocks[blockIndex] {
                                    let delta = toolUseDelta.input ?? ""
                                    if !toolState.isJsonResponseTool {
                                        continuation.yield(.toolInputDelta(id: toolState.toolCallId, delta: delta, providerMetadata: nil))
                                    }
                                    toolState.jsonText.append(delta)
                                    contentBlocks[blockIndex] = .toolCall(toolState)
                                }
                            }
                        }
                    }

                    if isJsonResponseFromTool || stopSequence != nil {
                        var bedrockPayload = providerMetadata?["bedrock"] ?? [:]
                        if isJsonResponseFromTool {
                            bedrockPayload["isJsonResponseFromTool"] = .bool(true)
                            bedrockPayload["stopSequence"] = stopSequence.map { .string($0) } ?? .null
                        } else if let stopSequence {
                            bedrockPayload["stopSequence"] = .string(stopSequence)
                        }
                        providerMetadata = ["bedrock": bedrockPayload]
                    }

                    continuation.yield(.finish(
                        finishReason: finishReason,
                        usage: convertBedrockUsage(usageMetrics),
                        providerMetadata: providerMetadata
                    ))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }

        return LanguageModelV3StreamResult(
            stream: stream,
            request: LanguageModelV3RequestInfo(body: prepared.command),
            response: LanguageModelV3StreamResponseInfo(headers: streamResponse.responseHeaders)
        )
    }

    // MARK: - Preparation

    private func prepareRequest(options: LanguageModelV3CallOptions) async throws -> PreparedRequest {
        var warnings: [SharedV3Warning] = []

        var bedrockOptions = (try await parseProviderOptions(
            provider: "bedrock",
            providerOptions: options.providerOptions,
            schema: bedrockProviderOptionsSchema
        )) ?? BedrockProviderOptions()

        if options.frequencyPenalty != nil {
            warnings.append(.unsupported(feature: "frequencyPenalty", details: nil))
        }

        if options.presencePenalty != nil {
            warnings.append(.unsupported(feature: "presencePenalty", details: nil))
        }

        if options.seed != nil {
            warnings.append(.unsupported(feature: "seed", details: nil))
        }

        var temperature = options.temperature
        if let value = temperature, value > 1 {
            warnings.append(.unsupported(
                feature: "temperature",
                details: "\(value) exceeds bedrock maximum of 1.0. clamped to 1.0"
            ))
            temperature = 1
        } else if let value = temperature, value < 0 {
            warnings.append(.unsupported(
                feature: "temperature",
                details: "\(value) is below bedrock minimum of 0. clamped to 0"
            ))
            temperature = 0
        }

        var jsonResponseTool: LanguageModelV3FunctionTool?
        if let responseFormat = options.responseFormat,
           case .json(let schema, _, _) = responseFormat,
           let schema {
            jsonResponseTool = LanguageModelV3FunctionTool(
                name: "json",
                inputSchema: schema,
                description: "Respond with a JSON object."
            )
        }

        var tools = options.tools
        if let jsonResponseTool {
            if tools == nil { tools = [] }
            tools?.append(.function(jsonResponseTool))
        }

        let effectiveToolChoice: LanguageModelV3ToolChoice? = jsonResponseTool != nil ? .required : options.toolChoice
        let preparedTools = try await prepareBedrockTools(
            tools: tools,
            toolChoice: effectiveToolChoice,
            modelId: modelIdentifier.rawValue
        )

        warnings.append(contentsOf: preparedTools.warnings)

        if let additionalTools = preparedTools.additionalTools {
            var existing = bedrockOptions.additionalModelRequestFields ?? [:]
            existing.merge(additionalTools) { _, new in new }
            bedrockOptions.additionalModelRequestFields = existing
        }

        if !preparedTools.betas.isEmpty || bedrockOptions.anthropicBeta != nil {
            let existingBetas = bedrockOptions.anthropicBeta ?? []
            let mergedBetas = !preparedTools.betas.isEmpty
                ? existingBetas + preparedTools.betas.sorted()
                : existingBetas
            var additional = bedrockOptions.additionalModelRequestFields ?? [:]
            additional["anthropic_beta"] = .array(mergedBetas.map { .string($0) })
            bedrockOptions.additionalModelRequestFields = additional
        }

        let modelId = modelIdentifier.rawValue
        let isAnthropicModel = modelId.contains("anthropic")
        let thinkingType = bedrockOptions.reasoningConfig?.type
        let isThinkingRequested = thinkingType == .enabled || thinkingType == .adaptive
        let thinkingBudget = thinkingType == .enabled ? bedrockOptions.reasoningConfig?.budgetTokens : nil
        let isAnthropicThinkingEnabled = isAnthropicModel && isThinkingRequested

        var inferenceConfig: [String: JSONValue] = [:]
        if let maxOutputTokens = options.maxOutputTokens {
            inferenceConfig["maxTokens"] = .number(Double(maxOutputTokens))
        }
        if let temperature {
            inferenceConfig["temperature"] = .number(temperature)
        }
        if let topP = options.topP {
            inferenceConfig["topP"] = .number(topP)
        }
        if let topK = options.topK {
            inferenceConfig["topK"] = .number(Double(topK))
        }
        if let stopSequences = options.stopSequences, !stopSequences.isEmpty {
            inferenceConfig["stopSequences"] = .array(stopSequences.map { .string($0) })
        }

        if isAnthropicThinkingEnabled {
            if let thinkingBudget {
                if let existing = inferenceConfig["maxTokens"], case .number(let value) = existing {
                    inferenceConfig["maxTokens"] = .number(value + Double(thinkingBudget))
                } else {
                    inferenceConfig["maxTokens"] = .number(Double(thinkingBudget + 4096))
                }

                var additional = bedrockOptions.additionalModelRequestFields ?? [:]
                additional["thinking"] = .object([
                    "type": .string("enabled"),
                    "budget_tokens": .number(Double(thinkingBudget))
                ])
                bedrockOptions.additionalModelRequestFields = additional
            } else if thinkingType == .adaptive {
                var additional = bedrockOptions.additionalModelRequestFields ?? [:]
                additional["thinking"] = .object(["type": .string("adaptive")])
                bedrockOptions.additionalModelRequestFields = additional
            }
        } else if !isAnthropicModel {
            if bedrockOptions.reasoningConfig?.budgetTokens != nil {
                warnings.append(.unsupported(
                    feature: "budgetTokens",
                    details: "budgetTokens applies only to Anthropic models on Bedrock and will be ignored for this model."
                ))
            }
            if thinkingType == .adaptive {
                warnings.append(.unsupported(
                    feature: "adaptive thinking",
                    details: "adaptive thinking type applies only to Anthropic models on Bedrock."
                ))
            }
        }

        if let maxReasoningEffort = bedrockOptions.reasoningConfig?.maxReasoningEffort {
            if isAnthropicModel {
                var additional = bedrockOptions.additionalModelRequestFields ?? [:]
                additional["output_config"] = .object([
                    "effort": .string(maxReasoningEffort.rawValue)
                ])
                bedrockOptions.additionalModelRequestFields = additional
            } else if modelId.hasPrefix("openai.") {
                var additional = bedrockOptions.additionalModelRequestFields ?? [:]
                additional["reasoning_effort"] = .string(maxReasoningEffort.rawValue)
                bedrockOptions.additionalModelRequestFields = additional
            } else {
                var payload: [String: JSONValue] = [
                    "maxReasoningEffort": .string(maxReasoningEffort.rawValue)
                ]
                if let thinkingType, thinkingType != .adaptive {
                    payload["type"] = .string(thinkingType.rawValue)
                }
                if let thinkingBudget {
                    payload["budgetTokens"] = .number(Double(thinkingBudget))
                }
                var additional = bedrockOptions.additionalModelRequestFields ?? [:]
                additional["reasoningConfig"] = .object(payload)
                bedrockOptions.additionalModelRequestFields = additional
            }
        }

        if isAnthropicThinkingEnabled && inferenceConfig.removeValue(forKey: "temperature") != nil {
            warnings.append(.unsupported(
                feature: "temperature",
                details: "temperature is not supported when thinking is enabled"
            ))
        }
        if isAnthropicThinkingEnabled && inferenceConfig.removeValue(forKey: "topP") != nil {
            warnings.append(.unsupported(
                feature: "topP",
                details: "topP is not supported when thinking is enabled"
            ))
        }
        if isAnthropicThinkingEnabled && inferenceConfig.removeValue(forKey: "topK") != nil {
            warnings.append(.unsupported(
                feature: "topK",
                details: "topK is not supported when thinking is enabled"
            ))
        }

        let toolsCount: Int = {
            guard let toolsValue = preparedTools.toolConfig["tools"],
                  case .array(let toolsArray) = toolsValue
            else { return 0 }
            return toolsArray.count
        }()
        let hasAnyTools = toolsCount > 0 || preparedTools.additionalTools != nil

        let filteredPrompt = hasAnyTools ? options.prompt : stripToolContent(from: options.prompt, warnings: &warnings)
        let isMistral = isMistralModel(modelId)
        let bedrockMessages = try await convertToBedrockChatMessages(filteredPrompt, isMistral: isMistral)

        // Filter out reasoningConfig and additionalModelRequestFields from providerOptions.bedrock.
        var filteredBedrockOptions = options.providerOptions?["bedrock"] ?? [:]
        filteredBedrockOptions.removeValue(forKey: "reasoningConfig")
        filteredBedrockOptions.removeValue(forKey: "additionalModelRequestFields")

        let additionalModelResponseFieldPaths: [JSONValue]? = isAnthropicModel
            ? [.string("/delta/stop_sequence")]
            : nil

        var command: [String: JSONValue] = [
            "system": .array(bedrockMessages.system),
            "messages": .array(bedrockMessages.messages),
        ]

        if let additionalModelResponseFieldPaths {
            command["additionalModelResponseFieldPaths"] = .array(additionalModelResponseFieldPaths)
        }

        if let additional = bedrockOptions.additionalModelRequestFields, !additional.isEmpty {
            command["additionalModelRequestFields"] = .object(additional)
        }

        if !inferenceConfig.isEmpty {
            command["inferenceConfig"] = .object(inferenceConfig)
        }

        for (key, value) in filteredBedrockOptions {
            command[key] = value
        }

        if toolsCount > 0 {
            command["toolConfig"] = .object(preparedTools.toolConfig)
        }

        return PreparedRequest(
            command: command,
            warnings: warnings,
            usesJsonResponseTool: jsonResponseTool != nil
        )
    }

    private func stripToolContent(from prompt: LanguageModelV3Prompt, warnings: inout [SharedV3Warning]) -> LanguageModelV3Prompt {
        let hasToolContent = prompt.contains { message in
            switch message {
            case .assistant(let parts, _):
                return parts.contains { part in
                    switch part {
                    case .toolCall, .toolResult:
                        return true
                    default:
                        return false
                    }
                }
            case .tool(let parts, _):
                return parts.contains { part in
                    if case .toolResult = part { return true }
                    return false
                }
            case .system, .user:
                return false
            }
        }

        guard hasToolContent else {
            return prompt
        }

        var modified: LanguageModelV3Prompt = []

        for message in prompt {
            switch message {
            case .system:
                modified.append(message)

            case .user:
                modified.append(message)

            case .assistant(let parts, let providerOptions):
                let filtered = parts.filter { part in
                    switch part {
                    case .toolCall, .toolResult:
                        return false
                    default:
                        return true
                    }
                }
                if !filtered.isEmpty {
                    modified.append(.assistant(content: filtered, providerOptions: providerOptions))
                }

            case .tool(let parts, let providerOptions):
                let filtered = parts.filter { part in
                    if case .toolResult = part { return false }
                    return true // keep tool-approval-response
                }
                if !filtered.isEmpty {
                    modified.append(.tool(content: filtered, providerOptions: providerOptions))
                }
            }
        }

        warnings.append(.unsupported(
            feature: "toolContent",
            details: "Tool calls and results removed from conversation because Bedrock does not support tool content without active tools."
        ))

        return modified
    }

    // MARK: - Helpers

    private func chatURL(for modelId: String, path: String) -> String {
        let encoded = bedrockEncodeURIComponent(modelId)
        return "\(config.baseURL())/model/\(encoded)/\(path)"
    }

    private func mergeHeaders(overrides: [String: String]?) -> [String: String] {
        let merged = combineHeaders(
            config.headers(),
            overrides?.mapValues { Optional($0) }
        )
        return merged.compactMapValues { $0 }
    }

    private struct GenerateContentMapping: Sendable {
        let content: [LanguageModelV3Content]
        let isJsonResponseFromTool: Bool
    }

    private func mapGenerateContent(
        response: BedrockGenerateResponse,
        usesJsonResponseTool: Bool,
        isMistral: Bool
    ) -> GenerateContentMapping {
        var items: [LanguageModelV3Content] = []
        var isJsonResponseFromTool = false

        for part in response.output.message.content {
            if let text = part.text {
                items.append(.text(LanguageModelV3Text(text: text)))
            }

            if let reasoning = part.reasoningContent {
                if let text = reasoning.reasoningText?.text {
                    var providerMetadata: SharedV3ProviderMetadata? = nil
                    if let signature = reasoning.reasoningText?.signature {
                        providerMetadata = ["bedrock": ["signature": .string(signature)]]
                    }
                    items.append(.reasoning(LanguageModelV3Reasoning(text: text, providerMetadata: providerMetadata)))
                } else if let redacted = reasoning.redactedReasoning?.data {
                    let metadata: SharedV3ProviderMetadata = ["bedrock": ["redactedData": .string(redacted)]]
                    items.append(.reasoning(LanguageModelV3Reasoning(text: "", providerMetadata: metadata)))
                }
            }

            if let toolUse = part.toolUse {
                let isJsonTool = usesJsonResponseTool && toolUse.name == "json"
                let inputText = (try? canonicalJSONString(from: toolUse.input ?? .object([:]))) ?? "{}"

                if isJsonTool {
                    isJsonResponseFromTool = true
                    items.append(.text(LanguageModelV3Text(text: inputText)))
                } else {
                    let rawToolCallId = toolUse.toolUseId
                    let toolCallId = normalizeToolCallId(rawToolCallId, isMistral: isMistral)
                    let toolName = toolUse.name
                    items.append(.toolCall(LanguageModelV3ToolCall(
                        toolCallId: toolCallId,
                        toolName: toolName,
                        input: inputText
                    )))
                }
            }
        }

        return GenerateContentMapping(content: items, isJsonResponseFromTool: isJsonResponseFromTool)
    }

    private func buildGenerateProviderMetadata(
        response: BedrockGenerateResponse,
        isJsonResponseFromTool: Bool,
        stopSequence: String?
    ) -> SharedV3ProviderMetadata? {
        let traceValue = response.trace
        let traceIsObject: Bool
        if let traceValue, case .object = traceValue {
            traceIsObject = true
        } else {
            traceIsObject = false
        }

        let hasCacheUsage = response.usage?.cacheWriteInputTokens != nil || response.usage?.cacheDetails != nil
        let shouldIncludeMetadata = response.trace != nil
            || response.usage != nil
            || response.performanceConfig != nil
            || response.serviceTier != nil
            || isJsonResponseFromTool
            || stopSequence != nil

        guard shouldIncludeMetadata else {
            return nil
        }

        var payload: [String: JSONValue] = [:]

        if traceIsObject, let traceValue {
            payload["trace"] = traceValue
        }

        if let performanceConfig = response.performanceConfig {
            payload["performanceConfig"] = performanceConfig
        }

        if let serviceTier = response.serviceTier {
            payload["serviceTier"] = serviceTier
        }

        if hasCacheUsage, let usage = response.usage {
            var usagePayload: [String: JSONValue] = [:]
            if let cacheWrite = usage.cacheWriteInputTokens {
                usagePayload["cacheWriteInputTokens"] = .number(Double(cacheWrite))
            }
            if let cacheDetails = usage.cacheDetails {
                usagePayload["cacheDetails"] = cacheDetails
            }
            payload["usage"] = .object(usagePayload)
        }

        if isJsonResponseFromTool {
            payload["isJsonResponseFromTool"] = .bool(true)
        }

        payload["stopSequence"] = stopSequence.map { .string($0) } ?? .null

        return ["bedrock": payload]
    }

    private func canonicalJSONString(from value: JSONValue) throws -> String {
        let anyValue = jsonValueToFoundation(value)
        let data = try JSONSerialization.data(withJSONObject: anyValue, options: [])
        guard let string = String(data: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(anyValue, EncodingError.Context(codingPath: [], debugDescription: "Unable to encode JSON value to string."))
        }
        return string
    }
}

private func convertBedrockUsage(_ usage: BedrockGenerateResponse.Usage?) -> LanguageModelV3Usage {
    // Port of `packages/amazon-bedrock/src/convert-bedrock-usage.ts`
    guard let usage else { return LanguageModelV3Usage() }

    let noCacheTokens = usage.inputTokens ?? 0
    let cacheReadTokens = usage.cacheReadInputTokens ?? 0
    let cacheWriteTokens = usage.cacheWriteInputTokens ?? 0
    let outputTokens = usage.outputTokens ?? 0

    return LanguageModelV3Usage(
        inputTokens: .init(
            total: noCacheTokens + cacheReadTokens + cacheWriteTokens,
            noCache: noCacheTokens,
            cacheRead: cacheReadTokens,
            cacheWrite: cacheWriteTokens
        ),
        outputTokens: .init(
            total: outputTokens,
            text: outputTokens,
            reasoning: nil
        ),
        raw: try? JSONEncoder().encodeToJSONValue(usage)
    )
}

private func convertBedrockUsage(_ usage: BedrockStreamEnvelope.Metadata.Usage?) -> LanguageModelV3Usage {
    // Port of `packages/amazon-bedrock/src/convert-bedrock-usage.ts`
    guard let usage else { return LanguageModelV3Usage() }

    let noCacheTokens = usage.inputTokens ?? 0
    let cacheReadTokens = usage.cacheReadInputTokens ?? 0
    let cacheWriteTokens = usage.cacheWriteInputTokens ?? 0
    let outputTokens = usage.outputTokens ?? 0

    return LanguageModelV3Usage(
        inputTokens: .init(
            total: noCacheTokens + cacheReadTokens + cacheWriteTokens,
            noCache: noCacheTokens,
            cacheRead: cacheReadTokens,
            cacheWrite: cacheWriteTokens
        ),
        outputTokens: .init(
            total: outputTokens,
            text: outputTokens,
            reasoning: nil
        ),
        raw: try? JSONEncoder().encodeToJSONValue(usage)
    )
}

private extension JSONEncoder {
    func encodeToJSONValue<T: Encodable>(_ value: T) throws -> JSONValue {
        let data = try encode(value)
        let raw = try JSONSerialization.jsonObject(with: data, options: [])
        return try jsonValue(from: raw)
    }
}

// MARK: - Content Block State

    private enum StreamContentBlockState {
        case text
        case reasoning
        case toolCall(ToolBlockState)
    }

    private struct ToolBlockState: Sendable {
        let toolCallId: String
        let toolName: String
        var jsonText: String
        let isJsonResponseTool: Bool
    }

private extension ParseJSONResult where Output == BedrockStreamEnvelope {
    var rawJSONValue: JSONValue? {
        switch self {
        case .success(_, let raw):
            return try? jsonValue(from: raw)
        case .failure(_, let raw):
            return raw.flatMap { try? jsonValue(from: $0) }
        }
    }
}



// MARK: - Streaming Schema

private struct BedrockAdditionalModelResponseFields: Codable, Sendable {
    struct Delta: Codable, Sendable {
        let stop_sequence: String?
    }

    let delta: Delta?
}

private struct BedrockToolUse: Codable, Sendable {
    let toolUseId: String
    let name: String
    let input: JSONValue?
}

private struct BedrockStreamEnvelope: Codable, Sendable {
    struct ContentBlockDelta: Codable, Sendable {
        struct Delta: Codable, Sendable {
            struct ToolUse: Codable, Sendable {
                let input: String?
            }

            struct ReasoningContent: Codable, Sendable {
                let text: String?
                let signature: String?
                let data: String?
            }

            let text: String?
            let toolUse: ToolUse?
            let reasoningContent: ReasoningContent?
        }
        let contentBlockIndex: Int
        let delta: Delta?
    }

    struct ContentBlockStart: Codable, Sendable {
        struct Start: Codable, Sendable {
            let toolUse: BedrockToolUse?
        }

        let contentBlockIndex: Int
        let start: Start?
    }

    struct ContentBlockStop: Codable, Sendable {
        let contentBlockIndex: Int
    }

    struct Metadata: Codable, Sendable {
        struct Usage: Codable, Sendable {
            let cacheReadInputTokens: Int?
            let cacheWriteInputTokens: Int?
            let cacheDetails: JSONValue?
            let inputTokens: Int?
            let outputTokens: Int?
            let totalTokens: Int?
        }

        let trace: JSONValue?
        let performanceConfig: JSONValue?
        let serviceTier: JSONValue?
        let usage: Usage?
    }

    struct MessageStop: Codable, Sendable {
        let additionalModelResponseFields: BedrockAdditionalModelResponseFields?
        let stopReason: String
    }

    let contentBlockDelta: ContentBlockDelta?
    let contentBlockStart: ContentBlockStart?
    let contentBlockStop: ContentBlockStop?
    let internalServerException: [String: JSONValue]?
    let messageStop: MessageStop?
    let metadata: Metadata?
    let modelStreamErrorException: [String: JSONValue]?
    let throttlingException: [String: JSONValue]?
    let validationException: [String: JSONValue]?
}

private extension BedrockStreamEnvelope {
    var firstError: [String: JSONValue]? {
        internalServerException ?? modelStreamErrorException ?? throttlingException ?? validationException
    }
}

private let bedrockStreamSchema = FlexibleSchema(
    Schema<BedrockStreamEnvelope>.codable(
        BedrockStreamEnvelope.self,
        jsonSchema: .object([
            "type": .string("object")
        ])
    )
)

// MARK: - Generate Response Schema

private struct BedrockGenerateResponse: Codable, Sendable {
    struct Output: Codable, Sendable {
        struct Message: Codable, Sendable {
            struct Content: Codable, Sendable {
                struct ReasoningContent: Codable, Sendable {
                    struct ReasoningText: Codable, Sendable {
                        let text: String
                        let signature: String?
                    }

                    struct RedactedReasoning: Codable, Sendable {
                        let data: String?
                    }

                    let reasoningText: ReasoningText?
                    let redactedReasoning: RedactedReasoning?

                    var text: String? { reasoningText?.text }
                    var signature: String? { reasoningText?.signature }
                    var data: String? { redactedReasoning?.data }
                }

                let text: String?
                let toolUse: BedrockToolUse?
                let reasoningContent: ReasoningContent?
            }

            let role: String
            let content: [Content]
        }

        let message: Message
    }

    struct Usage: Codable, Sendable {
        let inputTokens: Int?
        let outputTokens: Int?
        let totalTokens: Int?
        let cacheReadInputTokens: Int?
        let cacheWriteInputTokens: Int?
        let cacheDetails: JSONValue?
    }

    struct Metrics: Codable, Sendable {
        let latencyMs: Int?
    }

    let metrics: Metrics?
    let output: Output
    let stopReason: String
    let additionalModelResponseFields: BedrockAdditionalModelResponseFields?
    let trace: JSONValue?
    let performanceConfig: JSONValue?
    let serviceTier: JSONValue?
    let usage: Usage?
}

private let bedrockGenerateResponseSchema = FlexibleSchema(
    Schema<BedrockGenerateResponse>.codable(
        BedrockGenerateResponse.self,
        jsonSchema: .object([
            "type": .string("object")
        ])
    )
)
