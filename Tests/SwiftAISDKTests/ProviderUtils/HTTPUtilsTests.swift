import Testing
import Foundation
@testable import SwiftAISDK

/**
 Tests for HTTP utilities.
 Port of tests from is-abort-error.ts, resolve.ts, handle-fetch-error.ts
 */
struct HTTPUtilsTests {
    // MARK: - IsAbortError

    @Test("isAbortError detects CancellationError")
    func testCancellationError() {
        let error = CancellationError()
        #expect(isAbortError(error))
    }

    @Test("isAbortError detects URLError.cancelled")
    func testURLErrorCancelled() {
        let error = URLError(.cancelled)
        #expect(isAbortError(error))
    }

    @Test("isAbortError detects URLError.timedOut")
    func testURLErrorTimedOut() {
        let error = URLError(.timedOut)
        #expect(isAbortError(error))
    }

    @Test("isAbortError returns false for other errors")
    func testNonAbortError() {
        let error = URLError(.badURL)
        #expect(!isAbortError(error))
    }

    // MARK: - Resolve

    @Test("resolve handles raw value")
    func testResolveRawValue() async {
        let result = await resolve("test-value")
        #expect(result == "test-value")
    }

    @Test("resolve handles sync closure")
    func testResolveSyncClosure() async {
        let result = await resolve { "sync-value" }
        #expect(result == "sync-value")
    }

    @Test("resolve handles sync throwing closure")
    func testResolveSyncThrowingClosure() async {
        do {
            _ = try await resolve {
                throw URLError(.badURL)
            }
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(error is URLError)
        }
    }

    @Test("resolve handles async closure")
    func testResolveAsyncClosure() async throws {
        let result = try await resolve {
            try await Task.sleep(nanoseconds: 1_000_000) // 1ms
            return "async-value"
        }
        #expect(result == "async-value")
    }

    @Test("resolve handles async throwing closure")
    func testResolveAsyncThrowingClosure() async {
        do {
            _ = try await resolve {
                try await Task.sleep(nanoseconds: 1_000_000)
                throw URLError(.timedOut)
            }
            Issue.record("Expected error to be thrown")
        } catch {
            #expect(error is URLError)
        }
    }

    @Test("resolve handles nested objects")
    func testResolveNestedObjects() async {
        struct Nested: Equatable {
            let nested: Inner
            struct Inner: Equatable {
                let value: Int
            }
        }
        let value = Nested(nested: Nested.Inner(value: 42))
        let result = await resolve(value)
        #expect(result == value)
    }

    @Test("resolve handles optional nil")
    func testResolveOptionalNil() async {
        let value: String? = nil
        let result = await resolve(value)
        #expect(result == nil)
    }

    @Test("resolve handles dictionary (headers use-case)")
    func testResolveHeadersDictionary() async {
        let headers = ["Content-Type": "application/json"]
        let result = await resolve(headers)
        #expect(result == headers)
    }

    @Test("resolve handles function returning dictionary")
    func testResolveHeadersFunction() async {
        let headers: @Sendable () -> [String: String] = { ["Authorization": "Bearer token"] }
        let result: [String: String] = await resolve(headers)
        #expect(result == ["Authorization": "Bearer token"])
    }

    @Test("resolve handles async function returning dictionary")
    func testResolveHeadersAsyncFunction() async throws {
        let headers: @Sendable () async throws -> [String: String] = {
            try await Task.sleep(nanoseconds: 1_000_000)
            return ["X-Custom": "value"]
        }
        let result: [String: String] = try await resolve(headers)
        #expect(result == ["X-Custom": "value"])
    }

    @Test("resolve calls closure each time (stateful)")
    func testResolveStatefulClosure() async {
        final class Counter: @unchecked Sendable {
            var value = 0
        }
        let counter = Counter()

        let headers: @Sendable () -> [String: String] = {
            counter.value += 1
            return ["X-Request-Number": "\(counter.value)"]
        }

        let result1 = await resolve(headers)
        #expect(result1 == ["X-Request-Number": "1"])

        let result2 = await resolve(headers)
        #expect(result2 == ["X-Request-Number": "2"])

        let result3 = await resolve(headers)
        #expect(result3 == ["X-Request-Number": "3"])
    }

    // MARK: - HandleFetchError

    @Test("handleFetchError preserves abort errors")
    func testHandleFetchAbortError() {
        let error = CancellationError()
        let result = handleFetchError(
            error: error,
            url: "https://api.test.com",
            requestBodyValues: nil
        )
        #expect(result is CancellationError)
    }

    @Test("handleFetchError converts network errors to APICallError")
    func testHandleFetchNetworkError() {
        let error = URLError(.cannotConnectToHost)
        let result = handleFetchError(
            error: error,
            url: "https://api.test.com",
            requestBodyValues: nil
        )

        #expect(result is APICallError)
        if let apiError = result as? APICallError {
            #expect(apiError.isRetryable == true)
            #expect(apiError.url == "https://api.test.com")
        }
    }

    @Test("handleFetchError preserves other errors")
    func testHandleFetchOtherError() {
        let error = URLError(.badURL)
        let result = handleFetchError(
            error: error,
            url: "https://api.test.com",
            requestBodyValues: nil
        )
        #expect(result is URLError)
    }
}
