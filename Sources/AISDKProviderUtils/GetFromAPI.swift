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
   - validateUrl: `true` when `url` is untrusted (e.g. taken from a provider
     response): it is fetched through `fetchWithValidatedRedirects`, which rejects
     private targets and re-validates redirect hops (`DownloadError`). `false`
     only for URLs built from a developer-configured endpoint.
   - credentialedOrigin: When set, `headers` are sent only if `url` is same-origin
     with it (the user-agent is always kept), so credentials never reach a
     response-supplied host. Redirects that cross origin drop caller headers regardless.
   - trustedOrigin: Developer-configured origin exempt from URL validation when
     `validateUrl` is `true`. Never derived from response data.

 - Returns: The result from successfulResponseHandler
 - Throws: APICallError or handler errors
 */
public func getFromAPI<T>(
    url: String,
    headers: [String: String]? = nil,
    failedResponseHandler: ResponseHandler<APICallError>,
    successfulResponseHandler: ResponseHandler<T>,
    isAborted: (@Sendable () -> Bool)? = nil,
    fetch: FetchFunction? = nil,
    validateUrl: Bool = false,
    credentialedOrigin: String? = nil,
    trustedOrigin: String? = nil
) async throws -> ResponseHandlerResult<T> {
    do {
        // Prepare request
        guard let requestURL = URL(string: url) else {
            throw APICallError(
                message: "Invalid URL",
                url: url,
                requestBodyValues: nil
            )
        }

        // Withhold caller headers when the URL is not same-origin with the
        // origin allowed to receive credentials.
        let outgoingHeaders: [String: String]
        if let credentialedOrigin, !isSameOrigin(url, credentialedOrigin) {
            outgoingHeaders = [:]
        } else {
            outgoingHeaders = headers ?? [:]
        }

        let headersWithUA = withUserAgentSuffix(
            outgoingHeaders,
            "ai-sdk-provider-utils/\(PROVIDER_UTILS_VERSION)",
            getRuntimeEnvironmentUserAgent()
        )

        // Check cancellation before fetch
        if isAborted?() == true {
            throw CancellationError()
        }

        let providerResponse: ProviderHTTPResponse
        if validateUrl {
            providerResponse = try await fetchWithValidatedRedirects(
                url: url,
                headers: headersWithUA,
                isAborted: isAborted,
                fetch: fetch,
                trustedOrigin: trustedOrigin
            )
        } else {
            var request = URLRequest(url: requestURL)
            request.httpMethod = "GET"
            request.timeoutInterval = PROVIDER_UTILS_DEFAULT_REQUEST_TIMEOUT_INTERVAL

            for (key, value) in headersWithUA {
                request.setValue(value, forHTTPHeaderField: key)
            }

            let fetchResponse = try await fetchWithAbortCheck(
                fetch: fetch ?? defaultFetchFunction(),
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

            providerResponse = ProviderHTTPResponse(
                url: requestURL,
                httpResponse: httpResponse,
                body: fetchResponse.body
            )
        }

        let httpResponse = providerResponse.httpResponse
        let responseHeaders = extractResponseHeaders(from: httpResponse)

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
