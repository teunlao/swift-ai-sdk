/**
 Usage information for an image model call.

 Port of `@ai-sdk/provider/src/image-model/v3/image-model-v3-usage.ts`.
 */
public struct ImageModelV3Usage: Sendable, Codable, Equatable {
    /// The number of input (prompt) tokens used.
    public let inputTokens: Int?

    /// The number of output tokens used, if reported by the provider.
    public let outputTokens: Int?

    /// The total number of tokens as reported by the provider.
    public let totalTokens: Int?

    public init(
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        totalTokens: Int? = nil
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
    }
}

