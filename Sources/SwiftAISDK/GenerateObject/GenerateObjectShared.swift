import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Shared helpers for `generateObject` и `streamObject`.

 Port of `@ai-sdk/ai/src/generate-object` shared utilities.
 */
func makeGenerateObjectPrompt(
    system: String?,
    prompt: String?,
    messages: [ModelMessage]?
) throws -> Prompt {
    if prompt != nil, messages != nil {
        throw InvalidPromptError(
            prompt: "Prompt(system: \(system ?? "nil"), prompt: \(prompt ?? "nil"), messages: provided)",
            message: "Provide either `prompt` or `messages`, not both."
        )
    }

    if let prompt {
        return Prompt.text(prompt, system: system)
    }

    if let messages {
        return Prompt.messages(messages, system: system)
    }

    throw InvalidPromptError(
        prompt: "Prompt(system: \(system ?? "nil"))",
        message: "Either `prompt` or `messages` must be provided."
    )
}

func convertGenerateObjectRequestMetadata(
    _ info: LanguageModelV3RequestInfo?
) -> LanguageModelRequestMetadata {
    guard let body = info?.body else {
        return LanguageModelRequestMetadata()
    }

    if let json = try? jsonValue(from: body) {
        return LanguageModelRequestMetadata(body: json)
    }

    return LanguageModelRequestMetadata()
}

func convertGenerateObjectResponseBody(_ body: Any?) -> JSONValue? {
    guard let body else { return nil }

    if let json = body as? JSONValue {
        return json
    }

    return try? jsonValue(from: body)
}

func encodeGenerateObjectTelemetryValue<ResultValue>(_ value: ResultValue) -> String? {
    if let jsonValue = value as? JSONValue {
        return encodeJSONValueForTelemetry(jsonValue)
    }

    if let converted = try? jsonValue(from: value) {
        return encodeJSONValueForTelemetry(converted)
    }

    return nil
}
