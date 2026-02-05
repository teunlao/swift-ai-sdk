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
 */
public struct LanguageModelUsage: Sendable, Equatable, Codable {
    public struct InputTokenDetails: Sendable, Equatable, Codable {
        /// The number of non-cached input (prompt) tokens used.
        public let noCacheTokens: Int?

        /// The number of cached input (prompt) tokens read.
        public let cacheReadTokens: Int?

        /// The number of cached input (prompt) tokens written.
        public let cacheWriteTokens: Int?

        public init(
            noCacheTokens: Int? = nil,
            cacheReadTokens: Int? = nil,
            cacheWriteTokens: Int? = nil
        ) {
            self.noCacheTokens = noCacheTokens
            self.cacheReadTokens = cacheReadTokens
            self.cacheWriteTokens = cacheWriteTokens
        }
    }

    public struct OutputTokenDetails: Sendable, Equatable, Codable {
        /// The number of text tokens used.
        public let textTokens: Int?

        /// The number of reasoning tokens used.
        public let reasoningTokens: Int?

        public init(
            textTokens: Int? = nil,
            reasoningTokens: Int? = nil
        ) {
            self.textTokens = textTokens
            self.reasoningTokens = reasoningTokens
        }
    }

    /// The total number of input (prompt) tokens used.
    public let inputTokens: Int?

    /// Detailed information about the input tokens.
    public let inputTokenDetails: InputTokenDetails

    /// The number of total output (completion) tokens used.
    public let outputTokens: Int?

    /// Detailed information about the output tokens.
    public let outputTokenDetails: OutputTokenDetails

    /// The total number of tokens used.
    public let totalTokens: Int?

    /// Raw usage information from the provider.
    public let raw: JSONObject?

    /// @deprecated Use `outputTokenDetails.reasoningTokens` instead.
    @available(*, deprecated, message: "Use outputTokenDetails.reasoningTokens instead.")
    public let reasoningTokens: Int?

    /// @deprecated Use `inputTokenDetails.cacheReadTokens` instead.
    @available(*, deprecated, message: "Use inputTokenDetails.cacheReadTokens instead.")
    public let cachedInputTokens: Int?

    public init(
        inputTokens: Int? = nil,
        inputTokenDetails: InputTokenDetails = .init(),
        outputTokens: Int? = nil,
        outputTokenDetails: OutputTokenDetails = .init(),
        totalTokens: Int? = nil,
        raw: JSONObject? = nil,
        reasoningTokens: Int? = nil,
        cachedInputTokens: Int? = nil
    ) {
        self.inputTokens = inputTokens
        self.inputTokenDetails = inputTokenDetails
        self.outputTokens = outputTokens
        self.outputTokenDetails = outputTokenDetails
        self.totalTokens = totalTokens
        self.raw = raw
        self.reasoningTokens = reasoningTokens
        self.cachedInputTokens = cachedInputTokens
    }
}

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
 Usage information for an image model call.

 Type alias for `ImageModelV3Usage` from the Provider package.
 */
public typealias ImageModelUsage = ImageModelV3Usage

/**
 Convert provider-level usage into AI-level usage.
 */
public func asLanguageModelUsage(_ usage: LanguageModelV3Usage) -> LanguageModelUsage {
    let rawObject: JSONObject?
    if let raw = usage.raw, case .object(let object) = raw {
        rawObject = object
    } else {
        rawObject = nil
    }

    return LanguageModelUsage(
        inputTokens: usage.inputTokens.total,
        inputTokenDetails: .init(
            noCacheTokens: usage.inputTokens.noCache,
            cacheReadTokens: usage.inputTokens.cacheRead,
            cacheWriteTokens: usage.inputTokens.cacheWrite
        ),
        outputTokens: usage.outputTokens.total,
        outputTokenDetails: .init(
            textTokens: usage.outputTokens.text,
            reasoningTokens: usage.outputTokens.reasoning
        ),
        totalTokens: addTokenCounts(usage.inputTokens.total, usage.outputTokens.total),
        raw: rawObject,
        reasoningTokens: usage.outputTokens.reasoning,
        cachedInputTokens: usage.inputTokens.cacheRead
    )
}

/**
 Create a `LanguageModelUsage` where all token fields are `nil`.
 */
public func createNullLanguageModelUsage() -> LanguageModelUsage {
    return LanguageModelUsage()
}

/**
 Adds two `LanguageModelUsage` values together.

 Combines token counts from two usage records, properly handling optional values.
 If both token counts are nil, the result is nil. Otherwise, nil values are treated as 0.
 */
public func addLanguageModelUsage(
    _ usage1: LanguageModelUsage,
    _ usage2: LanguageModelUsage
) -> LanguageModelUsage {
    return LanguageModelUsage(
        inputTokens: addTokenCounts(usage1.inputTokens, usage2.inputTokens),
        inputTokenDetails: .init(
            noCacheTokens: addTokenCounts(usage1.inputTokenDetails.noCacheTokens, usage2.inputTokenDetails.noCacheTokens),
            cacheReadTokens: addTokenCounts(usage1.inputTokenDetails.cacheReadTokens, usage2.inputTokenDetails.cacheReadTokens),
            cacheWriteTokens: addTokenCounts(usage1.inputTokenDetails.cacheWriteTokens, usage2.inputTokenDetails.cacheWriteTokens)
        ),
        outputTokens: addTokenCounts(usage1.outputTokens, usage2.outputTokens),
        outputTokenDetails: .init(
            textTokens: addTokenCounts(usage1.outputTokenDetails.textTokens, usage2.outputTokenDetails.textTokens),
            reasoningTokens: addTokenCounts(usage1.outputTokenDetails.reasoningTokens, usage2.outputTokenDetails.reasoningTokens)
        ),
        totalTokens: addTokenCounts(usage1.totalTokens, usage2.totalTokens),
        raw: nil,
        reasoningTokens: addTokenCounts(usage1.reasoningTokens, usage2.reasoningTokens),
        cachedInputTokens: addTokenCounts(usage1.cachedInputTokens, usage2.cachedInputTokens)
    )
}

/**
 Adds two `ImageModelUsage` values together.

 Mirrors upstream `addImageModelUsage` behavior.
 */
public func addImageModelUsage(
    _ usage1: ImageModelUsage,
    _ usage2: ImageModelUsage
) -> ImageModelUsage {
    ImageModelUsage(
        inputTokens: addTokenCounts(usage1.inputTokens, usage2.inputTokens),
        outputTokens: addTokenCounts(usage1.outputTokens, usage2.outputTokens),
        totalTokens: addTokenCounts(usage1.totalTokens, usage2.totalTokens)
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
