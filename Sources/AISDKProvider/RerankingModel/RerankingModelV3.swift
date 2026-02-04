import Foundation

/**
 Specification for a reranking model that implements the reranking model interface version 3.

 Port of `@ai-sdk/provider/src/reranking-model/v3/reranking-model-v3.ts`.
 */
public protocol RerankingModelV3: Sendable {
    /**
     The reranking model must specify which reranking model interface version it implements.

     This allows us to evolve the reranking model interface while retaining backwards
     compatibility. The different implementation versions can be handled as a discriminated union.
     */
    var specificationVersion: String { get }

    /// Provider ID.
    var provider: String { get }

    /// Provider-specific model ID.
    var modelId: String { get }

    /**
     Rerank a list of documents using the query.

     Naming: "do" prefix to prevent accidental direct usage of the method by the user.
     */
    func doRerank(options: RerankingModelV3CallOptions) async throws -> RerankingModelV3DoRerankResult
}

extension RerankingModelV3 {
    public var specificationVersion: String { "v3" }
}

// MARK: - Call Options

/// Options for the reranking model call.
public struct RerankingModelV3CallOptions: Sendable {
    /// Documents to rerank.
    public let documents: Documents

    /// Query to rerank the documents against.
    public let query: String

    /// Optional limit returned documents to the top n documents.
    public let topN: Int?

    /// Abort signal for cancelling the operation.
    public let abortSignal: (@Sendable () -> Bool)?

    /// Additional provider-specific options.
    public let providerOptions: SharedV3ProviderOptions?

    /// Additional HTTP headers to be sent with the request (only applicable for HTTP-based providers).
    public let headers: SharedV3Headers?

    public init(
        documents: Documents,
        query: String,
        topN: Int? = nil,
        abortSignal: (@Sendable () -> Bool)? = nil,
        providerOptions: SharedV3ProviderOptions? = nil,
        headers: SharedV3Headers? = nil
    ) {
        self.documents = documents
        self.query = query
        self.topN = topN
        self.abortSignal = abortSignal
        self.providerOptions = providerOptions
        self.headers = headers
    }

    /// Documents that can be reranked: either texts or JSON objects.
    public enum Documents: Sendable, Equatable {
        case text(values: [String])
        case object(values: [JSONObject])
    }
}

// MARK: - Result Types

/// Result from `RerankingModelV3.doRerank`.
public struct RerankingModelV3DoRerankResult: Sendable {
    /// Ordered list of reranked documents (via index before reranking), sorted by relevance score descending.
    public let ranking: [RerankingModelV3Ranking]

    /// Additional provider-specific metadata.
    public let providerMetadata: SharedV3ProviderMetadata?

    /// Warnings for the call, e.g. unsupported settings.
    public let warnings: [SharedV3Warning]

    /// Optional response information for debugging purposes.
    public let response: RerankingModelV3ResponseInfo?

    public init(
        ranking: [RerankingModelV3Ranking],
        providerMetadata: SharedV3ProviderMetadata? = nil,
        warnings: [SharedV3Warning] = [],
        response: RerankingModelV3ResponseInfo? = nil
    ) {
        self.ranking = ranking
        self.providerMetadata = providerMetadata
        self.warnings = warnings
        self.response = response
    }
}

/// A single reranking entry.
public struct RerankingModelV3Ranking: Sendable, Equatable, Codable {
    /// The index of the document in the original list of documents before reranking.
    public let index: Int

    /// The relevance score of the document after reranking.
    public let relevanceScore: Double

    public init(index: Int, relevanceScore: Double) {
        self.index = index
        self.relevanceScore = relevanceScore
    }
}

/// Optional response information for debugging.
public struct RerankingModelV3ResponseInfo: @unchecked Sendable {
    /// ID for the generated response, if the provider sends one.
    public let id: String?

    /// Timestamp for the start of the generated response, if the provider sends one.
    public let timestamp: Date?

    /// The ID of the response model that was used to generate the response, if the provider sends one.
    public let modelId: String?

    /// Response headers.
    public let headers: SharedV3Headers?

    /// Response body.
    /// Marked @unchecked Sendable to match TypeScript's unknown type.
    public let body: Any?

    public init(
        id: String? = nil,
        timestamp: Date? = nil,
        modelId: String? = nil,
        headers: SharedV3Headers? = nil,
        body: Any? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.modelId = modelId
        self.headers = headers
        self.body = body
    }
}

