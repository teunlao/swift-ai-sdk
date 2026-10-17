import AISDKProvider

func mapPerplexityFinishReason(status: String?, incompleteReason: String?, hasFunctionCall: Bool) -> LanguageModelV4FinishReason.Unified {
    switch incompleteReason {
    case "max_output_tokens": return .length
    case "content_filter": return .contentFilter
    default: break
    }
    switch status {
    case "completed": return hasFunctionCall ? .toolCalls : .stop
    case "requires_action": return .toolCalls
    case "failed": return .error
    default: return hasFunctionCall ? .toolCalls : .other
    }
}
