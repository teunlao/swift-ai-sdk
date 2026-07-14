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
        self.supportedUrls = supportedUrls
        self.transformRequestBody = transformRequestBody
        self.metadataExtractor = metadataExtractor
        self.convertUsage = convertUsage
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

    public func languageModel(modelId: String) throws -> any LanguageModelV3 {
        languageFactory(OpenAICompatibleChatModelId(rawValue: modelId))
    }

    public func chatModel(modelId: String) throws -> any LanguageModelV3 {
        chatFactory(OpenAICompatibleChatModelId(rawValue: modelId))
    }

    public func completionModel(modelId: String) throws -> any LanguageModelV3 {
        completionFactory(OpenAICompatibleCompletionModelId(rawValue: modelId))
    }

    public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
        embeddingFactory(OpenAICompatibleEmbeddingModelId(rawValue: modelId))
    }

    public func imageModel(modelId: String) throws -> any ImageModelV3 {
        imageFactory(OpenAICompatibleImageModelId(rawValue: modelId))
    }
}

public final class OpenAICompatibleProviderV4: ProviderV4 {
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

    public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV4 {
        embeddingFactory(OpenAICompatibleEmbeddingModelId(rawValue: modelId))
    }

    public func imageModel(modelId: String) throws -> any ImageModelV4 {
        imageFactory(OpenAICompatibleImageModelId(rawValue: modelId))
    }
}

private struct OpenAICompatibleModelFactories: Sendable {
    let languageFactory: @Sendable (OpenAICompatibleChatModelId) -> OpenAICompatibleChatLanguageModel
    let languageFactoryV4: @Sendable (OpenAICompatibleChatModelId) -> OpenAICompatibleChatLanguageModelV4
    let completionFactory: @Sendable (OpenAICompatibleCompletionModelId) -> OpenAICompatibleCompletionLanguageModel
    let completionFactoryV4: @Sendable (OpenAICompatibleCompletionModelId) -> OpenAICompatibleCompletionLanguageModelV4
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
            supportedUrls: supportedUrls,
            transformRequestBody: transformRequestBody,
            convertUsage: convertUsage
        )
    }

    let languageFactory: @Sendable (OpenAICompatibleChatModelId) -> OpenAICompatibleChatLanguageModel = { modelId in
        OpenAICompatibleChatLanguageModel(modelId: modelId, config: chatConfig())
    }

    let languageFactoryV4: @Sendable (OpenAICompatibleChatModelId) -> OpenAICompatibleChatLanguageModelV4 = { modelId in
        OpenAICompatibleChatLanguageModelV4(modelId: modelId, config: chatConfig())
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

    let completionFactoryV4: @Sendable (OpenAICompatibleCompletionModelId) -> OpenAICompatibleCompletionLanguageModelV4 = { modelId in
        OpenAICompatibleCompletionLanguageModelV4(modelId: modelId, config: completionConfig())
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

    return OpenAICompatibleModelFactories(
        languageFactory: languageFactory,
        languageFactoryV4: languageFactoryV4,
        completionFactory: completionFactory,
        completionFactoryV4: completionFactoryV4,
        embeddingFactory: embeddingFactory,
        imageFactory: imageFactory
    )
}

public func createOpenAICompatible(
    settings: OpenAICompatibleProviderSettings
) -> OpenAICompatibleProviderV4 {
    let factories = makeOpenAICompatibleModelFactories(settings: settings)

    return OpenAICompatibleProviderV4(
        languageFactory: factories.languageFactoryV4,
        chatFactory: factories.languageFactoryV4,
        completionFactory: factories.completionFactoryV4,
        embeddingFactory: { OpenAICompatibleEmbeddingModelV4Adapter(wrapping: factories.embeddingFactory($0)) },
        imageFactory: { OpenAICompatibleImageModelV4Adapter(wrapping: factories.imageFactory($0)) }
    )
}

public func createOpenAICompatibleProvider(
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
