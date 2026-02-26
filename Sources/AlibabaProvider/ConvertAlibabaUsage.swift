import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/alibaba/src/convert-alibaba-usage.ts
// Ported from packages/openai-compatible/src/chat/convert-openai-compatible-chat-usage.ts
// Upstream commit: 73d5c59
//===----------------------------------------------------------------------===//

public struct AlibabaUsage: Sendable, Equatable, Codable {
    public struct PromptTokensDetails: Sendable, Equatable, Codable {
        public let cachedTokens: Int?
        public let cacheCreationInputTokens: Int?

        public init(
            cachedTokens: Int? = nil,
            cacheCreationInputTokens: Int? = nil
        ) {
            self.cachedTokens = cachedTokens
            self.cacheCreationInputTokens = cacheCreationInputTokens
        }

        private enum CodingKeys: String, CodingKey {
            case cachedTokens = "cached_tokens"
            case cacheCreationInputTokens = "cache_creation_input_tokens"
        }
    }

    public struct CompletionTokensDetails: Sendable, Equatable, Codable {
        public let reasoningTokens: Int?

        public init(reasoningTokens: Int? = nil) {
            self.reasoningTokens = reasoningTokens
        }

        private enum CodingKeys: String, CodingKey {
            case reasoningTokens = "reasoning_tokens"
        }
    }

    public let promptTokens: Int?
    public let completionTokens: Int?
    public let totalTokens: Int?
    public let promptTokensDetails: PromptTokensDetails?
    public let completionTokensDetails: CompletionTokensDetails?

    public init(
        promptTokens: Int? = nil,
        completionTokens: Int? = nil,
        totalTokens: Int? = nil,
        promptTokensDetails: PromptTokensDetails? = nil,
        completionTokensDetails: CompletionTokensDetails? = nil
    ) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.promptTokensDetails = promptTokensDetails
        self.completionTokensDetails = completionTokensDetails
    }

    private enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
        case promptTokensDetails = "prompt_tokens_details"
        case completionTokensDetails = "completion_tokens_details"
    }
}

public func convertAlibabaUsage(
    _ usage: AlibabaUsage?
) -> LanguageModelV3Usage {
    // Base usage mapping mirrors OpenAI-compatible usage conversion.
    let baseUsage: LanguageModelV3Usage
    if let usage {
        let promptTokens = usage.promptTokens ?? 0
        let completionTokens = usage.completionTokens ?? 0
        let cacheReadTokens = usage.promptTokensDetails?.cachedTokens ?? 0
        let reasoningTokens = usage.completionTokensDetails?.reasoningTokens ?? 0

        baseUsage = LanguageModelV3Usage(
            inputTokens: .init(
                total: promptTokens,
                noCache: promptTokens - cacheReadTokens,
                cacheRead: cacheReadTokens,
                cacheWrite: nil
            ),
            outputTokens: .init(
                total: completionTokens,
                text: completionTokens - reasoningTokens,
                reasoning: reasoningTokens
            ),
            raw: encodeToJSONValue(usage)
        )
    } else {
        baseUsage = LanguageModelV3Usage()
    }

    // Alibaba adds cache write tokens and recomputes noCache accordingly.
    let cacheWriteTokens = usage?.promptTokensDetails?.cacheCreationInputTokens ?? 0
    let noCacheTokens = (baseUsage.inputTokens.total ?? 0) - (baseUsage.inputTokens.cacheRead ?? 0) - cacheWriteTokens

    return LanguageModelV3Usage(
        inputTokens: .init(
            total: baseUsage.inputTokens.total,
            noCache: noCacheTokens,
            cacheRead: baseUsage.inputTokens.cacheRead,
            cacheWrite: cacheWriteTokens
        ),
        outputTokens: baseUsage.outputTokens,
        raw: baseUsage.raw
    )
}

private func encodeToJSONValue<T: Encodable>(_ value: T) -> JSONValue? {
    do {
        let data = try JSONEncoder().encode(value)
        let raw = try JSONSerialization.jsonObject(with: data, options: [])
        return try jsonValue(from: raw)
    } catch {
        return nil
    }
}
