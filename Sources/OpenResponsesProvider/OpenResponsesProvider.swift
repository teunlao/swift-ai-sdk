import AISDKProvider
import AISDKProviderUtils
import Foundation

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/open-responses/src/open-responses-provider.ts
// Upstream commit: 73d5c59
//===----------------------------------------------------------------------===//

public struct OpenResponsesProviderSettings: Sendable {
    /// URL for the Open Responses API POST endpoint.
    public var url: String

    /// Provider name. Used as key for provider options and metadata.
    public var name: String

    /// API key for authenticating requests.
    public var apiKey: String?

    /// Custom headers to include in the requests.
    public var headers: [String: String]?

    /// Custom fetch implementation.
    public var fetch: FetchFunction?

    public init(
        url: String,
        name: String,
        apiKey: String? = nil,
        headers: [String: String]? = nil,
        fetch: FetchFunction? = nil
    ) {
        self.url = url
        self.name = name
        self.apiKey = apiKey
        self.headers = headers
        self.fetch = fetch
    }
}

public final class OpenResponsesProvider: ProviderV3 {
    private let responsesFactory: @Sendable (String) -> OpenResponsesLanguageModel

    init(responses: @escaping @Sendable (String) -> OpenResponsesLanguageModel) {
        self.responsesFactory = responses
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV3 {
        responsesFactory(modelId)
    }

    public func languageModel(_ modelId: String) throws -> any LanguageModelV3 {
        try languageModel(modelId: modelId)
    }

    public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
        throw NoSuchModelError(modelId: modelId, modelType: .textEmbeddingModel)
    }

    public func imageModel(modelId: String) throws -> any ImageModelV3 {
        throw NoSuchModelError(modelId: modelId, modelType: .imageModel)
    }
}

public func createOpenResponses(options: OpenResponsesProviderSettings) -> OpenResponsesProvider {
    let providerName = options.name

    let headersClosure: @Sendable () -> [String: String] = {
        let apiKeyHeader: [String: String?] = options.apiKey.map { ["Authorization": "Bearer \($0)"] } ?? [:]
        let merged = combineHeaders(apiKeyHeader, options.headers?.mapValues { Optional($0) })
        return withUserAgentSuffix(merged, "ai-sdk/open-responses/\(OPEN_RESPONSES_VERSION)")
    }

    let responsesFactory: @Sendable (String) -> OpenResponsesLanguageModel = { modelId in
        OpenResponsesLanguageModel(
            modelId: modelId,
            config: OpenResponsesConfig(
                provider: "\(providerName).responses",
                url: options.url,
                headers: headersClosure,
                fetch: options.fetch,
                generateId: generateID
            )
        )
    }

    return OpenResponsesProvider(responses: responsesFactory)
}

