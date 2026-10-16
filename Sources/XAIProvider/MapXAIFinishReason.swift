import AISDKProvider

/// Maps xAI finish reasons to LanguageModelV4 finish reasons.
/// Mirrors `packages/xai/src/map-xai-finish-reason.ts`.
public func mapXaiFinishReason(_ finishReason: String?) -> LanguageModelV4FinishReason.Unified {
    switch finishReason {
    case "stop":
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
