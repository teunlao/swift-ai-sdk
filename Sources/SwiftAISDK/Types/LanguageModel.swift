import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Language model types and type aliases.

 Port of `@ai-sdk/ai/src/types/language-model.ts`.

 Provides type aliases and high-level types for working with language models
 in the AI SDK Core functions.
 */

/**
 Language model that is used by the AI SDK Core functions.

 Can be one of:
 - A string identifier (model ID that will be resolved via registry)
 - A `LanguageModelV3` protocol implementation
 - A `LanguageModelV2` protocol implementation

 TypeScript equivalent: `string | LanguageModelV3 | LanguageModelV2`
 */
public enum LanguageModel: Sendable {
    /// Model identifier string (will be resolved via registry)
    case string(String)

    /// Language model V3 implementation
    case v3(LanguageModelV3)

    /// Language model V2 implementation
    case v2(LanguageModelV2)
}

/**
 Reason why a language model finished generating a response.

 Can be one of the following:
 - `stop`: model generated stop sequence
 - `length`: model generated maximum number of tokens
 - `contentFilter`: content filter violation stopped the model
 - `toolCalls`: model triggered tool calls
 - `error`: model stopped because of an error
 - `other`: model stopped for other reasons

 Type alias for the unified finish reason from the Provider package.
 */
public typealias FinishReason = LanguageModelV3FinishReason.Unified

/**
 Warning from the model provider for this call.

 The call will proceed, but e.g. some settings might not be supported,
 which can lead to suboptimal results.

 Type alias for `SharedV3Warning` from the Provider package.
 */
public typealias CallWarning = SharedV3Warning

/**
 A source that has been used as input to generate the response.

 Type alias for `LanguageModelV3Source` from the Provider package.
 */
public typealias Source = LanguageModelV3Source

// Note: ToolChoice is defined in Core/Prompt/PrepareToolsAndToolChoice.swift
// to avoid circular dependencies and keep it close to where it's used.
