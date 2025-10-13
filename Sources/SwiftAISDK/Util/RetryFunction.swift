/**
 Type-erased wrapper for retry functions.

 Port of `@ai-sdk/ai/src/util/retry-with-exponential-backoff.ts` (RetryFunction type).

 Since Swift doesn't support storing generic functions directly as values,
 we use a type-erased wrapper that allows calling with any output type.
 */

/// Type-erased wrapper for retry functions.
///
/// Allows storing and calling retry logic with different output types.
public struct RetryFunctionWrapper: Sendable {
    private let maxRetries: Int
    private let initialDelayInMs: Int
    private let backoffFactor: Int
    private let abortSignal: (@Sendable () -> Bool)?

    /// Creates a retry function wrapper.
    ///
    /// - Parameters:
    ///   - maxRetries: Maximum number of retries
    ///   - initialDelayInMs: Initial delay in milliseconds
    ///   - backoffFactor: Multiplier for exponential backoff
    ///   - abortSignal: Optional abort signal
    init(
        maxRetries: Int,
        initialDelayInMs: Int,
        backoffFactor: Int,
        abortSignal: (@Sendable () -> Bool)?
    ) {
        self.maxRetries = maxRetries
        self.initialDelayInMs = initialDelayInMs
        self.backoffFactor = backoffFactor
        self.abortSignal = abortSignal
    }

    /// Calls the retry function with a specific output type.
    ///
    /// - Parameter fn: The function to retry
    /// - Returns: The result of the function
    /// - Throws: RetryError if all retries fail, or the original error if retries are disabled
    public func call<T>(_ fn: @escaping @Sendable () async throws -> T) async throws -> T {
        // Call _retryWithExponentialBackoff directly with the correct generic type
        return try await _retryWithExponentialBackoff(
            fn: fn,
            maxRetries: maxRetries,
            delayInMs: initialDelayInMs,
            backoffFactor: backoffFactor,
            abortSignal: abortSignal,
            errors: []
        )
    }
}
