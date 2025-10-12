import Foundation

/**
 Handles fetch errors and converts them to APICallError.
 Port of `@ai-sdk/provider-utils/src/handle-fetch-error.ts`
 */
public func handleFetchError(
    error: Error,
    url: String,
    requestBodyValues: JSONValue?
) -> Error {
    if isAbortError(error) {
        return error
    }

    // Network connection errors
    if let urlError = error as? URLError {
        switch urlError.code {
        case .cannotConnectToHost, .notConnectedToInternet, .networkConnectionLost:
            return APICallError(
                message: "Cannot connect to API: \(urlError.localizedDescription)",
                url: url,
                requestBodyValues: requestBodyValues,
                cause: error,
                isRetryable: true
            )
        default:
            break
        }
    }

    return error
}
