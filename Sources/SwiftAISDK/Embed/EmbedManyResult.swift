import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 The result of an `embedMany` call.

 Port of `@ai-sdk/ai/src/embed/embed-many-result.ts`.
 */
public protocol EmbedManyResult: Sendable {
    associatedtype Value: Sendable

    /// Values that were embedded.
    var values: [Value] { get }

    /// Embeddings in the same order as `values`.
    var embeddings: [Embedding] { get }

    /// Token usage aggregated across all calls.
    var usage: EmbeddingModelUsage { get }

    /// Provider-specific metadata, if any.
    var providerMetadata: ProviderMetadata? { get }

    /// Raw response information for each call, if available.
    var responses: [EmbeddingModelV3ResponseInfo?]? { get }
}

/**
 Default implementation of `EmbedManyResult`.

 Mirrors the upstream `DefaultEmbedManyResult` class.
 */
public final class DefaultEmbedManyResult<Value: Sendable>: EmbedManyResult {
    public let values: [Value]
    public let embeddings: [Embedding]
    public let usage: EmbeddingModelUsage
    public let providerMetadata: ProviderMetadata?
    public let responses: [EmbeddingModelV3ResponseInfo?]?

    public init(
        values: [Value],
        embeddings: [Embedding],
        usage: EmbeddingModelUsage,
        providerMetadata: ProviderMetadata? = nil,
        responses: [EmbeddingModelV3ResponseInfo?]? = nil
    ) {
        self.values = values
        self.embeddings = embeddings
        self.usage = usage
        self.providerMetadata = providerMetadata
        self.responses = responses
    }
}
