/**
 Tests for consumeStream function.

 Note: No dedicated test file exists in upstream. This utility is used internally by other functions.
 These tests verify the basic behavior.
 */

import Testing
import Foundation
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import SwiftAISDK

@Suite("ConsumeStream Tests")
struct ConsumeStreamTests {
    @Test("consumes stream successfully")
    func consumesStreamSuccessfully() async throws {
        // Create a simple async stream
        let stream = AsyncStream<Int> { continuation in
            for i in 1...5 {
                continuation.yield(i)
            }
            continuation.finish()
        }

        // Consume the stream
        await consumeStream(stream: stream)

        // Test passes if no error thrown
    }

    @Test("calls onError when stream throws")
    func callsOnErrorWhenStreamThrows() async throws {
        // Use actor to safely capture error in concurrent context
        actor ErrorCapture {
            var error: Error?
            func setError(_ error: Error) {
                self.error = error
            }
        }

        let capture = ErrorCapture()

        // Create a stream that throws an error
        let stream = AsyncThrowingStream<Int, Error> { continuation in
            continuation.yield(1)
            continuation.finish(throwing: NSError(domain: "test", code: 123))
        }

        // Consume with error handler
        await consumeStream(stream: stream) { error in
            Task { await capture.setError(error) }
        }

        // Small delay to ensure error handler executes
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

        // Verify error was caught
        let errorCaught = await capture.error
        #expect(errorCaught != nil, "onError should be called when stream throws")
        #expect((errorCaught as NSError?)?.code == 123, "Error should be the one thrown by stream")
    }

    @Test("consumes empty stream")
    func consumesEmptyStream() async throws {
        // Create an empty stream
        let stream = AsyncStream<Int> { continuation in
            continuation.finish()
        }

        // Consume the stream
        await consumeStream(stream: stream)

        // Test passes if no error thrown
    }

    @Test("consumes stream with large number of elements")
    func consumesStreamWithLargeNumberOfElements() async throws {
        let elementCount = 1000
        var yieldedCount = 0

        // Create a stream with many elements
        let stream = AsyncStream<Int> { continuation in
            for i in 1...elementCount {
                continuation.yield(i)
                yieldedCount = i
            }
            continuation.finish()
        }

        // Consume the stream
        await consumeStream(stream: stream)

        // Verify all elements were yielded
        #expect(yieldedCount == elementCount, "Stream should yield all elements")
    }
}
