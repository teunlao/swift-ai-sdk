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
    public var headers: [String: String]?
    public var fetch: FetchFunction?
    public var apiVersion: String?
    public var useDeploymentBasedUrls: Bool

    public init(
        resourceName: String? = nil,
        baseURL: String? = nil,
        apiKey: String? = nil,
        headers: [String: String]? = nil,
        fetch: FetchFunction? = nil,
        apiVersion: String? = nil,
        useDeploymentBasedUrls: Bool = false
    ) {
        self.resourceName = resourceName
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.headers = headers
        self.fetch = fetch
        self.apiVersion = apiVersion
        self.useDeploymentBasedUrls = useDeploymentBasedUrls
    }
}

/// Azure OpenAI provider implementation.
/// Mirrors `packages/azure/src/azure-openai-provider.ts`.
public final class AzureProvider: ProviderV3 {
    private let chatFactory: @Sendable (OpenAIChatModelId) -> OpenAIChatLanguageModel
    private let responsesFactory: @Sendable (OpenAIResponsesModelId) -> OpenAIResponsesLanguageModel
    private let completionFactory: @Sendable (OpenAICompletionModelId) -> OpenAICompletionLanguageModel
    private let embeddingFactory: @Sendable (OpenAIEmbeddingModelId) -> OpenAIEmbeddingModel
    private let imageFactory: @Sendable (OpenAIImageModelId) -> OpenAIImageModel
    private let transcriptionFactory: @Sendable (OpenAITranscriptionModelId) -> OpenAITranscriptionModel
    private let speechFactory: @Sendable (OpenAISpeechModelId) -> OpenAISpeechModel
    public let tools: AzureProviderTools

    init(
        chatFactory: @escaping @Sendable (OpenAIChatModelId) -> OpenAIChatLanguageModel,
        responsesFactory: @escaping @Sendable (OpenAIResponsesModelId) -> OpenAIResponsesLanguageModel,
        completionFactory: @escaping @Sendable (OpenAICompletionModelId) -> OpenAICompletionLanguageModel,
        embeddingFactory: @escaping @Sendable (OpenAIEmbeddingModelId) -> OpenAIEmbeddingModel,
        imageFactory: @escaping @Sendable (OpenAIImageModelId) -> OpenAIImageModel,
        transcriptionFactory: @escaping @Sendable (OpenAITranscriptionModelId) -> OpenAITranscriptionModel,
        speechFactory: @escaping @Sendable (OpenAISpeechModelId) -> OpenAISpeechModel,
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

    public func languageModel(modelId: String) throws -> any LanguageModelV3 {
        chatFactory(OpenAIChatModelId(rawValue: modelId))
    }

    public func chatModel(modelId: String) throws -> any LanguageModelV3 {
        chatFactory(OpenAIChatModelId(rawValue: modelId))
    }

    public func completionModel(modelId: String) -> any LanguageModelV3 {
        completionFactory(OpenAICompletionModelId(rawValue: modelId))
    }

    public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
        embeddingFactory(OpenAIEmbeddingModelId(rawValue: modelId))
    }

    public func imageModel(modelId: String) throws -> any ImageModelV3 {
        imageFactory(OpenAIImageModelId(rawValue: modelId))
    }

    public func transcriptionModel(modelId: String) -> any TranscriptionModelV3 {
        transcriptionFactory(OpenAITranscriptionModelId(rawValue: modelId))
    }

    public func speechModel(modelId: String) -> any SpeechModelV3 {
        speechFactory(OpenAISpeechModelId(rawValue: modelId))
    }

    public func callAsFunction(_ modelId: String) throws -> any LanguageModelV3 {
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

    @available(*, deprecated, message: "Use textEmbedding instead.")
    public func embedding(_ modelId: OpenAIEmbeddingModelId) -> OpenAIEmbeddingModel {
        embeddingFactory(modelId)
    }

    public func textEmbedding(_ modelId: OpenAIEmbeddingModelId) -> OpenAIEmbeddingModel {
        embeddingFactory(modelId)
    }

    public func image(_ modelId: OpenAIImageModelId) -> OpenAIImageModel {
        imageFactory(modelId)
    }

    public func imageModel(_ modelId: OpenAIImageModelId) -> OpenAIImageModel {
        imageFactory(modelId)
    }

    public func transcription(_ modelId: OpenAITranscriptionModelId) -> OpenAITranscriptionModel {
        transcriptionFactory(modelId)
    }

    public func speech(_ modelId: OpenAISpeechModelId) -> OpenAISpeechModel {
        speechFactory(modelId)
    }
}

public func createAzureProvider(settings: AzureProviderSettings = .init()) -> AzureProvider {
    let headersClosure: @Sendable () -> [String: String?] = {
        let apiKey: String
        do {
            apiKey = try loadAPIKey(
                apiKey: settings.apiKey,
                environmentVariableName: "AZURE_API_KEY",
                description: "Azure OpenAI"
            )
        } catch {
            fatalError("Azure OpenAI API key is missing: \(error)")
        }

        var baseHeaders: [String: String?] = [
            "api-key": apiKey
        ]

        if let customHeaders = settings.headers {
            for (key, value) in customHeaders {
                baseHeaders[key] = value
            }
        }

        let withUA = withUserAgentSuffix(baseHeaders, "ai-sdk/azure/\(AZURE_PROVIDER_VERSION)")
        return withUA.mapValues { Optional($0) }
    }

    let apiVersion = settings.apiVersion ?? "v1"
    let useDeploymentBasedUrls = settings.useDeploymentBasedUrls

    let resolveBaseURLPrefix: @Sendable () -> String = {
        if let base = settings.baseURL, !base.isEmpty {
            return withoutTrailingSlash(base) ?? base
        }

        let resourceName: String
        do {
            resourceName = try loadSetting(
                settingValue: settings.resourceName,
                environmentVariableName: "AZURE_RESOURCE_NAME",
                settingName: "resourceName",
                description: "Azure OpenAI resource name"
            )
        } catch {
            fatalError("Azure OpenAI resource name is missing: \(error)")
        }

        return "https://\(resourceName).openai.azure.com/openai"
    }

    let urlBuilder: @Sendable (OpenAIConfig.URLOptions) -> String = { options in
        let basePrefix = resolveBaseURLPrefix()
        let basePath: String
        if useDeploymentBasedUrls {
            basePath = "\(basePrefix)/deployments/\(options.modelId)\(options.path)"
        } else {
            basePath = "\(basePrefix)/v1\(options.path)"
        }

        if var components = URLComponents(string: basePath) {
            var items = components.queryItems ?? []
            items.removeAll { $0.name.caseInsensitiveCompare("api-version") == .orderedSame }
            items.append(URLQueryItem(name: "api-version", value: apiVersion))
            components.queryItems = items
            if let urlString = components.string {
                return urlString
            }
        }

        let separator = basePath.contains("?") ? "&" : "?"
        return "\(basePath)\(separator)api-version=\(apiVersion)"
    }

    let headers = headersClosure
    let fetch = settings.fetch

    let chatConfig = OpenAIConfig(
        provider: "azure.chat",
        url: urlBuilder,
        headers: headers,
        fetch: fetch
    )

    let responsesConfig = OpenAIConfig(
        provider: "azure.responses",
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

    let imageFactory: @Sendable (OpenAIImageModelId) -> OpenAIImageModel = { modelId in
        OpenAIImageModel(
            modelId: modelId,
            config: imageConfig
        )
    }

    let transcriptionFactory: @Sendable (OpenAITranscriptionModelId) -> OpenAITranscriptionModel = { modelId in
        OpenAITranscriptionModel(
            modelId: modelId,
            config: transcriptionConfig
        )
    }

    let speechFactory: @Sendable (OpenAISpeechModelId) -> OpenAISpeechModel = { modelId in
        OpenAISpeechModel(
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
public func createAzure(settings: AzureProviderSettings = .init()) -> AzureProvider {
    createAzureProvider(settings: settings)
}

/// Default Azure provider instance (`export const azure = createAzure()`).
public let azure: AzureProvider = createAzureProvider()
