import Testing
import Foundation
@testable import AISDKProvider
@testable import AISDKProviderUtils

/**
 Tests for delay utility.

 Port of `@ai-sdk/provider-utils/src/delay.test.ts`

 Note: Swift doesn't have fake timers like Vitest, so these tests use real timing
 but with very short delays for speed.
 */
struct DelayTests {
    @Test("delay resolves after specified time (basic smoke test)")
    func testBasicDelay() async throws {
        let start = Date()
        try await delay(50) // 50ms
        let elapsed = Date().timeIntervalSince(start)

        // Should take at least 50ms (with some tolerance)
        #expect(elapsed >= 0.045) // 45ms tolerance
    }

    @Test("delay resolves immediately when delayInMs is nil")
    func testNilDelay() async throws {
        let start = Date()
        try await delay(nil)
        let elapsed = Date().timeIntervalSince(start)

        // Should be nearly instant (< 10ms)
        #expect(elapsed < 0.01)
    }

    @Test("delay resolves immediately when delayInMs is 0")
    func testZeroDelay() async throws {
        let start = Date()
        try await delay(0)
        let elapsed = Date().timeIntervalSince(start)

        // Should be nearly instant (< 10ms)
        #expect(elapsed < 0.01)
    }

    @Test("delay throws when task is cancelled")
    func testCancellation() async throws {
        let task = Task {
            try await delay(1000) // 1 second
        }

        // Cancel after a short time
        try await delay(10) // 10ms
        task.cancel()

        // Should throw CancellationError
        do {
            try await task.value
            Issue.record("Expected CancellationError to be thrown")
        } catch is CancellationError {
            // Expected
        } catch {
            Issue.record("Expected CancellationError, got \(error)")
        }
    }

    @Test("delay throws immediately if task is already cancelled")
    func testAlreadyCancelled() async throws {
        let task = Task {
            try await delay(100)
        }

        // Cancel immediately
        task.cancel()

        // Should throw CancellationError
        do {
            try await task.value
            Issue.record("Expected CancellationError to be thrown")
        } catch is CancellationError {
            // Expected
        } catch {
            Issue.record("Expected CancellationError, got \(error)")
        }
    }

    @Test("delay works with multiple concurrent delays")
    func testMultipleDelays() async throws {
        var resolved1 = false
        var resolved2 = false
        var resolved3 = false

        // Start three delays
        async let delay1: () = {
            try await delay(20)
            resolved1 = true
        }()

        async let delay2: () = {
            try await delay(40)
            resolved2 = true
        }()

        async let delay3: () = {
            try await delay(60)
            resolved3 = true
        }()

        // Wait for all to complete
        _ = try await (delay1, delay2, delay3)

        #expect(resolved1)
        #expect(resolved2)
        #expect(resolved3)
    }

    @Test("delay handles very large delays (smoke test)")
    func testLargeDelay() async throws {
        // Don't actually wait for this - just verify it compiles and starts
        let task = Task {
            try await delay(Int.max)
        }

        // Cancel immediately to avoid long wait
        task.cancel()

        do {
            try await task.value
        } catch is CancellationError {
            // Expected
        }
    }

    @Test("delay handles negative delays (treated as 0)")
    func testNegativeDelay() async throws {
        let start = Date()
        try await delay(-100)
        let elapsed = Date().timeIntervalSince(start)

        // Should be nearly instant (< 10ms)
        #expect(elapsed < 0.01)
    }
}
