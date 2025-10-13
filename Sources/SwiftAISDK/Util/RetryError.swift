import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Error thrown when retry logic fails.

 Port of `@ai-sdk/ai/src/util/retry-error.ts`.

 Represents errors that occur during retry attempts, including when max retries
 are exceeded, when an error is not retryable, or when the operation is aborted.
 */

/// Reason for retry failure.
public enum RetryErrorReason: String, Sendable {
    /// Maximum number of retries exceeded.
    case maxRetriesExceeded
    /// Error is not retryable.
    case errorNotRetryable
    /// Operation was aborted.
    case abort
}

/// Error thrown when retry logic fails.
public struct RetryError: AISDKError, Sendable {
    public static let errorDomain = "vercel.ai.error.AI_RetryError"

    public let name = "AI_RetryError"
    public let message: String
    public let cause: (any Error)?

    /// The reason for retry failure.
    public let reason: RetryErrorReason

    /// All errors that occurred during retry attempts.
    public let errors: [any Error]

    /// The last error that occurred (for easier debugging).
    public let lastError: (any Error)?

    /// Creates a retry error.
    ///
    /// - Parameters:
    ///   - message: Description of the retry failure
    ///   - reason: The reason for failure
    ///   - errors: All errors encountered during retries
    public init(
        message: String,
        reason: RetryErrorReason,
        errors: [any Error]
    ) {
        self.message = message
        self.reason = reason
        self.errors = errors
        self.lastError = errors.last
        self.cause = errors.last
    }

    /// Checks if an error is a RetryError instance.
    ///
    /// - Parameter error: The error to check
    /// - Returns: `true` if the error is a RetryError, `false` otherwise
    public static func isInstance(_ error: any Error) -> Bool {
        hasMarker(error, marker: Self.errorDomain)
    }
}
