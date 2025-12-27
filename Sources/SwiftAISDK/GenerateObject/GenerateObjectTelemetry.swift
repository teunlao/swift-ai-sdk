import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Telemetry helpers for `generateObject` and `streamObject`.

 Port of `@ai-sdk/ai/src/generate-object` telemetry wiring.
 */
func makeGenerateObjectOuterTelemetryAttributes(
    telemetry: TelemetrySettings?,
    baseAttributes: Attributes,
    system: String?,
    prompt: String?,
    messages: [ModelMessage]?,
    schema: JSONValue?,
    schemaName: String?,
    schemaDescription: String?,
    outputKind: GenerateObjectOutputKind
) -> [String: ResolvableAttributeValue?] {
    var attributes: [String: ResolvableAttributeValue?] = [:]

    for (key, value) in assembleOperationName(operationId: "ai.generateObject", telemetry: telemetry) {
        attributes[key] = .value(value)
    }

    for (key, value) in baseAttributes {
        attributes[key] = .value(value)
    }

    attributes["ai.prompt"] = .input {
        guard let summary = summarizeGenerateObjectPrompt(system: system, prompt: prompt, messages: messages) else {
            return nil
        }
        return .string(summary)
    }

    if let schema {
        attributes["ai.schema"] = .input {
            guard let encoded = encodeJSONValueForTelemetry(schema) else { return nil }
            return .string(encoded)
        }
    }

    if let schemaName {
        attributes["ai.schema.name"] = .value(.string(schemaName))
    }

    if let schemaDescription {
        attributes["ai.schema.description"] = .value(.string(schemaDescription))
    }

    attributes["ai.settings.output"] = .value(.string(outputKind.rawValue))

    return attributes
}

func makeGenerateObjectInnerTelemetryAttributes(
    telemetry: TelemetrySettings?,
    baseAttributes: Attributes,
    promptMessages: [LanguageModelV3Message],
    callSettings: PreparedCallSettings,
    model: any LanguageModelV3
) -> [String: ResolvableAttributeValue?] {
    var attributes: [String: ResolvableAttributeValue?] = [:]

    for (key, value) in assembleOperationName(operationId: "ai.generateObject.doGenerate", telemetry: telemetry) {
        attributes[key] = .value(value)
    }

    for (key, value) in baseAttributes {
        attributes[key] = .value(value)
    }

    attributes["ai.prompt.messages"] = .input {
        guard let serialized = try? stringifyForTelemetry(promptMessages) else { return nil }
        return .string(serialized)
    }

    attributes["gen_ai.system"] = .value(.string(model.provider))
    attributes["gen_ai.request.model"] = .value(.string(model.modelId))

    if let frequencyPenalty = callSettings.frequencyPenalty {
        attributes["gen_ai.request.frequency_penalty"] = .value(.double(frequencyPenalty))
    }
    if let maxTokens = callSettings.maxOutputTokens {
        attributes["gen_ai.request.max_tokens"] = .value(.int(maxTokens))
    }
    if let presencePenalty = callSettings.presencePenalty {
        attributes["gen_ai.request.presence_penalty"] = .value(.double(presencePenalty))
    }
    if let temperature = callSettings.temperature {
        attributes["gen_ai.request.temperature"] = .value(.double(temperature))
    }
    if let topK = callSettings.topK {
        attributes["gen_ai.request.top_k"] = .value(.int(topK))
    }
    if let topP = callSettings.topP {
        attributes["gen_ai.request.top_p"] = .value(.double(topP))
    }

    return attributes
}

func makeGenerateObjectResponseTelemetryAttributes(
    telemetry: TelemetrySettings?,
    finishReason: FinishReason,
    objectOutput: @escaping @Sendable () -> String?,
    responseId: String,
    responseModelId: String,
    responseTimestamp: Date,
    providerMetadata: ProviderMetadata?,
    usage: LanguageModelUsage
) -> [String: ResolvableAttributeValue?] {
    var attributes: [String: ResolvableAttributeValue?] = [:]

    attributes["ai.response.finishReason"] = .value(.string(finishReason.rawValue))
    attributes["ai.response.object"] = .output {
        guard let encoded = objectOutput() else { return nil }
        return .string(encoded)
    }
    attributes["ai.response.id"] = .value(.string(responseId))
    attributes["ai.response.model"] = .value(.string(responseModelId))
    attributes["ai.response.timestamp"] = .value(.string(responseTimestamp.iso8601WithFractionalSeconds))

    if let providerMetadataString = encodeProviderMetadata(providerMetadata) {
        attributes["ai.response.providerMetadata"] = .value(.string(providerMetadataString))
    }

    if let inputTokens = usage.inputTokens {
        attributes["ai.usage.promptTokens"] = .value(.int(inputTokens))
        attributes["gen_ai.usage.input_tokens"] = .value(.int(inputTokens))
    }

    if let outputTokens = usage.outputTokens {
        attributes["ai.usage.completionTokens"] = .value(.int(outputTokens))
        attributes["gen_ai.usage.output_tokens"] = .value(.int(outputTokens))
    }

    if let totalTokens = usage.totalTokens {
        attributes["gen_ai.usage.total_tokens"] = .value(.int(totalTokens))
    }

    if let reasoningTokens = usage.reasoningTokens {
        attributes["gen_ai.usage.reasoning_tokens"] = .value(.int(reasoningTokens))
    }

    if let cachedTokens = usage.cachedInputTokens {
        attributes["gen_ai.usage.cached_input_tokens"] = .value(.int(cachedTokens))
    }

    attributes["gen_ai.response.finish_reasons"] = .value(.stringArray([finishReason.rawValue]))
    attributes["gen_ai.response.id"] = .value(.string(responseId))
    attributes["gen_ai.response.model"] = .value(.string(responseModelId))

    return attributes
}

func makeGenerateObjectRootFinishTelemetryAttributes(
    telemetry: TelemetrySettings?,
    baseAttributes: Attributes,
    usage: LanguageModelUsage,
    providerMetadata: ProviderMetadata?,
    finishReason: FinishReason,
    objectOutput: @escaping @Sendable () -> String?
) -> [String: ResolvableAttributeValue?] {
    var attributes: [String: ResolvableAttributeValue?] = [:]

    for (key, value) in baseAttributes {
        attributes[key] = .value(value)
    }

    attributes["ai.response.finishReason"] = .value(.string(finishReason.rawValue))
    attributes["ai.response.object"] = .output {
        guard let value = objectOutput() else { return nil }
        return .string(value)
    }

    if let providerMetadataString = encodeProviderMetadata(providerMetadata) {
        attributes["ai.response.providerMetadata"] = .value(.string(providerMetadataString))
    }

    if let inputTokens = usage.inputTokens {
        attributes["ai.usage.promptTokens"] = .value(.int(inputTokens))
    }

    if let outputTokens = usage.outputTokens {
        attributes["ai.usage.completionTokens"] = .value(.int(outputTokens))
    }

    if let totalTokens = usage.totalTokens {
        attributes["ai.usage.totalTokens"] = .value(.int(totalTokens))
    }

    if let reasoningTokens = usage.reasoningTokens {
        attributes["ai.usage.reasoningTokens"] = .value(.int(reasoningTokens))
    }

    if let cachedTokens = usage.cachedInputTokens {
        attributes["ai.usage.cachedInputTokens"] = .value(.int(cachedTokens))
    }

    return attributes
}

func makeStreamFirstChunkAttributes(msToFirstChunk: Double) -> Attributes {
    ["ai.stream.msToFirstChunk": .double(msToFirstChunk)]
}

// MARK: - Helpers

private func summarizeGenerateObjectPrompt(
    system: String?,
    prompt: String?,
    messages: [ModelMessage]?
) -> String? {
    var payload: [String: JSONValue] = [:]

    if let system {
        payload["system"] = .string(system)
    }

    if let prompt {
        payload["prompt"] = .string(prompt)
    }

    if let messages,
       let encodedMessages = try? jsonValue(from: messages) {
        payload["messages"] = encodedMessages
    }

    guard !payload.isEmpty else { return nil }
    return encodeJSONValueForTelemetry(.object(payload))
}

func encodeJSONValueForTelemetry(_ value: JSONValue) -> String? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(value) else { return nil }
    return String(data: data, encoding: .utf8)
}

private func encodeProviderMetadata(_ metadata: ProviderMetadata?) -> String? {
    guard let metadata else { return nil }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    guard let data = try? encoder.encode(metadata) else { return nil }
    return String(data: data, encoding: .utf8)
}

private extension Date {
    var iso8601WithFractionalSeconds: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: self)
    }
}
