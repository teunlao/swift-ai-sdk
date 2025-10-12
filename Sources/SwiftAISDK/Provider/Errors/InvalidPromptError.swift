/**
 * A prompt is invalid. This error should be thrown by providers when they cannot
 * process a prompt.
 *
 * Swift port of TypeScript `InvalidPromptError`.
 */
public struct InvalidPromptError: AISDKError, @unchecked Sendable {
    public static let errorDomain = "vercel.ai.error.AI_InvalidPromptError"

    public let name = "AI_InvalidPromptError"
    public let message: String
    public let cause: (any Error)?
    public let prompt: Any?

    public init(
        prompt: Any?,
        message: String,
        cause: (any Error)? = nil
    ) {
        self.prompt = prompt
        self.message = "Invalid prompt: \(message)"
        self.cause = cause
    }

    /// Check if an error is an instance of InvalidPromptError
    public static func isInstance(_ error: any Error) -> Bool {
        SwiftAISDK.hasMarker(error, marker: errorDomain)
    }
}
