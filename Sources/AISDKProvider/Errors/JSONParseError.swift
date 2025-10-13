/**
 * JSON parsing failed.
 *
 * Swift port of TypeScript `JSONParseError`.
 * Note: TODO v5 in upstream suggests renaming to ParseError.
 */
public struct JSONParseError: AISDKError, Sendable {
    public static let errorDomain = "vercel.ai.error.AI_JSONParseError"

    public let name = "AI_JSONParseError"
    public let message: String
    public let cause: (any Error)?
    public let text: String

    public init(text: String, cause: any Error) {
        self.text = text
        self.cause = cause
        self.message = """
            JSON parsing failed: \
            Text: \(text).
            Error message: \(getErrorMessage(cause))
            """
    }

    /// Check if an error is an instance of JSONParseError
    public static func isInstance(_ error: any Error) -> Bool {
        SwiftAISDK.hasMarker(error, marker: errorDomain)
    }
}
