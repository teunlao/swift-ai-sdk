import AISDKProvider
import AISDKProviderUtils

public struct PerplexityProviderSettings: Sendable {
    public var baseURL: String?
    public var apiKey: String?
    public var headers: [String: String]?
    public var fetch: FetchFunction?

    public init(baseURL: String? = nil, apiKey: String? = nil, headers: [String: String]? = nil, fetch: FetchFunction? = nil) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.headers = headers
        self.fetch = fetch
    }
}

public final class PerplexityProvider: ProviderV4 {
    private let settings: PerplexityProviderSettings
    private let baseURL: String
    private let headers: @Sendable () throws -> [String: String?]

    init(settings: PerplexityProviderSettings) {
        self.settings = settings
        baseURL = withoutTrailingSlash(settings.baseURL ?? "https://api.perplexity.ai")!
        headers = {
            let headers = combineHeaders(
                ["Authorization": "Bearer \(try loadAPIKey(apiKey: settings.apiKey, environmentVariableName: "PERPLEXITY_API_KEY", description: "Perplexity"))", "X-Pplx-Integration": "vercel-ai-sdk"],
                settings.headers?.mapValues(Optional.some)
            )
            return withUserAgentSuffix(headers, "ai-sdk-perplexity/\(PERPLEXITY_VERSION)").mapValues(Optional.some)
        }
    }

    public func languageModel(modelId: String) -> any LanguageModelV4 { languageModel(.init(rawValue: modelId)) }
    public func languageModel(_ modelId: PerplexityLanguageModelId) -> PerplexityLanguageModel {
        .init(modelId: modelId, config: .init(baseURL: baseURL, headers: headers, fetch: settings.fetch, generateId: generateID))
    }
    public func callAsFunction(_ modelId: PerplexityLanguageModelId) -> PerplexityLanguageModel { languageModel(modelId) }
    public func embeddingModel(modelId: String) -> any EmbeddingModelV4 { embedding(.init(rawValue: modelId)) }
    public func embedding(_ modelId: PerplexityEmbeddingModelId) -> PerplexityEmbeddingModel {
        .init(modelId: modelId, config: .init(provider: "perplexity.embedding", baseURL: baseURL, headers: headers, fetch: settings.fetch))
    }
    public func imageModel(modelId: String) throws -> any ImageModelV4 {
        throw NoSuchModelError(modelId: modelId, modelType: .imageModel)
    }
}

public func createPerplexity(settings: PerplexityProviderSettings = .init()) -> PerplexityProvider { .init(settings: settings) }
public let perplexity = createPerplexity()
