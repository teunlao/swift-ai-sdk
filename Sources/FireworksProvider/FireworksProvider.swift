import Foundation
import AISDKProvider
import AISDKProviderUtils
import OpenAICompatibleProvider

public struct FireworksProviderSettings: Sendable {
    public var apiKey: String?
    public var baseURL: String?
    public var headers: [String: String]?
    public var fetch: FetchFunction?
    public init(apiKey: String? = nil, baseURL: String? = nil, headers: [String: String]? = nil, fetch: FetchFunction? = nil) { self.apiKey = apiKey; self.baseURL = baseURL; self.headers = headers; self.fetch = fetch }
}

public final class FireworksProvider: ProviderV4 {
    private let settings: FireworksProviderSettings
    private let baseURL: String
    private let headers: @Sendable () throws -> [String: String]
    init(settings: FireworksProviderSettings) {
        self.settings = settings
        self.baseURL = withoutTrailingSlash(settings.baseURL) ?? "https://api.fireworks.ai/inference/v1"
        self.headers = {
            let key = try loadAPIKey(apiKey: settings.apiKey, environmentVariableName: "FIREWORKS_API_KEY", description: "Fireworks API key")
            return withUserAgentSuffix(combineHeaders(["Authorization": "Bearer \(key)"], settings.headers?.mapValues(Optional.some)), "ai-sdk-fireworks/\(FIREWORKS_VERSION)")
        }
    }
    public func languageModel(modelId: String) -> any LanguageModelV4 { chat(modelId: .init(rawValue: modelId)) }
    public func chatModel(modelId: String) -> OpenAICompatibleChatLanguageModel { chat(modelId: .init(rawValue: modelId)) }
    public func completionModel(modelId: String) -> OpenAICompatibleCompletionLanguageModel { completion(modelId: .init(rawValue: modelId)) }
    public func embeddingModel(modelId: String) -> any EmbeddingModelV4 { embedding(modelId: .init(rawValue: modelId)) }
    public func imageModel(modelId: String) -> any ImageModelV4 { image(modelId: .init(rawValue: modelId)) }
    public func callAsFunction(_ modelId: String) -> OpenAICompatibleChatLanguageModel { chatModel(modelId: modelId) }

    public func chat(modelId: FireworksChatModelId) -> OpenAICompatibleChatLanguageModel {
        let baseURL = baseURL
        return OpenAICompatibleChatLanguageModel(modelId: .init(rawValue: modelId.rawValue), config: .init(provider: "fireworks.chat", headers: headers, url: { "\(baseURL)\($0.path)" }, fetch: settings.fetch, includeUsage: true, errorConfiguration: fireworksErrorConfiguration, supportsStructuredOutputs: true, transformRequestBody: transformFireworksRequest))
    }
    public func completion(modelId: FireworksCompletionModelId) -> OpenAICompatibleCompletionLanguageModel {
        let baseURL = baseURL
        return OpenAICompatibleCompletionLanguageModel(modelId: .init(rawValue: modelId.rawValue), config: .init(provider: "fireworks.completion", headers: headers, url: { "\(baseURL)\($0.path)" }, fetch: settings.fetch, includeUsage: true, errorConfiguration: fireworksErrorConfiguration))
    }
    public func embedding(modelId: FireworksEmbeddingModelId) -> OpenAICompatibleEmbeddingModel {
        let baseURL = baseURL
        return OpenAICompatibleEmbeddingModel(modelId: .init(rawValue: modelId.rawValue), config: .init(provider: "fireworks.embedding", url: { "\(baseURL)\($0.path)" }, headers: headers, fetch: settings.fetch, errorConfiguration: fireworksErrorConfiguration))
    }
    public func image(modelId: FireworksImageModelId) -> FireworksImageModel {
        FireworksImageModel(modelId: modelId, config: .init(provider: "fireworks.image", baseURL: baseURL, headers: headers, fetch: settings.fetch))
    }
}

private func transformFireworksRequest(_ args: [String: JSONValue], _ warnings: inout [SharedV4Warning]) -> [String: JSONValue] {
    var body = args
    let thinking = body.removeValue(forKey: "thinking")
    let history = body.removeValue(forKey: "reasoningHistory")
    let cache = body.removeValue(forKey: "promptCacheKey")
    let tier = body.removeValue(forKey: "serviceTier")
    let reasoning = body.removeValue(forKey: "reasoning_effort")
    let effort: JSONValue?
    switch reasoning { case .string("minimal"): effort = .string("low"); case .string("xhigh"), .string("max"): effort = .string("high"); default: effort = reasoning }
    if effort != reasoning, case .string(let original) = reasoning, case .string(let mapped) = effort {
        warnings.append(.compatibility(feature: "reasoning", details: "reasoning \"\(original)\" is not directly supported by this model. mapped to effort \"\(mapped)\"."))
    }
    if let reasoning, reasoning != .null { body["reasoning_effort"] = effort }
    if let cache { body["prompt_cache_key"] = cache }
    if let tier { body["service_tier"] = tier }
    if let thinking, fireworksTruthy(thinking) {
        var fields: [String: JSONValue] = [:]
        if case .object(let object) = thinking {
            fields["type"] = object["type"]
            if let value = object["budgetTokens"] { fields["budget_tokens"] = value }
        }
        body["thinking"] = .object(fields)
    }
    if let history, fireworksTruthy(history) { body["reasoning_history"] = history }
    return body
}
private func fireworksTruthy(_ value: JSONValue) -> Bool {
    switch value { case .null: false; case .bool(let value): value; case .number(let value): value != 0; case .string(let value): !value.isEmpty; case .object, .array: true }
}

public func createFireworks(settings: FireworksProviderSettings = .init()) -> FireworksProvider { FireworksProvider(settings: settings) }
public let fireworks = createFireworks()
