import Foundation
import AISDKProvider
import AISDKProviderUtils
import OpenAICompatibleProvider

/// Settings for creating an xAI provider.
/// Mirrors `packages/xai/src/xai-provider.ts`.
public struct XAIProviderSettings: Sendable {
    public var baseURL: String?
    public var apiKey: String?
    public var headers: [String: String]?
    public var fetch: FetchFunction?

    public init(
        baseURL: String? = nil,
        apiKey: String? = nil,
        headers: [String: String]? = nil,
        fetch: FetchFunction? = nil
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.headers = headers
        self.fetch = fetch
    }
}

/// xAI provider implementation with support for chat and image models.
/// Mirrors `packages/xai/src/xai-provider.ts`.
public final class XAIProvider: ProviderV3 {
    private let languageModelFactory: @Sendable (XAIChatModelId) -> XAIChatLanguageModel
    private let imageModelFactory: @Sendable (XAIImageModelId) -> OpenAICompatibleImageModel

    init(
        languageModelFactory: @escaping @Sendable (XAIChatModelId) -> XAIChatLanguageModel,
        imageModelFactory: @escaping @Sendable (XAIImageModelId) -> OpenAICompatibleImageModel
    ) {
        self.languageModelFactory = languageModelFactory
        self.imageModelFactory = imageModelFactory
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV3 {
        languageModelFactory(XAIChatModelId(rawValue: modelId))
    }

    public func chatModel(modelId: String) throws -> any LanguageModelV3 {
        languageModelFactory(XAIChatModelId(rawValue: modelId))
    }

    public func chat(modelId: XAIChatModelId) -> XAIChatLanguageModel {
        languageModelFactory(modelId)
    }

    public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
        throw NoSuchModelError(modelId: modelId, modelType: .textEmbeddingModel)
    }

    public func imageModel(modelId: String) throws -> any ImageModelV3 {
        imageModelFactory(XAIImageModelId(rawValue: modelId))
    }

    public func image(modelId: XAIImageModelId) -> OpenAICompatibleImageModel {
        imageModelFactory(modelId)
    }

    public func callAsFunction(_ modelId: String) throws -> any LanguageModelV3 {
        try languageModel(modelId: modelId)
    }
}

public func createXAIProvider(settings: XAIProviderSettings = .init()) -> XAIProvider {
    let baseURL = withoutTrailingSlash(settings.baseURL) ?? "https://api.x.ai/v1"

    let headersClosure: @Sendable () -> [String: String?] = {
        var baseHeaders: [String: String?] = [:]
        let apiKey: String
        do {
            apiKey = try loadAPIKey(
                apiKey: settings.apiKey,
                environmentVariableName: "XAI_API_KEY",
                description: "xAI API key"
            )
        } catch {
            fatalError("xAI API key is missing: \(error)")
        }
        baseHeaders["Authorization"] = "Bearer \(apiKey)"

        if let custom = settings.headers {
            for (key, value) in custom {
                baseHeaders[key] = value
            }
        }

        let withUA = withUserAgentSuffix(baseHeaders, "ai-sdk/xai/\(XAI_PROVIDER_VERSION)")
        return withUA.mapValues { Optional($0) }
    }

    let languageModelFactory: @Sendable (XAIChatModelId) -> XAIChatLanguageModel = { modelId in
        XAIChatLanguageModel(
            modelId: modelId,
            config: XAIChatLanguageModel.Config(
                provider: "xai.chat",
                baseURL: baseURL,
                headers: headersClosure,
                generateId: generateID,
                fetch: settings.fetch
            )
        )
    }

    let imageModelFactory: @Sendable (XAIImageModelId) -> OpenAICompatibleImageModel = { modelId in
        OpenAICompatibleImageModel(
            modelId: OpenAICompatibleImageModelId(rawValue: modelId.rawValue),
            config: OpenAICompatibleImageModelConfig(
                provider: "xai.image",
                headers: { headersClosure().compactMapValues { $0 } },
                url: { options in "\(baseURL)\(options.path)" },
                fetch: settings.fetch,
                errorConfiguration: xaiErrorConfiguration
            )
        )
    }

    return XAIProvider(
        languageModelFactory: languageModelFactory,
        imageModelFactory: imageModelFactory
    )
}

/// Alias for createXAIProvider to match upstream naming.
public func createXai(settings: XAIProviderSettings = .init()) -> XAIProvider {
    createXAIProvider(settings: settings)
}

/// Default xAI provider instance (parity with `export const xai = createXai()`).
public let xai: XAIProvider = createXAIProvider()
