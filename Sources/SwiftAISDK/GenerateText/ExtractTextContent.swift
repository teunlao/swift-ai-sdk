/**
 Extract text content from language model content array.

 Port of `@ai-sdk/ai/src/generate-text/extract-text-content.ts`.

 Filters and concatenates all text parts from the content array,
 returning nil if no text parts are found.
 */

import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Extract text content from language model content array
/// - Parameter content: Array of content parts from the language model
/// - Returns: Concatenated text from all text parts, or nil if no text parts found
public func extractTextContent(content: [LanguageModelV3Content]) -> String? {
    let textParts = content.compactMap { part -> String? in
        guard case .text(let textPart) = part else {
            return nil
        }
        return textPart.text
    }

    guard !textParts.isEmpty else {
        return nil
    }

    return textParts.joined()
}
