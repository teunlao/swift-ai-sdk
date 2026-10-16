/**
 Applies default settings for a language model.

 Port of `@ai-sdk/ai/src/middleware/default-settings-middleware.ts`.

 Upstream deep-merges the settings object with the call parameters
 (`mergeObjects(settings, params)`): a parameter the call sets wins, nested
 objects (`providerOptions`, `headers`, a JSON `responseFormat`) merge key by
 key, arrays and scalars are replaced. Swift merges the typed fields the same way.
 */

import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Creates a middleware that applies default settings to language model calls.
public func defaultSettingsMiddleware(
    settings: DefaultSettings
) -> LanguageModelV4Middleware {
    LanguageModelV4Middleware(
        transformParams: { _, params, _ in
            LanguageModelV4CallOptions(
                prompt: params.prompt,
                maxOutputTokens: params.maxOutputTokens ?? settings.maxOutputTokens,
                temperature: params.temperature ?? settings.temperature,
                stopSequences: params.stopSequences ?? settings.stopSequences,
                topP: params.topP ?? settings.topP,
                topK: params.topK ?? settings.topK,
                presencePenalty: params.presencePenalty ?? settings.presencePenalty,
                frequencyPenalty: params.frequencyPenalty ?? settings.frequencyPenalty,
                responseFormat: mergeResponseFormat(settings.responseFormat, params.responseFormat),
                seed: params.seed ?? settings.seed,
                tools: params.tools ?? settings.tools,
                toolChoice: params.toolChoice ?? settings.toolChoice,
                includeRawChunks: params.includeRawChunks,
                abortSignal: params.abortSignal,
                headers: mergeSettingHeaders(settings.headers, params.headers),
                reasoning: params.reasoning,
                providerOptions: mergeProviderOptions(settings.providerOptions, params.providerOptions)
            )
        }
    )
}

/// Creates a V3 middleware that applies default settings to language model calls.
public func defaultSettingsMiddleware(
    settings: DefaultSettings
) -> LanguageModelV3Middleware {
    LanguageModelV3Middleware(
        transformParams: { _, params, _ in
            LanguageModelV3CallOptions(
                prompt: params.prompt,
                maxOutputTokens: params.maxOutputTokens ?? settings.maxOutputTokens,
                temperature: params.temperature ?? settings.temperature,
                stopSequences: params.stopSequences ?? settings.stopSequences,
                topP: params.topP ?? settings.topP,
                topK: params.topK ?? settings.topK,
                presencePenalty: params.presencePenalty ?? settings.presencePenalty,
                frequencyPenalty: params.frequencyPenalty ?? settings.frequencyPenalty,
                responseFormat: mergeResponseFormat(settings.responseFormat, params.responseFormat?.asV4)?.asV3,
                seed: params.seed ?? settings.seed,
                tools: params.tools ?? settings.tools?.map(\.asV3),
                toolChoice: params.toolChoice ?? settings.toolChoice?.asV3,
                includeRawChunks: params.includeRawChunks,
                abortSignal: params.abortSignal,
                headers: mergeSettingHeaders(settings.headers, params.headers),
                providerOptions: mergeProviderOptions(settings.providerOptions, params.providerOptions)
            )
        }
    )
}

/// Default settings that can be applied to language model calls.
///
/// All fields are optional. When specified, they will be used as defaults
/// unless overridden by the user at call time.
public struct DefaultSettings: Sendable {
    public let maxOutputTokens: Int?
    public let temperature: Double?
    public let stopSequences: [String]?
    public let topP: Double?
    public let topK: Int?
    public let presencePenalty: Double?
    public let frequencyPenalty: Double?
    public let responseFormat: LanguageModelV4ResponseFormat?
    public let seed: Int?
    public let tools: [LanguageModelV4Tool]?
    public let toolChoice: LanguageModelV4ToolChoice?
    public let headers: SharedV4Headers?
    public let providerOptions: SharedV4ProviderOptions?

    public init(
        maxOutputTokens: Int? = nil,
        temperature: Double? = nil,
        stopSequences: [String]? = nil,
        topP: Double? = nil,
        topK: Int? = nil,
        presencePenalty: Double? = nil,
        frequencyPenalty: Double? = nil,
        responseFormat: LanguageModelV4ResponseFormat? = nil,
        seed: Int? = nil,
        tools: [LanguageModelV4Tool]? = nil,
        toolChoice: LanguageModelV4ToolChoice? = nil,
        headers: SharedV4Headers? = nil,
        providerOptions: SharedV4ProviderOptions? = nil
    ) {
        self.maxOutputTokens = maxOutputTokens
        self.temperature = temperature
        self.stopSequences = stopSequences
        self.topP = topP
        self.topK = topK
        self.presencePenalty = presencePenalty
        self.frequencyPenalty = frequencyPenalty
        self.responseFormat = responseFormat
        self.seed = seed
        self.tools = tools
        self.toolChoice = toolChoice
        self.headers = headers
        self.providerOptions = providerOptions
    }
}

// MARK: - Merging (upstream `mergeObjects` over the typed settings)
// Provider options use the shared `mergeProviderOptions` deep merge.

func mergeSettingHeaders(_ base: SharedV4Headers?, _ overrides: SharedV4Headers?) -> SharedV4Headers? {
    guard let base else { return overrides }
    guard let overrides else { return base }
    return base.merging(overrides) { _, override in override }
}

private func mergeJSONObjects(
    _ base: [String: JSONValue],
    _ overrides: [String: JSONValue]
) -> [String: JSONValue] {
    base.merging(overrides) { baseValue, overrideValue in
        mergeJSONValues(baseValue, overrideValue)
    }
}

private func mergeJSONValues(_ base: JSONValue, _ override: JSONValue) -> JSONValue {
    if case .object(let baseObject) = base, case .object(let overrideObject) = override {
        return .object(mergeJSONObjects(baseObject, overrideObject))
    }
    return override
}

private func mergeResponseFormat(
    _ base: LanguageModelV4ResponseFormat?,
    _ override: LanguageModelV4ResponseFormat?
) -> LanguageModelV4ResponseFormat? {
    guard case let .json(baseSchema, baseName, baseDescription)? = base,
          case let .json(schema, name, description)? = override
    else {
        return override ?? base
    }
    let mergedSchema: JSONValue?
    switch (baseSchema, schema) {
    case let (baseSchema?, schema?):
        mergedSchema = mergeJSONValues(baseSchema, schema)
    default:
        mergedSchema = schema ?? baseSchema
    }
    return .json(schema: mergedSchema, name: name ?? baseName, description: description ?? baseDescription)
}

// MARK: - V3 conversions

private extension LanguageModelV3ResponseFormat {
    var asV4: LanguageModelV4ResponseFormat {
        switch self {
        case .text:
            return .text
        case let .json(schema, name, description):
            return .json(schema: schema, name: name, description: description)
        }
    }
}

private extension LanguageModelV4ResponseFormat {
    var asV3: LanguageModelV3ResponseFormat {
        switch self {
        case .text:
            return .text
        case let .json(schema, name, description):
            return .json(schema: schema, name: name, description: description)
        }
    }
}

private extension LanguageModelV4Tool {
    var asV3: LanguageModelV3Tool {
        switch self {
        case .function(let tool):
            return .function(LanguageModelV3FunctionTool(
                name: tool.name,
                inputSchema: tool.inputSchema,
                inputExamples: tool.inputExamples?.map { LanguageModelV3ToolInputExample(input: $0.input) },
                description: tool.description,
                strict: tool.strict,
                providerOptions: tool.providerOptions
            ))
        case .provider(let tool):
            return .provider(LanguageModelV3ProviderTool(id: tool.id, name: tool.name, args: tool.args))
        }
    }
}

private extension LanguageModelV4ToolChoice {
    var asV3: LanguageModelV3ToolChoice {
        switch self {
        case .auto:
            return .auto
        case .none:
            return .none
        case .required:
            return .required
        case .tool(let toolName):
            return .tool(toolName: toolName)
        }
    }
}
