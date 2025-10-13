import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Embedding model types and type aliases.

 Port of `@ai-sdk/ai/src/types/embedding-model.ts`.

 Provides type aliases for working with embedding models in the AI SDK Core functions.
 */

/**
 Embedding model that is used by the AI SDK Core functions.

 Can be one of:
 - A string identifier (model ID that will be resolved via registry)
 - An `EmbeddingModelV3` protocol implementation
 - An `EmbeddingModelV2` protocol implementation

 TypeScript equivalent: `string | EmbeddingModelV3<VALUE> | EmbeddingModelV2<VALUE>`
 */
public enum EmbeddingModel<VALUE: Sendable>: Sendable {
    /// Model identifier string (will be resolved via registry)
    case string(String)

    /// Embedding model V3 implementation
    case v3(any EmbeddingModelV3<VALUE>)

    /// Embedding model V2 implementation
    case v2(any EmbeddingModelV2<VALUE>)
}

/**
 Embedding vector.

 Type alias for `EmbeddingModelV3Embedding` from the Provider package.
 */
public typealias Embedding = EmbeddingModelV3Embedding
