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
    previousResponseId: String? = nil,
    promptCacheKey: String? = nil,
    reasoningEffort: String? = nil,
    reasoningSummary: String? = nil,
    textVerbosity: String? = nil,
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
      previousResponseId: previousResponseId,
      promptCacheKey: promptCacheKey,
      reasoningEffort: reasoningEffort,
      reasoningSummary: reasoningSummary,
      textVerbosity: textVerbosity,
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
    previousResponseId: String? = nil,
    promptCacheKey: String? = nil,
    reasoningEffort: String? = nil,
    reasoningSummary: String? = nil,
    textVerbosity: String? = nil,
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
      previousResponseId: previousResponseId,
      promptCacheKey: promptCacheKey,
      reasoningEffort: reasoningEffort,
      reasoningSummary: reasoningSummary,
      textVerbosity: textVerbosity,
      parallelToolCalls: parallelToolCalls,
      maxToolCalls: maxToolCalls,
      metadata: metadata,
      extra: extra
    )
  }
}
