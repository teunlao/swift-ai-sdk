import Foundation
import AISDKProvider

enum OpenAIChatFinishReasonMapper {
    static func map(_ value: String?) -> LanguageModelV3FinishReason.Unified {
        guard let value else { return .other }
        switch value {
        case "stop":
            return .stop
        case "length":
            return .length
        case "content_filter":
            return .contentFilter
        case "function_call", "tool_calls":
            return .toolCalls
        default:
            return .other
        }
    }
}
