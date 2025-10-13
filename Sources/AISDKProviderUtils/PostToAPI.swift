import Foundation
import AISDKProvider

/**
 HTTP POST utilities for API calls.

 Port of `@ai-sdk/provider-utils/src/post-to-api.ts`.

 Provides functions for making POST requests with JSON or FormData payloads,
 handling responses with custom success/failure handlers, and proper error wrapping.
 */

/// Type alias for URLSession-based fetch function (allows mocking in tests)
public typealias FetchFunction = @Sendable (URLRequest) async throws -> (Data, URLResponse)

/// Default fetch function using shared URLSession
private func getDefaultFetch() -> FetchFunction {
    { request in
        try await URLSession.shared.data(for: request)
    }
}

// MARK: - Post JSON to API

/**
 Posts JSON data to an API endpoint.

 - Parameters:
   - url: The URL to post to
   - headers: Optional HTTP headers (will be merged with Content-Type: application/json)
   - body: The body to encode as JSON
   - failedResponseHandler: Handler for non-2xx responses
   - successfulResponseHandler: Handler for successful responses
   - isAborted: Optional closure to check if request should be cancelled
   - fetch: Optional custom fetch function (for testing)

 - Returns: The result from successfulResponseHandler
 - Throws: APICallError or handler errors
 */
public func postJsonToAPI<T>(
    url: String,
    headers: [String: String]? = nil,
    body: some Encodable,
    failedResponseHandler: ResponseHandler<APICallError>,
    successfulResponseHandler: ResponseHandler<T>,
    isAborted: (@Sendable () -> Bool)? = nil,
    fetch: FetchFunction? = nil
) async throws -> ResponseHandlerResult<T> {
    let jsonData = try JSONEncoder().encode(body)

    var mergedHeaders = headers ?? [:]
    mergedHeaders["Content-Type"] = "application/json"

    return try await postToAPI(
        url: url,
        headers: mergedHeaders,
        body: PostBody(content: .json(jsonData), values: body),
        failedResponseHandler: failedResponseHandler,
        successfulResponseHandler: successfulResponseHandler,
        isAborted: isAborted,
        fetch: fetch
    )
}

// MARK: - Post FormData to API

/**
 Posts form data to an API endpoint.

 Port of `postFormDataToApi` from `@ai-sdk/provider-utils/src/post-to-api.ts:47-75`.

 - Parameters:
   - url: The URL to post to
   - headers: Optional HTTP headers (will be merged with Content-Type: application/x-www-form-urlencoded)
   - formData: Form data as key-value pairs
   - failedResponseHandler: Handler for non-2xx responses
   - successfulResponseHandler: Handler for successful responses
   - isAborted: Optional closure to check if request should be cancelled
   - fetch: Optional custom fetch function (for testing)

 - Returns: The result from successfulResponseHandler
 - Throws: APICallError or handler errors

 - Note: Upstream TypeScript uses FormData API (multipart/form-data).
         Swift implementation uses simplified application/x-www-form-urlencoded.
         For multipart/form-data, use a custom implementation.
 */
public func postFormDataToAPI<T>(
    url: String,
    headers: [String: String]? = nil,
    formData: [String: String],
    failedResponseHandler: ResponseHandler<APICallError>,
    successfulResponseHandler: ResponseHandler<T>,
    isAborted: (@Sendable () -> Bool)? = nil,
    fetch: FetchFunction? = nil
) async throws -> ResponseHandlerResult<T> {
    return try await postToAPI(
        url: url,
        headers: headers,
        body: PostBody(content: .formData(formData), values: formData),
        failedResponseHandler: failedResponseHandler,
        successfulResponseHandler: successfulResponseHandler,
        isAborted: isAborted,
        fetch: fetch
    )
}

// MARK: - Post Body Type

/// Represents the body content for POST requests
public struct PostBody: Sendable {
    public enum Content: Sendable {
        case json(Data)
        case data(Data)
        case formData([String: String])  // Simplified form data (key-value pairs)
    }

    let content: Content
    private let valuesStorage: AnySendable?

    public init(content: Content, values: Any?) {
        self.content = content
        if let values {
            self.valuesStorage = AnySendable(values)
        } else {
            self.valuesStorage = nil
        }
    }

    public var values: Any? {
        valuesStorage?.value
    }
}

// MARK: - Post to API (Base Function)

/**
 Base function for POST requests to API endpoints.

 Handles:
 - User-Agent header injection
 - Response status code checking
 - Error/success handler invocation
 - Error wrapping for network failures

 - Parameters:
   - url: The URL to post to
   - headers: Optional HTTP headers
   - body: The request body with content and values
   - failedResponseHandler: Handler for non-2xx responses
   - successfulResponseHandler: Handler for successful responses
   - isAborted: Optional closure to check cancellation
   - fetch: Optional custom fetch function

 - Returns: The result from successfulResponseHandler
 - Throws: APICallError or handler errors
 */
public func postToAPI<T>(
    url: String,
    headers: [String: String]? = nil,
    body: PostBody,
    failedResponseHandler: ResponseHandler<APICallError>,
    successfulResponseHandler: ResponseHandler<T>,
    isAborted: (@Sendable () -> Bool)? = nil,
    fetch: FetchFunction? = nil
) async throws -> ResponseHandlerResult<T> {
    let fetchImpl = fetch ?? getDefaultFetch()

    do {
        // Prepare request
        guard let requestURL = URL(string: url) else {
            throw APICallError(
                message: "Invalid URL",
                url: url,
                requestBodyValues: body.values
            )
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"

        // Add headers with User-Agent
        let headersWithUA = withUserAgentSuffix(
            headers ?? [:],
            "ai-sdk/provider-utils/\(VERSION)",
            getRuntimeEnvironmentUserAgent()
        )

        for (key, value) in headersWithUA {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Set body
        switch body.content {
        case .json(let data), .data(let data):
            request.httpBody = data
        case .formData(let fields):
            // Encode as application/x-www-form-urlencoded
            // RFC 3986: unreserved = ALPHA / DIGIT / "-" / "." / "_" / "~"
            var allowedCharacters = CharacterSet.alphanumerics
            allowedCharacters.insert(charactersIn: "-._~")

            let formString = fields
                .map { key, value in
                    let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? key
                    let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? value
                    return "\(encodedKey)=\(encodedValue)"
                }
                .joined(separator: "&")
            request.httpBody = formString.data(using: .utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }

        // Check cancellation before fetch
        if isAborted?() == true {
            throw CancellationError()
        }

        // Execute request
        let (data, urlResponse) = try await fetchImpl(request)

        guard let httpResponse = urlResponse as? HTTPURLResponse else {
            throw APICallError(
                message: "Invalid response type",
                url: url,
                requestBodyValues: body.values
            )
        }

        let responseHeaders = extractResponseHeaders(from: httpResponse)

        // Create ProviderHTTPResponse
        let providerResponse = ProviderHTTPResponse(
            url: requestURL,
            httpResponse: httpResponse,
            body: .data(data)
        )

        // Handle non-2xx responses
        if !(200...299).contains(httpResponse.statusCode) {
            let errorInput = ResponseHandlerInput(
                url: url,
                requestBodyValues: body.values,
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
                    requestBodyValues: body.values,
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
            requestBodyValues: body.values,
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
                requestBodyValues: body.values,
                statusCode: httpResponse.statusCode,
                responseHeaders: responseHeaders,
                responseBody: nil,
                cause: error
            )
        }

    } catch {
        throw handleFetchError(error: error, url: url, requestBodyValues: body.values)
    }
}
