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

 Type alias for `ImageModelV3` protocol from the Provider package.

 - Note: TypeScript type `ImageModelV3` is represented as `any ImageModelV3` in Swift
         to support any conforming implementation.
 */
public typealias ImageModel = any ImageModelV3

/**
 Warning from the model provider for this call.

 The call will proceed, but e.g. some settings might not be supported,
 which can lead to suboptimal results.

 Type alias for `ImageModelV3CallWarning` from the Provider package.
 */
public typealias ImageGenerationWarning = ImageModelV3CallWarning

/**
 Metadata from the model provider for this call.

 Type alias for `ImageModelV3ProviderMetadata` from the Provider package.
 */
public typealias ImageModelProviderMetadata = ImageModelV3ProviderMetadata
