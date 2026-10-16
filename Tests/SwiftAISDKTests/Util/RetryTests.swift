import Testing
import Foundation
import AISDKProvider
import SwiftAISDK
import GatewayProvider

@Suite("SDK retry boundaries")
struct RetryTests {
    @Test("gateway retryability overrides the HTTP status default", arguments: [(200, true), (503, false)])
    func explicitGatewayRetryability(status: Int, retryable: Bool) async throws {
        actor Attempts {
            var first = true
            func consumeFirst() -> Bool {
                defer { first = false }
                return first
            }
        }
        let attempts = Attempts()
        let retry = retryWithExponentialBackoffRespectingRetryHeaders(maxRetries: 1, initialDelayInMs: 0)
        do {
            let result = try await retry.call {
                if await attempts.consumeFirst() {
                    throw GatewayResponseError(statusCode: status, isRetryable: retryable)
                }
                return 42
            }
            #expect(retryable)
            #expect(result == 42)
        } catch let error as GatewayResponseError {
            #expect(!retryable)
            #expect(error.statusCode == status)
        }
    }

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

    @Test("Retry-After on a gateway cause delays a retry beyond the configured backoff")
    func honorsGatewayRetryAfter() async throws {
        actor Attempts {
            var first = true
            func consumeFirst() -> Bool {
                defer { first = false }
                return first
            }
        }
        let attempts = Attempts()
        let retry = retryWithExponentialBackoffRespectingRetryHeaders(maxRetries: 1, initialDelayInMs: 0)
        let clock = ContinuousClock()
        let start = clock.now
        let result = try await retry.call {
            if await attempts.consumeFirst() {
                throw GatewayRateLimitError(cause: APICallError(
                    message: "rate limit", url: "https://example.com/model", requestBodyValues: nil,
                    statusCode: 429, responseHeaders: ["retry-after": "0.02"]
                ))
            }
            return 42
        }
        #expect(result == 42)
        #expect(start.duration(to: clock.now) >= .milliseconds(20))
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
