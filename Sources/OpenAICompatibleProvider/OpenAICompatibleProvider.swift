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
    public var supportsMultiPartToolContent: Bool
    public var supportedUrls: (@Sendable () async throws -> [String: [NSRegularExpression]])?
    public var transformRequestBody: (@Sendable (_ body: [String: JSONValue]) -> [String: JSONValue])?
    public var metadataExtractor: OpenAICompatibleMetadataExtractor?
    public var convertUsage: (@Sendable (_ usage: OpenAICompatibleChatUsage?) -> LanguageModelV4Usage)?

    public init(
        baseURL: String,
        name: String,
        apiKey: String? = nil,
        headers: [String: String]? = nil,
        queryParams: [String: String]? = nil,
        fetch: FetchFunction? = nil,
        includeUsage: Bool = false,
        supportsStructuredOutputs: Bool = false,
        supportsMultiPartToolContent: Bool = false,
        supportedUrls: (@Sendable () async throws -> [String: [NSRegularExpression]])? = nil,
        transformRequestBody: (@Sendable (_ body: [String: JSONValue]) -> [String: JSONValue])? = nil,
        metadataExtractor: OpenAICompatibleMetadataExtractor? = nil,
        convertUsage: (@Sendable (_ usage: OpenAICompatibleChatUsage?) -> LanguageModelV4Usage)? = nil
    ) {
        self.baseURL = baseURL
        self.name = name
        self.apiKey = apiKey
        self.headers = headers
        self.queryParams = queryParams
        self.fetch = fetch
        self.includeUsage = includeUsage
        self.supportsStructuredOutputs = supportsStructuredOutputs
        self.supportsMultiPartToolContent = supportsMultiPartToolContent
        self.supportedUrls = supportedUrls
        self.transformRequestBody = transformRequestBody
        self.metadataExtractor = metadataExtractor
        self.convertUsage = convertUsage
    }
}

public final class OpenAICompatibleProvider: ProviderV4 {
    private let languageFactory: @Sendable (OpenAICompatibleChatModelId) -> any LanguageModelV4
    private let chatFactory: @Sendable (OpenAICompatibleChatModelId) -> any LanguageModelV4
    private let completionFactory: @Sendable (OpenAICompatibleCompletionModelId) -> any LanguageModelV4
    private let embeddingFactory: @Sendable (OpenAICompatibleEmbeddingModelId) -> any EmbeddingModelV4
    private let imageFactory: @Sendable (OpenAICompatibleImageModelId) -> any ImageModelV4

    public init(
        languageFactory: @escaping @Sendable (OpenAICompatibleChatModelId) -> any LanguageModelV4,
        chatFactory: @escaping @Sendable (OpenAICompatibleChatModelId) -> any LanguageModelV4,
        completionFactory: @escaping @Sendable (OpenAICompatibleCompletionModelId) -> any LanguageModelV4,
        embeddingFactory: @escaping @Sendable (OpenAICompatibleEmbeddingModelId) -> any EmbeddingModelV4,
        imageFactory: @escaping @Sendable (OpenAICompatibleImageModelId) -> any ImageModelV4
    ) {
        self.languageFactory = languageFactory
        self.chatFactory = chatFactory
        self.completionFactory = completionFactory
        self.embeddingFactory = embeddingFactory
        self.imageFactory = imageFactory
    }

    public func callAsFunction(_ modelId: String) -> any LanguageModelV4 {
        languageFactory(OpenAICompatibleChatModelId(rawValue: modelId))
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV4 {
        languageFactory(OpenAICompatibleChatModelId(rawValue: modelId))
    }

    public func chatModel(modelId: String) throws -> any LanguageModelV4 {
        chatFactory(OpenAICompatibleChatModelId(rawValue: modelId))
    }

    public func completionModel(modelId: String) throws -> any LanguageModelV4 {
        completionFactory(OpenAICompatibleCompletionModelId(rawValue: modelId))
    }

    public func embeddingModel(modelId: String) throws -> any EmbeddingModelV4 {
        embeddingFactory(OpenAICompatibleEmbeddingModelId(rawValue: modelId))
    }

    public func imageModel(modelId: String) throws -> any ImageModelV4 {
        imageFactory(OpenAICompatibleImageModelId(rawValue: modelId))
    }
}

private struct OpenAICompatibleModelFactories: Sendable {
    let languageFactory: @Sendable (OpenAICompatibleChatModelId) -> OpenAICompatibleChatLanguageModel
    let completionFactory: @Sendable (OpenAICompatibleCompletionModelId) -> OpenAICompatibleCompletionLanguageModel
    let embeddingFactory: @Sendable (OpenAICompatibleEmbeddingModelId) -> OpenAICompatibleEmbeddingModel
    let imageFactory: @Sendable (OpenAICompatibleImageModelId) -> OpenAICompatibleImageModel
}

private func makeOpenAICompatibleModelFactories(
    settings: OpenAICompatibleProviderSettings
) -> OpenAICompatibleModelFactories {
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
            "ai-sdk-openai-compatible/\(OPENAI_COMPATIBLE_VERSION)"
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
    let supportsMultiPartToolContent = settings.supportsMultiPartToolContent
    let supportedUrls = settings.supportedUrls
    let transformRequestBody = settings.transformRequestBody
    let metadataExtractor = settings.metadataExtractor
    let convertUsage = settings.convertUsage

    let errorConfiguration = defaultOpenAICompatibleErrorConfiguration

    let chatConfig: @Sendable () -> OpenAICompatibleChatConfig = {
        OpenAICompatibleChatConfig(
            provider: "\(providerName).chat",
            headers: headersClosure,
            url: urlBuilder,
            fetch: commonFetch,
            includeUsage: includeUsage,
            errorConfiguration: errorConfiguration,
            metadataExtractor: metadataExtractor,
            supportsStructuredOutputs: supportsStructuredOutputs,
            supportsMultiPartToolContent: supportsMultiPartToolContent,
            supportedUrls: supportedUrls,
            transformRequestBody: transformRequestBody,
            convertUsage: convertUsage
        )
    }

    let languageFactory: @Sendable (OpenAICompatibleChatModelId) -> OpenAICompatibleChatLanguageModel = { modelId in
        OpenAICompatibleChatLanguageModel(modelId: modelId, config: chatConfig())
    }

    let completionConfig: @Sendable () -> OpenAICompatibleCompletionConfig = {
        OpenAICompatibleCompletionConfig(
            provider: "\(providerName).completion",
            headers: headersClosure,
            url: urlBuilder,
            fetch: commonFetch,
            includeUsage: includeUsage,
            errorConfiguration: errorConfiguration
        )
    }

    let completionFactory: @Sendable (OpenAICompatibleCompletionModelId) -> OpenAICompatibleCompletionLanguageModel = { modelId in
        OpenAICompatibleCompletionLanguageModel(modelId: modelId, config: completionConfig())
    }

    let embeddingConfig: @Sendable () -> OpenAICompatibleEmbeddingConfig = {
        OpenAICompatibleEmbeddingConfig(
            provider: "\(providerName).embedding",
            url: urlBuilder,
            headers: headersClosure,
            fetch: commonFetch,
            errorConfiguration: errorConfiguration
        )
    }

    let embeddingFactory: @Sendable (OpenAICompatibleEmbeddingModelId) -> OpenAICompatibleEmbeddingModel = { modelId in
        OpenAICompatibleEmbeddingModel(modelId: modelId, config: embeddingConfig())
    }

    let imageConfig: @Sendable () -> OpenAICompatibleImageModelConfig = {
        OpenAICompatibleImageModelConfig(
            provider: "\(providerName).image",
            headers: headersClosure,
            url: urlBuilder,
            fetch: commonFetch,
            errorConfiguration: errorConfiguration
        )
    }

    let imageFactory: @Sendable (OpenAICompatibleImageModelId) -> OpenAICompatibleImageModel = { modelId in
        OpenAICompatibleImageModel(modelId: modelId, config: imageConfig())
    }

    return OpenAICompatibleModelFactories(
        languageFactory: languageFactory,
        completionFactory: completionFactory,
        embeddingFactory: embeddingFactory,
        imageFactory: imageFactory
    )
}

public func createOpenAICompatible(
    settings: OpenAICompatibleProviderSettings
) -> OpenAICompatibleProvider {
    let factories = makeOpenAICompatibleModelFactories(settings: settings)

    return OpenAICompatibleProvider(
        languageFactory: factories.languageFactory,
        chatFactory: factories.languageFactory,
        completionFactory: factories.completionFactory,
        embeddingFactory: factories.embeddingFactory,
        imageFactory: factories.imageFactory
    )
}
