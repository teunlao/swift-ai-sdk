import Foundation

/**
 Checks if an error is an abort/cancellation error.
 Port of `@ai-sdk/provider-utils/src/is-abort-error.ts`
 */
public func isAbortError(_ error: Error) -> Bool {
    if error is CancellationError {
        return true
    }

    // Check URLError cancellation codes
    if let urlError = error as? URLError {
        return urlError.code == .cancelled || urlError.code == .timedOut
    }

    return false
}
