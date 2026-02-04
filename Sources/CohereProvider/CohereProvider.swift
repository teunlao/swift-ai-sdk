import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/cohere/src/cohere-provider.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct CohereProviderSettings: Sendable {
    public var baseURL: String?
    public var apiKey: String?
    public var headers: [String: String]?
    public var fetch: FetchFunction?
    public var generateId: IDGenerator?

    public init(
        baseURL: String? = nil,
        apiKey: String? = nil,
        headers: [String: String]? = nil,
        fetch: FetchFunction? = nil,
        generateId: IDGenerator? = nil
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.headers = headers
        self.fetch = fetch
        self.generateId = generateId
    }
}

public final class CohereProvider: ProviderV3 {
    private let chatFactory: @Sendable (CohereChatModelId) -> CohereChatLanguageModel
    private let embeddingFactory: @Sendable (CohereEmbeddingModelId) -> CohereEmbeddingModel
    private let rerankingFactory: @Sendable (CohereRerankingModelId) -> CohereRerankingModel

    init(
        chatFactory: @escaping @Sendable (CohereChatModelId) -> CohereChatLanguageModel,
        embeddingFactory: @escaping @Sendable (CohereEmbeddingModelId) -> CohereEmbeddingModel,
        rerankingFactory: @escaping @Sendable (CohereRerankingModelId) -> CohereRerankingModel
    ) {
        self.chatFactory = chatFactory
        self.embeddingFactory = embeddingFactory
        self.rerankingFactory = rerankingFactory
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV3 {
        chatFactory(CohereChatModelId(rawValue: modelId))
    }

    public func chatModel(modelId: String) throws -> any LanguageModelV3 {
        try languageModel(modelId: modelId)
    }

    public func chat(modelId: CohereChatModelId) -> CohereChatLanguageModel {
        chatFactory(modelId)
    }

    public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
        embeddingFactory(CohereEmbeddingModelId(rawValue: modelId))
    }

    public func embedding(modelId: CohereEmbeddingModelId) -> CohereEmbeddingModel {
        embeddingFactory(modelId)
    }

    public func rerankingModel(modelId: String) throws -> (any RerankingModelV3)? {
        rerankingFactory(CohereRerankingModelId(rawValue: modelId))
    }

    public func reranking(modelId: CohereRerankingModelId) -> CohereRerankingModel {
        rerankingFactory(modelId)
    }

    public func imageModel(modelId: String) throws -> any ImageModelV3 {
        throw NoSuchModelError(modelId: modelId, modelType: .imageModel)
    }

    public func callAsFunction(_ modelId: String) throws -> any LanguageModelV3 {
        try languageModel(modelId: modelId)
    }
}

public func createCohereProvider(settings: CohereProviderSettings = .init()) -> CohereProvider {
    let baseURL = withoutTrailingSlash(settings.baseURL) ?? "https://api.cohere.com/v2"

    let headersClosure: @Sendable () -> [String: String?] = {
        var computed: [String: String?] = [:]
        let apiKey: String
        do {
            apiKey = try loadAPIKey(
                apiKey: settings.apiKey,
                environmentVariableName: "COHERE_API_KEY",
                description: "Cohere"
            )
        } catch {
            fatalError("Cohere API key is missing: \(error)")
        }

        computed["Authorization"] = "Bearer \(apiKey)"
        if let headers = settings.headers {
            for (key, value) in headers {
                computed[key] = value
            }
        }

        let withUA = withUserAgentSuffix(computed.compactMapValues { $0 }, "ai-sdk/cohere/\(COHERE_VERSION)")
        return withUA.mapValues { Optional($0) }
    }

    let chatFactory: @Sendable (CohereChatModelId) -> CohereChatLanguageModel = { modelId in
        CohereChatLanguageModel(
            modelId: modelId,
            config: CohereChatLanguageModel.Config(
                provider: "cohere.chat",
                baseURL: baseURL,
                headers: headersClosure,
                fetch: settings.fetch,
                generateId: settings.generateId ?? generateID
            )
        )
    }

    let embeddingFactory: @Sendable (CohereEmbeddingModelId) -> CohereEmbeddingModel = { modelId in
        CohereEmbeddingModel(
            modelId: modelId,
            config: CohereEmbeddingModel.Config(
                provider: "cohere.textEmbedding",
                baseURL: baseURL,
                headers: headersClosure,
                fetch: settings.fetch
            )
        )
    }

    let rerankingFactory: @Sendable (CohereRerankingModelId) -> CohereRerankingModel = { modelId in
        CohereRerankingModel(
            modelId: modelId,
            config: CohereRerankingModel.Config(
                provider: "cohere.reranking",
                baseURL: baseURL,
                headers: headersClosure,
                fetch: settings.fetch
            )
        )
    }

    return CohereProvider(
        chatFactory: chatFactory,
        embeddingFactory: embeddingFactory,
        rerankingFactory: rerankingFactory
    )
}

public let cohere = createCohereProvider()
