import Foundation
import AISDKProvider
import AISDKProviderUtils
import OpenAICompatibleProvider

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/deepinfra/src/deepinfra-provider.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct DeepInfraProviderSettings: Sendable {
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

public final class DeepInfraProvider: ProviderV3 {
    private let chatFactory: @Sendable (DeepInfraChatModelId) -> OpenAICompatibleChatLanguageModel
    private let completionFactory: @Sendable (DeepInfraCompletionModelId) -> OpenAICompatibleCompletionLanguageModel
    private let embeddingFactory: @Sendable (DeepInfraEmbeddingModelId) -> OpenAICompatibleEmbeddingModel
    private let imageFactory: @Sendable (DeepInfraImageModelId) -> DeepInfraImageModel

    init(
        chatFactory: @escaping @Sendable (DeepInfraChatModelId) -> OpenAICompatibleChatLanguageModel,
        completionFactory: @escaping @Sendable (DeepInfraCompletionModelId) -> OpenAICompatibleCompletionLanguageModel,
        embeddingFactory: @escaping @Sendable (DeepInfraEmbeddingModelId) -> OpenAICompatibleEmbeddingModel,
        imageFactory: @escaping @Sendable (DeepInfraImageModelId) -> DeepInfraImageModel
    ) {
        self.chatFactory = chatFactory
        self.completionFactory = completionFactory
        self.embeddingFactory = embeddingFactory
        self.imageFactory = imageFactory
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV3 {
        chatFactory(DeepInfraChatModelId(rawValue: modelId))
    }

    public func chatModel(modelId: String) throws -> any LanguageModelV3 {
        try languageModel(modelId: modelId)
    }

    public func completionModel(modelId: String) throws -> any LanguageModelV3 {
        completionFactory(DeepInfraCompletionModelId(rawValue: modelId))
    }

    public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
        embeddingFactory(DeepInfraEmbeddingModelId(rawValue: modelId))
    }

    public func imageModel(modelId: String) throws -> any ImageModelV3 {
        imageFactory(DeepInfraImageModelId(rawValue: modelId))
    }

    public func callAsFunction(_ modelId: String) throws -> any LanguageModelV3 {
        try languageModel(modelId: modelId)
    }

    public func chat(modelId: DeepInfraChatModelId) -> OpenAICompatibleChatLanguageModel {
        chatFactory(modelId)
    }

    public func completion(modelId: DeepInfraCompletionModelId) -> OpenAICompatibleCompletionLanguageModel {
        completionFactory(modelId)
    }

    public func embedding(modelId: DeepInfraEmbeddingModelId) -> OpenAICompatibleEmbeddingModel {
        embeddingFactory(modelId)
    }

    public func image(modelId: DeepInfraImageModelId) -> DeepInfraImageModel {
        imageFactory(modelId)
    }
}

public func createDeepInfraProvider(settings: DeepInfraProviderSettings = .init()) -> DeepInfraProvider {
    let baseURL = withoutTrailingSlash(settings.baseURL) ?? "https://api.deepinfra.com/v1"

    let headersClosure: @Sendable () -> [String: String] = {
        let apiKey: String
        do {
            apiKey = try loadAPIKey(
                apiKey: settings.apiKey,
                environmentVariableName: "DEEPINFRA_API_KEY",
                description: "DeepInfra API key"
            )
        } catch {
            fatalError("DeepInfra API key is missing: \(error)")
        }

        var baseHeaders: [String: String?] = [
            "Authorization": "Bearer \(apiKey)"
        ]

        if let customHeaders = settings.headers {
            for (key, value) in customHeaders {
                baseHeaders[key] = value
            }
        }

        return withUserAgentSuffix(baseHeaders, "ai-sdk/deepinfra/\(DEEPINFRA_VERSION)")
    }

    let fetch = settings.fetch

    let urlBuilder: @Sendable (OpenAICompatibleURLOptions) -> String = { options in
        "\(baseURL)/openai\(options.path)"
    }

    let chatFactory: @Sendable (DeepInfraChatModelId) -> OpenAICompatibleChatLanguageModel = { modelId in
        let config = OpenAICompatibleChatConfig(
            provider: "deepinfra.chat",
            headers: headersClosure,
            url: urlBuilder,
            fetch: fetch
        )
        return OpenAICompatibleChatLanguageModel(modelId: OpenAICompatibleChatModelId(rawValue: modelId.rawValue), config: config)
    }

    let completionFactory: @Sendable (DeepInfraCompletionModelId) -> OpenAICompatibleCompletionLanguageModel = { modelId in
        let config = OpenAICompatibleCompletionConfig(
            provider: "deepinfra.completion",
            headers: headersClosure,
            url: urlBuilder,
            fetch: fetch
        )
        return OpenAICompatibleCompletionLanguageModel(modelId: OpenAICompatibleCompletionModelId(rawValue: modelId.rawValue), config: config)
    }

    let embeddingFactory: @Sendable (DeepInfraEmbeddingModelId) -> OpenAICompatibleEmbeddingModel = { modelId in
        let config = OpenAICompatibleEmbeddingConfig(
            provider: "deepinfra.embedding",
            url: urlBuilder,
            headers: headersClosure,
            fetch: fetch
        )
        return OpenAICompatibleEmbeddingModel(modelId: OpenAICompatibleEmbeddingModelId(rawValue: modelId.rawValue), config: config)
    }

    let imageFactory: @Sendable (DeepInfraImageModelId) -> DeepInfraImageModel = { modelId in
        let config = DeepInfraImageModelConfig(
            provider: "deepinfra.image",
            baseURL: "\(baseURL)/inference",
            headers: { headersClosure().mapValues { Optional($0) } },
            fetch: fetch,
            currentDate: { Date() }
        )
        return DeepInfraImageModel(modelId: modelId, config: config)
    }

    return DeepInfraProvider(
        chatFactory: chatFactory,
        completionFactory: completionFactory,
        embeddingFactory: embeddingFactory,
        imageFactory: imageFactory
    )
}

public let deepinfra = createDeepInfraProvider()
