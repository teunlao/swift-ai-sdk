import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 The result of an `embed` call.

 Port of `@ai-sdk/ai/src/embed/embed-result.ts`.
 */
public protocol EmbedResult: Sendable {
    associatedtype Value: Sendable

    /// The value that was embedded.
    var value: Value { get }

    /// The embedding of the value.
    var embedding: Embedding { get }

    /// Token usage for the embedding operation.
    var usage: EmbeddingModelUsage { get }

    /// Provider warnings for the embedding operation.
    var warnings: [SharedV4Warning] { get }

    /// Provider-specific metadata, if any.
    var providerMetadata: ProviderMetadata? { get }

    /// Optional response information returned by the provider.
    var response: EmbeddingModelV4ResponseInfo? { get }
}

/**
 Default implementation of `EmbedResult`.

 Mirrors the upstream `DefaultEmbedResult` class.
 */
public final class DefaultEmbedResult<Value: Sendable>: EmbedResult {
    public let value: Value
    public let embedding: Embedding
    public let usage: EmbeddingModelUsage
    public let warnings: [SharedV4Warning]
    public let providerMetadata: ProviderMetadata?
    public let response: EmbeddingModelV4ResponseInfo?

    public init(
        value: Value,
        embedding: Embedding,
        usage: EmbeddingModelUsage,
        warnings: [SharedV4Warning] = [],
        providerMetadata: ProviderMetadata? = nil,
        response: EmbeddingModelV4ResponseInfo? = nil
    ) {
        self.value = value
        self.embedding = embedding
        self.usage = usage
        self.warnings = warnings
        self.providerMetadata = providerMetadata
        self.response = response
    }
}
