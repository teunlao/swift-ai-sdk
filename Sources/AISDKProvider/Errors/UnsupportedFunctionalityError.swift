/**
 * Functionality not supported error.
 *
 * Swift port of TypeScript `UnsupportedFunctionalityError`.
 */
public struct UnsupportedFunctionalityError: AISDKError, Sendable {
    public static let errorDomain = "vercel.ai.error.AI_UnsupportedFunctionalityError"

    public let name = "AI_UnsupportedFunctionalityError"
    public let message: String
    public let cause: (any Error)? = nil
    public let functionality: String

    public init(
        functionality: String,
        message: String? = nil
    ) {
        self.functionality = functionality
        self.message = message ?? "'\(functionality)' functionality not supported."
    }

    /// Check if an error is an instance of UnsupportedFunctionalityError
    public static func isInstance(_ error: any Error) -> Bool {
        hasMarker(error, marker: errorDomain)
    }
}
