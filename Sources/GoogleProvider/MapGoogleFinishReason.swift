import Foundation
import AISDKProvider

func mapGoogleFinishReason(
    finishReason: String?,
    hasToolCalls: Bool
) -> LanguageModelV4FinishReason.Unified {
    switch finishReason {
    case "STOP":
        return hasToolCalls ? .toolCalls : .stop
    case "MAX_TOKENS", "CONTINUATION":
        return .length
    case "IMAGE_SAFETY", "RECITATION", "SAFETY", "BLOCKLIST", "PROHIBITED_CONTENT", "SPII":
        return .contentFilter
    case "MALFORMED_FUNCTION_CALL":
        return .error
    case "FINISH_REASON_UNSPECIFIED", "OTHER", nil:
        return .other
    default:
        return .other
    }
}
