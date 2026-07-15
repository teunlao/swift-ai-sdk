import AISDKProvider

public func mapOpenAICompatibleFinishReason(_ finishReason: String?) -> LanguageModelV3FinishReason.Unified {
    switch finishReason {
    case "stop":
        return .stop
    case "length":
        return .length
    case "content_filter":
        return .contentFilter
    case "function_call", "tool_calls":
        return .toolCalls
    default:
        return .other
    }
}

public func mapOpenAICompatibleFinishReasonV4(_ finishReason: String?) -> LanguageModelV4FinishReason.Unified {
    switch finishReason {
    case "stop":
        return .stop
    case "length":
        return .length
    case "content_filter":
        return .contentFilter
    case "function_call", "tool_calls":
        return .toolCalls
    default:
        return .other
    }
}
