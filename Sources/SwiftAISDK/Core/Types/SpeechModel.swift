import Foundation

/**
 Speech model types and type aliases.

 Port of `@ai-sdk/ai/src/types/speech-model.ts`.

 Provides type aliases for working with text-to-speech models in the AI SDK Core functions.
 */

/**
 Speech model that is used by the AI SDK Core functions.

 Type alias for `SpeechModelV3` protocol from the Provider package.

 - Note: TypeScript type `SpeechModelV3` is represented as `any SpeechModelV3` in Swift
         to support any conforming implementation.
 */
public typealias SpeechModel = any SpeechModelV3

/**
 Warning from the model provider for this call.

 The call will proceed, but e.g. some settings might not be supported,
 which can lead to suboptimal results.

 Type alias for `SpeechModelV3CallWarning` from the Provider package.
 */
public typealias SpeechWarning = SpeechModelV3CallWarning
