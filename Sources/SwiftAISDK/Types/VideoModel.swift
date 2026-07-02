import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Video model types and type aliases.

 Port of `@ai-sdk/ai/src/types/video-model.ts`.
 */

/**
 Video model that is used by the AI SDK Core functions.

 Can be one of:
 - A string identifier (model ID that will be resolved via the default/global provider)
 - A `VideoModelV4` protocol implementation
 - A `VideoModelV3` protocol implementation

 TypeScript equivalent: `string | Experimental_VideoModelV4 | Experimental_VideoModelV3`
 */
public enum VideoModel: Sendable {
    /// Model identifier string (will be resolved via the global/default provider).
    case string(String)

    /// Video model V4 implementation.
    case v4(any VideoModelV4)

    /// Video model V3 implementation.
    case v3(any VideoModelV3)
}

/**
 Warning from the model provider for this call.

 Type alias for `SharedV4Warning` from the Provider package.
 */
public typealias VideoGenerationWarning = SharedV4Warning

/**
 Provider metadata returned from a video generation call.

 Type alias for `SharedV4ProviderMetadata` from the Provider package.
 */
public typealias VideoModelProviderMetadata = SharedV4ProviderMetadata
