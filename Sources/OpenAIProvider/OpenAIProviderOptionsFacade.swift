import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct OpenAIOptionsFacade: Sendable {
  public init() {}

  public func responses(
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
    var inner: [String: JSONValue] = extra

    if !include.isEmpty {
      inner["include"] = JSONValue.array(include.map { JSONValue.string($0.rawValue) })
    }
    if let serviceTier {
      inner["serviceTier"] = JSONValue.string(serviceTier)
    }
    if let strictJsonSchema {
      inner["strictJsonSchema"] = JSONValue.bool(strictJsonSchema)
    }
    if let store {
      inner["store"] = JSONValue.bool(store)
    }
    if let user {
      inner["user"] = JSONValue.string(user)
    }
    if let conversation {
      inner["conversation"] = JSONValue.string(conversation)
    }
    if let previousResponseId {
      inner["previousResponseId"] = JSONValue.string(previousResponseId)
    }
    if let promptCacheKey {
      inner["promptCacheKey"] = JSONValue.string(promptCacheKey)
    }
    if let promptCacheRetention {
      inner["promptCacheRetention"] = JSONValue.string(promptCacheRetention)
    }
    if let reasoningEffort {
      inner["reasoningEffort"] = JSONValue.string(reasoningEffort)
    }
    if let reasoningSummary {
      inner["reasoningSummary"] = JSONValue.string(reasoningSummary)
    }
    if let textVerbosity {
      inner["textVerbosity"] = JSONValue.string(textVerbosity)
    }
    if let truncation {
      inner["truncation"] = JSONValue.string(truncation)
    }
    if let systemMessageMode {
      let rawMode: String
      switch systemMessageMode {
      case .system:
        rawMode = "system"
      case .developer:
        rawMode = "developer"
      case .remove:
        rawMode = "remove"
      }
      inner["systemMessageMode"] = JSONValue.string(rawMode)
    }
    if let forceReasoning {
      inner["forceReasoning"] = JSONValue.bool(forceReasoning)
    }
    if let parallelToolCalls {
      inner["parallelToolCalls"] = JSONValue.bool(parallelToolCalls)
    }
    if let maxToolCalls {
      inner["maxToolCalls"] = JSONValue.number(Double(maxToolCalls))
    }
    if let metadata {
      inner["metadata"] = metadata
    }
    if let logprobs {
      switch logprobs {
      case .bool(let flag):
        inner["logprobs"] = JSONValue.bool(flag)
      case .number(let value):
        inner["logprobs"] = JSONValue.number(Double(value))
      }
    }

    return ["openai": inner]
  }
}
