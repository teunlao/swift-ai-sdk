import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Validates and prepares retry configuration.

 Port of `@ai-sdk/ai/src/util/prepare-retries.ts`.

 Validates the maxRetries parameter and creates a retry function
 with exponential backoff that respects rate limit headers.
 */

/// Result of preparing retry configuration.
public struct PreparedRetries: Sendable {
    /// Maximum number of retries.
    public let maxRetries: Int

    /// Retry function wrapper.
    public let retry: RetryFunctionWrapper

    /// Creates a prepared retries configuration.
    ///
    /// - Parameters:
    ///   - maxRetries: Maximum number of retries
    ///   - retry: Retry function wrapper
    public init(maxRetries: Int, retry: RetryFunctionWrapper) {
        self.maxRetries = maxRetries
        self.retry = retry
    }
}

/// Validates and prepares retry configuration.
///
/// - Parameters:
///   - maxRetries: Maximum number of retries (optional, default: 2)
///   - abortSignal: Optional abort signal for cancellation
/// - Returns: Prepared retries configuration
/// - Throws: InvalidArgumentError if maxRetries is invalid
public func prepareRetries(
    maxRetries: Int?,
    abortSignal: (@Sendable () -> Bool)?
) throws -> PreparedRetries {
    // Validate maxRetries if provided
    if let maxRetries = maxRetries {
        // Check if it's a valid integer (in Swift, Int is always an integer)
        // But we still need to check if it's >= 0
        if maxRetries < 0 {
            throw InvalidArgumentError(
                parameter: "maxRetries",
                value: .number(Double(maxRetries)),
                message: "maxRetries must be >= 0"
            )
        }
    }

    // Use default value if not provided
    let maxRetriesResult = maxRetries ?? 2

    // Create retry function
    let retry = retryWithExponentialBackoffRespectingRetryHeaders(
        maxRetries: maxRetriesResult,
        abortSignal: abortSignal
    )

    return PreparedRetries(
        maxRetries: maxRetriesResult,
        retry: retry
    )
}
