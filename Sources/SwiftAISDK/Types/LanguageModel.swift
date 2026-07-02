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
 - A `LanguageModelV4` protocol implementation
 - A `LanguageModelV3` protocol implementation
 - A `LanguageModelV2` protocol implementation

 TypeScript equivalent: `string | LanguageModelV4 | LanguageModelV3 | LanguageModelV2`
 */
public enum LanguageModel: Sendable {
    /// Model identifier string (will be resolved via registry)
    case string(String)

    /// Language model V4 implementation
    case v4(LanguageModelV4)

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

 Type alias for the unified finish reason from the current V4 Provider package.
 */
public typealias FinishReason = LanguageModelV4FinishReason.Unified

/**
 Warning from the model provider for this call.

 The call will proceed, but e.g. some settings might not be supported,
 which can lead to suboptimal results.

 Type alias for `SharedV4Warning` from the Provider package.
 */
public typealias CallWarning = SharedV4Warning

/**
 A source that has been used as input to generate the response.

 Type alias for `LanguageModelV4Source` from the Provider package.
 */
public typealias Source = LanguageModelV4Source

public func asFinishReason(_ reason: LanguageModelV3FinishReason.Unified) -> FinishReason {
    FinishReason(rawValue: reason.rawValue) ?? .other
}

public func asCallWarning(_ warning: SharedV3Warning) -> CallWarning {
    switch warning {
    case let .unsupported(feature, details):
        return .unsupported(feature: feature, details: details)
    case let .compatibility(feature, details):
        return .compatibility(feature: feature, details: details)
    case let .other(message):
        return .other(message: message)
    }
}

public func asSource(_ source: LanguageModelV3Source) -> Source {
    switch source {
    case let .url(id, url, title, providerMetadata):
        return .url(id: id, url: url, title: title, providerMetadata: providerMetadata)
    case let .document(id, mediaType, title, filename, providerMetadata):
        return .document(
            id: id,
            mediaType: mediaType,
            title: title,
            filename: filename,
            providerMetadata: providerMetadata
        )
    }
}

// Note: ToolChoice is defined in Core/Prompt/PrepareToolsAndToolChoice.swift
// to avoid circular dependencies and keep it close to where it's used.
