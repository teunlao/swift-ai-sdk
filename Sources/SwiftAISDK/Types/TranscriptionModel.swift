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

 Type alias for `TranscriptionModelV3` protocol from the Provider package.

 - Note: TypeScript type `TranscriptionModelV3` is represented as `any TranscriptionModelV3` in Swift
         to support any conforming implementation.
 */
public typealias TranscriptionModel = any TranscriptionModelV3

/**
 Warning from the model provider for this call.

 The call will proceed, but e.g. some settings might not be supported,
 which can lead to suboptimal results.

 Type alias for `SharedV3Warning` from the Provider package.
 */
public typealias TranscriptionWarning = SharedV3Warning
