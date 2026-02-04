import Foundation
import AISDKProvider
import AISDKProviderUtils
import OpenAICompatibleProvider

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/vercel/src/vercel-provider.ts
// Upstream commit: f3a72bc2a
//===----------------------------------------------------------------------===//

public struct VercelProviderSettings: Sendable {
    /// Vercel API key.
    public var apiKey: String?

    /// Base URL for the API calls.
    public var baseURL: String?

    /// Custom headers to include in the requests.
    public var headers: [String: String]?

    /// Custom fetch implementation. You can use it as a middleware to intercept requests,
    /// or to provide a custom fetch implementation for e.g. testing.
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

public final class VercelProvider: ProviderV3 {
    private let chatFactory: @Sendable (VercelChatModelId) -> OpenAICompatibleChatLanguageModel

    init(chatFactory: @escaping @Sendable (VercelChatModelId) -> OpenAICompatibleChatLanguageModel) {
        self.chatFactory = chatFactory
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV3 {
        chatFactory(VercelChatModelId(rawValue: modelId))
    }

    public func chatModel(modelId: String) throws -> any LanguageModelV3 {
        try languageModel(modelId: modelId)
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

    public func chat(_ modelId: VercelChatModelId) -> OpenAICompatibleChatLanguageModel {
        chatFactory(modelId)
    }

    public func languageModel(_ modelId: VercelChatModelId) -> OpenAICompatibleChatLanguageModel {
        chatFactory(modelId)
    }
}

private let defaultBaseURL = "https://api.v0.dev/v1"

public func createVercelProvider(settings: VercelProviderSettings = .init()) -> VercelProvider {
    let baseURL = withoutTrailingSlash(settings.baseURL) ?? defaultBaseURL

    let headersClosure: @Sendable () -> [String: String] = {
        let apiKey: String
        do {
            apiKey = try loadAPIKey(
                apiKey: settings.apiKey,
                environmentVariableName: "VERCEL_API_KEY",
                description: "Vercel"
            )
        } catch {
            fatalError("Vercel API key is missing: \(error)")
        }

        var computed: [String: String?] = [
            "Authorization": "Bearer \(apiKey)"
        ]

        if let customHeaders = settings.headers {
            for (key, value) in customHeaders {
                computed[key] = value
            }
        }

        return withUserAgentSuffix(computed, "ai-sdk/vercel/\(VERCEL_VERSION)")
    }

    let chatFactory: @Sendable (VercelChatModelId) -> OpenAICompatibleChatLanguageModel = { modelId in
        OpenAICompatibleChatLanguageModel(
            modelId: OpenAICompatibleChatModelId(rawValue: modelId.rawValue),
            config: OpenAICompatibleChatConfig(
                provider: "vercel.chat",
                headers: headersClosure,
                url: { options in "\(baseURL)\(options.path)" },
                fetch: settings.fetch
            )
        )
    }

    return VercelProvider(chatFactory: chatFactory)
}

/// Alias matching upstream naming (`createVercel`).
public func createVercel(settings: VercelProviderSettings = .init()) -> VercelProvider {
    createVercelProvider(settings: settings)
}

/// Default Vercel provider instance (`export const vercel = createVercel()`).
public let vercel: VercelProvider = createVercelProvider()

