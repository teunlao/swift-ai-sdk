import Foundation
import AISDKProvider

/**
 Creates an empty language model usage result for unavailable usage data.

 Port of `@ai-sdk/provider-utils/src/create-null-language-model-usage.ts`.
 */
public func createNullLanguageModelUsage() -> LanguageModelV4Usage {
    LanguageModelV4Usage(
        inputTokens: .init(total: nil, noCache: nil, cacheRead: nil, cacheWrite: nil),
        outputTokens: .init(total: nil, text: nil, reasoning: nil),
        raw: nil
    )
}

/**
 Converts common provider response fields into language model response metadata.
 `created` is a Unix timestamp in seconds.

 Port of `@ai-sdk/provider-utils/src/create-language-model-response-metadata.ts`.
 */
public func createLanguageModelResponseMetadata(
    id: String? = nil,
    model: String? = nil,
    created: Double? = nil
) -> LanguageModelV4ResponseMetadata {
    LanguageModelV4ResponseMetadata(
        id: id,
        timestamp: created.map { Date(timeIntervalSince1970: $0) },
        modelId: model
    )
}
