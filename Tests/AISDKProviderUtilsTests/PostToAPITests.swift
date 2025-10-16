import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils

/**
 Tests for PostToAPI utilities.

 Note: Upstream `@ai-sdk/provider-utils` does NOT have `post-to-api.test.ts`.
 These tests are created symmetrically to `get-from-api.test.ts` but adapted for POST requests.

 Tests cover:
 1. Successful JSON post with response parsing
 2. API error handling (non-2xx status codes)
 3. Network error handling (connection failures)
 4. Abort signal handling (cancellation)
 5. Header validation (User-Agent injection)
 6. Error handling in response handlers
 7. Form data encoding
 */

@Suite("postToApi")
struct PostToAPITests {
    private struct MockRequest: Codable, Equatable, Sendable {
        let name: String
        let value: Int
    }

    private struct MockResponse: Codable, Equatable, Sendable {
        let success: Bool
        let message: String
    }

    private func mockResponseSchema() -> FlexibleSchema<MockResponse> {
        let jsonSchema: JSONValue = [
            "type": "object",
            "properties": [
                "success": ["type": "boolean"],
                "message": ["type": "string"]
            ],
            "required": [.string("success"), .string("message")]
        ]

        return FlexibleSchema(
            Schema.codable(MockResponse.self, jsonSchema: jsonSchema)
        )
    }

    @Test("should successfully post JSON and parse response")
    func shouldSuccessfullyPostJsonAndParseResponse() async throws {
        let mockRequest = MockRequest(name: "test", value: 123)
        let mockSuccessResponse = MockResponse(success: true, message: "created")
        let mockData = try JSONEncoder().encode(mockSuccessResponse)

        actor RequestCapture {
            var request: URLRequest?
            func capture(_ req: URLRequest) { request = req }
            func get() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let mockFetch: FetchFunction = { request in
            await capture.capture(request)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 201,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": "application/json"
                ]
            )!

            return FetchResponse(body: .data(mockData), urlResponse: httpResponse)
        }

        let result = try await postJsonToAPI(
            url: "https://api.test.com/create",
            headers: ["Authorization": "Bearer test"],
            body: mockRequest,
            failedResponseHandler: createStatusCodeErrorResponseHandler(),
            successfulResponseHandler: createJsonResponseHandler(responseSchema: mockResponseSchema()),
            fetch: mockFetch
        )

        // Verify result
        #expect(result.value == mockSuccessResponse)

        // Verify request was made correctly
        let capturedRequest = await capture.get()
        #expect(capturedRequest?.httpMethod == "POST")
        #expect(capturedRequest?.url?.absoluteString == "https://api.test.com/create")

        // Verify headers
        let headers = capturedRequest?.allHTTPHeaderFields ?? [:]
        #expect(headers["Authorization"] == "Bearer test")
        #expect(headers["Content-Type"] == "application/json")
        #expect(headers["User-Agent"]?.contains("ai-sdk/provider-utils") == true)
        #expect(headers["User-Agent"]?.contains("runtime/") == true)

        // Verify body
        if let body = capturedRequest?.httpBody {
            let decodedRequest = try JSONDecoder().decode(MockRequest.self, from: body)
            #expect(decodedRequest == mockRequest)
        } else {
            Issue.record("Request body is missing")
        }
    }

    @Test("should handle API errors")
    func shouldHandleAPIErrors() async throws {
        let mockRequest = MockRequest(name: "test", value: 123)
        let errorResponse = ["error": "Forbidden"]
        let errorData = try JSONSerialization.data(withJSONObject: errorResponse)

        let mockFetch: FetchFunction = { request in
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 403,
                httpVersion: "HTTP/1.1",
                headerFields: [:]
            )!

            return FetchResponse(body: .data(errorData), urlResponse: httpResponse)
        }

        await #expect(throws: APICallError.self) {
            _ = try await postJsonToAPI(
                url: "https://api.test.com/create",
                body: mockRequest,
                failedResponseHandler: createStatusCodeErrorResponseHandler(),
                successfulResponseHandler: createJsonResponseHandler(responseSchema: mockResponseSchema()),
                fetch: mockFetch
            )
        }
    }

    @Test("should handle network errors")
    func shouldHandleNetworkErrors() async throws {
        let mockRequest = MockRequest(name: "test", value: 123)

        // Simulate network failure
        let mockFetch: FetchFunction = { _ in
            throw URLError(.cannotConnectToHost)
        }

        do {
            _ = try await postJsonToAPI(
                url: "https://api.test.com/create",
                body: mockRequest,
                failedResponseHandler: createStatusCodeErrorResponseHandler(),
                successfulResponseHandler: createJsonResponseHandler(responseSchema: mockResponseSchema()),
                fetch: mockFetch
            )
            Issue.record("Expected error to be thrown")
        } catch let error as APICallError {
            // Verify it's wrapped as APICallError with retryable flag
            #expect(error.isRetryable == true)
            #expect(error.message.contains("Cannot connect to API"))
        } catch {
            Issue.record("Expected APICallError, got \(type(of: error))")
        }
    }

    @Test("should handle abort signals")
    func shouldHandleAbortSignals() async throws {
        let mockRequest = MockRequest(name: "test", value: 123)

        let mockFetch: FetchFunction = { _ in
            // Simulate abort
            throw CancellationError()
        }

        await #expect(throws: Error.self) {
            _ = try await postJsonToAPI(
                url: "https://api.test.com/create",
                body: mockRequest,
                failedResponseHandler: createStatusCodeErrorResponseHandler(),
                successfulResponseHandler: createJsonResponseHandler(responseSchema: mockResponseSchema()),
                fetch: mockFetch
            )
        }
    }

    @Test("should include all required headers")
    func shouldIncludeAllRequiredHeaders() async throws {
        let mockRequest = MockRequest(name: "test", value: 123)
        let mockSuccessResponse = MockResponse(success: true, message: "ok")
        let mockData = try JSONEncoder().encode(mockSuccessResponse)

        actor HeaderCapture {
            var headers: [String: String]?
            func capture(_ h: [String: String]?) { headers = h }
            func get() -> [String: String]? { headers }
        }

        let capture = HeaderCapture()

        let mockFetch: FetchFunction = { request in
            await capture.capture(request.allHTTPHeaderFields)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [:]
            )!

            return FetchResponse(body: .data(mockData), urlResponse: httpResponse)
        }

        _ = try await postJsonToAPI(
            url: "https://api.test.com/create",
            headers: ["Authorization": "Bearer test"],
            body: mockRequest,
            failedResponseHandler: createStatusCodeErrorResponseHandler(),
            successfulResponseHandler: createJsonResponseHandler(responseSchema: mockResponseSchema()),
            fetch: mockFetch
        )

        let capturedHeaders = await capture.get()
        #expect(capturedHeaders?["Authorization"] == "Bearer test")
        #expect(capturedHeaders?["Content-Type"] == "application/json")
        #expect(capturedHeaders?["User-Agent"]?.contains("ai-sdk/provider-utils") == true)
    }

    @Test("should handle errors in response handlers")
    func shouldHandleErrorsInResponseHandlers() async throws {
        let mockRequest = MockRequest(name: "test", value: 123)
        // Return invalid JSON to trigger parsing error
        let invalidJSON = "invalid json".data(using: .utf8)!

        let mockFetch: FetchFunction = { request in
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [:]
            )!

            return FetchResponse(body: .data(invalidJSON), urlResponse: httpResponse)
        }

        await #expect(throws: APICallError.self) {
            _ = try await postJsonToAPI(
                url: "https://api.test.com/create",
                body: mockRequest,
                failedResponseHandler: createStatusCodeErrorResponseHandler(),
                successfulResponseHandler: createJsonResponseHandler(responseSchema: mockResponseSchema()),
                fetch: mockFetch
            )
        }
    }

    @Test("should handle streaming success bodies")
    func shouldHandleStreamingSuccessBodies() async throws {
        let mockRequest = MockRequest(name: "stream", value: 9)
        let mockSuccessResponse = MockResponse(success: true, message: "streamed")
        let encoded = try JSONEncoder().encode(mockSuccessResponse)

        let stream = AsyncThrowingStream<Data, Error> { continuation in
            continuation.yield(encoded)
            continuation.finish()
        }

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.test.com/create")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let mockFetch: FetchFunction = { _ in
            FetchResponse(body: .stream(stream), urlResponse: httpResponse)
        }

        let result = try await postJsonToAPI(
            url: "https://api.test.com/create",
            body: mockRequest,
            failedResponseHandler: createStatusCodeErrorResponseHandler(),
            successfulResponseHandler: createJsonResponseHandler(responseSchema: mockResponseSchema()),
            fetch: mockFetch
        )

        #expect(result.value == mockSuccessResponse)
    }

    @Test("should encode form data correctly")
    func shouldEncodeFormDataCorrectly() async throws {
        let formData = ["username": "test user", "email": "test@example.com"]
        let mockSuccessResponse = MockResponse(success: true, message: "submitted")
        let mockData = try JSONEncoder().encode(mockSuccessResponse)

        actor RequestCapture {
            var request: URLRequest?
            func capture(_ req: URLRequest) { request = req }
            func get() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let mockFetch: FetchFunction = { request in
            await capture.capture(request)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [:]
            )!

            return FetchResponse(body: .data(mockData), urlResponse: httpResponse)
        }

        let result = try await postFormDataToAPI(
            url: "https://api.test.com/submit",
            formData: formData,
            failedResponseHandler: createStatusCodeErrorResponseHandler(),
            successfulResponseHandler: createJsonResponseHandler(responseSchema: mockResponseSchema()),
            fetch: mockFetch
        )

        #expect(result.value == mockSuccessResponse)

        let capturedRequest = await capture.get()
        #expect(capturedRequest?.httpMethod == "POST")

        // Verify Content-Type is form-urlencoded
        let headers = capturedRequest?.allHTTPHeaderFields ?? [:]
        #expect(headers["Content-Type"] == "application/x-www-form-urlencoded")

        // Verify body is properly encoded
        if let body = capturedRequest?.httpBody,
           let bodyString = String(data: body, encoding: .utf8) {
            // Check that both fields are present (order may vary)
            #expect(bodyString.contains("username=test%20user"))
            #expect(bodyString.contains("email=test%40example.com"))
        } else {
            Issue.record("Form data body is missing")
        }
    }
}
