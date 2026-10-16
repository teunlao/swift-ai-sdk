import Foundation
import AISDKProvider

/**
 Sends a DELETE request.

 For URLs built from developer-configured endpoints only: there is no
 untrusted-URL validation path (use `getFromAPI` with `validateUrl` for
 response-supplied URLs).

 Port of `@ai-sdk/provider-utils/src/delete-from-api.ts`.
 */
public func deleteFromAPI<T>(
    url: String,
    headers: [String: String?]? = nil,
    failedResponseHandler: ResponseHandler<APICallError>,
    successfulResponseHandler: ResponseHandler<T>,
    isAborted: (@Sendable () -> Bool)? = nil,
    fetch: FetchFunction? = nil
) async throws -> ResponseHandlerResult<T> {
    let requestBodyValues: [String: String] = [:]
    let request = try makeAPIRequest(
        url: url,
        method: "DELETE",
        headers: headers ?? [:],
        requestBodyValues: requestBodyValues
    )

    return try await sendAPIRequest(
        request,
        url: url,
        requestBodyValues: requestBodyValues,
        failedResponseHandler: failedResponseHandler,
        successfulResponseHandler: successfulResponseHandler,
        isAborted: isAborted,
        fetch: fetch
    )
}
