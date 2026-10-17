import Foundation
import AISDKProvider
import AISDKProviderUtils
import OpenAIProvider

/// Settings for configuring the Azure OpenAI provider.
/// Mirrors `packages/azure/src/azure-openai-provider.ts`.
public struct AzureProviderSettings: Sendable {
    public var resourceName: String?
    public var baseURL: String?
    public var apiKey: String?
    public var tokenProvider: (@Sendable () async throws -> String)?
    public var headers: [String: String]?
    public var fetch: FetchFunction?
    public var apiVersion: String?
    public var useDeploymentBasedUrls: Bool

    public init(
        resourceName: String? = nil,
        baseURL: String? = nil,
        apiKey: String? = nil,
        tokenProvider: (@Sendable () async throws -> String)? = nil,
        headers: [String: String]? = nil,
        fetch: FetchFunction? = nil,
        apiVersion: String? = nil,
        useDeploymentBasedUrls: Bool = false
    ) {
        self.resourceName = resourceName
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.tokenProvider = tokenProvider
        self.headers = headers
        self.fetch = fetch
        self.apiVersion = apiVersion
        self.useDeploymentBasedUrls = useDeploymentBasedUrls
    }
}

/// Azure OpenAI provider implementation.
/// Mirrors `packages/azure/src/azure-openai-provider.ts`.
public final class AzureProvider: ProviderV4 {
    private let chatFactory: @Sendable (OpenAIChatModelId) -> OpenAIChatLanguageModel
    private let responsesFactory: @Sendable (OpenAIResponsesModelId) -> OpenAIResponsesLanguageModel
    private let completionFactory: @Sendable (OpenAICompletionModelId) -> OpenAICompletionLanguageModel
    private let embeddingFactory: @Sendable (OpenAIEmbeddingModelId) -> OpenAIEmbeddingModel
    private let imageFactory: @Sendable (OpenAIImageModelId) -> OpenAIImageModelV4
    private let transcriptionFactory: @Sendable (OpenAITranscriptionModelId) -> OpenAITranscriptionModelV4
    private let speechFactory: @Sendable (OpenAISpeechModelId) -> OpenAISpeechModelV4
    public let tools: AzureProviderTools

    init(
        chatFactory: @escaping @Sendable (OpenAIChatModelId) -> OpenAIChatLanguageModel,
        responsesFactory: @escaping @Sendable (OpenAIResponsesModelId) -> OpenAIResponsesLanguageModel,
        completionFactory: @escaping @Sendable (OpenAICompletionModelId) -> OpenAICompletionLanguageModel,
        embeddingFactory: @escaping @Sendable (OpenAIEmbeddingModelId) -> OpenAIEmbeddingModel,
        imageFactory: @escaping @Sendable (OpenAIImageModelId) -> OpenAIImageModelV4,
        transcriptionFactory: @escaping @Sendable (OpenAITranscriptionModelId) -> OpenAITranscriptionModelV4,
        speechFactory: @escaping @Sendable (OpenAISpeechModelId) -> OpenAISpeechModelV4,
        tools: AzureProviderTools
    ) {
        self.chatFactory = chatFactory
        self.responsesFactory = responsesFactory
        self.completionFactory = completionFactory
        self.embeddingFactory = embeddingFactory
        self.imageFactory = imageFactory
        self.transcriptionFactory = transcriptionFactory
        self.speechFactory = speechFactory
        self.tools = tools
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV4 {
        chatFactory(OpenAIChatModelId(rawValue: modelId))
    }

    public func chatModel(modelId: String) throws -> any LanguageModelV4 {
        chatFactory(OpenAIChatModelId(rawValue: modelId))
    }

    public func completionModel(modelId: String) -> any LanguageModelV4 {
        completionFactory(OpenAICompletionModelId(rawValue: modelId))
    }

    public func embeddingModel(modelId: String) throws -> any EmbeddingModelV4 {
        embeddingFactory(OpenAIEmbeddingModelId(rawValue: modelId))
    }

    public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV4 {
        try embeddingModel(modelId: modelId)
    }

    public func imageModel(modelId: String) throws -> any ImageModelV4 {
        imageFactory(OpenAIImageModelId(rawValue: modelId))
    }

    public func transcriptionModel(modelId: String) throws -> (any TranscriptionModelV4)? {
        transcriptionFactory(OpenAITranscriptionModelId(rawValue: modelId))
    }

    public func speechModel(modelId: String) throws -> (any SpeechModelV4)? {
        speechFactory(OpenAISpeechModelId(rawValue: modelId))
    }

    public func callAsFunction(_ modelId: String) throws -> any LanguageModelV4 {
        try languageModel(modelId: modelId)
    }

    public func chat(_ modelId: OpenAIChatModelId) -> OpenAIChatLanguageModel {
        chatFactory(modelId)
    }

    public func responses(_ modelId: OpenAIResponsesModelId) -> OpenAIResponsesLanguageModel {
        responsesFactory(modelId)
    }

    public func completion(_ modelId: OpenAICompletionModelId) -> OpenAICompletionLanguageModel {
        completionFactory(modelId)
    }

    public func embedding(_ modelId: OpenAIEmbeddingModelId) -> OpenAIEmbeddingModel {
        embeddingFactory(modelId)
    }

    public func embeddingModel(_ modelId: OpenAIEmbeddingModelId) -> OpenAIEmbeddingModel {
        embeddingFactory(modelId)
    }

    public func textEmbedding(_ modelId: OpenAIEmbeddingModelId) -> OpenAIEmbeddingModel {
        embeddingFactory(modelId)
    }

    public func image(_ modelId: OpenAIImageModelId) -> OpenAIImageModelV4 {
        imageFactory(modelId)
    }

    public func imageModel(_ modelId: OpenAIImageModelId) -> OpenAIImageModelV4 {
        imageFactory(modelId)
    }

    public func transcription(_ modelId: OpenAITranscriptionModelId) -> OpenAITranscriptionModelV4 {
        transcriptionFactory(modelId)
    }

    public func speech(_ modelId: OpenAISpeechModelId) -> OpenAISpeechModelV4 {
        speechFactory(modelId)
    }
}

public func createAzureProvider(settings: AzureProviderSettings = .init()) throws -> AzureProvider {
    if let apiKey = settings.apiKey, !apiKey.isEmpty, settings.tokenProvider != nil {
        throw InvalidArgumentError(
            argument: "apiKey/tokenProvider",
            message: "Both apiKey and tokenProvider were provided. Please use only one authentication method."
        )
    }

    let endpoint = try Endpoint(baseURL: settings.baseURL)
    let headers: @Sendable () throws -> [String: String?] = {
        var authHeaders: [String: String?] = [:]
        if settings.tokenProvider == nil {
            authHeaders["api-key"] = try loadAPIKey(
                apiKey: settings.apiKey,
                environmentVariableName: "AZURE_API_KEY",
                description: "Azure OpenAI"
            )
        }
        let combined = combineHeaders(authHeaders, settings.headers?.mapValues { Optional($0) })
        return withUserAgentSuffix(combined, "ai-sdk-azure/\(AZURE_PROVIDER_VERSION)").mapValues { Optional($0) }
    }

    let fetch: FetchFunction?
    if let tokenProvider = settings.tokenProvider {
        let baseFetch = settings.fetch ?? defaultFetchFunction()
        fetch = { request in
            var request = request
            if request.value(forHTTPHeaderField: "Authorization") == nil {
                request.setValue("Bearer \(try await tokenProvider())", forHTTPHeaderField: "Authorization")
            }
            return try await baseFetch(request)
        }
    } else {
        fetch = settings.fetch
    }

    let urlBuilder: @Sendable (OpenAIConfig.URLOptions) throws -> String = { options in
        let basePrefix: String
        if let baseURL = settings.baseURL {
            basePrefix = withoutTrailingSlash(baseURL) ?? baseURL
        } else {
            let resourceName = try loadSetting(
                settingValue: settings.resourceName,
                environmentVariableName: "AZURE_RESOURCE_NAME",
                settingName: "resourceName",
                description: "Azure OpenAI resource name"
            )
            guard isValidHostnamePart(resourceName) else {
                throw InvalidArgumentError(
                    argument: "resourceName",
                    message: "Invalid Azure resource name. Expected a single DNS label (letters, digits, and hyphens). Use `baseURL` for custom endpoints."
                )
            }
            basePrefix = "https://\(resourceName).openai.azure.com/openai"
        }

        let fullURL: String
        if settings.useDeploymentBasedUrls {
            fullURL = "\(basePrefix)/deployments/\(options.modelId)\(options.path)"
        } else if !endpoint.isAzure || endpoint.isVersioned {
            fullURL = basePrefix + options.path
        } else {
            fullURL = basePrefix + "/v1" + options.path
        }

        guard var url = URLComponents(string: fullURL), url.host != nil, url.scheme != nil else {
            throw InvalidArgumentError(argument: "baseURL", message: "Invalid Azure request URL.")
        }
        url.host = url.host?.lowercased()
        url.scheme = url.scheme?.lowercased()
        if settings.useDeploymentBasedUrls || (endpoint.isAzure && !endpoint.isVersioned && !endpoint.isFoundry) {
            url.percentEncodedQuery = url.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%20")
            var items = url.queryItems ?? []
            if let index = items.firstIndex(where: { $0.name == "api-version" }) {
                items[index] = URLQueryItem(name: "api-version", value: settings.apiVersion ?? "v1")
                items = items.enumerated().filter { $0.offset == index || $0.element.name != "api-version" }.map(\.element)
            } else {
                items.append(URLQueryItem(name: "api-version", value: settings.apiVersion ?? "v1"))
            }
            url.percentEncodedQuery = items.map {
                Endpoint.encodeQuery($0.name) + "=" + Endpoint.encodeQuery($0.value ?? "")
            }.joined(separator: "&")
        }
        guard let result = url.string else {
            throw InvalidArgumentError(argument: "baseURL", message: "Invalid Azure request URL.")
        }
        return result
    }

    let chatConfig = OpenAIConfig(
        provider: "azure.chat",
        url: urlBuilder,
        headers: headers,
        fetch: fetch
    )

    let responsesConfig = OpenAIConfig(
        provider: "azure.responses",
        explicitMessageItemType: endpoint.isFoundry,
        url: urlBuilder,
        headers: headers,
        fetch: fetch,
        fileIdPrefixes: ["assistant-"]
    )

    let completionConfig = OpenAIConfig(
        provider: "azure.completion",
        url: urlBuilder,
        headers: headers,
        fetch: fetch
    )

    let embeddingConfig = OpenAIConfig(
        provider: "azure.embeddings",
        url: urlBuilder,
        headers: headers,
        fetch: fetch
    )

    let imageConfig = OpenAIConfig(
        provider: "azure.image",
        imageInputCapabilities: .init(),
        url: urlBuilder,
        headers: headers,
        fetch: fetch
    )

    let transcriptionConfig = OpenAIConfig(
        provider: "azure.transcription",
        url: urlBuilder,
        headers: headers,
        fetch: fetch
    )

    let speechConfig = OpenAIConfig(
        provider: "azure.speech",
        url: urlBuilder,
        headers: headers,
        fetch: fetch
    )

    let chatFactory: @Sendable (OpenAIChatModelId) -> OpenAIChatLanguageModel = { modelId in
        OpenAIChatLanguageModel(
            modelId: modelId,
            config: chatConfig
        )
    }

    let responsesFactory: @Sendable (OpenAIResponsesModelId) -> OpenAIResponsesLanguageModel = { modelId in
        OpenAIResponsesLanguageModel(
            modelId: modelId,
            config: responsesConfig
        )
    }

    let completionFactory: @Sendable (OpenAICompletionModelId) -> OpenAICompletionLanguageModel = { modelId in
        OpenAICompletionLanguageModel(
            modelId: modelId,
            config: completionConfig
        )
    }

    let embeddingFactory: @Sendable (OpenAIEmbeddingModelId) -> OpenAIEmbeddingModel = { modelId in
        OpenAIEmbeddingModel(
            modelId: modelId,
            config: embeddingConfig
        )
    }

    let imageFactory: @Sendable (OpenAIImageModelId) -> OpenAIImageModelV4 = { modelId in
        OpenAIImageModelV4(
            modelId: modelId,
            config: imageConfig
        )
    }

    let transcriptionFactory: @Sendable (OpenAITranscriptionModelId) -> OpenAITranscriptionModelV4 = { modelId in
        OpenAITranscriptionModelV4(
            modelId: modelId,
            config: transcriptionConfig
        )
    }

    let speechFactory: @Sendable (OpenAISpeechModelId) -> OpenAISpeechModelV4 = { modelId in
        OpenAISpeechModelV4(
            modelId: modelId,
            config: speechConfig
        )
    }

    return AzureProvider(
        chatFactory: chatFactory,
        responsesFactory: responsesFactory,
        completionFactory: completionFactory,
        embeddingFactory: embeddingFactory,
        imageFactory: imageFactory,
        transcriptionFactory: transcriptionFactory,
        speechFactory: speechFactory,
        tools: azureOpenaiTools
    )
}

/// Alias to mirror TypeScript naming (`createAzure`).
public func createAzure(settings: AzureProviderSettings = .init()) throws -> AzureProvider {
    try createAzureProvider(settings: settings)
}

/// Default Azure provider instance (`export const azure = createAzure()`).
public let azure: AzureProvider = try! createAzureProvider()

private struct Endpoint: Sendable {
    let isAzure: Bool
    let isFoundry: Bool
    let isVersioned: Bool

    init(baseURL: String?) throws {
        guard let baseURL else {
            isAzure = true
            isFoundry = false
            isVersioned = false
            return
        }
        guard let url = URLComponents(string: baseURL), let host = url.host?.lowercased(), !host.isEmpty, url.scheme != nil else {
            throw InvalidArgumentError(argument: "baseURL", message: "Invalid Azure base URL.")
        }
        isAzure = [".openai.azure.com", ".services.ai.azure.com", ".cognitiveservices.azure.com"].contains { host.hasSuffix($0) }
        var path = url.path
        while path.hasSuffix("/") { path.removeLast() }
        isFoundry = host.hasSuffix(".services.ai.azure.com") && path.hasPrefix("/api/projects/")
        isVersioned = isAzure && path.lowercased().hasSuffix("/openai/v1")
    }

    static func encodeQuery(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789*-._")
        return value.addingPercentEncoding(withAllowedCharacters: allowed)!.replacingOccurrences(of: "%20", with: "+")
    }
}
