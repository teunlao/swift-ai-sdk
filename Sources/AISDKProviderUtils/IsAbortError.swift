import Foundation

/**
 Checks if an error is an abort/cancellation error requested by the caller.

 Port of `@ai-sdk/provider-utils/src/is-abort-error.ts`. Upstream's
 `TimeoutError` comes from the caller's `AbortSignal.timeout()`; its Swift
 counterpart is task cancellation or an `isAborted` check, which surface as
 `CancellationError` or `URLError.cancelled`. `URLError.timedOut` is a transport
 timeout, like undici's `UND_ERR_*_TIMEOUT`, and is handled as a retryable
 network failure by `handleFetchError`.
 */
public func isAbortError(_ error: Error) -> Bool {
    if error is CancellationError {
        return true
    }

    if let urlError = error as? URLError {
        return urlError.code == .cancelled
    }

    return false
}
