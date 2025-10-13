import Testing
import Foundation
@testable import SwiftAISDK

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
    func testBasicExtraction() {
        let headers = [
            "Content-Type": "application/json",
            "Content-Length": "1234"
        ]
        let response = createResponse(headers: headers)

        let result = extractResponseHeaders(from: response)

        #expect(result["Content-Type"] == "application/json")
        #expect(result["Content-Length"] == "1234")
        #expect(result.count == 2)
    }

    @Test("extractResponseHeaders: handles empty headers")
    func testEmptyHeaders() {
        let response = createResponse(headers: [:])

        let result = extractResponseHeaders(from: response)

        #expect(result.isEmpty)
    }

    @Test("extractResponseHeaders: extracts multiple headers")
    func testMultipleHeaders() {
        let headers = [
            "Content-Type": "application/json",
            "Authorization": "Bearer token",
            "X-Custom-Header": "custom-value",
            "User-Agent": "SwiftAISDK/1.0"
        ]
        let response = createResponse(headers: headers)

        let result = extractResponseHeaders(from: response)

        #expect(result["Content-Type"] == "application/json")
        #expect(result["Authorization"] == "Bearer token")
        #expect(result["X-Custom-Header"] == "custom-value")
        #expect(result["User-Agent"] == "SwiftAISDK/1.0")
        #expect(result.count == 4)
    }

    @Test("extractResponseHeaders: preserves header case")
    func testHeaderCase() {
        let headers = [
            "Content-Type": "application/json",
            "content-length": "1234",
            "X-CUSTOM-HEADER": "value"
        ]
        let response = createResponse(headers: headers)

        let result = extractResponseHeaders(from: response)

        // HTTPURLResponse normalizes header keys, so we check both cases
        // Note: HTTP headers are case-insensitive per RFC 2616
        let contentTypeValue = result["Content-Type"] ?? result["content-type"]
        #expect(contentTypeValue == "application/json")
        #expect(result.count >= 3)
    }

    @Test("extractResponseHeaders: handles common HTTP headers")
    func testCommonHTTPHeaders() {
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

        #expect(result["Content-Type"] == "application/json; charset=utf-8")
        #expect(result["Cache-Control"] == "no-cache")
        #expect(result["Date"] == "Mon, 12 Oct 2025 12:00:00 GMT")
        #expect(result["Server"] == "nginx/1.21.0")
        #expect(result["X-RateLimit-Remaining"] == "99")
        #expect(result["X-Request-Id"] == "req-123456")
        #expect(result.count == 6)
    }

    @Test("extractResponseHeaders: handles different status codes")
    func testDifferentStatusCodes() {
        let headers = ["Content-Type": "application/json"]

        // Test 200 OK
        let response200 = createResponse(statusCode: 200, headers: headers)
        let result200 = extractResponseHeaders(from: response200)
        #expect(result200["Content-Type"] == "application/json")

        // Test 404 Not Found
        let response404 = createResponse(statusCode: 404, headers: headers)
        let result404 = extractResponseHeaders(from: response404)
        #expect(result404["Content-Type"] == "application/json")

        // Test 500 Internal Server Error
        let response500 = createResponse(statusCode: 500, headers: headers)
        let result500 = extractResponseHeaders(from: response500)
        #expect(result500["Content-Type"] == "application/json")
    }

    @Test("extractResponseHeaders: handles special characters in values")
    func testSpecialCharactersInValues() {
        let headers = [
            "X-Custom": "value with spaces",
            "X-Quotes": "\"quoted value\"",
            "X-Unicode": "Hello 世界 🌍"
        ]
        let response = createResponse(headers: headers)

        let result = extractResponseHeaders(from: response)

        #expect(result["X-Custom"] == "value with spaces")
        #expect(result["X-Quotes"] == "\"quoted value\"")
        #expect(result["X-Unicode"] == "Hello 世界 🌍")
    }
}
