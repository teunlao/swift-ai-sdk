import AISDKProvider

/// Maps xAI finish reasons to LanguageModelV3 finish reasons.
/// Mirrors `packages/xai/src/map-xai-finish-reason.ts`.
public func mapXaiFinishReason(_ finishReason: String?) -> LanguageModelV3FinishReason {
    switch finishReason {
    case "stop":
        return .stop
    case "length":
        return .length
    case "tool_calls", "function_call":
        return .toolCalls
    case "content_filter":
        return .contentFilter
    case .some:
        return .unknown
    case .none:
        return .unknown
    }
}
