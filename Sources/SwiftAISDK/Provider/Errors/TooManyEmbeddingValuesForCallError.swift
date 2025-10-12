/**
 Too many values for a single embedding call.

 Port of `@ai-sdk/provider/src/errors/too-many-embedding-values-for-call-error.ts`.

 Thrown when the number of values to embed exceeds the model's maxEmbeddingsPerCall limit.
 */
public struct TooManyEmbeddingValuesForCallError: AISDKError, @unchecked Sendable {
    public static let errorDomain = "vercel.ai.error.AI_TooManyEmbeddingValuesForCallError"

    public let name = "AI_TooManyEmbeddingValuesForCallError"
    public let message: String
    public let cause: (any Error)? = nil

    public let provider: String
    public let modelId: String
    public let maxEmbeddingsPerCall: Int
    public let values: [Any]

    public init(
        provider: String,
        modelId: String,
        maxEmbeddingsPerCall: Int,
        values: [Any]
    ) {
        self.provider = provider
        self.modelId = modelId
        self.maxEmbeddingsPerCall = maxEmbeddingsPerCall
        self.values = values

        self.message = """
            Too many values for a single embedding call. \
            The \(provider) model "\(modelId)" can only embed up to \
            \(maxEmbeddingsPerCall) values per call, but \(values.count) values were provided.
            """
    }

    /// Check if an error is an instance of TooManyEmbeddingValuesForCallError
    public static func isInstance(_ error: any Error) -> Bool {
        SwiftAISDK.hasMarker(error, marker: errorDomain)
    }
}
