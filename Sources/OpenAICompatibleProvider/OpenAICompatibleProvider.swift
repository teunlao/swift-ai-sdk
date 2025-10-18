import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct OpenAICompatibleProviderSettings: Sendable {
    public var baseURL: String
    public var name: String
    public var apiKey: String?
    public var headers: [String: String]?
    public var queryParams: [String: String]?
    public var fetch: FetchFunction?
    public var includeUsage: Bool
    public var supportsStructuredOutputs: Bool

    public init(
        baseURL: String,
        name: String,
        apiKey: String? = nil,
        headers: [String: String]? = nil,
        queryParams: [String: String]? = nil,
        fetch: FetchFunction? = nil,
        includeUsage: Bool = false,
        supportsStructuredOutputs: Bool = false
    ) {
        self.baseURL = baseURL
        self.name = name
        self.apiKey = apiKey
        self.headers = headers
        self.queryParams = queryParams
        self.fetch = fetch
        self.includeUsage = includeUsage
        self.supportsStructuredOutputs = supportsStructuredOutputs
    }
}

public final class OpenAICompatibleProvider: ProviderV3 {
    private let languageFactory: @Sendable (OpenAICompatibleChatModelId) -> OpenAICompatibleChatLanguageModel
    private let chatFactory: @Sendable (OpenAICompatibleChatModelId) -> OpenAICompatibleChatLanguageModel
    private let completionFactory: @Sendable (OpenAICompatibleCompletionModelId) -> OpenAICompatibleCompletionLanguageModel
    private let embeddingFactory: @Sendable (OpenAICompatibleEmbeddingModelId) -> OpenAICompatibleEmbeddingModel
    private let imageFactory: @Sendable (OpenAICompatibleImageModelId) -> OpenAICompatibleImageModel

    public init(
        languageFactory: @escaping @Sendable (OpenAICompatibleChatModelId) -> OpenAICompatibleChatLanguageModel,
        chatFactory: @escaping @Sendable (OpenAICompatibleChatModelId) -> OpenAICompatibleChatLanguageModel,
        completionFactory: @escaping @Sendable (OpenAICompatibleCompletionModelId) -> OpenAICompatibleCompletionLanguageModel,
        embeddingFactory: @escaping @Sendable (OpenAICompatibleEmbeddingModelId) -> OpenAICompatibleEmbeddingModel,
        imageFactory: @escaping @Sendable (OpenAICompatibleImageModelId) -> OpenAICompatibleImageModel
    ) {
        self.languageFactory = languageFactory
        self.chatFactory = chatFactory
        self.completionFactory = completionFactory
        self.embeddingFactory = embeddingFactory
        self.imageFactory = imageFactory
    }

    public func languageModel(modelId: String) -> any LanguageModelV3 {
        languageFactory(OpenAICompatibleChatModelId(rawValue: modelId))
    }

    public func chatModel(modelId: String) -> any LanguageModelV3 {
        chatFactory(OpenAICompatibleChatModelId(rawValue: modelId))
    }

    public func completionModel(modelId: String) -> any LanguageModelV3 {
        completionFactory(OpenAICompatibleCompletionModelId(rawValue: modelId))
    }

    public func textEmbeddingModel(modelId: String) -> any EmbeddingModelV3<String> {
        embeddingFactory(OpenAICompatibleEmbeddingModelId(rawValue: modelId))
    }

    public func imageModel(modelId: String) -> any ImageModelV3 {
        imageFactory(OpenAICompatibleImageModelId(rawValue: modelId))
    }
}

public func createOpenAICompatibleProvider(
    settings: OpenAICompatibleProviderSettings
) -> OpenAICompatibleProvider {
    let baseURL = withoutTrailingSlash(settings.baseURL) ?? settings.baseURL
    let providerName = settings.name

    var headerEntries: [String: String?] = [:]
    if let apiKey = settings.apiKey, !apiKey.isEmpty {
        headerEntries["Authorization"] = "Bearer \(apiKey)"
    }
    if let customHeaders = settings.headers {
        for (key, value) in customHeaders {
            headerEntries[key] = value
        }
    }
    let baseHeaders = headerEntries

    let headersClosure: @Sendable () -> [String: String] = {
        withUserAgentSuffix(
            baseHeaders,
            "ai-sdk/openai-compatible/\(OPENAI_COMPATIBLE_VERSION)"
        )
    }

    let queryItems = settings.queryParams

    let urlBuilder: @Sendable (OpenAICompatibleURLOptions) -> String = { options in
        var base = baseURL + options.path
        if let queryItems, !queryItems.isEmpty {
            var components = URLComponents(string: base) ?? URLComponents()
            components.queryItems = queryItems.map { URLQueryItem(name: $0.key, value: $0.value) }
            if let urlString = components.string {
                base = urlString
            }
        }
        return base
    }

    let commonFetch = settings.fetch
    let includeUsage = settings.includeUsage
    let supportsStructuredOutputs = settings.supportsStructuredOutputs

    let errorConfiguration = defaultOpenAICompatibleErrorConfiguration

    let languageFactory: @Sendable (OpenAICompatibleChatModelId) -> OpenAICompatibleChatLanguageModel = { modelId in
        OpenAICompatibleChatLanguageModel(
            modelId: modelId,
            config: OpenAICompatibleChatConfig(
                provider: "\(providerName).chat",
                headers: headersClosure,
                url: urlBuilder,
                fetch: commonFetch,
                includeUsage: includeUsage,
                errorConfiguration: errorConfiguration,
                supportsStructuredOutputs: supportsStructuredOutputs
            )
        )
    }

    let completionFactory: @Sendable (OpenAICompatibleCompletionModelId) -> OpenAICompatibleCompletionLanguageModel = { modelId in
        OpenAICompatibleCompletionLanguageModel(
            modelId: modelId,
            config: OpenAICompatibleCompletionConfig(
                provider: "\(providerName).completion",
                headers: headersClosure,
                url: urlBuilder,
                fetch: commonFetch,
                includeUsage: includeUsage,
                errorConfiguration: errorConfiguration
            )
        )
    }

    let embeddingFactory: @Sendable (OpenAICompatibleEmbeddingModelId) -> OpenAICompatibleEmbeddingModel = { modelId in
        OpenAICompatibleEmbeddingModel(
            modelId: modelId,
            config: OpenAICompatibleEmbeddingConfig(
                provider: "\(providerName).embedding",
                url: urlBuilder,
                headers: headersClosure,
                fetch: commonFetch,
                errorConfiguration: errorConfiguration
            )
        )
    }

    let imageFactory: @Sendable (OpenAICompatibleImageModelId) -> OpenAICompatibleImageModel = { modelId in
        OpenAICompatibleImageModel(
            modelId: modelId,
            config: OpenAICompatibleImageModelConfig(
                provider: "\(providerName).image",
                headers: headersClosure,
                url: urlBuilder,
                fetch: commonFetch,
                errorConfiguration: errorConfiguration
            )
        )
    }

    return OpenAICompatibleProvider(
        languageFactory: languageFactory,
        chatFactory: languageFactory,
        completionFactory: completionFactory,
        embeddingFactory: embeddingFactory,
        imageFactory: imageFactory
    )
}
