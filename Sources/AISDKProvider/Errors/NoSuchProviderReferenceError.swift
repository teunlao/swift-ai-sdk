/**
 Provider reference not found error.

 Swift port of TypeScript `NoSuchProviderReferenceError`.
 */
public struct NoSuchProviderReferenceError: AISDKError, Sendable {
    public static let errorDomain = "vercel.ai.error.AI_NoSuchProviderReferenceError"

    public let name = "AI_NoSuchProviderReferenceError"
    public let message: String
    public let cause: (any Error)? = nil
    public let provider: String
    public let reference: SharedV4ProviderReference

    public init(
        provider: String,
        reference: SharedV4ProviderReference,
        message: String? = nil
    ) {
        self.provider = provider
        self.reference = reference
        self.message = message ?? "No provider reference found for provider '\(provider)'. Available providers: \(reference.keys.joined(separator: ", "))"
    }

    /// Check if an error is an instance of NoSuchProviderReferenceError.
    public static func isInstance(_ error: any Error) -> Bool {
        hasMarker(error, marker: errorDomain)
    }
}
