import AISDKProvider

public func mapOpenAICompatibleFinishReason(_ finishReason: String?) -> LanguageModelV3FinishReason {
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
        return .unknown
    }
}
