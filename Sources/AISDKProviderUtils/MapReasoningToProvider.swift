import Foundation
import AISDKProvider

private let defaultReasoningBudgetPercentages: [LanguageModelV4ReasoningEffort: Double] = [
    .minimal: 0.02,
    .low: 0.1,
    .medium: 0.3,
    .high: 0.6,
    .xhigh: 0.9
]

/**
 Checks whether a reasoning setting should be forwarded to a provider.

 Swift port of `@ai-sdk/provider-utils/src/map-reasoning-to-provider.ts`
 `isCustomReasoning`.
 */
public func isCustomReasoning(_ reasoning: LanguageModelV4ReasoningEffort) -> Bool {
    reasoning != .providerDefault
}

public func isCustomReasoning(_ reasoning: LanguageModelV4ReasoningEffort?) -> Bool {
    guard let reasoning else {
        return false
    }
    return isCustomReasoning(reasoning)
}

/**
 Maps a top-level reasoning level to a provider-specific effort string.

 Adds the upstream compatibility or unsupported warning when the model does not
 support the exact top-level reasoning level.
 */
public func mapReasoningToProviderEffort(
    reasoning: LanguageModelV4ReasoningEffort,
    effortMap: [LanguageModelV4ReasoningEffort: String],
    warnings: inout [SharedV4Warning]
) -> String? {
    guard let mapped = effortMap[reasoning] else {
        warnings.append(.unsupported(
            feature: "reasoning",
            details: #"reasoning "\#(reasoning.rawValue)" is not supported by this model."#
        ))
        return nil
    }

    if mapped != reasoning.rawValue {
        warnings.append(.compatibility(
            feature: "reasoning",
            details: #"reasoning "\#(reasoning.rawValue)" is not directly supported by this model. mapped to effort "\#(mapped)"."#
        ))
    }

    return mapped
}

/**
 Maps a top-level reasoning level to an absolute provider token budget.

 The calculated budget matches upstream: percentage of max output tokens,
 rounded, then clamped to the configured minimum and maximum.
 */
public func mapReasoningToProviderBudget(
    reasoning: LanguageModelV4ReasoningEffort,
    maxOutputTokens: Int,
    maxReasoningBudget: Int,
    minReasoningBudget: Int = 1024,
    budgetPercentages: [LanguageModelV4ReasoningEffort: Double]? = nil,
    warnings: inout [SharedV4Warning]
) -> Int? {
    let percentages = budgetPercentages ?? defaultReasoningBudgetPercentages

    guard let percentage = percentages[reasoning] else {
        warnings.append(.unsupported(
            feature: "reasoning",
            details: #"reasoning "\#(reasoning.rawValue)" is not supported by this model."#
        ))
        return nil
    }

    let rawBudget = Int((Double(maxOutputTokens) * percentage).rounded())
    return min(maxReasoningBudget, max(minReasoningBudget, rawBudget))
}
