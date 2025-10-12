/**
 * Error thrown when response body is empty.
 *
 * Swift port of TypeScript `EmptyResponseBodyError`.
 */
public struct EmptyResponseBodyError: AISDKError, Sendable {
    public static let errorDomain = "vercel.ai.error.AI_EmptyResponseBodyError"

    public let name = "AI_EmptyResponseBodyError"
    public let message: String
    public let cause: (any Error)? = nil

    public init(message: String = "Empty response body") {
        self.message = message
    }

    /// Check if an error is an instance of EmptyResponseBodyError
    public static func isInstance(_ error: any Error) -> Bool {
        SwiftAISDK.hasMarker(error, marker: errorDomain)
    }
}
