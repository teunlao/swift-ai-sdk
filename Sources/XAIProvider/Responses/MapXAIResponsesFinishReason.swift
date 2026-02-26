import Foundation
import AISDKProvider

/// Maps xAI responses status to unified finish reason.
/// Mirrors `packages/xai/src/responses/map-xai-responses-finish-reason.ts`.
func mapXaiResponsesFinishReason(_ finishReason: String?) -> LanguageModelV3FinishReason.Unified {
    switch finishReason {
    case "stop", "completed":
        return .stop
    case "length":
        return .length
    case "tool_calls", "function_call":
        return .toolCalls
    case "content_filter":
        return .contentFilter
    default:
        return .other
    }
}

