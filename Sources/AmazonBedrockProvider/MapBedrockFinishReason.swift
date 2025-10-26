import AISDKProvider

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/amazon-bedrock/src/map-bedrock-finish-reason.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

func mapBedrockFinishReason(_ reason: String?) -> LanguageModelV3FinishReason {
    switch reason {
    case "stop_sequence", "end_turn":
        return .stop
    case "max_tokens":
        return .length
    case "content_filtered", "guardrail_intervened":
        return .contentFilter
    case "tool_use":
        return .toolCalls
    default:
        return .unknown
    }
}
