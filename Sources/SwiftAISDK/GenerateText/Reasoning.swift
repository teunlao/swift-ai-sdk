import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Converts an array of reasoning parts to a single reasoning text string.

 Port of `@ai-sdk/ai/src/generate-text/reasoning.ts`.
 */

/// Converts reasoning parts to a single text string.
/// Returns nil if the reasoning text is empty.
public func asReasoningText(_ reasoningParts: [ReasoningPart]) -> String? {
    let reasoningText = reasoningParts.map { $0.text }.joined()
    return reasoningText.isEmpty ? nil : reasoningText
}
