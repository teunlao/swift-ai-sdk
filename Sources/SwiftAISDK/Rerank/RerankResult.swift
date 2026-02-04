import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 The result of a `rerank` call.

 Port of `@ai-sdk/ai/src/rerank/rerank-result.ts`.
 */
public protocol RerankResult: Sendable {
    associatedtype Value: Sendable

    /// The original documents that were reranked.
    var originalDocuments: [Value] { get }

    /// Reranked documents (sorted by relevance score in descending order).
    var rerankedDocuments: [Value] { get }

    /// Ranking entries (sorted by relevance score in descending order).
    var ranking: [RerankRanking<Value>] { get }

    /// Optional provider-specific metadata.
    var providerMetadata: ProviderMetadata? { get }

    /// Raw response information.
    var response: RerankResponse { get }
}

/// A single reranking entry.
public struct RerankRanking<Value: Sendable>: Sendable {
    /// Index of the original document in the input list.
    public let originalIndex: Int

    /// Relevance score for the document.
    public let score: Double

    /// The reranked document.
    public let document: Value

    public init(originalIndex: Int, score: Double, document: Value) {
        self.originalIndex = originalIndex
        self.score = score
        self.document = document
    }
}

/// Response information for a rerank call.
public struct RerankResponse: @unchecked Sendable, Equatable {
    /// ID for the generated response if the provider sends one.
    public let id: String?

    /// Timestamp of the generated response.
    public let timestamp: Date

    /// The ID of the model that was used to generate the response.
    public let modelId: String

    /// Response headers.
    public let headers: [String: String]?

    /// Response body.
    /// Marked @unchecked Sendable to match TypeScript's unknown type.
    public let body: Any?

    public init(
        id: String? = nil,
        timestamp: Date,
        modelId: String,
        headers: [String: String]? = nil,
        body: Any? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.modelId = modelId
        self.headers = headers
        self.body = body
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id &&
            lhs.timestamp == rhs.timestamp &&
            lhs.modelId == rhs.modelId &&
            lhs.headers == rhs.headers
        // NOTE: We intentionally do not compare `body` (unknown/Any) for Equatable parity.
    }
}

/**
 Default implementation of `RerankResult`.

 Mirrors the upstream `DefaultRerankResult` class.
 */
public final class DefaultRerankResult<Value: Sendable>: RerankResult {
    public let originalDocuments: [Value]
    public let ranking: [RerankRanking<Value>]
    public let providerMetadata: ProviderMetadata?
    public let response: RerankResponse

    public init(
        originalDocuments: [Value],
        ranking: [RerankRanking<Value>],
        providerMetadata: ProviderMetadata? = nil,
        response: RerankResponse
    ) {
        self.originalDocuments = originalDocuments
        self.ranking = ranking
        self.providerMetadata = providerMetadata
        self.response = response
    }

    public var rerankedDocuments: [Value] {
        ranking.map(\.document)
    }
}
