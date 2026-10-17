import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct CohereProviderSettings: Sendable {
    public var baseURL: String?
    public var apiKey: String?
    public var headers: [String: String]?
    public var fetch: FetchFunction?
    public var generateId: IDGenerator?

    public init(baseURL: String? = nil, apiKey: String? = nil, headers: [String: String]? = nil,
                fetch: FetchFunction? = nil, generateId: IDGenerator? = nil) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.headers = headers
        self.fetch = fetch
        self.generateId = generateId
    }
}

public final class CohereProvider: ProviderV4 {
    private let settings: CohereProviderSettings
    private let baseURL: String
    private let headers: @Sendable () throws -> [String: String?]

    init(settings: CohereProviderSettings) {
        self.settings = settings
        baseURL = withoutTrailingSlash(settings.baseURL) ?? "https://api.cohere.com/v2"
        headers = {
            let headers = combineHeaders(
                ["Authorization": "Bearer \(try loadAPIKey(apiKey: settings.apiKey, environmentVariableName: "COHERE_API_KEY", description: "Cohere"))"],
                settings.headers?.mapValues(Optional.some)
            )
            return withUserAgentSuffix(headers, "ai-sdk-cohere/\(COHERE_VERSION)").mapValues(Optional.some)
        }
    }

    public func languageModel(modelId: String) -> any LanguageModelV4 { languageModel(.init(rawValue: modelId)) }
    public func languageModel(_ modelId: CohereChatModelId) -> CohereChatLanguageModel {
        .init(modelId: modelId, config: .init(provider: "cohere.chat", baseURL: baseURL, headers: headers,
                                            fetch: settings.fetch, generateId: settings.generateId ?? generateID))
    }
    public func callAsFunction(_ modelId: CohereChatModelId) -> CohereChatLanguageModel { languageModel(modelId) }
    public func embeddingModel(modelId: String) -> any EmbeddingModelV4 { embedding(modelId: .init(rawValue: modelId)) }
    public func embedding(modelId: CohereEmbeddingModelId) -> CohereEmbeddingModel {
        .init(modelId: modelId, config: .init(provider: "cohere.textEmbedding", baseURL: baseURL, headers: headers, fetch: settings.fetch))
    }
    public func rerankingModel(modelId: String) -> (any RerankingModelV4)? { reranking(modelId: .init(rawValue: modelId)) }
    public func reranking(modelId: CohereRerankingModelId) -> CohereRerankingModel {
        .init(modelId: modelId, config: .init(provider: "cohere.reranking", baseURL: baseURL, headers: headers, fetch: settings.fetch))
    }
    public func imageModel(modelId: String) throws -> any ImageModelV4 {
        throw NoSuchModelError(modelId: modelId, modelType: .imageModel)
    }
}

public func createCohere(settings: CohereProviderSettings = .init()) -> CohereProvider { .init(settings: settings) }
public let cohere = createCohere()
