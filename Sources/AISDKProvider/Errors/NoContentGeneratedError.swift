/**
 * Thrown when the AI provider fails to generate any content.
 *
 * Swift port of TypeScript `NoContentGeneratedError`.
 */
public struct NoContentGeneratedError: AISDKError, Sendable {
    public static let errorDomain = "vercel.ai.error.AI_NoContentGeneratedError"

    public let name = "AI_NoContentGeneratedError"
    public let message: String
    public let cause: (any Error)? = nil

    public init(message: String = "No content generated.") {
        self.message = message
    }

    /// Check if an error is an instance of NoContentGeneratedError
    public static func isInstance(_ error: any Error) -> Bool {
        hasMarker(error, marker: errorDomain)
    }
}
