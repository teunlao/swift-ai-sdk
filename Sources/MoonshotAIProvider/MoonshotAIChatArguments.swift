import Foundation
import AISDKProvider
import AISDKProviderUtils

func prepareMoonshotRequest(modelId: String, providerName: String, structuredOutputs: Bool, options: LanguageModelV4CallOptions) async throws -> (body: [String: JSONValue], warnings: [SharedV4Warning]) {
    let moonshot = try await parseProviderOptions(provider: providerName, providerOptions: options.providerOptions, schema: moonshotLanguageOptionsSchema) ?? .init()
    var warnings: [SharedV4Warning] = []
    if options.topK != nil { warnings.append(.unsupported(feature: "topK", details: nil)) }
    if options.seed != nil { warnings.append(.unsupported(feature: "seed", details: nil)) }
    let family = moonshotModelFamily(modelId)
    let sampling = family == .unknown || family == .v1
    if !sampling {
        for (feature, value) in [("temperature", options.temperature), ("topP", options.topP), ("frequencyPenalty", options.frequencyPenalty), ("presencePenalty", options.presencePenalty)] where value != nil {
            warnings.append(.unsupported(feature: feature, details: "\(feature) is fixed by model \"\(modelId)\" and has been omitted."))
        }
    }
    let tools = try prepareMoonshotTools(tools: options.tools, choice: options.toolChoice, modelId: modelId)
    let requested = moonshot.thinking
    let preserve = moonshot.reasoningHistory == .preserved
    let custom = options.reasoning != nil && options.reasoning != .providerDefault
    let noReasoning = options.reasoning == LanguageModelV4ReasoningEffort.none
    if requested?.budgetTokens != nil {
        warnings.append(.deprecated(setting: "providerOptions.moonshotai.thinking.budgetTokens", message: "Moonshot Chat Completions does not support budget_tokens. Remove budgetTokens; the option has been omitted."))
    }
    var thinking: [String: JSONValue]?
    var effort: String?
    if family != .k3 && family != .unknown && moonshot.reasoningEffort != nil {
        warnings.append(.unsupported(feature: "reasoningEffort", details: "reasoningEffort is only supported by Kimi K3 and has been omitted for model \"\(modelId)\"."))
    }
    switch family {
    case .k3:
        if requested != nil { warnings.append(.unsupported(feature: "thinking", details: "Kimi K3 always reasons and does not accept the thinking field. The option has been omitted.")) }
        if noReasoning { warnings.append(.unsupported(feature: "reasoning \"none\"", details: "Kimi K3 reasoning cannot be disabled.")) }
    case .k27:
        if requested?.type == .disabled || noReasoning {
            warnings.append(.unsupported(feature: requested?.type == .disabled ? "thinking.type \"disabled\"" : "reasoning \"none\"", details: "Kimi K2.7 thinking cannot be disabled."))
        } else if requested?.type == .enabled { thinking = ["type": .string("enabled")] }
    case .k26, .k25:
        let mode = requested?.type?.rawValue ?? (custom ? (noReasoning ? "disabled" : "enabled") : nil)
        if mode != nil || (family == .k26 && preserve) {
            thinking = ["type": .string(mode ?? "enabled")]
            if family == .k26 && preserve { thinking?["keep"] = .string("all") }
        }
    case .v1:
        if requested != nil { warnings.append(.unsupported(feature: "thinking", details: "thinking is not supported by model \"\(modelId)\" and has been omitted.")) }
        if custom && !noReasoning { warnings.append(.unsupported(feature: "reasoning", details: "reasoning is not supported by model \"\(modelId)\".")) }
    case .unknown:
        if noReasoning { warnings.append(.unsupported(feature: "reasoning \"none\"", details: "Use providerOptions.moonshotai.thinking to control thinking on custom models.")) }
        if let mode = requested?.type { thinking = ["type": .string(mode.rawValue)] }
    }
    if preserve && (family == .k25 || family == .v1 || family == .unknown) { warnings.append(.unsupported(feature: "reasoningHistory 'preserved' is not supported by model \"\(modelId)\"", details: nil)) }
    if family == .k3 || family == .unknown {
        effort = moonshot.reasoningEffort?.rawValue
        if effort == nil, let reasoning = options.reasoning, reasoning != .providerDefault && reasoning != .none {
            effort = mapReasoningToProviderEffort(reasoning: reasoning, effortMap: [.minimal: "low", .low: "low", .medium: "high", .high: "high", .xhigh: "max", .max: "max"], warnings: &warnings)
        }
    }
    var responseFormat: JSONValue?
    if case .json(let schema, let name, _) = options.responseFormat {
        if structuredOutputs, let schema {
            var definition = schema
            if case .object(var object) = definition { object["$schema"] = nil; definition = .object(object) }
            responseFormat = .object(["type": .string("json_schema"), "json_schema": .object(["name": .string(name ?? "response"), "strict": .bool(moonshot.strictJsonSchema ?? true), "schema": try normalizeJsonSchemaForMFJS(definition)])])
        } else { responseFormat = .object(["type": .string("json_object")]) }
    }
    let converted = try await convertToMoonshotAIChatMessages(prompt: options.prompt, modelId: modelId, providerOptionsName: providerName, responseFormat: responseFormat)
    warnings.append(contentsOf: converted.warnings)
    var body: [String: JSONValue] = ["model": .string(modelId), "messages": .array(converted.messages)]
    if moonshot.logprobs == true || moonshot.topLogprobs != nil { body["logprobs"] = .bool(true) }
    if let value = moonshot.topLogprobs { body["top_logprobs"] = .number(Double(value)) }
    if let value = options.maxOutputTokens { body["max_completion_tokens"] = .number(Double(value)) }
    if sampling {
        if let value = options.temperature { body["temperature"] = .number(value) }
        if let value = options.topP { body["top_p"] = .number(value) }
        if let value = options.frequencyPenalty { body["frequency_penalty"] = .number(value) }
        if let value = options.presencePenalty { body["presence_penalty"] = .number(value) }
    }
    if let responseFormat { body["response_format"] = responseFormat }
    if let value = options.stopSequences { body["stop"] = .array(value.map(JSONValue.string)) }
    if let value = tools.tools { body["tools"] = .array(value) }
    if let value = tools.choice { body["tool_choice"] = value }
    if let value = moonshot.prediction { body["prediction"] = try moonshotJSONValue(value) }
    if let thinking { body["thinking"] = .object(thinking) }
    if let effort { body["reasoning_effort"] = .string(effort) }
    if let value = moonshot.promptCacheKey { body["prompt_cache_key"] = .string(value) }
    if let value = moonshot.safetyIdentifier { body["safety_identifier"] = .string(value) }
    return (body, warnings + tools.warnings)
}
