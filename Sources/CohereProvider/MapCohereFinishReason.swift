import AISDKProvider

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/cohere/src/map-cohere-finish-reason.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

@Sendable
func mapCohereFinishReason(_ value: String?) -> LanguageModelV3FinishReason {
    switch value {
    case "COMPLETE", "STOP_SEQUENCE":
        return .stop
    case "MAX_TOKENS":
        return .length
    case "ERROR":
        return .error
    case "TOOL_CALL":
        return .toolCalls
    default:
        return .unknown
    }
}
