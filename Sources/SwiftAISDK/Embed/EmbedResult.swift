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

    /// Provider-specific metadata, if any.
    var providerMetadata: ProviderMetadata? { get }

    /// Optional response information returned by the provider.
    var response: EmbeddingModelV3ResponseInfo? { get }
}

/**
 Default implementation of `EmbedResult`.

 Mirrors the upstream `DefaultEmbedResult` class.
 */
public final class DefaultEmbedResult<Value: Sendable>: EmbedResult {
    public let value: Value
    public let embedding: Embedding
    public let usage: EmbeddingModelUsage
    public let providerMetadata: ProviderMetadata?
    public let response: EmbeddingModelV3ResponseInfo?

    public init(
        value: Value,
        embedding: Embedding,
        usage: EmbeddingModelUsage,
        providerMetadata: ProviderMetadata? = nil,
        response: EmbeddingModelV3ResponseInfo? = nil
    ) {
        self.value = value
        self.embedding = embedding
        self.usage = usage
        self.providerMetadata = providerMetadata
        self.response = response
    }
}
