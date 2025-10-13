/**
 Extract reasoning content from language model content array.

 Port of `@ai-sdk/ai/src/generate-text/extract-reasoning-content.ts`.

 Filters and concatenates all reasoning parts from the content array,
 joining them with newlines. Returns nil if no reasoning parts are found.
 */

import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Extract reasoning content from language model content array
/// - Parameter content: Array of content parts from the language model
/// - Returns: Concatenated reasoning text joined with newlines, or nil if no reasoning parts found
public func extractReasoningContent(content: [LanguageModelV3Content]) -> String? {
    let reasoningParts = content.compactMap { part -> String? in
        guard case .reasoning(let reasoningPart) = part else {
            return nil
        }
        return reasoningPart.text
    }

    guard !reasoningParts.isEmpty else {
        return nil
    }

    return reasoningParts.joined(separator: "\n")
}
