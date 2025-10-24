import Testing
import Foundation
@testable import AISDKProvider
@testable import AISDKProviderUtils

/**
 Tests for extractResponseHeaders utility function.

 Port of behavior tests for `@ai-sdk/provider-utils/src/extract-response-headers.ts`

 Note: The original TypeScript file has no dedicated test file, but the function is
 extensively used throughout the codebase. These tests verify expected behavior
 based on usage patterns.
 */
struct ExtractResponseHeadersTests {
    /// Helper function to create HTTPURLResponse with custom headers
    private func createResponse(
        url: String = "https://api.example.com",
        statusCode: Int = 200,
        headers: [String: String]
    ) -> HTTPURLResponse {
        return HTTPURLResponse(
            url: URL(string: url)!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    }

    @Test("extractResponseHeaders: extracts headers from response")
    func testBasicExtraction() throws {
        let headers = [
            "Content-Type": "application/json",
            "Content-Length": "1234"
        ]
        let response = createResponse(headers: headers)

        let result = extractResponseHeaders(from: response)

        // Keys are normalized to lowercase to match JavaScript Headers API
        #expect(result["content-type"] == "application/json")
        #expect(result["content-length"] == "1234")
        #expect(result.count == 2)
    }

    @Test("extractResponseHeaders: handles empty headers")
    func testEmptyHeaders() throws {
        let response = createResponse(headers: [:])

        let result = extractResponseHeaders(from: response)

        #expect(result.isEmpty)
    }

    @Test("extractResponseHeaders: extracts multiple headers")
    func testMultipleHeaders() throws {
        let headers = [
            "Content-Type": "application/json",
            "Authorization": "Bearer token",
            "X-Custom-Header": "custom-value",
            "User-Agent": "SwiftAISDK/1.0"
        ]
        let response = createResponse(headers: headers)

        let result = extractResponseHeaders(from: response)

        // Keys are normalized to lowercase to match JavaScript Headers API
        #expect(result["content-type"] == "application/json")
        #expect(result["authorization"] == "Bearer token")
        #expect(result["x-custom-header"] == "custom-value")
        #expect(result["user-agent"] == "SwiftAISDK/1.0")
        #expect(result.count == 4)
    }

    @Test("extractResponseHeaders: preserves header case")
    func testHeaderCase() throws {
        let headers = [
            "Content-Type": "application/json",
            "content-length": "1234",
            "X-CUSTOM-HEADER": "value"
        ]
        let response = createResponse(headers: headers)

        let result = extractResponseHeaders(from: response)

        // All keys are normalized to lowercase to match JavaScript Headers API
        // Note: HTTP headers are case-insensitive per RFC 2616
        #expect(result["content-type"] == "application/json")
        #expect(result["content-length"] == "1234")
        #expect(result["x-custom-header"] == "value")
        #expect(result.count == 3)
    }

    @Test("extractResponseHeaders: handles common HTTP headers")
    func testCommonHTTPHeaders() throws {
        let headers = [
            "Content-Type": "application/json; charset=utf-8",
            "Cache-Control": "no-cache",
            "Date": "Mon, 12 Oct 2025 12:00:00 GMT",
            "Server": "nginx/1.21.0",
            "X-RateLimit-Remaining": "99",
            "X-Request-Id": "req-123456"
        ]
        let response = createResponse(headers: headers)

        let result = extractResponseHeaders(from: response)

        // Keys are normalized to lowercase to match JavaScript Headers API
        #expect(result["content-type"] == "application/json; charset=utf-8")
        #expect(result["cache-control"] == "no-cache")
        #expect(result["date"] == "Mon, 12 Oct 2025 12:00:00 GMT")
        #expect(result["server"] == "nginx/1.21.0")
        #expect(result["x-ratelimit-remaining"] == "99")
        #expect(result["x-request-id"] == "req-123456")
        #expect(result.count == 6)
    }

    @Test("extractResponseHeaders: handles different status codes")
    func testDifferentStatusCodes() throws {
        let headers = ["Content-Type": "application/json"]

        // Test 200 OK
        let response200 = createResponse(statusCode: 200, headers: headers)
        let result200 = extractResponseHeaders(from: response200)
        #expect(result200["content-type"] == "application/json")

        // Test 404 Not Found
        let response404 = createResponse(statusCode: 404, headers: headers)
        let result404 = extractResponseHeaders(from: response404)
        #expect(result404["content-type"] == "application/json")

        // Test 500 Internal Server Error
        let response500 = createResponse(statusCode: 500, headers: headers)
        let result500 = extractResponseHeaders(from: response500)
        #expect(result500["content-type"] == "application/json")
    }

    @Test("extractResponseHeaders: handles special characters in values")
    func testSpecialCharactersInValues() throws {
        let headers = [
            "X-Custom": "value with spaces",
            "X-Quotes": "\"quoted value\"",
            "X-Unicode": "Hello 世界 🌍"
        ]
        let response = createResponse(headers: headers)

        let result = extractResponseHeaders(from: response)

        // Keys are normalized to lowercase to match JavaScript Headers API
        #expect(result["x-custom"] == "value with spaces")
        #expect(result["x-quotes"] == "\"quoted value\"")
        #expect(result["x-unicode"] == "Hello 世界 🌍")
    }
}
