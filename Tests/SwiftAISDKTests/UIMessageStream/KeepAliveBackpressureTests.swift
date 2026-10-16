import Foundation
import Testing
import SwiftAISDK

@Suite("SSE keep-alive backpressure")
struct KeepAliveBackpressureTests {
    @Test("paused downstream does not drain a pull-based data source")
    func sourceDemand() async throws {
        let source = SSEPulls(["first", "second", "third"])
        let output = try createSSEStreamWithKeepAlive(
            stream: AsyncThrowingStream(unfolding: { source.next() }), keepAliveMs: 60_000
        )
        let stream = createAsyncIterableStream(source: output)
        var iterator = stream.makeAsyncIterator()
        #expect(try await iterator.next() == ": stream-open\n\n")
        #expect(source.count == 0)
        #expect(try await iterator.next() == "first")
        #expect(source.count == 1)
        #expect(try await iterator.next() == "second")
        #expect(source.count == 2)
        await stream.cancel()
        #expect(source.count == 2)
    }

    @Test("heartbeats retain one pending read and preserve its data")
    func pendingReadSurvivesHeartbeats() async throws {
        let source = PendingSSERead()
        defer { source.finish() }
        let output = try createSSEStreamWithKeepAlive(
            stream: AsyncThrowingStream(unfolding: { await source.next() }), keepAliveMs: 1
        )
        let stream = createAsyncIterableStream(source: output)
        var iterator = stream.makeAsyncIterator()
        #expect(try await iterator.next() == ": stream-open\n\n")
        #expect(try await iterator.next() == ": keep-alive\n\n")
        try await sseBounded { await source.started.wait() }
        #expect(try await iterator.next() == ": keep-alive\n\n")
        #expect(source.count == 1)
        source.send("payload")
        var payload: String?
        while let value = try await iterator.next() {
            if !value.hasPrefix(":") { payload = value; break }
        }
        #expect(payload == "payload")
        #expect(source.count == 1)
        await stream.cancel()
    }

    @Test("cancelling a pending heartbeat read closes the source")
    func sourceCancellation() async throws {
        let source = AsyncThrowingStream<String, Error>.makeStream()
        let closed = SSEClosed()
        source.continuation.onTermination = { _ in closed.signal() }
        let output = try createSSEStreamWithKeepAlive(stream: source.stream, keepAliveMs: 1)
        let stream = createAsyncIterableStream(source: output)
        var iterator = stream.makeAsyncIterator()
        #expect(try await iterator.next() == ": stream-open\n\n")
        #expect(try await iterator.next() == ": keep-alive\n\n")
        await stream.cancel()
        try await sseBounded { await closed.wait() }
        #expect(try await iterator.next() == nil)
    }
}

private final class SSEPulls: @unchecked Sendable {
    private let lock = NSLock()
    private let values: [String]
    private var index = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return index }
    init(_ values: [String]) { self.values = values }
    func next() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard index < values.count else { return nil }
        defer { index += 1 }
        return values[index]
    }
}

private final class PendingSSERead: @unchecked Sendable {
    let started = SSEClosed()
    private let lock = NSLock()
    private var reads = 0
    private var continuation: CheckedContinuation<String?, Never>?
    var count: Int { lock.lock(); defer { lock.unlock() }; return reads }
    func next() async -> String? {
        await withCheckedContinuation { continuation in
            lock.lock()
            reads += 1
            self.continuation = continuation
            lock.unlock()
            started.signal()
        }
    }
    func send(_ value: String) { resume(value) }
    func finish() { resume(nil) }
    private func resume(_ value: String?) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: value)
    }
}

private final class SSEClosed: Sendable {
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation
    init() { (stream, continuation) = AsyncStream.makeStream() }
    func signal() { continuation.yield(()); continuation.finish() }
    func wait() async { for await _ in stream {} }
}

private struct SSETimeout: Error {}

private func sseBounded(_ operation: @escaping @Sendable () async -> Void) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask { await operation() }
        group.addTask { try await Task.sleep(nanoseconds: 1_000_000_000); throw SSETimeout() }
        try await group.next()
        group.cancelAll()
    }
}
