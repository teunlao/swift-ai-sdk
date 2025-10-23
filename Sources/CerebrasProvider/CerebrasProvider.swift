import Foundation
import AISDKProvider
import AISDKProviderUtils
import OpenAICompatibleProvider

/// Settings for configuring the Cerebras provider.
/// Mirrors `packages/cerebras/src/cerebras-provider.ts`.
public struct CerebrasProviderSettings: Sendable {
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

/// Cerebras provider implementation backed by the OpenAI-compatible chat client.
/// Mirrors `packages/cerebras/src/cerebras-provider.ts`.
public final class CerebrasProvider: ProviderV3 {
    private let chatFactory: @Sendable (CerebrasChatModelId) -> OpenAICompatibleChatLanguageModel

    init(chatFactory: @escaping @Sendable (CerebrasChatModelId) -> OpenAICompatibleChatLanguageModel) {
        self.chatFactory = chatFactory
    }

    public func languageModel(modelId: String) -> any LanguageModelV3 {
        chatFactory(CerebrasChatModelId(rawValue: modelId))
    }

    public func chatModel(modelId: String) -> any LanguageModelV3 {
        chatFactory(CerebrasChatModelId(rawValue: modelId))
    }

    public func textEmbeddingModel(modelId: String) -> any EmbeddingModelV3<String> {
        fatalError(NoSuchModelError(modelId: modelId, modelType: .textEmbeddingModel).localizedDescription)
    }

    public func imageModel(modelId: String) -> any ImageModelV3 {
        fatalError(NoSuchModelError(modelId: modelId, modelType: .imageModel).localizedDescription)
    }

    public func callAsFunction(_ modelId: String) -> any LanguageModelV3 {
        languageModel(modelId: modelId)
    }

    public func chat(_ modelId: CerebrasChatModelId) -> OpenAICompatibleChatLanguageModel {
        chatFactory(modelId)
    }

    public func languageModel(_ modelId: CerebrasChatModelId) -> OpenAICompatibleChatLanguageModel {
        chatFactory(modelId)
    }
}

public func createCerebrasProvider(settings: CerebrasProviderSettings = .init()) -> CerebrasProvider {
    let baseURL = withoutTrailingSlash(settings.baseURL) ?? "https://api.cerebras.ai/v1"

    let headersClosure: @Sendable () -> [String: String] = {
        let apiKey: String
        do {
            apiKey = try loadAPIKey(
                apiKey: settings.apiKey,
                environmentVariableName: "CEREBRAS_API_KEY",
                description: "Cerebras API key"
            )
        } catch {
            fatalError("Cerebras API key is missing: \(error)")
        }

        var headers: [String: String?] = [
            "Authorization": "Bearer \(apiKey)"
        ]

        if let customHeaders = settings.headers {
            for (key, value) in customHeaders {
                headers[key] = value
            }
        }

        let withUA = withUserAgentSuffix(headers, "ai-sdk/cerebras/\(CEREBRAS_PROVIDER_VERSION)")
        return withUA
    }

    let chatFactory: @Sendable (CerebrasChatModelId) -> OpenAICompatibleChatLanguageModel = { modelId in
        OpenAICompatibleChatLanguageModel(
            modelId: OpenAICompatibleChatModelId(rawValue: modelId.rawValue),
            config: OpenAICompatibleChatConfig(
                provider: "cerebras.chat",
                headers: headersClosure,
                url: { options in "\(baseURL)\(options.path)" },
                fetch: settings.fetch,
                errorConfiguration: cerebrasErrorConfiguration,
                supportsStructuredOutputs: true
            )
        )
    }

    return CerebrasProvider(chatFactory: chatFactory)
}

/// Alias matching upstream naming (`createCerebras`).
public func createCerebras(settings: CerebrasProviderSettings = .init()) -> CerebrasProvider {
    createCerebrasProvider(settings: settings)
}

/// Default Cerebras provider instance (`export const cerebras = createCerebras()`).
public let cerebras: CerebrasProvider = createCerebrasProvider()
