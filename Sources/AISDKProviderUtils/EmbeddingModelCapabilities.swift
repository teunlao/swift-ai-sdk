import Foundation
import AISDKProvider

/**
 Experimental: an embedding model that exposes the UTF-8 input byte budget of
 one call, so automatic batching can split values that exceed it.

 This capability lives outside the versioned embedding model specification.
 Port of `EMBEDDING_MODEL_MAX_INPUT_BYTES_PER_CALL` from
 `@ai-sdk/provider-utils/src/embedding-model-capabilities.ts`; upstream keys the
 property by a symbol, Swift by conformance.
 */
public protocol EmbeddingModelMaxInputBytesPerCall: Sendable {
    /// Maximum UTF-8 bytes of all values in one call; `nil` when unknown.
    var maxInputBytesPerCall: Int? { get async throws }
}

/// Input of `EmbeddingModelProviderOptionsTransformer.transformProviderOptions`.
public struct EmbeddingModelProviderOptionsTransformerOptions: Sendable {
    public let providerOptions: SharedV4ProviderOptions?
    /// All values of the original request.
    public let values: [String]
    /// Range of `values` sent in this automatically batched call.
    public let startIndex: Int
    public let endIndex: Int

    public init(
        providerOptions: SharedV4ProviderOptions?,
        values: [String],
        startIndex: Int,
        endIndex: Int
    ) {
        self.providerOptions = providerOptions
        self.values = values
        self.startIndex = startIndex
        self.endIndex = endIndex
    }
}

/**
 Experimental: an embedding model that adapts provider options to one call of an
 automatically batched request (e.g. per-value options aligned to the batch).

 This capability lives outside the versioned embedding model specification.
 Port of `EMBEDDING_MODEL_PROVIDER_OPTIONS_TRANSFORMER` from
 `@ai-sdk/provider-utils/src/embedding-model-capabilities.ts`.
 */
public protocol EmbeddingModelProviderOptionsTransformer: Sendable {
    func transformProviderOptions(
        _ options: EmbeddingModelProviderOptionsTransformerOptions
    ) async throws -> SharedV4ProviderOptions?
}
