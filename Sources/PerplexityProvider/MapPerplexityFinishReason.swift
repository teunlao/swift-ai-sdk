import AISDKProvider

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/perplexity/src/map-perplexity-finish-reason.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

@Sendable
func mapPerplexityFinishReason(_ value: String?) -> LanguageModelV3FinishReason.Unified {
    switch value {
    case "stop":
        return .stop
    case "length":
        return .length
    default:
        return .other
    }
}
