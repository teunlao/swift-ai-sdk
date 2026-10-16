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
import GatewayProvider

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

    var ms = headers["retry-after-ms"].flatMap(parseRetryNumber)
    if let retryAfter = headers["retry-after"], ms == nil {
        if let seconds = parseRetryNumber(retryAfter) {
            ms = seconds * 1000
        } else {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            for format in ["EEE, dd MMM yyyy HH:mm:ss zzz", "EEEE, dd-MMM-yy HH:mm:ss zzz", "EEE MMM d HH:mm:ss yyyy"] {
                formatter.dateFormat = format
                if let date = formatter.date(from: retryAfter) {
                    ms = date.timeIntervalSinceNow * 1000
                    break
                }
            }
        }
    }
    if let ms, ms.isFinite, ms >= 0, ms < Double(Int.max),
       ms < 60_000 || ms < Double(exponentialBackoffDelay) {
        return Int(ms)
    }
    return exponentialBackoffDelay
}

private let retryNumberPrefix = try! NSRegularExpression(pattern: #"^[+-]?(?:Infinity|(?:[0-9]+\.?[0-9]*|\.[0-9]+)(?:[eE][+-]?[0-9]+)?)"#)

private func parseRetryNumber(_ text: String) -> Double? {
    let whitespace = CharacterSet.whitespacesAndNewlines
        .subtracting(CharacterSet(charactersIn: "\u{85}"))
        .union(CharacterSet(charactersIn: "\u{FEFF}"))
    let trimmed = text.trimmingCharacters(in: whitespace)
    guard let match = retryNumberPrefix.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
          let range = Range(match.range, in: trimmed) else { return nil }
    let number = String(trimmed[range])
    if number.hasSuffix("Infinity") { return number.hasPrefix("-") ? -.infinity : .infinity }
    return Double(number)
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
    abortSignal: (@Sendable () -> Bool)? = nil,
    additionalRetryableError: (@Sendable (any Error) async -> Bool)? = nil
) -> RetryFunctionWrapper {
    RetryFunctionWrapper(
        maxRetries: maxRetries,
        initialDelayInMs: initialDelayInMs,
        backoffFactor: backoffFactor,
        abortSignal: abortSignal,
        additionalRetryableError: additionalRetryableError
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
    errors: [any Error],
    additionalRetryableError: (@Sendable (any Error) async -> Bool)? = nil
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

        let errorMessage: String
        if let gateway = error as? any GatewayError {
            errorMessage = gateway.message.isEmpty ? gateway.name : "\(gateway.name): \(gateway.message)"
        } else {
            errorMessage = AISDKProvider.getErrorMessage(error)
        }
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
        let apiError = error as? APICallError
        let gatewayError = error as? any GatewayError
        let shouldRetry = apiError?.isRetryable == true || gatewayError?.isRetryable == true
            ? true
            : await additionalRetryableError?(error) ?? false
        if shouldRetry {
            let retryDelay = (apiError ?? gatewayError?.cause as? APICallError).map {
                getRetryDelayInMs(error: $0, exponentialBackoffDelay: delayInMs)
            } ?? delayInMs

            // Check if task was cancelled
            try Task.checkCancellation()

            // Wait before retrying
            try await delay(retryDelay, abortSignal: abortSignal)

            let product = delayInMs.multipliedReportingOverflow(by: backoffFactor)
            let limit = (delayInMs < 0) != (backoffFactor < 0) ? Int.min : Int.max
            let nextDelay = product.overflow ? limit : product.partialValue
            return try await _retryWithExponentialBackoff(
                fn: fn,
                maxRetries: maxRetries,
                delayInMs: nextDelay,
                backoffFactor: backoffFactor,
                abortSignal: abortSignal,
                errors: newErrors,
                additionalRetryableError: additionalRetryableError
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
