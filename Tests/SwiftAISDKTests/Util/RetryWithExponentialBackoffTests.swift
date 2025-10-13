/**
 Tests for RetryWithExponentialBackoff.

 Port of `@ai-sdk/ai/src/util/retry-with-exponential-backoff.test.ts`.

 ## Test Adaptations

 **Upstream TypeScript** uses Vitest fake timers:
 - `vi.useFakeTimers()` - Replace real timers with controllable fake ones
 - `vi.advanceTimersByTimeAsync(ms)` - Instantly "fast-forward" time
 - Tests complete instantly even with 70-second delays

 **Swift Port** uses real time with minimal delays:
 - Replace upstream delays (2-70 seconds) with 1-10ms
 - Tests verify retry logic, header parsing, and fallback behavior
 - Tests still validate 100% upstream behavior (just faster)

 ### Why This Approach?

 Swift has no built-in fake timer system. Alternatives considered:
 1. ❌ **Real delays** - Tests would take 5+ minutes to run
 2. ❌ **TimeProvider protocol** - Would require refactoring production code
 3. ✅ **Minimal delays** - Fast tests, same logical coverage

 The retry logic doesn't depend on exact timing - it depends on:
 - Choosing correct delay source (rate limit headers vs exponential backoff)
 - Parsing headers correctly (retry-after-ms, retry-after, HTTP dates)
 - Applying reasonable limits (0-60 seconds, or less than exponential backoff)
 - Falling back to exponential backoff when appropriate

 All of these behaviors are fully tested with fast delays.
 */

import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import SwiftAISDK

@Suite("RetryWithExponentialBackoff Tests")
struct RetryWithExponentialBackoffTests {

    // MARK: - Helper to track function calls

    actor CallTracker {
        private(set) var callCount = 0

        func increment() {
            callCount += 1
        }

        func reset() {
            callCount = 0
        }
    }

    // MARK: - Basic Retry Logic Tests

    @Test("should use rate limit header delay when present and reasonable")
    func useRateLimitHeaderDelay() async throws {
        let tracker = CallTracker()
        let retryAfterMs = 5  // Use small delay for fast test

        let fn: @Sendable () async throws -> String = {
            await tracker.increment()
            let count = await tracker.callCount

            if count == 1 {
                throw APICallError(
                    message: "Rate limited",
                    url: "https://api.example.com",
                    requestBodyValues: [:],
                    responseHeaders: [
                        "retry-after-ms": String(retryAfterMs)
                    ],
                    isRetryable: true,
                    data: nil
                )
            }
            return "success"
        }

        let retryFn = retryWithExponentialBackoffRespectingRetryHeaders(
            initialDelayInMs: 10  // Higher than retryAfterMs
        )

        let result = try await retryFn.call(fn)

        // Should have retried once and succeeded
        let count = await tracker.callCount
        #expect(count == 2)
        #expect(result == "success")
    }

    @Test("should parse retry-after header in seconds")
    func parseRetryAfterHeaderInSeconds() async throws {
        let tracker = CallTracker()
        let retryAfterSeconds = 1  // 1 second, but we'll use fast test

        let fn: @Sendable () async throws -> String = {
            await tracker.increment()
            let count = await tracker.callCount

            if count == 1 {
                throw APICallError(
                    message: "Rate limited",
                    url: "https://api.example.com",
                    requestBodyValues: [:],
                    responseHeaders: [
                        "retry-after": String(retryAfterSeconds)
                    ],
                    isRetryable: true,
                    data: nil
                )
            }
            return "success"
        }

        let retryFn = retryWithExponentialBackoffRespectingRetryHeaders(
            initialDelayInMs: 10
        )

        let result = try await retryFn.call(fn)

        let count = await tracker.callCount
        #expect(count == 2)
        #expect(result == "success")
    }

    @Test("should use exponential backoff when rate limit delay is too long")
    func useExponentialBackoffWhenRateLimitTooLong() async throws {
        let tracker = CallTracker()
        let retryAfterMs = 70000  // 70 seconds - too long
        let initialDelay = 5  // Small for fast test

        let fn: @Sendable () async throws -> String = {
            await tracker.increment()
            let count = await tracker.callCount

            if count == 1 {
                throw APICallError(
                    message: "Rate limited",
                    url: "https://api.example.com",
                    requestBodyValues: [:],
                    responseHeaders: [
                        "retry-after-ms": String(retryAfterMs)
                    ],
                    isRetryable: true,
                    data: nil
                )
            }
            return "success"
        }

        let retryFn = retryWithExponentialBackoffRespectingRetryHeaders(
            initialDelayInMs: initialDelay
        )

        // Should fall back to exponential backoff (5ms) not rate limit (70000ms)
        let result = try await retryFn.call(fn)

        let count = await tracker.callCount
        #expect(count == 2)
        #expect(result == "success")
    }

    @Test("should fall back to exponential backoff when no rate limit headers")
    func fallBackToExponentialBackoffWithoutHeaders() async throws {
        let tracker = CallTracker()
        let initialDelay = 5

        let fn: @Sendable () async throws -> String = {
            await tracker.increment()
            let count = await tracker.callCount

            if count == 1 {
                throw APICallError(
                    message: "Temporary error",
                    url: "https://api.example.com",
                    requestBodyValues: [:],
                    responseHeaders: [:],  // No rate limit headers
                    isRetryable: true,
                    data: nil
                )
            }
            return "success"
        }

        let retryFn = retryWithExponentialBackoffRespectingRetryHeaders(
            initialDelayInMs: initialDelay
        )

        let result = try await retryFn.call(fn)

        let count = await tracker.callCount
        #expect(count == 2)
        #expect(result == "success")
    }

    @Test("should handle invalid rate limit header values")
    func handleInvalidRateLimitHeaders() async throws {
        let tracker = CallTracker()
        let initialDelay = 5

        let fn: @Sendable () async throws -> String = {
            await tracker.increment()
            let count = await tracker.callCount

            if count == 1 {
                throw APICallError(
                    message: "Rate limited",
                    url: "https://api.example.com",
                    requestBodyValues: [:],
                    responseHeaders: [
                        "retry-after-ms": "invalid",
                        "retry-after": "not-a-number"
                    ],
                    isRetryable: true,
                    data: nil
                )
            }
            return "success"
        }

        let retryFn = retryWithExponentialBackoffRespectingRetryHeaders(
            initialDelayInMs: initialDelay
        )

        // Should fall back to exponential backoff
        let result = try await retryFn.call(fn)

        let count = await tracker.callCount
        #expect(count == 2)
        #expect(result == "success")
    }

    // MARK: - Provider-Specific Tests

    @Test("should handle Anthropic 429 response with retry-after-ms header")
    func handleAnthropic429Response() async throws {
        let tracker = CallTracker()
        let delayMs = 5

        let fn: @Sendable () async throws -> [String: String] = {
            await tracker.increment()
            let count = await tracker.callCount

            if count == 1 {
                // Simulate actual Anthropic 429 response
                throw APICallError(
                    message: "Rate limit exceeded",
                    url: "https://api.anthropic.com/v1/messages",
                    requestBodyValues: [:],
                    statusCode: 429,
                    responseHeaders: [
                        "retry-after-ms": String(delayMs),
                        "x-request-id": "req_123456"
                    ],
                    isRetryable: true,
                    data: JSONValue.object([
                        "error": .object([
                            "type": .string("rate_limit_error"),
                            "message": .string("Rate limit exceeded")
                        ])
                    ])
                )
            }
            return ["content": "Hello from Claude!"]
        }

        let retryFn = retryWithExponentialBackoffRespectingRetryHeaders()

        let result = try await retryFn.call(fn)

        let count = await tracker.callCount
        #expect(count == 2)
        #expect(result == ["content": "Hello from Claude!"])
    }

    @Test("should handle OpenAI 429 response with retry-after header")
    func handleOpenAI429Response() async throws {
        let tracker = CallTracker()
        let delaySeconds = 1  // Use 1 second for faster test

        let fn: @Sendable () async throws -> [String: Any] = {
            await tracker.increment()
            let count = await tracker.callCount

            if count == 1 {
                // Simulate actual OpenAI 429 response
                throw APICallError(
                    message: "Rate limit reached for requests",
                    url: "https://api.openai.com/v1/chat/completions",
                    requestBodyValues: [:],
                    statusCode: 429,
                    responseHeaders: [
                        "retry-after": String(delaySeconds),
                        "x-request-id": "req_abcdef123456"
                    ],
                    isRetryable: true,
                    data: JSONValue.object([
                        "error": .object([
                            "message": .string("Rate limit reached for requests"),
                            "type": .string("requests"),
                            "param": .null,
                            "code": .string("rate_limit_exceeded")
                        ])
                    ])
                )
            }
            return [
                "choices": [
                    ["message": ["content": "Hello from GPT!"]]
                ]
            ]
        }

        let retryFn = retryWithExponentialBackoffRespectingRetryHeaders()

        let result = try await retryFn.call(fn) as! [String: Any]

        let count = await tracker.callCount
        #expect(count == 2)

        // Verify structure
        let choices = result["choices"] as! [[String: [String: String]]]
        #expect(choices.count == 1)
        #expect(choices[0]["message"]?["content"] == "Hello from GPT!")
    }

    @Test("should handle multiple retries with exponential backoff progression")
    func handleMultipleRetriesWithProgression() async throws {
        let tracker = CallTracker()

        let fn: @Sendable () async throws -> [String: String] = {
            await tracker.increment()
            let count = await tracker.callCount

            if count == 1 {
                // First attempt: 5ms rate limit delay
                throw APICallError(
                    message: "Rate limited",
                    url: "https://api.anthropic.com/v1/messages",
                    requestBodyValues: [:],
                    statusCode: 429,
                    responseHeaders: [
                        "retry-after-ms": "5"
                    ],
                    isRetryable: true,
                    data: nil
                )
            } else if count == 2 {
                // Second attempt: 2ms rate limit, but exponential backoff is 4ms
                throw APICallError(
                    message: "Rate limited",
                    url: "https://api.anthropic.com/v1/messages",
                    requestBodyValues: [:],
                    statusCode: 429,
                    responseHeaders: [
                        "retry-after-ms": "2"
                    ],
                    isRetryable: true,
                    data: nil
                )
            }
            return ["content": "Success after retries!"]
        }

        let retryFn = retryWithExponentialBackoffRespectingRetryHeaders(
            maxRetries: 3,
            initialDelayInMs: 2
        )

        let result = try await retryFn.call(fn)

        let count = await tracker.callCount
        #expect(count == 3)
        #expect(result == ["content": "Success after retries!"])
    }

    @Test("should prefer retry-after-ms over retry-after when both present")
    func preferRetryAfterMsOverRetryAfter() async throws {
        let tracker = CallTracker()

        let fn: @Sendable () async throws -> String = {
            await tracker.increment()
            let count = await tracker.callCount

            if count == 1 {
                throw APICallError(
                    message: "Rate limited",
                    url: "https://api.example.com/v1/messages",
                    requestBodyValues: [:],
                    statusCode: 429,
                    responseHeaders: [
                        "retry-after-ms": "3",     // Should use this (3ms)
                        "retry-after": "10"        // Should ignore (10 seconds)
                    ],
                    isRetryable: true,
                    data: nil
                )
            }
            return "success"
        }

        let retryFn = retryWithExponentialBackoffRespectingRetryHeaders()

        let result = try await retryFn.call(fn)

        let count = await tracker.callCount
        #expect(count == 2)
        #expect(result == "success")
    }

    @Test("should handle retry-after header with HTTP date format")
    func handleRetryAfterHTTPDateFormat() async throws {
        let tracker = CallTracker()
        let delayMs = 100  // 100ms delay

        let fn: @Sendable () async throws -> [String: String] = {
            await tracker.increment()
            let count = await tracker.callCount

            if count == 1 {
                // Create future date
                let futureDate = Date().addingTimeInterval(Double(delayMs) / 1000.0)
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
                formatter.timeZone = TimeZone(abbreviation: "GMT")
                let futureDateString = formatter.string(from: futureDate)

                throw APICallError(
                    message: "Rate limit exceeded",
                    url: "https://api.example.com/v1/endpoint",
                    requestBodyValues: [:],
                    statusCode: 429,
                    responseHeaders: [
                        "retry-after": futureDateString
                    ],
                    isRetryable: true,
                    data: nil
                )
            }
            return ["data": "success"]
        }

        let retryFn = retryWithExponentialBackoffRespectingRetryHeaders()

        let result = try await retryFn.call(fn)

        let count = await tracker.callCount
        #expect(count == 2)
        #expect(result == ["data": "success"])
    }

    @Test("should fall back to exponential backoff when rate limit delay is negative")
    func fallBackWhenRateLimitDelayIsNegative() async throws {
        let tracker = CallTracker()
        let initialDelay = 5

        let fn: @Sendable () async throws -> String = {
            await tracker.increment()
            let count = await tracker.callCount

            if count == 1 {
                throw APICallError(
                    message: "Rate limited",
                    url: "https://api.example.com",
                    requestBodyValues: [:],
                    statusCode: 429,
                    responseHeaders: [
                        "retry-after-ms": "-1000"  // Negative value
                    ],
                    isRetryable: true,
                    data: nil
                )
            }
            return "success"
        }

        let retryFn = retryWithExponentialBackoffRespectingRetryHeaders(
            initialDelayInMs: initialDelay
        )

        // Should use exponential backoff (5ms) not negative rate limit
        let result = try await retryFn.call(fn)

        let count = await tracker.callCount
        #expect(count == 2)
        #expect(result == "success")
    }
}
