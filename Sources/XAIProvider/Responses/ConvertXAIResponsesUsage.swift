import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Converts xAI responses usage info into unified usage representation.
/// Mirrors `packages/xai/src/responses/convert-xai-responses-usage.ts`.
func convertXaiResponsesUsage(_ usage: XAIResponsesUsage) -> LanguageModelV4Usage {
    func field(_ key: String, details: String) -> JSONValue? {
        guard case .object(let object) = usage.raw,
              case .object(let values)? = object[details] else { return nil }
        return values[key]
    }
    func count(_ value: Int?, raw: JSONValue?) -> Int? {
        value ?? (raw == nil || raw == .null ? 0 : nil)
    }
    func subtract(_ left: Int?, _ right: Int?) -> Int? {
        guard let left, let right else { return nil }
        let result = left.subtractingReportingOverflow(right)
        return result.overflow ? nil : result.partialValue
    }
    let cacheReadTokens = count(usage.inputTokensDetails?.cachedTokens, raw: field("cached_tokens", details: "input_tokens_details"))
    let reasoningTokens = count(usage.outputTokensDetails?.reasoningTokens, raw: field("reasoning_tokens", details: "output_tokens_details"))

    var totalInputTokens: Int?
    var noCacheInputTokens: Int?
    if let inputTokens = usage.inputTokens, let cacheReadTokens {
        if cacheReadTokens <= inputTokens {
            totalInputTokens = inputTokens
            noCacheInputTokens = subtract(inputTokens, cacheReadTokens)
        } else {
            let result = inputTokens.addingReportingOverflow(cacheReadTokens)
            totalInputTokens = result.overflow ? nil : result.partialValue
            noCacheInputTokens = inputTokens
        }
    }

    return LanguageModelV4Usage(
        inputTokens: .init(
            total: totalInputTokens,
            noCache: noCacheInputTokens,
            cacheRead: cacheReadTokens,
            cacheWrite: nil
        ),
        outputTokens: .init(
            total: usage.outputTokens,
            text: subtract(usage.outputTokens, reasoningTokens),
            reasoning: reasoningTokens
        ),
        raw: usage.raw
    )
}
