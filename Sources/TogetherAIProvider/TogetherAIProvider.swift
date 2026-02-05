import Foundation
import AISDKProvider
import AISDKProviderUtils
import OpenAICompatibleProvider

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/togetherai/src/togetherai-provider.ts
// Upstream commit: f3a72bc2a
//===----------------------------------------------------------------------===//

public struct TogetherAIProviderSettings: Sendable {
    public var apiKey: String?
    public var baseURL: String?
    public var headers: [String: String]?
    public var fetch: FetchFunction?

    public init(
        apiKey: String? = nil,
        baseURL: String? = nil,
        headers: [String: String]? = nil,
        fetch: FetchFunction? = nil
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.headers = headers
        self.fetch = fetch
    }
}

public final class TogetherAIProvider: ProviderV3 {
    private let chatFactory: @Sendable (TogetherAIChatModelId) -> OpenAICompatibleChatLanguageModel
    private let completionFactory: @Sendable (TogetherAICompletionModelId) -> OpenAICompatibleCompletionLanguageModel
    private let embeddingFactory: @Sendable (TogetherAIEmbeddingModelId) -> OpenAICompatibleEmbeddingModel
    private let imageFactory: @Sendable (TogetherAIImageModelId) -> TogetherAIImageModel
    private let rerankingFactory: @Sendable (TogetherAIRerankingModelId) -> TogetherAIRerankingModel

    init(
        chatFactory: @escaping @Sendable (TogetherAIChatModelId) -> OpenAICompatibleChatLanguageModel,
        completionFactory: @escaping @Sendable (TogetherAICompletionModelId) -> OpenAICompatibleCompletionLanguageModel,
        embeddingFactory: @escaping @Sendable (TogetherAIEmbeddingModelId) -> OpenAICompatibleEmbeddingModel,
        imageFactory: @escaping @Sendable (TogetherAIImageModelId) -> TogetherAIImageModel,
        rerankingFactory: @escaping @Sendable (TogetherAIRerankingModelId) -> TogetherAIRerankingModel
    ) {
        self.chatFactory = chatFactory
        self.completionFactory = completionFactory
        self.embeddingFactory = embeddingFactory
        self.imageFactory = imageFactory
        self.rerankingFactory = rerankingFactory
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV3 {
        chatFactory(TogetherAIChatModelId(rawValue: modelId))
    }

    public func chatModel(modelId: String) throws -> any LanguageModelV3 {
        try languageModel(modelId: modelId)
    }

    public func completionModel(modelId: String) throws -> any LanguageModelV3 {
        completionFactory(TogetherAICompletionModelId(rawValue: modelId))
    }

    public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
        embeddingFactory(TogetherAIEmbeddingModelId(rawValue: modelId))
    }

    public func imageModel(modelId: String) throws -> any ImageModelV3 {
        imageFactory(TogetherAIImageModelId(rawValue: modelId))
    }

    public func rerankingModel(modelId: String) throws -> (any RerankingModelV3)? {
        rerankingFactory(TogetherAIRerankingModelId(rawValue: modelId))
    }

    public func callAsFunction(_ modelId: String) throws -> any LanguageModelV3 {
        try languageModel(modelId: modelId)
    }

    public func chat(modelId: TogetherAIChatModelId) -> OpenAICompatibleChatLanguageModel {
        chatFactory(modelId)
    }

    public func completion(modelId: TogetherAICompletionModelId) -> OpenAICompatibleCompletionLanguageModel {
        completionFactory(modelId)
    }

    public func embedding(modelId: TogetherAIEmbeddingModelId) -> OpenAICompatibleEmbeddingModel {
        embeddingFactory(modelId)
    }

    public func image(modelId: TogetherAIImageModelId) -> TogetherAIImageModel {
        imageFactory(modelId)
    }

    public func reranking(modelId: TogetherAIRerankingModelId) -> TogetherAIRerankingModel {
        rerankingFactory(modelId)
    }
}

public func createTogetherAIProvider(settings: TogetherAIProviderSettings = .init()) -> TogetherAIProvider {
    let baseURL = withoutTrailingSlash(settings.baseURL) ?? "https://api.together.xyz/v1"

    let headersClosure: @Sendable () -> [String: String] = {
        let apiKey: String
        do {
            apiKey = try loadAPIKey(
                apiKey: settings.apiKey,
                environmentVariableName: "TOGETHER_AI_API_KEY",
                description: "TogetherAI"
            )
        } catch {
            fatalError("TogetherAI API key is missing: \(error)")
        }

        var computed: [String: String?] = [
            "Authorization": "Bearer \(apiKey)"
        ]

        if let customHeaders = settings.headers {
            for (key, value) in customHeaders {
                computed[key] = value
            }
        }

        return withUserAgentSuffix(
            computed.compactMapValues { $0 },
            "ai-sdk/togetherai/\(TOGETHERAI_VERSION)"
        )
    }

    let optionalHeadersClosure: @Sendable () -> [String: String?] = {
        headersClosure().mapValues { Optional($0) }
    }

    let fetch = settings.fetch

    let urlBuilder: @Sendable (OpenAICompatibleURLOptions) -> String = { options in
        "\(baseURL)\(options.path)"
    }

    let chatFactory: @Sendable (TogetherAIChatModelId) -> OpenAICompatibleChatLanguageModel = { modelId in
        let config = OpenAICompatibleChatConfig(
            provider: "togetherai.chat",
            headers: headersClosure,
            url: urlBuilder,
            fetch: fetch
        )
        return OpenAICompatibleChatLanguageModel(
            modelId: OpenAICompatibleChatModelId(rawValue: modelId.rawValue),
            config: config
        )
    }

    let completionFactory: @Sendable (TogetherAICompletionModelId) -> OpenAICompatibleCompletionLanguageModel = { modelId in
        let config = OpenAICompatibleCompletionConfig(
            provider: "togetherai.completion",
            headers: headersClosure,
            url: urlBuilder,
            fetch: fetch
        )
        return OpenAICompatibleCompletionLanguageModel(
            modelId: OpenAICompatibleCompletionModelId(rawValue: modelId.rawValue),
            config: config
        )
    }

    let embeddingFactory: @Sendable (TogetherAIEmbeddingModelId) -> OpenAICompatibleEmbeddingModel = { modelId in
        let config = OpenAICompatibleEmbeddingConfig(
            provider: "togetherai.embedding",
            url: urlBuilder,
            headers: headersClosure,
            fetch: fetch
        )
        return OpenAICompatibleEmbeddingModel(
            modelId: OpenAICompatibleEmbeddingModelId(rawValue: modelId.rawValue),
            config: config
        )
    }

    let imageFactory: @Sendable (TogetherAIImageModelId) -> TogetherAIImageModel = { modelId in
        TogetherAIImageModel(
            modelId: modelId,
            config: TogetherAIImageModelConfig(
                provider: "togetherai.image",
                baseURL: baseURL,
                headers: optionalHeadersClosure,
                fetch: fetch
            )
        )
    }

    let rerankingFactory: @Sendable (TogetherAIRerankingModelId) -> TogetherAIRerankingModel = { modelId in
        TogetherAIRerankingModel(
            modelId: modelId,
            config: TogetherAIRerankingModel.Config(
                provider: "togetherai.reranking",
                baseURL: baseURL,
                headers: optionalHeadersClosure,
                fetch: fetch
            )
        )
    }

    return TogetherAIProvider(
        chatFactory: chatFactory,
        completionFactory: completionFactory,
        embeddingFactory: embeddingFactory,
        imageFactory: imageFactory,
        rerankingFactory: rerankingFactory
    )
}

/// Alias matching upstream naming (`createTogetherAI`).
public func createTogetherAI(settings: TogetherAIProviderSettings = .init()) -> TogetherAIProvider {
    createTogetherAIProvider(settings: settings)
}

public let togetherai = createTogetherAIProvider()
