import Foundation
import Testing
@testable import SwiftAISDK

/**
 Tests for `simulateReadableStream`.

 Port of `@ai-sdk/ai/src/util/simulate-readable-stream.test.ts`.
 */
@Suite("Simulate Readable Stream Tests")
struct SimulateReadableStreamTests {

    private actor DelayRecorder {
        private(set) var delays: [Int?] = []

        func record(_ value: Int?) {
            delays.append(value)
        }

        func values() -> [Int?] {
            delays
        }
    }

    private func collect<T: Sendable>(
        _ stream: AsyncThrowingStream<T, Error>
    ) async throws -> [T] {
        var iterator = stream.makeAsyncIterator()
        var result: [T] = []
        while let value = try await iterator.next() {
            result.append(value)
        }
        return result
    }

    @Test("should create a readable stream with provided values")
    func createsStreamWithValues() async throws {
        let stream = simulateReadableStream(chunks: ["a", "b", "c"])
        let values = try await collect(stream)
        #expect(values == ["a", "b", "c"])
    }

    @Test("should respect delay configuration")
    func respectsDelayConfiguration() async throws {
        let recorder = DelayRecorder()
        let stream = simulateReadableStream(
            chunks: [1, 2, 3],
            initialDelayInMs: 500,
            chunkDelayInMs: 100,
            _internal: SimulateReadableStreamInternalOptions { delay in
                await recorder.record(delay)
            }
        )

        _ = try await collect(stream)
        #expect(await recorder.values() == [500, 100, 100])
    }

    @Test("should handle empty values array")
    func handlesEmptyValues() async throws {
        let stream = simulateReadableStream(chunks: [Int]())
        var iterator = stream.makeAsyncIterator()
        let first = try await iterator.next()
        #expect(first == nil)
    }

    @Test("should handle different value types")
    func handlesDifferentTypes() async throws {
        struct Message: Equatable, Sendable { let id: Int; let text: String }
        let chunks = [
            Message(id: 1, text: "hello"),
            Message(id: 2, text: "world")
        ]

        let stream = simulateReadableStream(chunks: chunks)
        let collected = try await collect(stream)
        #expect(collected == chunks)
    }

    @Test("should skip all delays when both are nil")
    func skipAllDelays() async throws {
        let recorder = DelayRecorder()
        let stream = simulateReadableStream(
            chunks: [1, 2, 3],
            initialDelayInMs: nil,
            chunkDelayInMs: nil,
            _internal: SimulateReadableStreamInternalOptions { delay in
                await recorder.record(delay)
            }
        )

        _ = try await collect(stream)
        #expect(await recorder.values() == [nil, nil, nil])
    }

    @Test("should apply chunk delays but skip initial delay when nil")
    func skipInitialDelayOnly() async throws {
        let recorder = DelayRecorder()
        let stream = simulateReadableStream(
            chunks: [1, 2, 3],
            initialDelayInMs: nil,
            chunkDelayInMs: 100,
            _internal: SimulateReadableStreamInternalOptions { delay in
                await recorder.record(delay)
            }
        )

        _ = try await collect(stream)
        #expect(await recorder.values() == [nil, 100, 100])
    }

    @Test("should apply initial delay but skip chunk delays when nil")
    func skipChunkDelaysOnly() async throws {
        let recorder = DelayRecorder()
        let stream = simulateReadableStream(
            chunks: [1, 2, 3],
            initialDelayInMs: 500,
            chunkDelayInMs: nil,
            _internal: SimulateReadableStreamInternalOptions { delay in
                await recorder.record(delay)
            }
        )

        _ = try await collect(stream)
        #expect(await recorder.values() == [500, nil, nil])
    }
}
