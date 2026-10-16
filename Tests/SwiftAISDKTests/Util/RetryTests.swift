import Testing
import AISDKProvider
import SwiftAISDK
import GatewayProvider

@Suite("SDK retry boundaries")
struct RetryTests {
    @Test("exhausted gateway retries retain typed errors and their rendered message")
    func exhaustedGatewayRetries() async throws {
        let retry = retryWithExponentialBackoffRespectingRetryHeaders(maxRetries: 1, initialDelayInMs: 0)
        do {
            _ = try await retry.call { () async throws -> Int in throw GatewayRateLimitError() }
            Issue.record("Expected retry exhaustion")
        } catch let error as RetryError {
            #expect(error.reason == .maxRetriesExceeded)
            #expect(error.errors.count == 2)
            #expect(error.lastError is GatewayRateLimitError)
            #expect(error.message == "Failed after 2 attempts. Last error: GatewayRateLimitError: Rate limit exceeded")
        }
    }

    @Test("non-finite and oversized Retry-After values use the configured backoff", arguments: ["Infinity", "1e100"])
    func unreasonableRetryHeader(value: String) async throws {
        actor Attempts {
            var first = true
            func consumeFirst() -> Bool {
                defer { first = false }
                return first
            }
        }
        let attempts = Attempts()
        let retry = retryWithExponentialBackoffRespectingRetryHeaders(maxRetries: 1, initialDelayInMs: 0)
        let result = try await retry.call {
            if await attempts.consumeFirst() {
                throw APICallError(
                    message: "transient", url: "https://example.com/model", requestBodyValues: nil,
                    statusCode: 503, responseHeaders: ["retry-after-ms": value]
                )
            }
            return 42
        }
        #expect(result == 42)
    }
}
