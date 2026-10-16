import Foundation
import AISDKProvider

/**
 Sends a prepared request and routes the response through the failure or
 success handler, with the error wrapping shared by the `*ToAPI` helpers:
 handler failures become `APICallError`s ("Failed to process error/successful
 response"), and transport failures pass through `handleFetchError`.
 */
func sendAPIRequest<T>(
    _ request: URLRequest,
    url: String,
    requestBodyValues: Any?,
    failedResponseHandler: ResponseHandler<APICallError>,
    successfulResponseHandler: ResponseHandler<T>,
    isAborted: (@Sendable () -> Bool)?,
    fetch: FetchFunction?
) async throws -> ResponseHandlerResult<T> {
    do {
        if isAborted?() == true {
            throw CancellationError()
        }

        let fetchResponse = try await fetchWithAbortCheck(
            fetch: fetch ?? defaultFetchFunction(),
            request: request,
            isAborted: isAborted
        )

        guard let httpResponse = fetchResponse.urlResponse as? HTTPURLResponse,
              let requestURL = request.url else {
            throw APICallError(
                message: "Invalid response type",
                url: url,
                requestBodyValues: requestBodyValues
            )
        }

        let responseHeaders = extractResponseHeaders(from: httpResponse)
        let input = ResponseHandlerInput(
            url: url,
            requestBodyValues: requestBodyValues,
            response: ProviderHTTPResponse(
                url: requestURL,
                httpResponse: httpResponse,
                body: fetchResponse.body
            )
        )

        if !(200...299).contains(httpResponse.statusCode) {
            let errorInfo: ResponseHandlerResult<APICallError>
            do {
                errorInfo = try await failedResponseHandler(input)
            } catch {
                if isAbortError(error) || error is APICallError {
                    throw error
                }

                throw APICallError(
                    message: "Failed to process error response",
                    url: url,
                    requestBodyValues: requestBodyValues,
                    statusCode: httpResponse.statusCode,
                    responseHeaders: responseHeaders,
                    cause: error
                )
            }

            throw errorInfo.value
        }

        do {
            return try await successfulResponseHandler(input)
        } catch {
            if isAbortError(error) || error is APICallError {
                throw error
            }

            throw APICallError(
                message: "Failed to process successful response",
                url: url,
                requestBodyValues: requestBodyValues,
                statusCode: httpResponse.statusCode,
                responseHeaders: responseHeaders,
                cause: error
            )
        }
    } catch {
        throw handleFetchError(error: error, url: url, requestBodyValues: requestBodyValues)
    }
}

/// Builds a request with the provider-utils user-agent suffix applied to `headers`.
func makeAPIRequest(
    url: String,
    method: String,
    headers: [String: String?],
    requestBodyValues: Any?
) throws -> URLRequest {
    guard let requestURL = URL(string: url) else {
        throw APICallError(
            message: "Invalid URL",
            url: url,
            requestBodyValues: requestBodyValues
        )
    }

    var request = URLRequest(url: requestURL)
    request.httpMethod = method
    request.timeoutInterval = PROVIDER_UTILS_DEFAULT_REQUEST_TIMEOUT_INTERVAL

    let headersWithUA = withUserAgentSuffix(
        headers,
        "ai-sdk-provider-utils/\(PROVIDER_UTILS_VERSION)",
        getRuntimeEnvironmentUserAgent()
    )
    for (name, value) in headersWithUA {
        request.setValue(value, forHTTPHeaderField: name)
    }

    return request
}
