import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/mistral/src/mistral-provider.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct MistralProviderSettings: Sendable {
    public var baseURL: String?
    public var apiKey: String?
    public var headers: [String: String]?
    public var fetch: FetchFunction?
    public var generateId: IDGenerator?

    public init(
        baseURL: String? = nil,
        apiKey: String? = nil,
        headers: [String: String]? = nil,
        fetch: FetchFunction? = nil,
        generateId: IDGenerator? = nil
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.headers = headers
        self.fetch = fetch
        self.generateId = generateId
    }
}

public final class MistralProvider: ProviderV3 {
    private let chatFactory: @Sendable (MistralChatModelId) -> MistralChatLanguageModel
    private let embeddingFactory: @Sendable (MistralEmbeddingModelId) -> MistralEmbeddingModel

    init(
        chatFactory: @escaping @Sendable (MistralChatModelId) -> MistralChatLanguageModel,
        embeddingFactory: @escaping @Sendable (MistralEmbeddingModelId) -> MistralEmbeddingModel
    ) {
        self.chatFactory = chatFactory
        self.embeddingFactory = embeddingFactory
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV3 {
        chatFactory(MistralChatModelId(rawValue: modelId))
    }

    public func chatModel(modelId: String) throws -> any LanguageModelV3 {
        chatFactory(MistralChatModelId(rawValue: modelId))
    }

    public func chat(modelId: MistralChatModelId) -> MistralChatLanguageModel {
        chatFactory(modelId)
    }

    public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
        embeddingFactory(MistralEmbeddingModelId(rawValue: modelId))
    }

    public func textEmbedding(_ modelId: MistralEmbeddingModelId) -> MistralEmbeddingModel {
        embeddingFactory(modelId)
    }

    public func embedding(_ modelId: MistralEmbeddingModelId) -> MistralEmbeddingModel {
        embeddingFactory(modelId)
    }

    public func imageModel(modelId: String) throws -> any ImageModelV3 {
        throw NoSuchModelError(modelId: modelId, modelType: .imageModel)
    }

    public func callAsFunction(_ modelId: String) throws -> any LanguageModelV3 {
        try languageModel(modelId: modelId)
    }
}

public func createMistralProvider(settings: MistralProviderSettings = .init()) -> MistralProvider {
    let baseURL = withoutTrailingSlash(settings.baseURL) ?? "https://api.mistral.ai/v1"

    let headersClosure: @Sendable () -> [String: String?] = {
        let apiKey: String
        do {
            apiKey = try loadAPIKey(
                apiKey: settings.apiKey,
                environmentVariableName: "MISTRAL_API_KEY",
                description: "Mistral"
            )
        } catch {
            fatalError("Mistral API key is missing: \(error)")
        }

        var headers: [String: String?] = [
            "Authorization": "Bearer \(apiKey)"
        ]

        if let customHeaders = settings.headers {
            for (key, value) in customHeaders {
                headers[key] = value
            }
        }

        let withUA = withUserAgentSuffix(headers.compactMapValues { $0 }, "ai-sdk/mistral/\(MISTRAL_VERSION)")
        return withUA.mapValues { Optional($0) }
    }

    let chatFactory: @Sendable (MistralChatModelId) -> MistralChatLanguageModel = { modelId in
        MistralChatLanguageModel(
            modelId: modelId,
            config: MistralChatLanguageModel.Config(
                provider: "mistral.chat",
                baseURL: baseURL,
                headers: headersClosure,
                fetch: settings.fetch,
                generateId: settings.generateId ?? generateID
            )
        )
    }

    let embeddingFactory: @Sendable (MistralEmbeddingModelId) -> MistralEmbeddingModel = { modelId in
        MistralEmbeddingModel(
            modelId: modelId,
            config: MistralEmbeddingModel.Config(
                provider: "mistral.embedding",
                baseURL: baseURL,
                headers: headersClosure,
                fetch: settings.fetch
            )
        )
    }

    return MistralProvider(
        chatFactory: chatFactory,
        embeddingFactory: embeddingFactory
    )
}

public let mistral: MistralProvider = createMistralProvider()
