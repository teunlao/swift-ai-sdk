import Foundation
import AISDKProvider

/// Transport failures that a retry can recover from: the Swift counterparts of
/// upstream's `fetch failed` causes and retryable network error codes.
private let retryableURLErrorCodes: Set<URLError.Code> = [
    .cannotConnectToHost,
    .cannotFindHost,
    .dnsLookupFailed,
    .networkConnectionLost,
    .notConnectedToInternet,
    .secureConnectionFailed,
    // Transport timeouts: the counterpart of undici's headers/body/connect timeouts.
    .timedOut,
]

private let retryablePOSIXErrorCodes: Set<POSIXErrorCode> = [
    .ECONNRESET,
    .ECONNREFUSED,
    .ETIMEDOUT,
    .EPIPE,
]

/**
 Handles fetch errors and converts network failures into retryable `APICallError`s.

 The error and its cause chain are searched for a network failure. An
 `APICallError` caused by one (e.g. a response body that failed mid-read) is
 returned as a retryable copy; any other error caused by one becomes a
 retryable "Cannot connect to API" error. Abort errors and other errors are
 returned unchanged.

 Port of `@ai-sdk/provider-utils/src/handle-fetch-error.ts`.
 */
public func handleFetchError(
    error: Error,
    url: String,
    requestBodyValues: Any?
) -> Error {
    if isAbortError(error) {
        return error
    }

    guard findNetworkError(error) != nil else {
        return error
    }

    if let apiCallError = error as? APICallError {
        return APICallError(
            message: apiCallError.message,
            url: apiCallError.url,
            requestBodyValues: apiCallError.requestBodyValues,
            statusCode: apiCallError.statusCode,
            responseHeaders: apiCallError.responseHeaders,
            responseBody: apiCallError.responseBody,
            cause: apiCallError.cause,
            isRetryable: true,
            data: apiCallError.data
        )
    }

    return APICallError(
        message: "Cannot connect to API: \(networkErrorMessage(error))",
        url: url,
        requestBodyValues: requestBodyValues,
        cause: error,
        isRetryable: true
    )
}

private func findNetworkError(_ error: Error) -> Error? {
    var current: Error? = error
    var depth = 0

    while let candidate = current, depth < 32 {
        if isRetryableNetworkError(candidate) {
            return candidate
        }
        current = cause(of: candidate)
        depth += 1
    }

    return nil
}

private func isRetryableNetworkError(_ error: Error) -> Bool {
    if let urlError = error as? URLError {
        return retryableURLErrorCodes.contains(urlError.code)
    }

    if let posixError = error as? POSIXError {
        return retryablePOSIXErrorCodes.contains(posixError.code)
    }

    let nsError = error as NSError
    if nsError.domain == NSPOSIXErrorDomain, let code = POSIXErrorCode(rawValue: Int32(nsError.code)) {
        return retryablePOSIXErrorCodes.contains(code)
    }

    return false
}

private func cause(of error: Error) -> Error? {
    if let sdkError = error as? any AISDKError {
        return sdkError.cause
    }

    return (error as NSError).userInfo[NSUnderlyingErrorKey] as? Error
}

private func networkErrorMessage(_ error: Error) -> String {
    if let sdkError = error as? any AISDKError {
        return sdkError.message
    }
    return error.localizedDescription
}
