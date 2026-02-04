import AISDKProvider

func mapGroqFinishReason(_ finishReason: String?) -> LanguageModelV3FinishReason.Unified {
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
