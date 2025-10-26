import Foundation
import AISDKProvider
import AISDKProviderUtils
import OpenAICompatibleProvider

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/fireworks/src/fireworks-provider.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

private let FIREWORKS_DEFAULT_BASE_URL = "https://api.fireworks.ai/inference/v1"

public struct FireworksProviderSettings: Sendable {
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

public final class FireworksProvider: ProviderV3 {
    private let chatFactory: @Sendable (FireworksChatModelId) -> OpenAICompatibleChatLanguageModel
    private let completionFactory: @Sendable (FireworksCompletionModelId) -> OpenAICompatibleCompletionLanguageModel
    private let embeddingFactory: @Sendable (FireworksEmbeddingModelId) -> OpenAICompatibleEmbeddingModel
    private let imageFactory: @Sendable (FireworksImageModelId) -> FireworksImageModel

    init(
        chatFactory: @escaping @Sendable (FireworksChatModelId) -> OpenAICompatibleChatLanguageModel,
        completionFactory: @escaping @Sendable (FireworksCompletionModelId) -> OpenAICompatibleCompletionLanguageModel,
        embeddingFactory: @escaping @Sendable (FireworksEmbeddingModelId) -> OpenAICompatibleEmbeddingModel,
        imageFactory: @escaping @Sendable (FireworksImageModelId) -> FireworksImageModel
    ) {
        self.chatFactory = chatFactory
        self.completionFactory = completionFactory
        self.embeddingFactory = embeddingFactory
        self.imageFactory = imageFactory
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV3 {
        chatFactory(FireworksChatModelId(rawValue: modelId))
    }

    public func chatModel(modelId: String) throws -> any LanguageModelV3 {
        try languageModel(modelId: modelId)
    }

    public func completionModel(modelId: String) throws -> any LanguageModelV3 {
        completionFactory(FireworksCompletionModelId(rawValue: modelId))
    }

    public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
        embeddingFactory(FireworksEmbeddingModelId(rawValue: modelId))
    }

    public func imageModel(modelId: String) throws -> any ImageModelV3 {
        imageFactory(FireworksImageModelId(rawValue: modelId))
    }

    public func callAsFunction(_ modelId: String) throws -> any LanguageModelV3 {
        try languageModel(modelId: modelId)
    }

    // MARK: - Convenience Accessors

    public func chat(modelId: FireworksChatModelId) -> OpenAICompatibleChatLanguageModel {
        chatFactory(modelId)
    }

    public func completion(modelId: FireworksCompletionModelId) -> OpenAICompatibleCompletionLanguageModel {
        completionFactory(modelId)
    }

    public func embedding(modelId: FireworksEmbeddingModelId) -> OpenAICompatibleEmbeddingModel {
        embeddingFactory(modelId)
    }

    public func textEmbedding(_ modelId: FireworksEmbeddingModelId) -> OpenAICompatibleEmbeddingModel {
        embeddingFactory(modelId)
    }

    public func image(modelId: FireworksImageModelId) -> FireworksImageModel {
        imageFactory(modelId)
    }
}

public func createFireworksProvider(settings: FireworksProviderSettings = .init()) -> FireworksProvider {
    let baseURL = withoutTrailingSlash(settings.baseURL) ?? FIREWORKS_DEFAULT_BASE_URL

    let headersClosure: @Sendable () -> [String: String] = {
        let apiKey: String
        do {
            apiKey = try loadAPIKey(
                apiKey: settings.apiKey,
                environmentVariableName: "FIREWORKS_API_KEY",
                description: "Fireworks API key"
            )
        } catch {
            fatalError("Fireworks API key is missing: \(error)")
        }

        var baseHeaders: [String: String?] = [
            "Authorization": "Bearer \(apiKey)"
        ]

        if let customHeaders = settings.headers {
            for (key, value) in customHeaders {
                baseHeaders[key] = value
            }
        }

        return withUserAgentSuffix(baseHeaders, "ai-sdk/fireworks/\(FIREWORKS_VERSION)")
    }

    let fetch = settings.fetch

    let urlBuilder: @Sendable (OpenAICompatibleURLOptions) -> String = { options in
        "\(baseURL)\(options.path)"
    }

    let chatFactory: @Sendable (FireworksChatModelId) -> OpenAICompatibleChatLanguageModel = { modelId in
        let config = OpenAICompatibleChatConfig(
            provider: "fireworks.chat",
            headers: headersClosure,
            url: urlBuilder,
            fetch: fetch,
            errorConfiguration: fireworksErrorConfiguration
        )
        return OpenAICompatibleChatLanguageModel(
            modelId: OpenAICompatibleChatModelId(rawValue: modelId.rawValue),
            config: config
        )
    }

    let completionFactory: @Sendable (FireworksCompletionModelId) -> OpenAICompatibleCompletionLanguageModel = { modelId in
        let config = OpenAICompatibleCompletionConfig(
            provider: "fireworks.completion",
            headers: headersClosure,
            url: urlBuilder,
            fetch: fetch,
            errorConfiguration: fireworksErrorConfiguration
        )
        return OpenAICompatibleCompletionLanguageModel(
            modelId: OpenAICompatibleCompletionModelId(rawValue: modelId.rawValue),
            config: config
        )
    }

    let embeddingFactory: @Sendable (FireworksEmbeddingModelId) -> OpenAICompatibleEmbeddingModel = { modelId in
        let config = OpenAICompatibleEmbeddingConfig(
            provider: "fireworks.embedding",
            url: urlBuilder,
            headers: headersClosure,
            fetch: fetch,
            errorConfiguration: fireworksErrorConfiguration
        )
        return OpenAICompatibleEmbeddingModel(
            modelId: OpenAICompatibleEmbeddingModelId(rawValue: modelId.rawValue),
            config: config
        )
    }

    let imageFactory: @Sendable (FireworksImageModelId) -> FireworksImageModel = { modelId in
        let config = FireworksImageModelConfig(
            provider: "fireworks.image",
            baseURL: baseURL,
            headers: headersClosure,
            fetch: fetch,
            currentDate: { Date() }
        )
        return FireworksImageModel(modelId: modelId, config: config)
    }

    return FireworksProvider(
        chatFactory: chatFactory,
        completionFactory: completionFactory,
        embeddingFactory: embeddingFactory,
        imageFactory: imageFactory
    )
}

public let fireworks = createFireworksProvider()
