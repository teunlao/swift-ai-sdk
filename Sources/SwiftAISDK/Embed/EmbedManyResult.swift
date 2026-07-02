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

    /// Provider warnings aggregated across all calls.
    var warnings: [SharedV4Warning] { get }

    /// Provider-specific metadata, if any.
    var providerMetadata: ProviderMetadata? { get }

    /// Raw response information for each call, if available.
    var responses: [EmbeddingModelV4ResponseInfo?]? { get }
}

/**
 Default implementation of `EmbedManyResult`.

 Mirrors the upstream `DefaultEmbedManyResult` class.
 */
public final class DefaultEmbedManyResult<Value: Sendable>: EmbedManyResult {
    public let values: [Value]
    public let embeddings: [Embedding]
    public let usage: EmbeddingModelUsage
    public let warnings: [SharedV4Warning]
    public let providerMetadata: ProviderMetadata?
    public let responses: [EmbeddingModelV4ResponseInfo?]?

    public init(
        values: [Value],
        embeddings: [Embedding],
        usage: EmbeddingModelUsage,
        warnings: [SharedV4Warning] = [],
        providerMetadata: ProviderMetadata? = nil,
        responses: [EmbeddingModelV4ResponseInfo?]? = nil
    ) {
        self.values = values
        self.embeddings = embeddings
        self.usage = usage
        self.warnings = warnings
        self.providerMetadata = providerMetadata
        self.responses = responses
    }
}
