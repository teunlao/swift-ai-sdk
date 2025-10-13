import Foundation

/**
 * Error thrown when an API call fails.
 *
 * Swift port of TypeScript `APICallError`.
 */
public struct APICallError: AISDKError, @unchecked Sendable {
    public static let errorDomain = "vercel.ai.error.AI_APICallError"

    public let name = "AI_APICallError"
    public let message: String
    public let cause: (any Error)?

    public let url: String
    public let requestBodyValues: Any?
    public let statusCode: Int?
    public let responseHeaders: [String: String]?
    public let responseBody: String?
    public let isRetryable: Bool
    public let data: Any?

    public init(
        message: String,
        url: String,
        requestBodyValues: Any?,
        statusCode: Int? = nil,
        responseHeaders: [String: String]? = nil,
        responseBody: String? = nil,
        cause: (any Error)? = nil,
        isRetryable: Bool? = nil,
        data: Any? = nil
    ) {
        self.message = message
        self.url = url
        self.requestBodyValues = requestBodyValues
        self.statusCode = statusCode
        self.responseHeaders = responseHeaders
        self.responseBody = responseBody
        self.cause = cause

        // Default isRetryable logic (same as TypeScript)
        if let isRetryable = isRetryable {
            self.isRetryable = isRetryable
        } else if let statusCode = statusCode {
            self.isRetryable = statusCode == 408 || // request timeout
                statusCode == 409 || // conflict
                statusCode == 429 || // too many requests
                statusCode >= 500    // server error
        } else {
            self.isRetryable = false
        }

        self.data = data
    }

    /// Check if an error is an instance of APICallError
    public static func isInstance(_ error: any Error) -> Bool {
        hasMarker(error, marker: errorDomain)
    }
}
