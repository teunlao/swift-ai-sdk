/**
 Provider not found error.

 Port of `@ai-sdk/ai/src/registry/no-such-provider-error.ts`.

 Thrown when a requested provider is not found in the registry.
 */
public struct NoSuchProviderError: AISDKError, Sendable {
    public static let errorDomain = "vercel.ai.error.AI_NoSuchProviderError"

    public let name: String
    public let message: String
    public let cause: (any Error)? = nil
    public let modelId: String
    public let modelType: String
    public let providerId: String
    public let availableProviders: [String]

    public init(
        modelId: String,
        modelType: String,
        providerId: String,
        availableProviders: [String],
        message: String? = nil
    ) {
        self.name = "AI_NoSuchProviderError"
        self.modelId = modelId
        self.modelType = modelType
        self.providerId = providerId
        self.availableProviders = availableProviders
        self.message = message ?? "No such provider: \(providerId) (available providers: \(availableProviders.joined(separator: ", ")))"
    }

    /// Check if an error is an instance of NoSuchProviderError
    public static func isInstance(_ error: any Error) -> Bool {
        SwiftAISDK.hasMarker(error, marker: errorDomain)
    }
}
