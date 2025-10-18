import AISDKProvider

@inline(__always)
func mapOpenAIResponsesFinishReason(_ value: String?) -> LanguageModelV3FinishReason {
    guard let value else { return .stop }
    switch value {
    case "stop": return .stop
    case "length": return .length
    case "content_filter": return .contentFilter
    case "tool_calls": return .toolCalls
    default: return .other
    }
}
