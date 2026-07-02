/**
 Usage information for an image model call.

 Port of `@ai-sdk/provider/src/image-model/v4/image-model-v4-usage.ts`.
 */
public struct ImageModelV4Usage: Sendable, Codable, Equatable {
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let totalTokens: Int?

    public init(inputTokens: Int? = nil, outputTokens: Int? = nil, totalTokens: Int? = nil) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
    }
}
