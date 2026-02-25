import AISDKProvider

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/open-responses/src/responses/map-open-responses-finish-reason.ts
// Upstream commit: 73d5c59
//===----------------------------------------------------------------------===//

public func mapOpenResponsesFinishReason(
    finishReason: String?,
    hasToolCalls: Bool
) -> LanguageModelV3FinishReason.Unified {
    switch finishReason {
    case nil:
        return hasToolCalls ? .toolCalls : .stop
    case "max_output_tokens":
        return .length
    case "content_filter":
        return .contentFilter
    default:
        return hasToolCalls ? .toolCalls : .other
    }
}

