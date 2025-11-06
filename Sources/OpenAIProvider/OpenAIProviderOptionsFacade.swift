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
    if let previousResponseId {
      inner["previousResponseId"] = JSONValue.string(previousResponseId)
    }
    if let promptCacheKey {
      inner["promptCacheKey"] = JSONValue.string(promptCacheKey)
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
