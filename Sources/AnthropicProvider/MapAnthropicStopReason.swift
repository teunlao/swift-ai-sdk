import AISDKProvider

public func mapAnthropicStopReason(
    finishReason: String?,
    isJsonResponseFromTool: Bool = false
) -> LanguageModelV3FinishReason {
    switch finishReason {
    case "pause_turn", "end_turn", "stop_sequence":
        return .stop
    case "refusal":
        return .contentFilter
    case "tool_use":
        return isJsonResponseFromTool ? .stop : .toolCalls
    case "max_tokens":
        return .length
    default:
        return .unknown
    }
}
