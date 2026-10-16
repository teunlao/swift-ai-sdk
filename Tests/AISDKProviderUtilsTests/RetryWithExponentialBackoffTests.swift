import Foundation
import Testing
@testable import AISDKProviderUtils

@Suite("retryWithExponentialBackoff")
struct RetryWithExponentialBackoffTests {
    private struct Flaky: Error {}
    private struct Fatal: Error {}

    private actor Attempts {
        private(set) var count = 0
        func next() -> Int {
            count += 1
            return count
        }
    }

    private struct Stopped: Error {
        let reason: RetryFunction.ErrorReason
        let attempts: Int
    }

    private func retry(maxRetries: Int = 2) -> RetryFunction {
        retryWithExponentialBackoff(
            maxRetries: maxRetries,
            initialDelayInMs: 0,
            shouldRetry: { $0 is Flaky },
            createRetryError: { _, reason, errors in Stopped(reason: reason, attempts: errors.count) }
        )
    }

    @Test("retries retryable errors until the operation succeeds")
    func retriesUntilSuccess() async throws {
        let attempts = Attempts()
        let value = try await retry()({
            if await attempts.next() < 3 { throw Flaky() }
            return "ok"
        })

        #expect(value == "ok")
        #expect(await attempts.count == 3)
    }

    @Test("stops after maxRetries with a maxRetriesExceeded error")
    func stopsAfterMaxRetries() async throws {
        let attempts = Attempts()
        let error = await #expect(throws: Stopped.self) {
            _ = try await retry()({ () async throws -> String in
                _ = await attempts.next()
                throw Flaky()
            })
        }

        #expect(error?.reason == .maxRetriesExceeded)
        #expect(error?.attempts == 3)
    }

    @Test("rethrows a first-try non-retryable error unwrapped and wraps later ones")
    func handlesNonRetryableErrors() async throws {
        await #expect(throws: Fatal.self) {
            _ = try await retry()({ () async throws -> String in throw Fatal() })
        }

        let attempts = Attempts()
        let error = await #expect(throws: Stopped.self) {
            _ = try await retry()({ () async throws -> String in
                if await attempts.next() == 1 { throw Flaky() }
                throw Fatal()
            })
        }
        #expect(error?.reason == .errorNotRetryable)
        #expect(error?.attempts == 2)
    }
}
