import Foundation

/**
 Specification for a reranking model that implements the reranking model interface version 4.

 Port of `@ai-sdk/provider/src/reranking-model/v4/reranking-model-v4.ts`.
 */
public protocol RerankingModelV4: Sendable {
    var specificationVersion: String { get }
    var provider: String { get }
    var modelId: String { get }

    func doRerank(options: RerankingModelV4CallOptions) async throws -> RerankingModelV4Result
}

extension RerankingModelV4 {
    public var specificationVersion: String { "v4" }
}

public struct RerankingModelV4CallOptions: Sendable {
    public let documents: Documents
    public let query: String
    public let topN: Int?
    public let abortSignal: (@Sendable () -> Bool)?
    public let providerOptions: SharedV4ProviderOptions?
    public let headers: SharedV4Headers?

    public init(
        documents: Documents,
        query: String,
        topN: Int? = nil,
        abortSignal: (@Sendable () -> Bool)? = nil,
        providerOptions: SharedV4ProviderOptions? = nil,
        headers: SharedV4Headers? = nil
    ) {
        self.documents = documents
        self.query = query
        self.topN = topN
        self.abortSignal = abortSignal
        self.providerOptions = providerOptions
        self.headers = headers
    }

    public enum Documents: Sendable, Equatable {
        case text(values: [String])
        case object(values: [JSONObject])
    }
}

public struct RerankingModelV4Result: Sendable {
    public let ranking: [RerankingModelV4Ranking]
    public let providerMetadata: SharedV4ProviderMetadata?
    public let warnings: [SharedV4Warning]
    public let response: RerankingModelV4ResponseInfo?

    public init(
        ranking: [RerankingModelV4Ranking],
        providerMetadata: SharedV4ProviderMetadata? = nil,
        warnings: [SharedV4Warning] = [],
        response: RerankingModelV4ResponseInfo? = nil
    ) {
        self.ranking = ranking
        self.providerMetadata = providerMetadata
        self.warnings = warnings
        self.response = response
    }
}

public struct RerankingModelV4Ranking: Sendable, Equatable, Codable {
    public let index: Int
    public let relevanceScore: Double

    public init(index: Int, relevanceScore: Double) {
        self.index = index
        self.relevanceScore = relevanceScore
    }
}

public struct RerankingModelV4ResponseInfo: @unchecked Sendable {
    public let id: String?
    public let timestamp: Date?
    public let modelId: String?
    public let headers: SharedV4Headers?
    public let body: Any?

    public init(
        id: String? = nil,
        timestamp: Date? = nil,
        modelId: String? = nil,
        headers: SharedV4Headers? = nil,
        body: Any? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.modelId = modelId
        self.headers = headers
        self.body = body
    }
}
