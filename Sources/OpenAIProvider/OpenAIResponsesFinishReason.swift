import AISDKProvider

@inline(__always)
func mapOpenAIResponsesFinishReason(
    finishReason: String?,
    hasFunctionCall: Bool
) -> LanguageModelV3FinishReason {
    switch finishReason {
    case nil:
        return hasFunctionCall ? .toolCalls : .stop
    case "max_output_tokens":
        return .length
    case "content_filter":
        return .contentFilter
    default:
        return hasFunctionCall ? .toolCalls : .other
    }
}
