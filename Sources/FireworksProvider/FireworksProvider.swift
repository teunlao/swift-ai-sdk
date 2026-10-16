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

private func createFireworksAuthFetch(
    apiKey: String?,
    customFetch: FetchFunction?
) -> FetchFunction {
    let baseFetch = customFetch ?? defaultFetchFunction()

    return { request in
        var modified = request
        var headers = modified.allHTTPHeaderFields ?? [:]

        let hasAuthorization = headers.keys.contains { $0.lowercased() == "authorization" }
        if !hasAuthorization {
            let resolved = try loadAPIKey(
                apiKey: apiKey,
                environmentVariableName: "FIREWORKS_API_KEY",
                description: "Fireworks API key"
            )
            headers["Authorization"] = "Bearer \(resolved)"
            modified.allHTTPHeaderFields = headers
        }

        return try await baseFetch(modified)
    }
}

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

public final class FireworksProvider: ProviderV4 {
    private let chatFactory: @Sendable (FireworksChatModelId) -> OpenAICompatibleChatLanguageModelV4
    private let completionFactory: @Sendable (FireworksCompletionModelId) -> OpenAICompatibleCompletionLanguageModelV4
    private let embeddingFactory: @Sendable (FireworksEmbeddingModelId) -> OpenAICompatibleEmbeddingModelV4
    private let imageFactory: @Sendable (FireworksImageModelId) -> FireworksImageModel

    init(
        chatFactory: @escaping @Sendable (FireworksChatModelId) -> OpenAICompatibleChatLanguageModelV4,
        completionFactory: @escaping @Sendable (FireworksCompletionModelId) -> OpenAICompatibleCompletionLanguageModelV4,
        embeddingFactory: @escaping @Sendable (FireworksEmbeddingModelId) -> OpenAICompatibleEmbeddingModelV4,
        imageFactory: @escaping @Sendable (FireworksImageModelId) -> FireworksImageModel
    ) {
        self.chatFactory = chatFactory
        self.completionFactory = completionFactory
        self.embeddingFactory = embeddingFactory
        self.imageFactory = imageFactory
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV4 {
        chatFactory(FireworksChatModelId(rawValue: modelId))
    }

    public func chatModel(modelId: String) throws -> any LanguageModelV4 {
        try languageModel(modelId: modelId)
    }

    public func completionModel(modelId: String) throws -> any LanguageModelV4 {
        completionFactory(FireworksCompletionModelId(rawValue: modelId))
    }

    public func embeddingModel(modelId: String) throws -> any EmbeddingModelV4 {
        embeddingFactory(FireworksEmbeddingModelId(rawValue: modelId))
    }

    public func imageModel(modelId: String) throws -> any ImageModelV4 {
        imageFactory(FireworksImageModelId(rawValue: modelId))
    }

    public func callAsFunction(_ modelId: String) throws -> any LanguageModelV4 {
        try languageModel(modelId: modelId)
    }

    // MARK: - Convenience Accessors

    public func chat(modelId: FireworksChatModelId) -> OpenAICompatibleChatLanguageModelV4 {
        chatFactory(modelId)
    }

    public func completion(modelId: FireworksCompletionModelId) -> OpenAICompatibleCompletionLanguageModelV4 {
        completionFactory(modelId)
    }

    public func embedding(modelId: FireworksEmbeddingModelId) -> OpenAICompatibleEmbeddingModelV4 {
        embeddingFactory(modelId)
    }

    public func textEmbedding(_ modelId: FireworksEmbeddingModelId) -> OpenAICompatibleEmbeddingModelV4 {
        embeddingFactory(modelId)
    }

    public func image(modelId: FireworksImageModelId) -> FireworksImageModel {
        imageFactory(modelId)
    }
}

public func createFireworks(settings: FireworksProviderSettings = .init()) -> FireworksProvider {
    let baseURL = withoutTrailingSlash(settings.baseURL) ?? FIREWORKS_DEFAULT_BASE_URL

    let headersClosure: @Sendable () -> [String: String] = {
        var baseHeaders: [String: String?] = [:]

        if let customHeaders = settings.headers {
            for (key, value) in customHeaders {
                baseHeaders[key] = value
            }
        }

        return withUserAgentSuffix(baseHeaders, "ai-sdk-fireworks/\(FIREWORKS_VERSION)")
    }

    let fetch = createFireworksAuthFetch(
        apiKey: settings.apiKey,
        customFetch: settings.fetch
    )

    let urlBuilder: @Sendable (OpenAICompatibleURLOptions) -> String = { options in
        "\(baseURL)\(options.path)"
    }

    let chatFactory: @Sendable (FireworksChatModelId) -> OpenAICompatibleChatLanguageModelV4 = { modelId in
        let config = OpenAICompatibleChatConfig(
            provider: "fireworks.chat",
            headers: headersClosure,
            url: urlBuilder,
            fetch: fetch,
            errorConfiguration: fireworksErrorConfiguration
        )
        return OpenAICompatibleChatLanguageModelV4(
            modelId: OpenAICompatibleChatModelId(rawValue: modelId.rawValue),
            config: config
        )
    }

    let completionFactory: @Sendable (FireworksCompletionModelId) -> OpenAICompatibleCompletionLanguageModelV4 = { modelId in
        let config = OpenAICompatibleCompletionConfig(
            provider: "fireworks.completion",
            headers: headersClosure,
            url: urlBuilder,
            fetch: fetch,
            errorConfiguration: fireworksErrorConfiguration
        )
        return OpenAICompatibleCompletionLanguageModelV4(
            modelId: OpenAICompatibleCompletionModelId(rawValue: modelId.rawValue),
            config: config
        )
    }

    let embeddingFactory: @Sendable (FireworksEmbeddingModelId) -> OpenAICompatibleEmbeddingModelV4 = { modelId in
        let config = OpenAICompatibleEmbeddingConfig(
            provider: "fireworks.embedding",
            url: urlBuilder,
            headers: headersClosure,
            fetch: fetch,
            errorConfiguration: fireworksErrorConfiguration
        )
        return OpenAICompatibleEmbeddingModelV4(
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


public let fireworks = createFireworks()
