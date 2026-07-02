import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Speech model types and type aliases.

 Port of `@ai-sdk/ai/src/types/speech-model.ts`.

 Provides type aliases for working with text-to-speech models in the AI SDK Core functions.
 */

/**
 Speech model that is used by the AI SDK Core functions.

 Can be one of:
 - A string identifier (model ID that will be resolved via the default/global provider)
 - A `SpeechModelV4` protocol implementation
 - A `SpeechModelV3` protocol implementation
 - A `SpeechModelV2` protocol implementation

 TypeScript equivalent: `string | SpeechModelV4 | SpeechModelV3 | SpeechModelV2`
 */
public enum SpeechModel: Sendable {
    /// Model identifier string (will be resolved via the global/default provider).
    case string(String)

    /// Speech model V4 implementation.
    case v4(any SpeechModelV4)

    /// Speech model V3 implementation.
    case v3(any SpeechModelV3)

    /// Speech model V2 implementation.
    case v2(any SpeechModelV2)
}

/**
 Warning from the model provider for this call.

 The call will proceed, but e.g. some settings might not be supported,
 which can lead to suboptimal results.

 Type alias for `SharedV4Warning` from the Provider package.
 */
public typealias SpeechWarning = SharedV4Warning
