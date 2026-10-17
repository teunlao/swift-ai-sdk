import AISDKProvider

func mapCohereFinishReason(_ value: String?) -> LanguageModelV4FinishReason.Unified {
    switch value {
    case "COMPLETE", "STOP_SEQUENCE": return .stop
    case "MAX_TOKENS": return .length
    case "ERROR": return .error
    case "TOOL_CALL": return .toolCalls
    default: return .other
    }
}
