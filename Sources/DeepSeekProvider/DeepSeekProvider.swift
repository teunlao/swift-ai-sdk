import Foundation
import AISDKProvider
import AISDKProviderUtils
import OpenAICompatibleProvider

/// Settings for configuring the DeepSeek provider.
/// Mirrors `packages/deepseek/src/deepseek-provider.ts`.
public struct DeepSeekProviderSettings: Sendable {
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

/// DeepSeek provider backed by the OpenAI-compatible chat implementation.
/// Mirrors `packages/deepseek/src/deepseek-provider.ts`.
public final class DeepSeekProvider: ProviderV3 {
    private let chatFactory: @Sendable (DeepSeekChatModelId) -> OpenAICompatibleChatLanguageModel

    init(chatFactory: @escaping @Sendable (DeepSeekChatModelId) -> OpenAICompatibleChatLanguageModel) {
        self.chatFactory = chatFactory
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV3 {
        chatFactory(DeepSeekChatModelId(rawValue: modelId))
    }

    public func chatModel(modelId: String) throws -> any LanguageModelV3 {
        chatFactory(DeepSeekChatModelId(rawValue: modelId))
    }

    public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
        throw NoSuchModelError(modelId: modelId, modelType: .textEmbeddingModel)
    }

    public func imageModel(modelId: String) throws -> any ImageModelV3 {
        throw NoSuchModelError(modelId: modelId, modelType: .imageModel)
    }

    public func callAsFunction(_ modelId: String) throws -> any LanguageModelV3 {
        try languageModel(modelId: modelId)
    }

    public func chat(_ modelId: DeepSeekChatModelId) -> OpenAICompatibleChatLanguageModel {
        chatFactory(modelId)
    }

    public func languageModel(_ modelId: DeepSeekChatModelId) -> OpenAICompatibleChatLanguageModel {
        chatFactory(modelId)
    }
}

public func createDeepSeekProvider(settings: DeepSeekProviderSettings = .init()) -> DeepSeekProvider {
    let baseURL = withoutTrailingSlash(settings.baseURL) ?? "https://api.deepseek.com/v1"

    let headersClosure: @Sendable () -> [String: String] = {
        let apiKey: String
        do {
            apiKey = try loadAPIKey(
                apiKey: settings.apiKey,
                environmentVariableName: "DEEPSEEK_API_KEY",
                description: "DeepSeek API key"
            )
        } catch {
            fatalError("DeepSeek API key is missing: \(error)")
        }

        var headers: [String: String?] = [
            "Authorization": "Bearer \(apiKey)"
        ]

        if let customHeaders = settings.headers {
            for (key, value) in customHeaders {
                headers[key] = value
            }
        }

        let withUA = withUserAgentSuffix(headers, "ai-sdk/deepseek/\(DEEPSEEK_PROVIDER_VERSION)")
        return withUA
    }

    let chatFactory: @Sendable (DeepSeekChatModelId) -> OpenAICompatibleChatLanguageModel = { modelId in
        OpenAICompatibleChatLanguageModel(
            modelId: OpenAICompatibleChatModelId(rawValue: modelId.rawValue),
            config: OpenAICompatibleChatConfig(
                provider: "deepseek.chat",
                headers: headersClosure,
                url: { options in "\(baseURL)\(options.path)" },
                fetch: settings.fetch,
                metadataExtractor: deepSeekMetadataExtractor
            )
        )
    }

    return DeepSeekProvider(chatFactory: chatFactory)
}

/// Alias matching the upstream naming (`createDeepSeek`).
public func createDeepSeek(settings: DeepSeekProviderSettings = .init()) -> DeepSeekProvider {
    createDeepSeekProvider(settings: settings)
}

/// Default DeepSeek provider instance (`export const deepseek = createDeepSeek()`).
public let deepseek: DeepSeekProvider = createDeepSeekProvider()
