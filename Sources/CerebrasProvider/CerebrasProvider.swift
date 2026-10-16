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
public final class CerebrasProvider: ProviderV4 {
    private let chatFactory: @Sendable (CerebrasChatModelId) -> OpenAICompatibleChatLanguageModel

    init(chatFactory: @escaping @Sendable (CerebrasChatModelId) -> OpenAICompatibleChatLanguageModel) {
        self.chatFactory = chatFactory
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV4 {
        chatFactory(CerebrasChatModelId(rawValue: modelId))
    }

    public func chatModel(modelId: String) throws -> any LanguageModelV4 {
        chatFactory(CerebrasChatModelId(rawValue: modelId))
    }

    public func embeddingModel(modelId: String) throws -> any EmbeddingModelV4 {
        throw NoSuchModelError(modelId: modelId, modelType: .embeddingModel)
    }

    public func imageModel(modelId: String) throws -> any ImageModelV4 {
        throw NoSuchModelError(modelId: modelId, modelType: .imageModel)
    }

    public func callAsFunction(_ modelId: String) throws -> any LanguageModelV4 {
        try languageModel(modelId: modelId)
    }

    public func chat(_ modelId: CerebrasChatModelId) -> OpenAICompatibleChatLanguageModel {
        chatFactory(modelId)
    }

    public func languageModel(_ modelId: CerebrasChatModelId) -> OpenAICompatibleChatLanguageModel {
        chatFactory(modelId)
    }
}

private func createCerebrasAuthFetch(
    apiKey: String?,
    customFetch: FetchFunction?
) -> FetchFunction {
    let baseFetch = customFetch ?? defaultFetchFunction()

    return { request in
        var modified = request
        var headers = modified.allHTTPHeaderFields ?? [:]

        let resolved = try loadAPIKey(
            apiKey: apiKey,
            environmentVariableName: "CEREBRAS_API_KEY",
            description: "Cerebras API key"
        )

        let hasAuthorization = headers.keys.contains { $0.lowercased() == "authorization" }
        if !hasAuthorization {
            headers["Authorization"] = "Bearer \(resolved)"
            modified.allHTTPHeaderFields = headers
        }

        return try await baseFetch(modified)
    }
}

public func createCerebras(settings: CerebrasProviderSettings = .init()) -> CerebrasProvider {
    let baseURL = withoutTrailingSlash(settings.baseURL) ?? "https://api.cerebras.ai/v1"

    let headersClosure: @Sendable () -> [String: String] = {
        var headers: [String: String?] = [:]

        if let customHeaders = settings.headers {
            for (key, value) in customHeaders {
                headers[key] = value
            }
        }

        let withUA = withUserAgentSuffix(headers, "ai-sdk-cerebras/\(CEREBRAS_PROVIDER_VERSION)")
        return withUA
    }

    let fetch = createCerebrasAuthFetch(
        apiKey: settings.apiKey,
        customFetch: settings.fetch
    )

    let chatFactory: @Sendable (CerebrasChatModelId) -> OpenAICompatibleChatLanguageModel = { modelId in
        OpenAICompatibleChatLanguageModel(
            modelId: OpenAICompatibleChatModelId(rawValue: modelId.rawValue),
            config: OpenAICompatibleChatConfig(
                provider: "cerebras.chat",
                headers: headersClosure,
                url: { options in "\(baseURL)\(options.path)" },
                fetch: fetch,
                errorConfiguration: cerebrasErrorConfiguration,
                supportsStructuredOutputs: true
            )
        )
    }

    return CerebrasProvider(chatFactory: chatFactory)
}


/// Default Cerebras provider instance (`export const cerebras = createCerebras()`).
public let cerebras: CerebrasProvider = createCerebras()
