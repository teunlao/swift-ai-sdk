import AISDKProvider

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/huggingface/src/responses/map-huggingface-responses-finish-reason.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

func mapHuggingFaceResponsesFinishReason(_ reason: String?) -> LanguageModelV3FinishReason.Unified {
    switch reason {
    case "stop":
        return .stop
    case "length":
        return .length
    case "content_filter":
        return .contentFilter
    case "tool_calls":
        return .toolCalls
    case "error":
        return .error
    default:
        return .other
    }
}
