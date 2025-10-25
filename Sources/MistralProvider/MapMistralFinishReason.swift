import AISDKProvider

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/mistral/src/map-mistral-finish-reason.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public func mapMistralFinishReason(_ finishReason: String?) -> LanguageModelV3FinishReason {
    switch finishReason {
    case "stop":
        return .stop
    case "length", "model_length":
        return .length
    case "tool_calls":
        return .toolCalls
    case .some:
        return .unknown
    case .none:
        return .unknown
    }
}
