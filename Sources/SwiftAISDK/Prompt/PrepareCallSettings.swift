import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Validated language model call options.
public typealias PreparedCallSettings = LanguageModelCallOptions

/**
 Validates call settings.

 Port of `@ai-sdk/ai/src/prompt/prepare-language-model-call-options.ts`.

 - Throws: `InvalidArgumentError` when `maxOutputTokens` is below 1.
 */
public func prepareCallSettings(
    maxOutputTokens: Int? = nil,
    temperature: Double? = nil,
    topP: Double? = nil,
    topK: Int? = nil,
    presencePenalty: Double? = nil,
    frequencyPenalty: Double? = nil,
    stopSequences: [String]? = nil,
    seed: Int? = nil,
    reasoning: LanguageModelV4ReasoningEffort? = nil
) throws -> LanguageModelCallOptions {
    try LanguageModelCallOptions(
        maxOutputTokens: maxOutputTokens,
        temperature: temperature,
        topP: topP,
        topK: topK,
        presencePenalty: presencePenalty,
        frequencyPenalty: frequencyPenalty,
        stopSequences: stopSequences,
        seed: seed,
        reasoning: reasoning
    ).prepared()
}

extension CallSettings {
    /// The language model call options of these settings.
    public var languageModelCallOptions: LanguageModelCallOptions {
        LanguageModelCallOptions(
            maxOutputTokens: maxOutputTokens,
            temperature: temperature,
            topP: topP,
            topK: topK,
            presencePenalty: presencePenalty,
            frequencyPenalty: frequencyPenalty,
            stopSequences: stopSequences,
            seed: seed,
            reasoning: reasoning
        )
    }
}
