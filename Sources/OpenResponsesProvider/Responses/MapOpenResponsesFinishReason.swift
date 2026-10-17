import AISDKProvider

func mapOpenResponsesFinishReason(finishReason: String?, hasToolCalls: Bool) -> LanguageModelV4FinishReason.Unified {
    switch finishReason {
    case nil: return hasToolCalls ? .toolCalls : .stop
    case "max_output_tokens": return .length
    case "content_filter": return .contentFilter
    default: return hasToolCalls ? .toolCalls : .other
    }
}
