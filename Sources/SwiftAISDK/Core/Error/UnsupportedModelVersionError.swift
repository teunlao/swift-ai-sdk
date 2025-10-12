import Foundation

/**
 Error thrown when a model with an unsupported version is used.

 Port of `@ai-sdk/ai/src/error/unsupported-model-version-error.ts`.
 */
public struct UnsupportedModelVersionError: AISDKError, Sendable {
    /// General AI SDK error domain (no specialized marker for this error type)
    public static let errorDomain = "vercel.ai.error"

    public let name = "AI_UnsupportedModelVersionError"
    public let message: String
    public let cause: (any Error)? = nil

    /// The unsupported version string
    public let version: String

    /// The provider name
    public let provider: String

    /// The model ID
    public let modelId: String

    public init(
        version: String,
        provider: String,
        modelId: String
    ) {
        self.version = version
        self.provider = provider
        self.modelId = modelId
        self.message = "Unsupported model version \(version) for provider \"\(provider)\" and model \"\(modelId)\". AI SDK 5 only supports models that implement specification version \"v2\"."
    }
}
