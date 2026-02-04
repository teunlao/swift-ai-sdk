import Foundation
import AISDKProvider

func mapGoogleGenerativeAIFinishReason(
    finishReason: String?,
    hasToolCalls: Bool
) -> LanguageModelV3FinishReason.Unified {
    switch finishReason {
    case "STOP":
        return hasToolCalls ? .toolCalls : .stop
    case "MAX_TOKENS":
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
