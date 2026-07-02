import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Image model types and type aliases.

 Port of `@ai-sdk/ai/src/types/image-model.ts`.

 Provides type aliases for working with image generation models in the AI SDK Core functions.
 */

/**
 Image model that is used by the AI SDK Core functions.

 Can be one of:
 - A string identifier (model ID that will be resolved via the default/global provider)
 - An `ImageModelV4` protocol implementation
 - An `ImageModelV3` protocol implementation
 - An `ImageModelV2` protocol implementation

 TypeScript equivalent: `string | ImageModelV4 | ImageModelV3 | ImageModelV2`
 */
public enum ImageModel: Sendable {
    /// Model identifier string (will be resolved via the global/default provider).
    case string(String)

    /// Image model V4 implementation.
    case v4(any ImageModelV4)

    /// Image model V3 implementation.
    case v3(any ImageModelV3)

    /// Image model V2 implementation.
    case v2(any ImageModelV2)
}

/**
 Warning from the model provider for this call.

 The call will proceed, but e.g. some settings might not be supported,
 which can lead to suboptimal results.

 Type alias for `SharedV4Warning` from the Provider package.
 */
public typealias ImageGenerationWarning = SharedV4Warning

/**
 Metadata from the model provider for this call.

 Type alias for `ImageModelV4ProviderMetadata` from the Provider package.
 */
public typealias ImageModelProviderMetadata = ImageModelV4ProviderMetadata
