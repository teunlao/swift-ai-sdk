import Foundation
import Testing
import AISDKProviderUtils
@testable import SwiftAISDK

@Suite("pipeUIMessageStreamToResponse")
struct PipeUIMessageStreamToResponseTests {
    @Test("should write to response with headers and encoded stream")
    func writesToResponse() async throws {
        let response = MockStreamTextResponseWriter()
        let stream = makeChunkStream([
            .textStart(id: "1", providerMetadata: nil),
            .textDelta(id: "1", delta: "test-data", providerMetadata: nil),
            .textEnd(id: "1", providerMetadata: nil)
        ])

        try await pipeUIMessageStreamToResponse(
            response: response,
            stream: stream,
            options: StreamTextUIResponseOptions<UIMessage>(
                responseInit: UIMessageStreamResponseInit(
                    headers: ["Custom-Header": "test"],
                    status: 200,
                    statusText: "OK"
                )
            )
        )

        await response.waitForEnd()

        #expect(response.statusCode == 200)
        #expect(response.statusMessage == "OK")
        #expect(response.headers.lowercasedKeys() == [
            "content-type": "text/event-stream",
            "cache-control": "no-cache",
            "connection": "keep-alive",
            "x-vercel-ai-ui-message-stream": "v1",
            "x-accel-buffering": "no",
            "custom-header": "test"
        ])

        #expect(response.decodedChunks() == [
            "data: {\"id\":\"1\",\"type\":\"text-start\"}\n\n",
            "data: {\"delta\":\"test-data\",\"id\":\"1\",\"type\":\"text-delta\"}\n\n",
            "data: {\"id\":\"1\",\"type\":\"text-end\"}\n\n",
            "data: [DONE]\n\n"
        ])
    }

    @Test("disconnect cancels a source while its next chunk is pending")
    func disconnectDuringRead() async throws {
        let response = ControlledResponse()
        let pending = AsyncThrowingStream<AnyUIMessageChunk, Error>.makeStream()
        let reading = DelayedPromise<Void>()
        let terminated = DelayedPromise<Bool>()
        pending.continuation.onTermination = { reason in
            if case .cancelled = reason { terminated.resolve(true) }
            else { terminated.resolve(false) }
        }
        let stream = AsyncThrowingStream<AnyUIMessageChunk, Error>(unfolding: {
            reading.resolve(())
            var iterator = pending.stream.makeAsyncIterator()
            return try await iterator.next()
        })
        let pipe = Task {
            try await pipeUIMessageStreamToResponse(response: response, stream: stream,
                options: StreamTextUIResponseOptions<UIMessage>())
        }
        let deadline = Task {
            try await Task.sleep(for: .seconds(1))
            pending.continuation.finish()
            reading.reject(CancellationError())
            pipe.cancel()
        }
        defer { deadline.cancel(); pending.continuation.finish() }
        try await reading.task.value
        response.close()
        try await pipe.value
        #expect(try await terminated.task.value)
        #expect(response.snapshot().chunks.isEmpty)
        #expect(!response.snapshot().ended)
    }

    @Test("disconnect cancels a source and a write waiting for drain")
    func disconnectDuringWrite() async throws {
        let response = ControlledResponse(paused: true)
        let source = AsyncThrowingStream<AnyUIMessageChunk, Error>.makeStream()
        let terminated = DelayedPromise<Bool>()
        source.continuation.onTermination = { reason in
            if case .cancelled = reason { terminated.resolve(true) }
            else { terminated.resolve(false) }
        }
        source.continuation.yield(.textStart(id: "1", providerMetadata: nil))
        let pipe = Task {
            try await pipeUIMessageStreamToResponse(response: response, stream: source.stream,
                options: StreamTextUIResponseOptions<UIMessage>())
        }
        let deadline = Task {
            try await Task.sleep(for: .seconds(1))
            source.continuation.finish()
            response.writeStarted.reject(CancellationError())
            response.drain()
            pipe.cancel()
        }
        defer { deadline.cancel(); source.continuation.finish() }
        try await response.writeStarted.task.value
        response.close()
        try await pipe.value
        #expect(try await terminated.task.value)
        #expect(response.snapshot().chunks.count == 1)
        #expect(!response.snapshot().ended)
    }

    @Test("backpressure pauses source reads until the writer drains")
    func waitsForDrain() async throws {
        actor Source {
            var reads = 0
            func next() -> AnyUIMessageChunk? {
                reads += 1
                return reads == 1 ? .textStart(id: "1", providerMetadata: nil) : nil
            }
        }
        let source = Source()
        let response = ControlledResponse(paused: true)
        let stream = AsyncThrowingStream<AnyUIMessageChunk, Error>(unfolding: { await source.next() })
        let pipe = Task {
            try await pipeUIMessageStreamToResponse(response: response, stream: stream,
                options: StreamTextUIResponseOptions<UIMessage>())
        }
        let deadline = Task {
            try await Task.sleep(for: .seconds(1))
            response.writeStarted.reject(CancellationError())
            pipe.cancel()
        }
        defer { deadline.cancel(); response.drain() }
        try await response.writeStarted.task.value
        #expect(await source.reads == 1)
        #expect(!response.snapshot().ended)
        response.drain()
        try await pipe.value
        #expect(response.snapshot().chunks == [
            "data: {\"id\":\"1\",\"type\":\"text-start\"}\n\n", "data: [DONE]\n\n"
        ])
        #expect(response.snapshot().ended)
    }

    @Test("an already disconnected response cancels the source without writing")
    func alreadyDisconnected() async throws {
        let response = ControlledResponse()
        response.close()
        let source = AsyncThrowingStream<AnyUIMessageChunk, Error>.makeStream()
        let terminated = DelayedPromise<Bool>()
        source.continuation.onTermination = { reason in
            if case .cancelled = reason { terminated.resolve(true) }
            else { terminated.resolve(false) }
        }
        let deadline = Task {
            try await Task.sleep(for: .seconds(1))
            source.continuation.finish()
        }
        defer { deadline.cancel(); source.continuation.finish() }
        try await pipeUIMessageStreamToResponse(response: response, stream: source.stream,
            options: StreamTextUIResponseOptions<UIMessage>())
        #expect(try await terminated.task.value)
        #expect(response.snapshot().chunks.isEmpty)
        #expect(!response.snapshot().ended)
    }

    @Test("write failures propagate and cancel the source")
    func writeFailure() async throws {
        let response = ControlledResponse(fails: true)
        let source = AsyncThrowingStream<AnyUIMessageChunk, Error>.makeStream()
        let terminated = DelayedPromise<Bool>()
        source.continuation.onTermination = { reason in
            if case .cancelled = reason { terminated.resolve(true) }
            else { terminated.resolve(false) }
        }
        source.continuation.yield(.textStart(id: "1", providerMetadata: nil))
        let deadline = Task {
            try await Task.sleep(for: .seconds(1))
            source.continuation.finish()
        }
        defer { deadline.cancel(); source.continuation.finish() }
        await #expect(throws: ResponseFailure.self) {
            try await pipeUIMessageStreamToResponse(response: response, stream: source.stream,
                options: StreamTextUIResponseOptions<UIMessage>())
        }
        #expect(try await terminated.task.value)
        #expect(response.snapshot().ended)
    }

    @Test("should handle errors in the stream")
    func writesErrorChunks() async throws {
        let response = MockStreamTextResponseWriter()
        let stream = makeChunkStream([
            .error(errorText: "Custom error message")
        ])

        try await pipeUIMessageStreamToResponse(
            response: response,
            stream: stream,
            options: StreamTextUIResponseOptions<UIMessage>(
                responseInit: UIMessageStreamResponseInit(status: 200)
            )
        )

        await response.waitForEnd()

        #expect(response.decodedChunks() == [
            "data: {\"errorText\":\"Custom error message\",\"type\":\"error\"}\n\n",
            "data: [DONE]\n\n"
        ])
    }

    @Test("encodes abort reason and finishReason fields")
    func encodesAbortReasonAndFinishReason() async throws {
        let response = MockStreamTextResponseWriter()
        let stream = makeChunkStream([
            .abort(reason: "manual abort"),
            .finish(finishReason: .stop, messageMetadata: nil)
        ])

        try await pipeUIMessageStreamToResponse(
            response: response,
            stream: stream,
            options: StreamTextUIResponseOptions<UIMessage>(
                responseInit: UIMessageStreamResponseInit(status: 200)
            )
        )

        await response.waitForEnd()

        #expect(response.decodedChunks() == [
            "data: {\"reason\":\"manual abort\",\"type\":\"abort\"}\n\n",
            "data: {\"finishReason\":\"stop\",\"type\":\"finish\"}\n\n",
            "data: [DONE]\n\n"
        ])
    }
}

// MARK: - Helpers

private struct ResponseFailure: Error {}

private final class ControlledResponse: StreamTextResponseWriter, @unchecked Sendable {
    private let lock = NSLock()
    private var closed = false
    private var ended = false
    private var chunks: [Data] = []
    private var listeners: [UUID: @Sendable () -> Void] = [:]
    private let paused: Bool
    private let fails: Bool
    private let writable = AsyncThrowingStream<Void, Error>.makeStream()
    let writeStarted = DelayedPromise<Void>()

    init(paused: Bool = false, fails: Bool = false) {
        self.paused = paused
        self.fails = fails
    }

    var isClosed: Bool { lock.withLock { closed } }
    func writeHead(status: Int, statusText: String?, headers: [String: String]) {}
    func onClose(_ handler: @escaping @Sendable () -> Void) -> @Sendable () -> Void {
        let id = UUID()
        lock.withLock { listeners[id] = handler }
        return { [self] in lock.withLock { _ = listeners.removeValue(forKey: id) } }
    }
    func write(_ data: Data) async throws {
        try Task.checkCancellation()
        lock.withLock { chunks.append(data) }
        writeStarted.resolve(())
        if fails { throw ResponseFailure() }
        if paused {
            for try await _ in writable.stream { break }
        }
        try Task.checkCancellation()
    }
    func end() { lock.withLock { ended = true } }
    func close() {
        let callbacks = lock.withLock {
            closed = true
            return Array(listeners.values)
        }
        callbacks.forEach { $0() }
    }
    func drain() { writable.continuation.finish() }
    func snapshot() -> (chunks: [String], ended: Bool) {
        lock.withLock { (chunks.map { String(decoding: $0, as: UTF8.self) }, ended) }
    }
}

private func makeChunkStream(
    _ chunks: [AnyUIMessageChunk]
) -> AsyncThrowingStream<AnyUIMessageChunk, Error> {
    AsyncThrowingStream { continuation in
        for chunk in chunks {
            continuation.yield(chunk)
        }
        continuation.finish()
    }
}

private extension Dictionary where Key == String, Value == String {
    func lowercasedKeys() -> [String: String] {
        reduce(into: [:]) { result, entry in
            result[entry.key.lowercased()] = entry.value
        }
    }
}
