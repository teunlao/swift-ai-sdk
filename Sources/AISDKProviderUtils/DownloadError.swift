import Foundation
import AISDKProvider

/// Error thrown when downloading a file fails.
public struct DownloadError: AISDKError, Sendable {
    public static let errorDomain = "vercel.ai.error.AI_DownloadError"

    public let name = "AI_DownloadError"
    public let message: String
    public let cause: (any Error)?

    /// The URL that failed to download.
    public let url: String

    /// HTTP status code if the error occurred during HTTP request.
    public let statusCode: Int?

    /// HTTP status text if the error occurred during HTTP request.
    public let statusText: String?

    public init(
        url: String,
        statusCode: Int? = nil,
        statusText: String? = nil,
        cause: (any Error)? = nil,
        message: String? = nil
    ) {
        self.url = url
        self.statusCode = statusCode
        self.statusText = statusText
        self.cause = cause

        if let message {
            self.message = message
        } else if let cause {
            self.message = "Failed to download \(url): \(cause)"
        } else if let statusCode, let statusText {
            self.message = "Failed to download \(url): \(statusCode) \(statusText)"
        } else {
            self.message = "Failed to download \(url)"
        }
    }

    /// Checks if the given error is a `DownloadError`.
    public static func isInstance(_ error: any Error) -> Bool {
        hasMarker(error, marker: errorDomain)
    }
}
