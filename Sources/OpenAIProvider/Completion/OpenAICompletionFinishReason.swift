import AISDKProvider

enum OpenAICompletionFinishReasonMapper {
    static func map(_ value: String?) -> LanguageModelV3FinishReason {
        switch value {
        case "stop":
            return .stop
        case "length":
            return .length
        case "content_filter":
            return .contentFilter
        case "function_call", "tool_calls":
            return .toolCalls
        case .none:
            return .unknown
        default:
            return .unknown
        }
    }
}
