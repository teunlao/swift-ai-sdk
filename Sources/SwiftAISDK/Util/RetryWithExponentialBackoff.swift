/**
 Retry logic with exponential backoff and respect for rate limit headers.

 Port of `@ai-sdk/ai/src/util/retry-with-exponential-backoff.ts`.

 Implements retry logic that:
 - Uses exponential backoff for delays between retries
 - Respects rate limit headers (retry-after-ms, retry-after) from API responses
 - Handles abort signals for cancellation
 - Collects all errors encountered during retries
 */

import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Gets the retry delay in milliseconds, respecting rate limit headers.
///
/// - Parameters:
///   - error: The API call error containing response headers
///   - exponentialBackoffDelay: The calculated exponential backoff delay
/// - Returns: The delay to use before the next retry
func getRetryDelayInMs(
    error: APICallError,
    exponentialBackoffDelay: Int
) -> Int {
    guard let headers = error.responseHeaders else {
        return exponentialBackoffDelay
    }

    var ms: Int?

    // retry-after-ms is more precise than retry-after and used by e.g. OpenAI
    if let retryAfterMs = headers["retry-after-ms"] {
        if let timeoutMs = Int(retryAfterMs) {
            ms = timeoutMs
        } else if let timeoutMs = Double(retryAfterMs) {
            ms = Int(timeoutMs)
        }
    }

    // About the Retry-After header: https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Retry-After
    if let retryAfter = headers["retry-after"], ms == nil {
        if let timeoutSeconds = Double(retryAfter) {
            ms = Int(timeoutSeconds * 1000)
        } else {
            // Try to parse as HTTP date
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            formatter.timeZone = TimeZone(abbreviation: "GMT")

            if let date = formatter.date(from: retryAfter) {
                let delayMs = Int(date.timeIntervalSince(Date()) * 1000)
                ms = delayMs
            }
        }
    }

    // Check that the delay is reasonable:
    // Accept if it's between 0 and 60 seconds, or if it's less than the exponential backoff
    if let ms = ms,
       ms >= 0,
       (ms < 60 * 1000 || ms < exponentialBackoffDelay) {
        return ms
    }

    return exponentialBackoffDelay
}

/// Creates a retry function with exponential backoff that respects retry headers.
///
/// The retry strategy:
/// - Retries failed API calls with exponential backoff
/// - Respects rate limit headers (retry-after-ms and retry-after) if provided and reasonable (0-60 seconds)
/// - Can be configured with max retries, initial delay, and backoff factor
///
/// - Parameters:
///   - maxRetries: Maximum number of retries (default: 2)
///   - initialDelayInMs: Initial delay in milliseconds (default: 2000)
///   - backoffFactor: Multiplier for exponential backoff (default: 2)
///   - abortSignal: Optional abort signal to cancel retries
/// - Returns: A retry function wrapper that can be called with any output type
public func retryWithExponentialBackoffRespectingRetryHeaders(
    maxRetries: Int = 2,
    initialDelayInMs: Int = 2000,
    backoffFactor: Int = 2,
    abortSignal: (@Sendable () -> Bool)? = nil
) -> RetryFunctionWrapper {
    RetryFunctionWrapper(
        maxRetries: maxRetries,
        initialDelayInMs: initialDelayInMs,
        backoffFactor: backoffFactor,
        abortSignal: abortSignal
    )
}

/// Internal recursive retry implementation.
///
/// - Parameters:
///   - fn: The function to retry
///   - maxRetries: Maximum number of retries
///   - delayInMs: Current delay in milliseconds
///   - backoffFactor: Multiplier for exponential backoff
///   - abortSignal: Optional abort signal
///   - errors: Accumulated errors from previous attempts
/// - Returns: The result of the function
/// - Throws: RetryError or the original error
func _retryWithExponentialBackoff<OUTPUT>(
    fn: @escaping @Sendable () async throws -> OUTPUT,
    maxRetries: Int,
    delayInMs: Int,
    backoffFactor: Int,
    abortSignal: (@Sendable () -> Bool)?,
    errors: [any Error]
) async throws -> OUTPUT {
    do {
        return try await fn()
    } catch {
        // Check if this is an abort error
        if isAbortError(error) {
            throw error // don't retry when the request was aborted
        }

        // Don't wrap the error when retries are disabled
        if maxRetries == 0 {
            throw error
        }

        let errorMessage = AISDKProvider.getErrorMessage(error)
        let newErrors = errors + [error]
        let tryNumber = newErrors.count

        // Check if we've exceeded max retries
        if tryNumber > maxRetries {
            throw RetryError(
                message: "Failed after \(tryNumber) attempts. Last error: \(errorMessage)",
                reason: .maxRetriesExceeded,
                errors: newErrors
            )
        }

        // Check if error is retryable
        if let apiError = error as? APICallError,
           apiError.isRetryable == true,
           tryNumber <= maxRetries {
            // Calculate delay
            let retryDelay = getRetryDelayInMs(
                error: apiError,
                exponentialBackoffDelay: delayInMs
            )

            // Check if task was cancelled
            try Task.checkCancellation()

            // Wait before retrying
            try await delay(retryDelay)

            // Retry with increased delay
            return try await _retryWithExponentialBackoff(
                fn: fn,
                maxRetries: maxRetries,
                delayInMs: backoffFactor * delayInMs,
                backoffFactor: backoffFactor,
                abortSignal: abortSignal,
                errors: newErrors
            )
        }

        // Don't wrap the error when a non-retryable error occurs on the first try
        if tryNumber == 1 {
            throw error
        }

        // Throw RetryError for non-retryable errors after the first attempt
        throw RetryError(
            message: "Failed after \(tryNumber) attempts with non-retryable error: '\(errorMessage)'",
            reason: .errorNotRetryable,
            errors: newErrors
        )
    }
}
