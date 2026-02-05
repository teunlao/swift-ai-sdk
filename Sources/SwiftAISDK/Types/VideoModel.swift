import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Video model types and type aliases.

 Port of `@ai-sdk/ai/src/types/video-model.ts`.
 */

/**
 Video model that is used by the AI SDK Core functions.

 Type alias for `Experimental_VideoModelV3` from the upstream Provider package.
 */
public typealias VideoModel = any VideoModelV3

/**
 Warning from the model provider for this call.

 Type alias for `SharedV3Warning` from the Provider package.
 */
public typealias VideoGenerationWarning = SharedV3Warning

/**
 Provider metadata returned from a video generation call.

 Type alias for `SharedV3ProviderMetadata` from the Provider package.
 */
public typealias VideoModelProviderMetadata = SharedV3ProviderMetadata

