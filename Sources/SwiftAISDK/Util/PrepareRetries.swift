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
    abortSignal: (@Sendable () -> Bool)?,
    additionalRetryableError: (@Sendable (any Error) async -> Bool)? = nil,
    parameter: String = "maxRetries",
    defaultMaxRetries: Int = 2
) throws -> PreparedRetries {
    if let maxRetries, maxRetries < 0 {
        throw InvalidArgumentError(
            parameter: parameter,
            value: JSONValue.number(Double(maxRetries)),
            message: "\(parameter) must be >= 0"
        )
    }

    let maxRetriesResult = maxRetries ?? defaultMaxRetries

    // Create retry function
    let retry = retryWithExponentialBackoffRespectingRetryHeaders(
        maxRetries: maxRetriesResult,
        abortSignal: abortSignal,
        additionalRetryableError: additionalRetryableError
    )

    return PreparedRetries(
        maxRetries: maxRetriesResult,
        retry: retry
    )
}
