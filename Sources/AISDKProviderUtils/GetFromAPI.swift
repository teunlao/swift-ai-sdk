import Foundation
import AISDKProvider

/**
 HTTP GET utilities for API calls.

 Port of `@ai-sdk/provider-utils/src/get-from-api.ts`.

 Provides functions for making GET requests to API endpoints,
 handling responses with custom success/failure handlers, and proper error wrapping.
 */

/**
 Performs a GET request to an API endpoint.

 Handles:
 - User-Agent header injection
 - Response status code checking
 - Error/success handler invocation
 - Error wrapping for network failures

 - Parameters:
   - url: The URL to fetch from
   - headers: Optional HTTP headers
   - failedResponseHandler: Handler for non-2xx responses
   - successfulResponseHandler: Handler for successful responses
   - isAborted: Optional closure to check if request should be cancelled
   - fetch: Optional custom fetch function (for testing)

 - Returns: The result from successfulResponseHandler
 - Throws: APICallError or handler errors
 */
public func getFromAPI<T>(
    url: String,
    headers: [String: String]? = nil,
    failedResponseHandler: ResponseHandler<APICallError>,
    successfulResponseHandler: ResponseHandler<T>,
    isAborted: (@Sendable () -> Bool)? = nil,
    fetch: FetchFunction? = nil
) async throws -> ResponseHandlerResult<T> {
    let fetchImpl = fetch ?? defaultFetchFunction()

    do {
        // Prepare request
        guard let requestURL = URL(string: url) else {
            throw APICallError(
                message: "Invalid URL",
                url: url,
                requestBodyValues: nil
            )
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.timeoutInterval = PROVIDER_UTILS_DEFAULT_REQUEST_TIMEOUT_INTERVAL

        // Add headers with User-Agent
        let headersWithUA = withUserAgentSuffix(
            headers ?? [:],
            "ai-sdk/provider-utils/\(PROVIDER_UTILS_VERSION)",
            getRuntimeEnvironmentUserAgent()
        )

        for (key, value) in headersWithUA {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Check cancellation before fetch
        if isAborted?() == true {
            throw CancellationError()
        }

        // Execute request
        let fetchResponse = try await fetchWithAbortCheck(
            fetch: fetchImpl,
            request: request,
            isAborted: isAborted
        )

        guard let httpResponse = fetchResponse.urlResponse as? HTTPURLResponse else {
            throw APICallError(
                message: "Invalid response type",
                url: url,
                requestBodyValues: nil
            )
        }

        let responseHeaders = extractResponseHeaders(from: httpResponse)

        // Create ProviderHTTPResponse
        let providerResponse = ProviderHTTPResponse(
            url: requestURL,
            httpResponse: httpResponse,
            body: fetchResponse.body
        )

        // Handle non-2xx responses
        if !(200...299).contains(httpResponse.statusCode) {
            let errorInput = ResponseHandlerInput(
                url: url,
                requestBodyValues: nil,
                response: providerResponse
            )

            let errorInfo: ResponseHandlerResult<APICallError>
            do {
                errorInfo = try await failedResponseHandler(errorInput)
            } catch let error as APICallError {
                throw error
            } catch {
                if isAbortError(error) {
                    throw error
                }

                throw APICallError(
                    message: "Failed to process error response",
                    url: url,
                    requestBodyValues: nil,
                    statusCode: httpResponse.statusCode,
                    responseHeaders: responseHeaders,
                    responseBody: nil,
                    cause: error
                )
            }

            throw errorInfo.value
        }

        // Handle successful response
        let successInput = ResponseHandlerInput(
            url: url,
            requestBodyValues: nil,
            response: providerResponse
        )

        do {
            return try await successfulResponseHandler(successInput)
        } catch let error as APICallError {
            throw error
        } catch {
            if isAbortError(error) {
                throw error
            }

            throw APICallError(
                message: "Failed to process successful response",
                url: url,
                requestBodyValues: nil,
                statusCode: httpResponse.statusCode,
                responseHeaders: responseHeaders,
                responseBody: nil,
                cause: error
            )
        }

    } catch {
        throw handleFetchError(error: error, url: url, requestBodyValues: nil)
    }
}
