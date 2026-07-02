import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Transcription model types and type aliases.

 Port of `@ai-sdk/ai/src/types/transcription-model.ts`.

 Provides type aliases for working with speech-to-text models in the AI SDK Core functions.
 */

/**
 Transcription model that is used by the AI SDK Core functions.

 Can be one of:
 - A string identifier (model ID that will be resolved via the default/global provider)
 - A `TranscriptionModelV4` protocol implementation
 - A `TranscriptionModelV3` protocol implementation
 - A `TranscriptionModelV2` protocol implementation

 TypeScript equivalent: `string | TranscriptionModelV4 | TranscriptionModelV3 | TranscriptionModelV2`
 */
public enum TranscriptionModel: Sendable {
    /// Model identifier string (will be resolved via the global/default provider).
    case string(String)

    /// Transcription model V4 implementation.
    case v4(any TranscriptionModelV4)

    /// Transcription model V3 implementation.
    case v3(any TranscriptionModelV3)

    /// Transcription model V2 implementation.
    case v2(any TranscriptionModelV2)
}

/**
 Warning from the model provider for this call.

 The call will proceed, but e.g. some settings might not be supported,
 which can lead to suboptimal results.

 Type alias for `SharedV4Warning` from the Provider package.
 */
public typealias TranscriptionWarning = SharedV4Warning
