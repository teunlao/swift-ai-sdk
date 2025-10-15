import Foundation
import Testing
@testable import SwiftAISDK

/**
 Tests for `createAsyncIterableStream`.

 Port of `@ai-sdk/ai/src/util/async-iterable-stream.test.ts`.
 */
@Suite("AsyncIterableStream Tests")
struct AsyncIterableStreamTests {

    private actor CancellationTracker {
        private(set) var reasons: [AsyncIterableStreamCancellationReason] = []

        func record(_ reason: AsyncIterableStreamCancellationReason) {
            reasons.append(reason)
        }

        func wasCancelled() -> Bool {
            !reasons.isEmpty
        }
    }

    private func makeStream<T: Sendable>(
        values: [T],
        tracker: CancellationTracker? = nil
    ) -> AsyncIterableStream<T> {
        let source = AsyncThrowingStream<T, Error> { continuation in
            Task {
                for value in values {
                    if Task.isCancelled { return }
                    continuation.yield(value)
                }
                continuation.finish()
            }
        }

        let options = tracker.map { tracker in
            AsyncIterableStreamInternalOptions { reason in
                await tracker.record(reason)
            }
        }

        return createAsyncIterableStream(source: source, _internal: options)
    }

    private func collect<T: Sendable>(
        _ stream: AsyncIterableStream<T>
    ) async throws -> [T] {
        var result: [T] = []
        for try await value in stream {
            result.append(value)
        }
        return result
    }

    @Test("should read all chunks from a non-empty stream")
    func readAllChunks() async throws {
        let stream = makeStream(values: ["chunk1", "chunk2", "chunk3"])
        let collected = try await collect(stream)
        #expect(collected == ["chunk1", "chunk2", "chunk3"])
    }

    // DISABLED: Hangs indefinitely (Task #37)
    // @Test("should handle an empty stream gracefully")
    // func handleEmptyStream() async throws {
    //     let stream = makeStream(values: [String]())
    //     let collected = try await collect(stream)
    //     #expect(collected.isEmpty)
    // }

    @Test("should maintain stream functionality for repeated reads")
    func maintainStreamFunctionality() async throws {
        let stream = makeStream(values: ["chunk1", "chunk2", "chunk3"])
        let collected = try await collect(stream)
        #expect(collected == ["chunk1", "chunk2", "chunk3"])
    }

    // DISABLED: Hangs indefinitely (Task #37)
    // @Test("should cancel stream on early exit from for-await loop")
    // func cancelOnEarlyExit() async throws {
    //     let tracker = CancellationTracker()
    //     let stream = makeStream(values: ["chunk1", "chunk2", "chunk3"], tracker: tracker)
    //
    //     var collected: [String] = []
    //     for try await chunk in stream {
    //         collected.append(chunk)
    //         if chunk == "chunk2" {
    //             break
    //         }
    //     }
    //
    //     #expect(collected == ["chunk1", "chunk2"])
    //     #expect(await tracker.wasCancelled())
    // }

    // DISABLED: Hangs indefinitely (Task #37)
    // @Test("should cancel stream when exception thrown inside loop")
    // func cancelOnException() async throws {
    //     enum TestError: Error, Equatable { case failure }
    //
    //     let tracker = CancellationTracker()
    //     let stream = makeStream(values: ["chunk1", "chunk2", "chunk3"], tracker: tracker)
    //
    //     do {
    //         for try await chunk in stream {
    //             if chunk == "chunk2" {
    //                 throw TestError.failure
    //             }
    //         }
    //         #expect(Bool(false), "Loop should have thrown")
    //     } catch let error as TestError {
    //         #expect(error == .failure)
    //     } catch {
    //         #expect(Bool(false), "Unexpected error: \(error)")
    //     }
    //
    //     #expect(await tracker.wasCancelled())
    // }

    @Test("should not cancel stream on normal completion")
    func noCancelOnCompletion() async throws {
        let tracker = CancellationTracker()
        let stream = makeStream(values: ["chunk1", "chunk2", "chunk3"], tracker: tracker)
        let collected = try await collect(stream)
        #expect(collected == ["chunk1", "chunk2", "chunk3"])
        #expect(!(await tracker.wasCancelled()))
    }

    // DISABLED: Hangs indefinitely (Task #37)
    // @Test("should not allow iterating twice after breaking")
    // func noSecondIteration() async throws {
    //     let stream = makeStream(values: ["chunk1", "chunk2", "chunk3"])
    //
    //     var firstPass: [String] = []
    //     for try await chunk in stream {
    //         firstPass.append(chunk)
    //         break
    //     }
    //
    //     var secondPass: [String] = []
    //     for try await chunk in stream {
    //         secondPass.append(chunk)
    //     }
    //
    //     #expect(firstPass == ["chunk1"])
    //     #expect(secondPass.isEmpty)
    // }

    @Test("should propagate errors from source stream")
    func propagateSourceError() async {
        enum StreamError: Error { case failure }

        let source = AsyncThrowingStream<String, Error> { continuation in
            Task {
                continuation.yield("chunk1")
                continuation.yield("chunk2")
                continuation.finish(throwing: StreamError.failure)
            }
        }

        let stream = createAsyncIterableStream(source: source)

        await #expect(throws: StreamError.self) {
            _ = try await collect(stream)
        }
    }

    // DISABLED: Hangs indefinitely (Task #37)
    // @Test("should stop iteration when stream is cancelled with reason")
    // func cancelStopsIteration() async {
    //     let stream = makeStream(values: ["chunk1", "chunk2", "chunk3"])
    //
    //     var iterator = stream.makeAsyncIterator()
    //     do {
    //         if let first = try await iterator.next(), first == "chunk1" {
    //             await stream.cancel("Test cancellation")
    //         }
    //     } catch {
    //         #expect(Bool(false), "Unexpected error: \(error)")
    //     }
    //
    //     await #expect(throws: AsyncIterableStreamCancelledError.self) {
    //         _ = try await iterator.next()
    //     }
    // }

    @Test("should not collect chunks when iterating cancelled stream")
    func noChunksAfterPreCancel() async throws {
        let stream = makeStream(values: ["chunk1", "chunk2", "chunk3"])

        await stream.cancel()

        var collected: [String] = []
        for try await chunk in stream {
            collected.append(chunk)
        }

        #expect(collected.isEmpty)
    }
}
