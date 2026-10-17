import AISDKProvider

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/huggingface/src/responses/map-huggingface-responses-finish-reason.ts
// Upstream commit: 8a5233b15b1e69573d63faee6cd0014559252ee4
//===----------------------------------------------------------------------===//

func mapHuggingFaceResponsesFinishReason(_ reason: String?) -> LanguageModelV4FinishReason.Unified {
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
