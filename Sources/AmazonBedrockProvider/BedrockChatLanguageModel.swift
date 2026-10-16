import Foundation
import AISDKProvider
import AISDKProviderUtils
import AnthropicProvider

public final class BedrockChatLanguageModel: LanguageModelV4 {
    struct Config: Sendable {
        let baseURL: @Sendable () throws -> String
        let headers: @Sendable () -> [String: String?]
        let fetch: FetchFunction?
        let generateId: @Sendable () -> String
        var modelFamily: BedrockChatModelSettings.ModelFamily? = nil
    }
    private struct PreparedRequest {
        let command: [String: JSONValue]
        let warnings: [SharedV4Warning]
        let usesJsonResponseTool: Bool
        let usesJsonInstruction: Bool
    }
    private let modelIdentifier: BedrockChatModelId
    private let config: Config
    init(modelId: BedrockChatModelId, config: Config) { self.modelIdentifier = modelId; self.config = config }
    public var provider: String { "amazon-bedrock" }
    public var modelId: String { modelIdentifier.rawValue }
    public var supportedUrls: [String: [NSRegularExpression]] {
        ["image/*": [try! NSRegularExpression(pattern: "^s3://")], "video/*": [try! NSRegularExpression(pattern: "^s3://")]]
    }

    public func doGenerate(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4GenerateResult {
        let prepared = try await prepareRequest(options)
        let response = try await postJsonToAPI(
            url: "\(try config.baseURL())/model/\(bedrockEncodeURIComponent(modelId))/converse",
            headers: headers(options.headers), body: JSONValue.object(prepared.command),
            failedResponseHandler: createJsonErrorResponseHandler(errorSchema: BedrockErrorSchema, errorToMessage: { $0.message }),
            successfulResponseHandler: createJsonResponseHandler(responseSchema: bedrockGenerateResponseSchema),
            isAborted: options.abortSignal, fetch: config.fetch
        )
        var content: [LanguageModelV4Content] = []
        var isJsonResponseFromTool = false
        var extractor = JsonObjectTextExtractor()
        for part in response.value.output.message.content {
            let texts = part.text.map { [$0] } ?? part.citationsContent?.content?.compactMap(\.text) ?? []
            for text in texts { content.append(.text(.init(text: prepared.usesJsonInstruction ? extractor.process(text) : text))) }
            if let reasoning = part.reasoningContent {
                if let text = reasoning.reasoningText {
                    content.append(.reasoning(.init(text: text.text, providerMetadata: text.signature.map { bedrockMetadata(["signature": .string($0)]) })))
                } else if let redacted = reasoning.redactedReasoning {
                    content.append(.reasoning(.init(text: "", providerMetadata: bedrockMetadata(["redactedData": .string(redacted.data)]))))
                } else if let redacted = reasoning.redactedContent {
                    content.append(.reasoning(.init(text: "", providerMetadata: bedrockMetadata(["redactedContent": .string(redacted)]))))
                }
            }
            if let tool = part.toolUse {
                let input = try bedrockJSONString(tool.input ?? .object([:]))
                if prepared.usesJsonResponseTool && tool.name == "json" {
                    isJsonResponseFromTool = true
                    content.append(.text(.init(text: input)))
                } else {
                    content.append(.toolCall(.init(toolCallId: normalizeToolCallId(tool.toolUseId.isEmpty ? config.generateId() : tool.toolUseId, isMistral: isMistralModel(modelId)), toolName: tool.name, input: input)))
                }
            }
        }
        let value = response.value
        let stopSequence = value.additionalModelResponseFields?.delta?.stop_sequence
        var metadata = metadataPayload(usage: value.usage, trace: value.trace, performanceConfig: value.performanceConfig, serviceTier: value.serviceTier)
        if value.trace != nil || isJsonResponseFromTool || stopSequence != nil || metadata != nil {
            if metadata == nil { metadata = [:] }
            if isJsonResponseFromTool { metadata?["isJsonResponseFromTool"] = .bool(true) }
            metadata?["stopSequence"] = stopSequence.map(JSONValue.string) ?? .null
        }
        return LanguageModelV4GenerateResult(
            content: content,
            finishReason: .init(unified: mapBedrockFinishReason(value.stopReason, isJsonResponseFromTool: isJsonResponseFromTool), raw: value.stopReason),
            usage: convertBedrockUsage(value.usage), providerMetadata: metadata.map(bedrockMetadata),
            request: .init(body: prepared.command),
            response: .init(id: response.responseHeaders["x-amzn-requestid"], timestamp: parseBedrockHTTPDate(response.responseHeaders["date"]), modelId: modelId, headers: response.responseHeaders),
            warnings: prepared.warnings
        )
    }

    public func doStream(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4StreamResult {
        let prepared = try await prepareRequest(options)
        let response = try await postJsonToAPI(
            url: "\(try config.baseURL())/model/\(bedrockEncodeURIComponent(modelId))/converse-stream",
            headers: headers(options.headers), body: JSONValue.object(prepared.command),
            failedResponseHandler: bedrockFailedResponseHandler,
            successfulResponseHandler: createBedrockEventStreamResponseHandler(chunkSchema: bedrockStreamSchema),
            isAborted: options.abortSignal, fetch: config.fetch
        )
        let modelId = modelId
        let stream = AsyncThrowingStream<LanguageModelV4StreamPart, Error> { continuation in
            continuation.yield(.streamStart(warnings: prepared.warnings))
            continuation.yield(.responseMetadata(id: response.responseHeaders["x-amzn-requestid"], modelId: modelId, timestamp: parseBedrockHTTPDate(response.responseHeaders["date"])))
            let task = Task {
                var finishReason = LanguageModelV4FinishReason(unified: .other)
                var usage: BedrockUsage?
                var metadata: [String: JSONValue]?
                var isJsonResponseFromTool = false
                var stopSequence: String?
                var blocks: [Int: BedrockStreamBlock] = [:]
                var extractor = JsonObjectTextExtractor()
                do {
                    for try await result in response.value {
                        try Task.checkCancellation()
                        let raw = result.rawJSONValue
                        if options.includeRawChunks == true, let raw { continuation.yield(.raw(rawValue: raw)) }
                        let chunk: BedrockStreamEnvelope
                        switch result {
                        case .failure(let error, _):
                            finishReason = .init(unified: .error)
                            continuation.yield(.error(error: .error(error)))
                            continue
                        case .success(let value, _): chunk = value
                        }
                        if let (type, payload) = chunk.firstError {
                            finishReason = .init(unified: .error)
                            let status = bedrockStreamErrorStatus(type)
                            let message: String
                            if case .string(let text)? = payload["message"] { message = text } else { message = "Amazon Bedrock stream failed with \(type)" }
                            continuation.yield(.error(error: .providerStreamError(.init(message: message, type: type, statusCode: status.code, isRetryable: status.retryable, data: raw ?? .object([type: .object(payload)])))))
                            continue
                        }
                        if let stop = chunk.messageStop {
                            finishReason = .init(unified: mapBedrockFinishReason(stop.stopReason, isJsonResponseFromTool: isJsonResponseFromTool), raw: stop.stopReason)
                            stopSequence = stop.additionalModelResponseFields?.delta?.stop_sequence
                        }
                        if let value = chunk.metadata {
                            if let metrics = value.usage { usage = metrics }
                            if let payload = metadataPayload(usage: value.usage, trace: value.trace, performanceConfig: value.performanceConfig, serviceTier: value.serviceTier, stream: true) { metadata = payload }
                        }
                        if let start = chunk.contentBlockStart, start.start?.toolUse == nil {
                            blocks[start.contentBlockIndex] = .text
                            continuation.yield(.textStart(id: String(start.contentBlockIndex), providerMetadata: nil))
                        }
                        if let delta = chunk.contentBlockDelta, let text = delta.delta?.text, !text.isEmpty {
                            let index = delta.contentBlockIndex
                            if blocks[index] == nil { blocks[index] = .text; continuation.yield(.textStart(id: String(index), providerMetadata: nil)) }
                            let text = prepared.usesJsonInstruction ? extractor.process(text) : text
                            if !text.isEmpty { continuation.yield(.textDelta(id: String(index), delta: text, providerMetadata: nil)) }
                        }
                        if let stop = chunk.contentBlockStop, let block = blocks.removeValue(forKey: stop.contentBlockIndex) {
                            let id = String(stop.contentBlockIndex)
                            switch block {
                            case .text: continuation.yield(.textEnd(id: id, providerMetadata: nil))
                            case .reasoning(let redacted): continuation.yield(.reasoningEnd(id: id, providerMetadata: redacted.map { bedrockMetadata(["redactedContent": .string($0)]) }))
                            case .tool(let tool):
                                if tool.isJson {
                                    isJsonResponseFromTool = true
                                    continuation.yield(.textStart(id: id, providerMetadata: nil))
                                    continuation.yield(.textDelta(id: id, delta: tool.input, providerMetadata: nil))
                                    continuation.yield(.textEnd(id: id, providerMetadata: nil))
                                } else {
                                    continuation.yield(.toolInputEnd(id: tool.id, providerMetadata: nil))
                                    continuation.yield(.toolCall(.init(toolCallId: tool.id, toolName: tool.name, input: tool.input.isEmpty ? "{}" : tool.input)))
                                }
                            }
                        }
                        if let delta = chunk.contentBlockDelta, let reasoning = delta.delta?.reasoningContent {
                            let index = delta.contentBlockIndex
                            let hasContent = [reasoning.text, reasoning.signature, reasoning.data, reasoning.redactedContent].contains { $0?.isEmpty == false }
                            if hasContent && blocks[index] == nil { blocks[index] = .reasoning(nil); continuation.yield(.reasoningStart(id: String(index), providerMetadata: nil)) }
                            if let text = reasoning.text, !text.isEmpty { continuation.yield(.reasoningDelta(id: String(index), delta: text, providerMetadata: nil)) }
                            else if let signature = reasoning.signature, !signature.isEmpty { continuation.yield(.reasoningDelta(id: String(index), delta: "", providerMetadata: bedrockMetadata(["signature": .string(signature)]))) }
                            else if let data = reasoning.data, !data.isEmpty { continuation.yield(.reasoningDelta(id: String(index), delta: "", providerMetadata: bedrockMetadata(["redactedData": .string(data)]))) }
                            else if let redacted = reasoning.redactedContent, !redacted.isEmpty, case .reasoning(let previous) = blocks[index] { blocks[index] = .reasoning((previous ?? "") + redacted) }
                        }
                        if let start = chunk.contentBlockStart, let tool = start.start?.toolUse {
                            let id = normalizeToolCallId(tool.toolUseId, isMistral: isMistralModel(modelId))
                            let isJson = prepared.usesJsonResponseTool && tool.name == "json"
                            blocks[start.contentBlockIndex] = .tool(.init(id: id, name: tool.name, input: "", isJson: isJson))
                            if !isJson { continuation.yield(.toolInputStart(id: id, toolName: tool.name, providerMetadata: nil, providerExecuted: nil, dynamic: nil, title: nil)) }
                        }
                        if let delta = chunk.contentBlockDelta, let input = delta.delta?.toolUse?.input, case .tool(var tool) = blocks[delta.contentBlockIndex] {
                            if !tool.isJson { continuation.yield(.toolInputDelta(id: tool.id, delta: input, providerMetadata: nil)) }
                            tool.input += input
                            blocks[delta.contentBlockIndex] = .tool(tool)
                        }
                    }
                    if isJsonResponseFromTool || stopSequence != nil {
                        if metadata == nil { metadata = [:] }
                        if isJsonResponseFromTool { metadata?["isJsonResponseFromTool"] = .bool(true) }
                        metadata?["stopSequence"] = stopSequence.map(JSONValue.string) ?? .null
                    }
                    continuation.yield(.finish(finishReason: finishReason, usage: convertBedrockUsage(usage), providerMetadata: metadata.map(bedrockMetadata)))
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return .init(stream: stream, request: .init(body: prepared.command), response: .init(headers: response.responseHeaders))
    }

    private func prepareRequest(_ options: LanguageModelV4CallOptions) async throws -> PreparedRequest {
        var settings = try await parseBedrockOptions(providerOptions: options.providerOptions, schema: bedrockProviderOptionsSchema) ?? .init()
        let anthropic = try await parseProviderOptions(provider: "anthropic", providerOptions: options.providerOptions, schema: bedrockAnthropicOptionsSchema)
        let capabilities = getAnthropicModelCapabilities(modelId: modelId)
        var warnings: [SharedV4Warning] = []
        for (feature, present) in [("frequencyPenalty", options.frequencyPenalty != nil), ("presencePenalty", options.presencePenalty != nil), ("seed", options.seed != nil)] where present { warnings.append(.unsupported(feature: feature, details: nil)) }
        var temperature = options.temperature
        var topP = options.topP
        var topK = options.topK
        if capabilities.rejectsSamplingParameters {
            for (feature, present) in [("temperature", temperature != nil), ("topP", topP != nil), ("topK", topK != nil)] where present { warnings.append(.unsupported(feature: feature, details: "\(feature) is not supported by \(modelId) and will be ignored")) }
            temperature = nil; topP = nil; topK = nil
        }
        let openAIId = modelId.range(of: "^(?:[^.]+\\.)?(openai\\..+)$", options: .regularExpression) != nil
        let isGptOss = modelId.contains("openai.gpt-oss-") && openAIId
        let isNova = modelId.contains("amazon.nova-2-lite-v1:0")
        if !openAIId || isGptOss, let value = temperature, value > 1 || value < 0 {
            temperature = min(1, max(0, value))
            warnings.append(.unsupported(feature: "temperature", details: value > 1 ? "\(value) exceeds bedrock maximum of 1.0. clamped to 1.0" : "\(value) is below bedrock minimum of 0. clamped to 0"))
        }
        let isAnthropic = isBedrockAnthropicModel(modelId, modelFamily: config.modelFamily, reasoningBudgetTokens: settings.reasoningConfig?.budgetTokens)
        resolveReasoning(options.reasoning, settings: &settings, isAnthropic: isAnthropic, isOpenAI: openAIId, isNova: isNova, warnings: &warnings)
        let thinkingType = settings.reasoningConfig?.type
        let thinkingEnabled = thinkingType == .enabled || thinkingType == .adaptive
        let mode = settings.structuredOutputMode ?? anthropic?.structuredOutputMode ?? .auto
        var additional = settings.additionalModelRequestFields ?? [:]
        if mode == .jsonTool, case .object(var output)? = additional["output_config"] {
            output.removeValue(forKey: "format")
            additional["output_config"] = output.isEmpty ? nil : .object(output)
        }
        var schema: JSONValue?
        if case .json(let value, _, _) = options.responseFormat { schema = value }
        let nativeSupported = bedrockSupportsNativeStructuredOutput(modelId) && (capabilities.supportsStructuredOutput || thinkingEnabled || config.modelFamily == .anthropic)
        let useNative = isAnthropic && schema != nil && (mode == .outputFormat || (mode == .auto && nativeSupported))
        let useInstruction = !useNative && isAnthropic && schema != nil && (
            capabilities.rejectsForcedToolUse ||
            (modelId.contains("claude-") && (!capabilities.isKnownModel || !capabilities.supportsStructuredOutput) && !bedrockSupportsNativeStructuredOutput(modelId) && mode != .jsonTool) ||
            (mode != .jsonTool && !bedrockSupportsStrictTools(modelId) && options.tools?.isEmpty == false)
        )
        let jsonTool = schema != nil && !useNative && !useInstruction
        var tools = options.tools
        if jsonTool, let schema { tools = (tools ?? []) + [.function(.init(name: "json", inputSchema: schema, description: "Respond with a JSON object."))] }
        let preparedTools = try await prepareBedrockTools(tools: tools, toolChoice: jsonTool ? .required : options.toolChoice, modelId: modelId, modelFamily: config.modelFamily, reasoningBudgetTokens: settings.reasoningConfig?.budgetTokens, disableParallelToolUse: anthropic?.disableParallelToolUse, rejectsForcedToolUse: capabilities.rejectsForcedToolUse)
        warnings += preparedTools.warnings
        additional.merge(preparedTools.additionalTools ?? [:]) { _, new in new }
        if !preparedTools.betas.isEmpty || settings.anthropicBeta != nil { additional["anthropic_beta"] = .array(((settings.anthropicBeta ?? []) + preparedTools.betas.sorted()).map(JSONValue.string)) }
        var inference: [String: JSONValue] = [:]
        if let value = options.maxOutputTokens { inference["maxTokens"] = .number(Double(value)) }
        if let value = temperature { inference["temperature"] = .number(value) }
        if let value = topP { inference["topP"] = .number(value) }
        if let value = topK { inference["topK"] = .number(Double(value)) }
        if let value = options.stopSequences { inference["stopSequences"] = .array(value.map(JSONValue.string)) }
        if isAnthropic && thinkingEnabled {
            if thinkingType == .enabled, let budget = settings.reasoningConfig?.budgetTokens {
                inference["maxTokens"] = .number(Double(options.maxOutputTokens ?? 4096) + budget)
                additional["thinking"] = .object(["type": .string("enabled"), "budget_tokens": .number(budget)])
            } else if thinkingType == .adaptive {
                var thinking: [String: JSONValue] = ["type": .string("adaptive")]
                if let display = settings.reasoningConfig?.display { thinking["display"] = .string(display.rawValue) }
                additional["thinking"] = .object(thinking)
            }
        } else if !isAnthropic {
            if settings.reasoningConfig?.budgetTokens != nil { warnings.append(.unsupported(feature: "budgetTokens", details: "budgetTokens applies only to Anthropic models on Bedrock and will be ignored for this model.")) }
            if thinkingType == .adaptive { warnings.append(.unsupported(feature: "adaptive thinking", details: "adaptive thinking type applies only to Anthropic models on Bedrock.")) }
        }
        if let effort = settings.reasoningConfig?.maxReasoningEffort {
            if isAnthropic {
                var output = additional["output_config"]?.objectValue ?? [:]
                output["effort"] = .string(effort.rawValue); additional["output_config"] = .object(output)
            } else if openAIId {
                if isGptOss { additional["reasoning_effort"] = .string(effort.rawValue) }
                else { var reasoning = additional["reasoning"]?.objectValue ?? [:]; reasoning["effort"] = .string(effort.rawValue); additional["reasoning"] = .object(reasoning) }
            } else {
                var reasoning: [String: JSONValue] = ["maxReasoningEffort": .string(effort.rawValue)]
                if let type = thinkingType, type != .adaptive { reasoning["type"] = .string(type.rawValue) }
                additional["reasoningConfig"] = .object(reasoning)
            }
        }
        if isNova && thinkingType == .enabled && [BedrockMaxReasoningEffort.high, .xhigh, .max].contains(where: { $0 == settings.reasoningConfig?.maxReasoningEffort }), inference.removeValue(forKey: "maxTokens") != nil {
            warnings.append(.unsupported(feature: "maxOutputTokens", details: "maxOutputTokens is not supported by \(modelId) when high reasoning is enabled and will be ignored"))
        }
        if useNative, let schema {
            var output = additional["output_config"]?.objectValue ?? [:]
            output["format"] = .object(["type": .string("json_schema"), "schema": sanitizeAnthropicJSONSchema(schema)])
            additional["output_config"] = .object(output)
        }
        if isAnthropic && thinkingEnabled {
            for feature in ["temperature", "topP", "topK"] where inference.removeValue(forKey: feature) != nil { warnings.append(.unsupported(feature: feature, details: "\(feature) is not supported when thinking is enabled")) }
        }
        if openAIId {
            for feature in isGptOss ? ["stopSequences"] : ["temperature", "topP", "stopSequences"] where inference.removeValue(forKey: feature) != nil { warnings.append(.unsupported(feature: feature, details: "\(feature) is not supported by this OpenAI model on the Converse API")) }
        }
        let hasTools = preparedTools.toolConfig["tools"]?.arrayValue?.isEmpty == false || preparedTools.additionalTools != nil
        var prompt = hasTools ? options.prompt : stripBedrockToolContent(options.prompt, warnings: &warnings)
        if useInstruction, let schema { prompt = try injectBedrockJSONInstruction(prompt, schema: schema) }
        let converted = try await convertToBedrockChatMessages(prompt, isMistral: isMistralModel(modelId))
        var command: [String: JSONValue] = ["system": .array(converted.system), "messages": .array(converted.messages)]
        if !additional.isEmpty { command["additionalModelRequestFields"] = .object(additional) }
        if isAnthropic { command["additionalModelResponseFieldPaths"] = .array([.string("/delta/stop_sequence")]) }
        if !inference.isEmpty { command["inferenceConfig"] = .object(inference) }
        if let tier = settings.serviceTier { command["serviceTier"] = .object(["type": .string(tier.rawValue)]) }
        if let metadata = settings.requestMetadata { command["requestMetadata"] = .object(metadata.mapValues(JSONValue.string)) }
        let excluded = Set(["reasoningConfig", "additionalModelRequestFields", "serviceTier", "structuredOutputMode", "requestMetadata"])
        for (key, value) in options.providerOptions?["amazonBedrock"] ?? options.providerOptions?["bedrock"] ?? [:] where !excluded.contains(key) { command[key] = value }
        if preparedTools.toolConfig["tools"]?.arrayValue?.isEmpty == false { command["toolConfig"] = .object(preparedTools.toolConfig) }
        return .init(command: command, warnings: warnings, usesJsonResponseTool: jsonTool, usesJsonInstruction: useInstruction)
    }

    private func resolveReasoning(_ reasoning: LanguageModelV4ReasoningEffort?, settings: inout BedrockProviderOptions, isAnthropic: Bool, isOpenAI: Bool, isNova: Bool, warnings: inout [SharedV4Warning]) {
        guard let reasoning, isCustomReasoning(reasoning) else { return }
        if settings.reasoningConfig?.type == .disabled { settings.reasoningConfig?.maxReasoningEffort = nil; settings.reasoningConfig?.budgetTokens = nil; return }
        var config = settings.reasoningConfig ?? .init()
        if isAnthropic {
            let capabilities = getAnthropicModelCapabilities(modelId: modelId)
            if reasoning == .none { settings.reasoningConfig = .init(type: .disabled); return }
            if capabilities.supportsAdaptiveThinking {
                config.type = config.type ?? .adaptive
                config.maxReasoningEffort = config.maxReasoningEffort ?? portableEffort(reasoning, isNova: false, warnings: &warnings)
            } else {
                let budget = config.budgetTokens ?? mapReasoningToProviderBudget(reasoning: reasoning, maxOutputTokens: capabilities.maxOutputTokens, maxReasoningBudget: capabilities.maxOutputTokens, warnings: &warnings).map(Double.init)
                if let budget { config.type = config.type ?? .enabled; config.budgetTokens = budget }
            }
        } else if reasoning != .none {
            if isOpenAI || isNova || settings.reasoningConfig != nil {
                if isNova { config.type = config.type ?? .enabled }
                config.maxReasoningEffort = config.maxReasoningEffort ?? portableEffort(reasoning, isNova: isNova, warnings: &warnings)
            } else {
                warnings.append(.unsupported(feature: "reasoning", details: "Portable reasoning is not supported for this model and will be ignored. If the model supports a provider-specific reasoning configuration, use providerOptions.amazonBedrock.reasoningConfig."))
                return
            }
        } else { return }
        settings.reasoningConfig = config
    }

    private func portableEffort(_ reasoning: LanguageModelV4ReasoningEffort, isNova: Bool, warnings: inout [SharedV4Warning]) -> BedrockMaxReasoningEffort? {
        let map: [LanguageModelV4ReasoningEffort: String] = [.minimal: "low", .low: "low", .medium: "medium", .high: "high", .xhigh: isNova ? "high" : "max", .max: isNova ? "high" : "max"]
        return mapReasoningToProviderEffort(reasoning: reasoning, effortMap: map, warnings: &warnings).flatMap(BedrockMaxReasoningEffort.init(rawValue:))
    }

    private func headers(_ overrides: [String: String]?) -> [String: String] { combineHeaders(config.headers(), overrides?.mapValues(Optional.some)).compactMapValues { $0 } }
}

private func stripBedrockToolContent(_ prompt: LanguageModelV4Prompt, warnings: inout [SharedV4Warning]) -> LanguageModelV4Prompt {
    var removed = false
    let result = prompt.compactMap { message -> LanguageModelV4Message? in
        switch message {
        case .assistant(let parts, let options):
            let filtered = parts.filter { if case .toolCall = $0 { removed = true; return false }; if case .toolResult = $0 { removed = true; return false }; return true }
            return filtered.isEmpty ? nil : .assistant(content: filtered, providerOptions: options)
        case .tool(let parts, let options):
            let filtered = parts.filter { if case .toolResult = $0 { removed = true; return false }; return true }
            return filtered.isEmpty ? nil : .tool(content: filtered, providerOptions: options)
        case .user(let parts, _): return parts.isEmpty ? nil : message
        default: return message
        }
    }
    if removed { warnings.append(.unsupported(feature: "toolContent", details: "Tool calls and results removed from conversation because Bedrock does not support tool content without active tools.")) }
    return removed ? result : prompt
}

private func injectBedrockJSONInstruction(_ prompt: LanguageModelV4Prompt, schema: JSONValue) throws -> LanguageModelV4Prompt {
    let instruction = "JSON schema:\n\(try bedrockJSONString(schema))\nYou MUST answer with only a JSON object that matches the JSON schema above. Do not wrap it in markdown fences or include any other text."
    var prompt = prompt
    if case .system(let content, let options)? = prompt.first { prompt[0] = .system(content: content.isEmpty ? instruction : content + "\n\n" + instruction, providerOptions: options) }
    else { prompt.insert(.system(content: instruction, providerOptions: nil), at: 0) }
    return prompt
}

private enum BedrockStreamBlock {
    case text
    case reasoning(String?)
    case tool(Tool)
    struct Tool { let id: String; let name: String; var input: String; let isJson: Bool }
}

private struct JsonObjectTextExtractor {
    private var started = false
    private var completed = false
    private var depth = 0
    private var inString = false
    private var escaped = false
    mutating func process(_ text: String) -> String {
        var result = ""
        for character in text {
            if completed { break }
            if !started { if character == "{" { started = true; depth = 1; result.append(character) }; continue }
            result.append(character)
            if escaped { escaped = false; continue }
            if character == "\\" && inString { escaped = true; continue }
            if character == "\"" { inString.toggle(); continue }
            if inString { continue }
            if character == "{" { depth += 1 }
            else if character == "}" { depth -= 1; if depth == 0 { completed = true } }
        }
        return result
    }
}

private func bedrockMetadata(_ payload: [String: JSONValue]) -> SharedV4ProviderMetadata { ["amazonBedrock": payload, "bedrock": payload] }
private func parseBedrockHTTPDate(_ value: String?) -> Date? {
    guard let value else { return nil }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    formatter.timeZone = TimeZone(abbreviation: "GMT")
    return formatter.date(from: value)
}

func bedrockStreamErrorStatus(_ type: String) -> (code: Int?, retryable: Bool?) {
    switch type.lowercased() {
    case "internalserverexception": return (500, true)
    case "modelstreamerrorexception": return (424, true)
    case "serviceunavailableexception": return (503, true)
    case "throttlingexception": return (429, true)
    case "validationexception": return (400, false)
    default: return (nil, nil)
    }
}

private struct BedrockPerformanceConfig: Codable, Sendable { let latency: String }
private struct BedrockServiceTierMetadata: Codable, Sendable { let type: String }
private struct BedrockCacheDetail: Decodable, Sendable {
    let raw: JSONValue
    private enum CodingKeys: String, CodingKey { case inputTokens, ttl }
    init(from decoder: Decoder) throws {
        raw = try JSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _ = try container.decode(Double.self, forKey: .inputTokens)
        _ = try container.decode(String.self, forKey: .ttl)
    }
}
private struct BedrockUsage: Codable, Sendable {
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadInputTokens: Int?
    let cacheWriteInputTokens: Int?
    let cacheDetails: JSONValue?
    let raw: JSONValue
    private enum CodingKeys: String, CodingKey { case inputTokens, outputTokens, cacheReadInputTokens, cacheWriteInputTokens, cacheDetails }
    init(from decoder: Decoder) throws {
        raw = try JSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        inputTokens = try container.decode(Int.self, forKey: .inputTokens)
        outputTokens = try container.decode(Int.self, forKey: .outputTokens)
        cacheReadInputTokens = try container.decodeIfPresent(Int.self, forKey: .cacheReadInputTokens)
        cacheWriteInputTokens = try container.decodeIfPresent(Int.self, forKey: .cacheWriteInputTokens)
        cacheDetails = try container.decodeIfPresent([BedrockCacheDetail].self, forKey: .cacheDetails).map { .array($0.map(\.raw)) }
    }
    func encode(to encoder: Encoder) throws { try raw.encode(to: encoder) }
}
private func convertBedrockUsage(_ usage: BedrockUsage?) -> LanguageModelV4Usage {
    guard let usage else { return .init() }
    let read = usage.cacheReadInputTokens ?? 0
    let write = usage.cacheWriteInputTokens ?? 0
    return .init(inputTokens: .init(total: usage.inputTokens + read + write, noCache: usage.inputTokens, cacheRead: read, cacheWrite: write), outputTokens: .init(total: usage.outputTokens, text: usage.outputTokens), raw: usage.raw)
}
private func metadataPayload(usage: BedrockUsage?, trace: JSONValue?, performanceConfig: BedrockPerformanceConfig?, serviceTier: BedrockServiceTierMetadata?, stream: Bool = false) -> [String: JSONValue]? {
    var payload: [String: JSONValue] = [:]
    if let trace {
        switch trace {
        case .object, .array: payload["trace"] = trace
        case .null, .bool(false), .number(0), .string(""): break
        default: if stream { payload["trace"] = trace }
        }
    }
    if let performanceConfig { payload["performanceConfig"] = .object(["latency": .string(performanceConfig.latency)]) }
    if let serviceTier { payload["serviceTier"] = .object(["type": .string(serviceTier.type)]) }
    if let usage, usage.cacheWriteInputTokens != nil || usage.cacheDetails != nil {
        var cache: [String: JSONValue] = [:]
        if let value = usage.cacheWriteInputTokens { cache["cacheWriteInputTokens"] = .number(Double(value)) }
        if let value = usage.cacheDetails { cache["cacheDetails"] = value }
        payload["usage"] = .object(cache)
    }
    return payload.isEmpty && !(!stream && usage != nil) ? nil : payload
}

private struct BedrockAdditionalResponseFields: Codable, Sendable {
    struct Delta: Codable, Sendable { let stop_sequence: String? }
    let delta: Delta?
}
private struct BedrockToolUse: Codable, Sendable { let toolUseId: String; let name: String; let input: JSONValue? }
private struct BedrockGenerateResponse: Codable, Sendable {
    struct Output: Codable, Sendable {
        struct Message: Codable, Sendable {
            struct Content: Codable, Sendable {
                struct Reasoning: Codable, Sendable {
                    struct Text: Codable, Sendable { let text: String; let signature: String? }
                    struct Redacted: Codable, Sendable { let data: String }
                    let reasoningText: Text?
                    let redactedReasoning: Redacted?
                    let redactedContent: String?
                    private enum CodingKeys: String, CodingKey { case reasoningText, redactedReasoning, redactedContent }
                    init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        reasoningText = try container.decodeIfPresent(Text.self, forKey: .reasoningText)
                        redactedReasoning = try container.decodeIfPresent(Redacted.self, forKey: .redactedReasoning)
                        redactedContent = try container.decodeIfPresent(String.self, forKey: .redactedContent)
                        guard reasoningText != nil || redactedReasoning != nil || redactedContent != nil else {
                            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid Bedrock reasoning content."))
                        }
                    }
                }
                struct Citations: Codable, Sendable {
                    struct Text: Codable, Sendable { let text: String? }
                    let content: [Text]?
                }
                let text: String?
                let toolUse: BedrockToolUse?
                let reasoningContent: Reasoning?
                let citationsContent: Citations?
            }
            let role: String
            let content: [Content]
        }
        let message: Message
    }
    struct Metrics: Codable, Sendable { let latencyMs: Double }
    let output: Output
    let stopReason: String
    let usage: BedrockUsage
    let metrics: Metrics?
    let additionalModelResponseFields: BedrockAdditionalResponseFields?
    let trace: JSONValue?
    let performanceConfig: BedrockPerformanceConfig?
    let serviceTier: BedrockServiceTierMetadata?
    private enum CodingKeys: String, CodingKey { case output, stopReason, usage, metrics, additionalModelResponseFields, trace, performanceConfig, serviceTier }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        output = try container.decode(Output.self, forKey: .output)
        stopReason = try container.decode(String.self, forKey: .stopReason)
        usage = try container.decode(BedrockUsage.self, forKey: .usage)
        guard case .object(let rawUsage) = usage.raw, case .number? = rawUsage["totalTokens"] else {
            throw DecodingError.dataCorruptedError(forKey: .usage, in: container, debugDescription: "Bedrock generation usage requires totalTokens.")
        }
        metrics = try container.decodeIfPresent(Metrics.self, forKey: .metrics)
        additionalModelResponseFields = try container.decodeIfPresent(BedrockAdditionalResponseFields.self, forKey: .additionalModelResponseFields)
        trace = try container.decodeIfPresent(JSONValue.self, forKey: .trace)
        performanceConfig = try container.decodeIfPresent(BedrockPerformanceConfig.self, forKey: .performanceConfig)
        serviceTier = try container.decodeIfPresent(BedrockServiceTierMetadata.self, forKey: .serviceTier)
    }
}
private struct BedrockStreamEnvelope: Codable, Sendable {
    struct Delta: Codable, Sendable {
        struct Content: Codable, Sendable {
            struct Tool: Codable, Sendable { let input: String }
            struct Reasoning: Codable, Sendable {
                let text: String?
                let signature: String?
                let data: String?
                let redactedContent: String?
                private enum CodingKeys: String, CodingKey { case text, signature, data, redactedContent }
                init(from decoder: Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    text = try container.decodeIfPresent(String.self, forKey: .text)
                    signature = try container.decodeIfPresent(String.self, forKey: .signature)
                    data = try container.decodeIfPresent(String.self, forKey: .data)
                    redactedContent = try container.decodeIfPresent(String.self, forKey: .redactedContent)
                    guard text != nil || signature != nil || data != nil || redactedContent != nil else {
                        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid Bedrock reasoning delta."))
                    }
                }
            }
            let text: String?
            let toolUse: Tool?
            let reasoningContent: Reasoning?
            let citation: [String: JSONValue]?
            private enum CodingKeys: String, CodingKey { case text, toolUse, reasoningContent, citation }
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                text = try container.decodeIfPresent(String.self, forKey: .text)
                toolUse = try container.decodeIfPresent(Tool.self, forKey: .toolUse)
                reasoningContent = try container.decodeIfPresent(Reasoning.self, forKey: .reasoningContent)
                citation = try container.decodeIfPresent([String: JSONValue].self, forKey: .citation)
                guard text != nil || toolUse != nil || reasoningContent != nil || citation != nil else {
                    throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid Bedrock content delta."))
                }
            }
        }
        let contentBlockIndex: Int
        let delta: Content?
    }
    struct Start: Codable, Sendable {
        struct Content: Codable, Sendable { let toolUse: BedrockToolUse? }
        let contentBlockIndex: Int
        let start: Content?
    }
    struct Stop: Codable, Sendable { let contentBlockIndex: Int }
    struct MessageStop: Codable, Sendable { let stopReason: String; let additionalModelResponseFields: BedrockAdditionalResponseFields? }
    struct Metadata: Codable, Sendable { let usage: BedrockUsage?; let trace: JSONValue?; let performanceConfig: BedrockPerformanceConfig?; let serviceTier: BedrockServiceTierMetadata? }
    let contentBlockDelta: Delta?
    let contentBlockStart: Start?
    let contentBlockStop: Stop?
    let messageStop: MessageStop?
    let metadata: Metadata?
    let internalServerException: [String: JSONValue]?
    let modelStreamErrorException: [String: JSONValue]?
    let serviceUnavailableException: [String: JSONValue]?
    let throttlingException: [String: JSONValue]?
    let validationException: [String: JSONValue]?
    var firstError: (String, [String: JSONValue])? {
        for (type, payload) in [("internalServerException", internalServerException), ("modelStreamErrorException", modelStreamErrorException), ("serviceUnavailableException", serviceUnavailableException), ("throttlingException", throttlingException), ("validationException", validationException)] {
            if let payload { return (type, payload) }
        }
        return nil
    }
}
private let bedrockGenerateResponseSchema = bedrockOptionsSchema(BedrockGenerateResponse.self)
private let bedrockStreamSchema = bedrockOptionsSchema(BedrockStreamEnvelope.self)
private extension ParseJSONResult where Output == BedrockStreamEnvelope {
    var rawJSONValue: JSONValue? {
        switch self {
        case .success(_, let raw): return try? jsonValue(from: raw)
        case .failure(_, let raw): return raw.flatMap { try? jsonValue(from: $0) }
        }
    }
}
private extension JSONValue {
    var objectValue: [String: JSONValue]? { if case .object(let value) = self { return value }; return nil }
    var arrayValue: [JSONValue]? { if case .array(let value) = self { return value }; return nil }
}
