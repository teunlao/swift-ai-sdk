import AISDKProvider

enum OpenAICompletionFinishReasonMapper {
    static func map(_ value: String?) -> LanguageModelV3FinishReason.Unified {
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
            return .other
        default:
            return .other
        }
    }

    static func mapV4(_ value: String?) -> LanguageModelV4FinishReason.Unified {
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
            return .other
        default:
            return .other
        }
    }
}
