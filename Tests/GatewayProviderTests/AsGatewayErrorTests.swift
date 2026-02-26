import Foundation
import Testing
import AISDKProvider
@testable import GatewayProvider

@Suite("asGatewayError")
struct AsGatewayErrorTests {
    final class MockCodeError: Error, LocalizedError {
        let message: String
        let code: String

        init(message: String, code: String) {
            self.message = message
            self.code = code
        }

        var errorDescription: String? { message }
    }

    final class MockNetworkError: Error, LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    @Test("timeout error detection: UND_ERR_* codes map to GatewayTimeoutError")
    func detectsUndiciTimeoutCodes() async throws {
        let error1 = MockCodeError(message: "Request timeout", code: "UND_ERR_HEADERS_TIMEOUT")
        let result1 = asGatewayError(error1)
        #expect(GatewayTimeoutError.isInstance(result1))
        if let err = result1 as? GatewayTimeoutError {
            #expect(err.message.contains("Request timeout"))
        }

        let error2 = MockCodeError(message: "Body timeout", code: "UND_ERR_BODY_TIMEOUT")
        let result2 = asGatewayError(error2)
        #expect(GatewayTimeoutError.isInstance(result2))

        let error3 = MockCodeError(message: "Connect timeout", code: "UND_ERR_CONNECT_TIMEOUT")
        let result3 = asGatewayError(error3)
        #expect(GatewayTimeoutError.isInstance(result3))
    }

    @Test("non-timeout errors are not treated as GatewayTimeoutError")
    func nonTimeoutErrors() async throws {
        let error = MockNetworkError("Network error")
        let result = asGatewayError(error)

        #expect(GatewayTimeoutError.isInstance(result) == false)
        #expect(GatewayResponseError.isInstance(result))
        if let err = result as? GatewayResponseError {
            #expect(err.message.contains("Gateway request failed: Network error"))
        }

        let connRefused = MockCodeError(message: "Connection refused", code: "ECONNREFUSED")
        let result2 = asGatewayError(connRefused)
        #expect(GatewayTimeoutError.isInstance(result2) == false)
        #expect(GatewayResponseError.isInstance(result2))
    }

    @Test("passes through existing GatewayError instances")
    func passesThroughExistingGatewayError() async throws {
        let existing = GatewayTimeoutError.createTimeoutError(originalMessage: "existing timeout")
        let result = asGatewayError(existing)
        #expect(GatewayTimeoutError.isInstance(result))
        if let err = result as? GatewayTimeoutError {
            #expect(err.message == existing.message)
        }
    }

    @Test("handles non-Error objects and nil")
    func handlesNonErrorObjectsAndNil() async throws {
        let result1 = asGatewayError(["message": "timeout occurred"])
        #expect(GatewayTimeoutError.isInstance(result1) == false)
        #expect(GatewayResponseError.isInstance(result1))

        let result2 = asGatewayError(nil)
        #expect(GatewayTimeoutError.isInstance(result2) == false)
        #expect(GatewayResponseError.isInstance(result2))
    }

    @Test("timeout error properties: cause/status/type")
    func timeoutErrorProperties() async throws {
        let original = MockCodeError(message: "timeout error", code: "UND_ERR_HEADERS_TIMEOUT")
        let result = asGatewayError(original)

        guard let err = result as? GatewayTimeoutError else {
            Issue.record("Expected GatewayTimeoutError")
            return
        }

        #expect(err.statusCode == 408)
        #expect(err.type == "timeout_error")

        if let cause = err.cause as? MockCodeError {
            #expect(cause === original)
        } else {
            Issue.record("Expected cause to be the original error")
        }
    }

    @Test("APICallError with timeout cause maps to GatewayTimeoutError")
    func apiCallErrorWithTimeoutCause() async throws {
        let timeoutCause = MockCodeError(message: "Request timeout", code: "UND_ERR_HEADERS_TIMEOUT")

        let apiError = APICallError(
            message: "Cannot connect to API: Request timeout",
            url: "https://example.com",
            requestBodyValues: [:],
            cause: timeoutCause
        )

        let result = asGatewayError(apiError)
        #expect(GatewayTimeoutError.isInstance(result))
        if let err = result as? GatewayTimeoutError {
            #expect(err.message.contains("Gateway request timed out"))
        }

        let nonTimeout = APICallError(
            message: "Cannot connect to API: Network connection failed",
            url: "https://example.com",
            requestBodyValues: [:],
            statusCode: 500,
            responseBody: #"{"error":{"message":"Internal error","type":"internal_error"}}"#,
            cause: MockNetworkError("Network connection failed")
        )

        let result2 = asGatewayError(nonTimeout)
        #expect(GatewayTimeoutError.isInstance(result2) == false)
    }
}
