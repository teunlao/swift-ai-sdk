import Foundation
import AISDKProvider

func mapGoogleGenerativeAIFinishReason(
    finishReason: String?,
    hasToolCalls: Bool
) -> LanguageModelV3FinishReason {
    switch finishReason {
    case "STOP":
        return hasToolCalls ? .toolCalls : .stop
    case "MAX_TOKENS":
        return .length
    case "IMAGE_SAFETY", "RECITATION", "SAFETY", "BLOCKLIST", "PROHIBITED_CONTENT", "SPII":
        return .contentFilter
    case "FINISH_REASON_UNSPECIFIED", "OTHER":
        return .other
    case "MALFORMED_FUNCTION_CALL":
        return .error
    case nil:
        return .unknown
    default:
        return .unknown
    }
}
