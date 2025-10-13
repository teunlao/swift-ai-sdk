import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Token usage types and utilities.

 Port of `@ai-sdk/ai/src/types/usage.ts`.

 Provides type aliases and helper functions for tracking token usage
 across different model types.
 */

/**
 Represents the number of tokens used in a prompt and completion.

 Type alias for `LanguageModelV3Usage` from the Provider package.
 */
public typealias LanguageModelUsage = LanguageModelV3Usage

/**
 Represents the number of tokens used in an embedding.

 Note: This will be replaced with EmbeddingModelV3Usage in the future
 (as noted in upstream TODO).
 */
public struct EmbeddingModelUsage: Sendable, Equatable, Codable {
    /// The number of tokens used in the embedding.
    public let tokens: Int

    public init(tokens: Int) {
        self.tokens = tokens
    }
}

/**
 Adds two `LanguageModelUsage` values together.

 Combines token counts from two usage records, properly handling optional values.
 If both token counts are nil, the result is nil. Otherwise, nil values are treated as 0.

 - Parameters:
   - usage1: The first usage record.
   - usage2: The second usage record.
 - Returns: A new usage record with combined token counts.
 */
public func addLanguageModelUsage(
    _ usage1: LanguageModelUsage,
    _ usage2: LanguageModelUsage
) -> LanguageModelUsage {
    return LanguageModelV3Usage(
        inputTokens: addTokenCounts(usage1.inputTokens, usage2.inputTokens),
        outputTokens: addTokenCounts(usage1.outputTokens, usage2.outputTokens),
        totalTokens: addTokenCounts(usage1.totalTokens, usage2.totalTokens),
        reasoningTokens: addTokenCounts(usage1.reasoningTokens, usage2.reasoningTokens),
        cachedInputTokens: addTokenCounts(usage1.cachedInputTokens, usage2.cachedInputTokens)
    )
}

/**
 Adds two optional token counts together.

 If both counts are nil, returns nil.
 Otherwise, treats nil as 0 and returns the sum.

 - Parameters:
   - tokenCount1: The first token count.
   - tokenCount2: The second token count.
 - Returns: The sum of the token counts, or nil if both are nil.
 */
private func addTokenCounts(
    _ tokenCount1: Int?,
    _ tokenCount2: Int?
) -> Int? {
    if tokenCount1 == nil && tokenCount2 == nil {
        return nil
    }
    return (tokenCount1 ?? 0) + (tokenCount2 ?? 0)
}
