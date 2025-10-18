import AISDKProvider

@inline(__always)
func mapOpenAIResponsesFinishReason(
    finishReason: String?,
    hasFunctionCall: Bool
) -> LanguageModelV3FinishReason {
    switch finishReason {
    case nil:
        return hasFunctionCall ? .toolCalls : .stop
    case "stop":
        return hasFunctionCall ? .toolCalls : .stop
    case "length", "max_output_tokens":
        return .length
    case "content_filter":
        return .contentFilter
    case "tool_calls":
        return .toolCalls
    default:
        return hasFunctionCall ? .toolCalls : .unknown
    }
}
