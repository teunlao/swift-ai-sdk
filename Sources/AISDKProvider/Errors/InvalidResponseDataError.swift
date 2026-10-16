import Foundation

/**
 * Server returned a response with invalid data content.
 * This should be thrown by providers when they cannot parse the response from the API.
 *
 * Swift port of TypeScript `InvalidResponseDataError`.
 */
public struct InvalidResponseDataError: AISDKError, @unchecked Sendable {
    public static let errorDomain = "vercel.ai.error.AI_InvalidResponseDataError"

    public let name = "AI_InvalidResponseDataError"
    public let message: String
    public let cause: (any Error)? = nil
    public let data: Any?

    public init(
        data: Any?,
        message: String? = nil
    ) {
        self.data = data

        if let message = message {
            self.message = message
        } else {
            self.message = "Invalid response data: \(stringifyErrorValue(data))."
        }
    }

    /// Check if an error is an instance of InvalidResponseDataError
    public static func isInstance(_ error: any Error) -> Bool {
        hasMarker(error, marker: errorDomain)
    }
}
