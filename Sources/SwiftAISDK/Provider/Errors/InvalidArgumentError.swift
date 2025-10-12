/**
 * A function argument is invalid.
 *
 * Swift port of TypeScript `InvalidArgumentError`.
 */
public struct InvalidArgumentError: AISDKError, Sendable {
    public static let errorDomain = "vercel.ai.error.AI_InvalidArgumentError"

    public let name = "AI_InvalidArgumentError"
    public let message: String
    public let cause: (any Error)?
    public let argument: String

    public init(
        argument: String,
        message: String,
        cause: (any Error)? = nil
    ) {
        self.argument = argument
        self.message = message
        self.cause = cause
    }

    /// Check if an error is an instance of InvalidArgumentError
    public static func isInstance(_ error: any Error) -> Bool {
        SwiftAISDK.hasMarker(error, marker: errorDomain)
    }
}
