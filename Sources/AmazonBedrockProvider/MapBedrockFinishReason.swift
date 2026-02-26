import AISDKProvider

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/amazon-bedrock/src/map-bedrock-finish-reason.ts
// Upstream commit: 73d5c5920
//===----------------------------------------------------------------------===//

func mapBedrockFinishReason(
    _ reason: String?,
    isJsonResponseFromTool: Bool = false
) -> LanguageModelV3FinishReason.Unified {
    switch reason {
    case "stop_sequence", "end_turn":
        return .stop
    case "max_tokens":
        return .length
    case "content_filtered", "guardrail_intervened":
        return .contentFilter
    case "tool_use":
        return isJsonResponseFromTool ? .stop : .toolCalls
    default:
        return .other
    }
}
