import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Converts xAI responses usage info into unified usage representation.
/// Mirrors `packages/xai/src/responses/convert-xai-responses-usage.ts`.
func convertXaiResponsesUsage(_ usage: XAIResponsesUsage) -> LanguageModelV3Usage {
    let cacheReadTokens = usage.inputTokensDetails?.cachedTokens ?? 0
    let reasoningTokens = usage.outputTokensDetails?.reasoningTokens ?? 0

    let inputTokensIncludesCached = cacheReadTokens <= usage.inputTokens

    let totalInputTokens = inputTokensIncludesCached
        ? usage.inputTokens
        : usage.inputTokens + cacheReadTokens

    let noCacheInputTokens = inputTokensIncludesCached
        ? usage.inputTokens - cacheReadTokens
        : usage.inputTokens

    return LanguageModelV3Usage(
        inputTokens: .init(
            total: totalInputTokens,
            noCache: noCacheInputTokens,
            cacheRead: cacheReadTokens,
            cacheWrite: nil
        ),
        outputTokens: .init(
            total: usage.outputTokens,
            text: usage.outputTokens - reasoningTokens,
            reasoning: reasoningTokens
        ),
        raw: try? JSONEncoder().encodeToJSONValue(usage)
    )
}

private extension JSONEncoder {
    func encodeToJSONValue<T: Encodable>(_ value: T) throws -> JSONValue {
        let data = try encode(value)
        let raw = try JSONSerialization.jsonObject(with: data, options: [])
        return try jsonValue(from: raw)
    }
}
