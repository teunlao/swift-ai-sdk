import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/perplexity/src/perplexity-provider.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct PerplexityProviderSettings: Sendable {
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

public final class PerplexityProvider: ProviderV3 {
    private let languageModelFactory: @Sendable (PerplexityLanguageModelId) -> PerplexityLanguageModel

    init(languageModelFactory: @escaping @Sendable (PerplexityLanguageModelId) -> PerplexityLanguageModel) {
        self.languageModelFactory = languageModelFactory
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV3 {
        languageModelFactory(PerplexityLanguageModelId(rawValue: modelId))
    }

    public func chatModel(modelId: String) throws -> any LanguageModelV3 {
        try languageModel(modelId: modelId)
    }

    public func chat(modelId: PerplexityLanguageModelId) -> PerplexityLanguageModel {
        languageModelFactory(modelId)
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
}

public func createPerplexityProvider(settings: PerplexityProviderSettings = .init()) -> PerplexityProvider {
    let baseURL = withoutTrailingSlash(settings.baseURL) ?? "https://api.perplexity.ai"

    let headersClosure: @Sendable () -> [String: String?] = {
        var computed: [String: String?] = [:]

        let apiKey: String
        do {
            apiKey = try loadAPIKey(
                apiKey: settings.apiKey,
                environmentVariableName: "PERPLEXITY_API_KEY",
                description: "Perplexity"
            )
        } catch {
            fatalError("Perplexity API key is missing: \(error)")
        }

        computed["Authorization"] = "Bearer \(apiKey)"
        if let headers = settings.headers {
            for (key, value) in headers {
                computed[key] = value
            }
        }

        let withUA = withUserAgentSuffix(computed.compactMapValues { $0 }, "ai-sdk/perplexity/\(PERPLEXITY_VERSION)")
        return withUA.mapValues { Optional($0) }
    }

    let languageFactory: @Sendable (PerplexityLanguageModelId) -> PerplexityLanguageModel = { modelId in
        PerplexityLanguageModel(
            modelId: modelId,
            config: PerplexityLanguageModel.Config(
                baseURL: baseURL,
                headers: headersClosure,
                fetch: settings.fetch,
                generateId: settings.generateId ?? generateID
            )
        )
    }

    return PerplexityProvider(languageModelFactory: languageFactory)
}

public let perplexity = createPerplexityProvider()
