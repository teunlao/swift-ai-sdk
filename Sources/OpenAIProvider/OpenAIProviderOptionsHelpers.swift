import Foundation
import AISDKProvider
import AISDKProviderUtils

public extension OpenAIProvider {
  /// Swift-friendly builder for OpenAI Responses provider options.
  /// Returns the same SharedV3ProviderOptions dictionary as manual construction.
  static func responsesOptions(
    include: [OpenAIResponsesIncludeValue] = [],
    serviceTier: String? = nil,
    strictJsonSchema: Bool? = nil,
    store: Bool? = nil,
    user: String? = nil,
    logprobs: OpenAIResponsesLogprobsOption? = nil,
    conversation: String? = nil,
    previousResponseId: String? = nil,
    promptCacheKey: String? = nil,
    promptCacheRetention: String? = nil,
    reasoningEffort: String? = nil,
    reasoningSummary: String? = nil,
    textVerbosity: String? = nil,
    truncation: String? = nil,
    systemMessageMode: OpenAIResponsesSystemMessageMode? = nil,
    forceReasoning: Bool? = nil,
    parallelToolCalls: Bool? = nil,
    maxToolCalls: Int? = nil,
    metadata: JSONValue? = nil,
    extra: [String: JSONValue] = [:]
  ) -> ProviderOptions {
    OpenAIOptionsFacade().responses(
      include: include,
      serviceTier: serviceTier,
      strictJsonSchema: strictJsonSchema,
      store: store,
      user: user,
      logprobs: logprobs,
      conversation: conversation,
      previousResponseId: previousResponseId,
      promptCacheKey: promptCacheKey,
      promptCacheRetention: promptCacheRetention,
      reasoningEffort: reasoningEffort,
      reasoningSummary: reasoningSummary,
      textVerbosity: textVerbosity,
      truncation: truncation,
      systemMessageMode: systemMessageMode,
      forceReasoning: forceReasoning,
      parallelToolCalls: parallelToolCalls,
      maxToolCalls: maxToolCalls,
      metadata: metadata,
      extra: extra
    )
  }

  func responsesOptions(
    include: [OpenAIResponsesIncludeValue] = [],
    serviceTier: String? = nil,
    strictJsonSchema: Bool? = nil,
    store: Bool? = nil,
    user: String? = nil,
    logprobs: OpenAIResponsesLogprobsOption? = nil,
    conversation: String? = nil,
    previousResponseId: String? = nil,
    promptCacheKey: String? = nil,
    promptCacheRetention: String? = nil,
    reasoningEffort: String? = nil,
    reasoningSummary: String? = nil,
    textVerbosity: String? = nil,
    truncation: String? = nil,
    systemMessageMode: OpenAIResponsesSystemMessageMode? = nil,
    forceReasoning: Bool? = nil,
    parallelToolCalls: Bool? = nil,
    maxToolCalls: Int? = nil,
    metadata: JSONValue? = nil,
    extra: [String: JSONValue] = [:]
  ) -> ProviderOptions {
    options.responses(
      include: include,
      serviceTier: serviceTier,
      strictJsonSchema: strictJsonSchema,
      store: store,
      user: user,
      logprobs: logprobs,
      conversation: conversation,
      previousResponseId: previousResponseId,
      promptCacheKey: promptCacheKey,
      promptCacheRetention: promptCacheRetention,
      reasoningEffort: reasoningEffort,
      reasoningSummary: reasoningSummary,
      textVerbosity: textVerbosity,
      truncation: truncation,
      systemMessageMode: systemMessageMode,
      forceReasoning: forceReasoning,
      parallelToolCalls: parallelToolCalls,
      maxToolCalls: maxToolCalls,
      metadata: metadata,
      extra: extra
    )
  }
}
