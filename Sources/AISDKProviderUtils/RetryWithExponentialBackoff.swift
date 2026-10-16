import Foundation
import AISDKProvider

/**
 Retries a failed operation with exponential backoff. Create one with
 `retryWithExponentialBackoff(...)` and call it with the operation.

 Swift port of `RetryFunction` from `@ai-sdk/provider-utils/src/retry-with-exponential-backoff.ts`;
 upstream's generic function type becomes a callable struct.
 */
public struct RetryFunction: Sendable {
    /// Why retrying stopped. Port of upstream `RetryErrorReason`.
    public enum ErrorReason: String, Sendable, Equatable {
        case maxRetriesExceeded
        case errorNotRetryable
    }

    /// Decides whether an error is retried.
    public typealias ShouldRetry = @Sendable (_ error: any Error) async -> Bool

    /// Chooses the delay before the next attempt; receives the exponential backoff delay.
    public typealias DelayProvider = @Sendable (_ error: any Error, _ exponentialBackoffDelay: Int) -> Int

    /// Builds the error thrown when retrying stops after more than one attempt.
    public typealias ErrorFactory = @Sendable (
        _ message: String,
        _ reason: ErrorReason,
        _ errors: [any Error]
    ) -> any Error

    /// Error thrown by the default `ErrorFactory`.
    public struct Failure: Error, LocalizedError, Sendable {
        public let message: String
        public var errorDescription: String? { message }
    }

    let maxRetries: Int
    let initialDelayInMs: Int
    let backoffFactor: Int
    let abortSignal: (@Sendable () -> Bool)?
    let shouldRetry: ShouldRetry
    let getDelayInMs: DelayProvider
    let createRetryError: ErrorFactory

    public func callAsFunction<Output: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Output
    ) async throws -> Output {
        var delayInMs = initialDelayInMs
        var errors: [any Error] = []

        while true {
            do {
                return try await operation()
            } catch {
                // Never retry an aborted request.
                if isAbortError(error) {
                    throw error
                }

                // Errors are not wrapped when retries are disabled.
                if maxRetries == 0 {
                    throw error
                }

                let errorMessage = getErrorMessage(error)
                errors.append(error)
                let tryNumber = errors.count

                if tryNumber > maxRetries {
                    throw createRetryError(
                        "Failed after \(tryNumber) attempts. Last error: \(errorMessage)",
                        .maxRetriesExceeded,
                        errors
                    )
                }

                if await shouldRetry(error) {
                    try await delay(
                        getDelayInMs(error, delayInMs),
                        abortSignal: abortSignal
                    )
                    delayInMs *= backoffFactor
                    continue
                }

                // A non-retryable error on the first try is not wrapped.
                if tryNumber == 1 {
                    throw error
                }

                throw createRetryError(
                    "Failed after \(tryNumber) attempts with non-retryable error: '\(errorMessage)'",
                    .errorNotRetryable,
                    errors
                )
            }
        }
    }
}

/**
 Creates a function that retries a failed operation with exponential backoff.

 Port of `retryWithExponentialBackoff` from `@ai-sdk/provider-utils/src/retry-with-exponential-backoff.ts`.
 */
public func retryWithExponentialBackoff(
    maxRetries: Int = 2,
    initialDelayInMs: Int = 2000,
    backoffFactor: Int = 2,
    abortSignal: (@Sendable () -> Bool)? = nil,
    shouldRetry: @escaping RetryFunction.ShouldRetry,
    getDelayInMs: RetryFunction.DelayProvider? = nil,
    createRetryError: RetryFunction.ErrorFactory? = nil
) -> RetryFunction {
    RetryFunction(
        maxRetries: maxRetries,
        initialDelayInMs: initialDelayInMs,
        backoffFactor: backoffFactor,
        abortSignal: abortSignal,
        shouldRetry: shouldRetry,
        getDelayInMs: getDelayInMs ?? { _, exponentialBackoffDelay in exponentialBackoffDelay },
        createRetryError: createRetryError ?? { message, _, _ in RetryFunction.Failure(message: message) }
    )
}
