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
 - An `EmbeddingModelV4` protocol implementation
 - An `EmbeddingModelV3` protocol implementation
 - An `EmbeddingModelV2` protocol implementation

 TypeScript equivalent: `string | EmbeddingModelV4 | EmbeddingModelV3 | EmbeddingModelV2<string>`
 */
public enum EmbeddingModel: Sendable {
    /// Model identifier string (will be resolved via registry)
    case string(String)

    /// Embedding model V4 implementation
    case v4(any EmbeddingModelV4)

    /// Embedding model V3 implementation
    case v3(any EmbeddingModelV3<String>)

    /// Embedding model V2 implementation
    case v2(any EmbeddingModelV2<String>)
}

/**
 Embedding vector.

 Type alias for `EmbeddingModelV4Embedding` from the Provider package.
 */
public typealias Embedding = EmbeddingModelV4Embedding
