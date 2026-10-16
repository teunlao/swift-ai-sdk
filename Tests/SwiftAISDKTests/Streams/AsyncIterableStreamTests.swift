import Foundation
import Testing
import SwiftAISDK

@Suite("AsyncIterableStream")
struct AsyncIterableStreamTests {
    @Test("preserves source order and end-of-stream")
    func orderedValues() async throws {
        let stream = createAsyncIterableStream(source: ImmediateAsyncSequence([1, 2, 3]))
        #expect(try await collect(stream) == [1, 2, 3])
        #expect(try await collect(stream).isEmpty)
    }

    @Test("pulls only requested elements and releases a generic iterator")
    func demandAndRelease() async throws {
        let source = PullSource()
        let stream = createAsyncIterableStream(source: PullSequence(source: source))
        #expect(source.reads == 0)
        var iterator = stream.makeAsyncIterator()
        #expect(try await iterator.next() == 1)
        await stream.cancel()
        #expect(source.reads == 1)
        #expect(source.released)
        #expect(try await iterator.next() == nil)
    }

    @Test("early iteration exit cancels a retained native source")
    func earlyExit() async throws {
        let source = AsyncThrowingStream<Int, Error>.makeStream()
        let termination = StreamSignal()
        source.continuation.onTermination = { _ in termination.signal() }
        source.continuation.yield(1)
        source.continuation.yield(2)
        let stream = createAsyncIterableStream(source: source.stream)
        #expect(try await firstValue(stream) == 1)
        try await bounded { await termination.wait() }
        #expect(try await collect(stream).isEmpty)
    }

    @Test("cancellation before a read closes a native nonthrowing source")
    func cancelBeforeRead() async throws {
        let source = AsyncStream<Int>.makeStream()
        let termination = StreamSignal()
        source.continuation.onTermination = { _ in termination.signal() }
        let stream = createAsyncIterableStream(source: source.stream)
        await stream.cancel()
        try await bounded { await termination.wait() }
        #expect(try await collect(stream).isEmpty)
    }

    @Test("an active consumer cancellation reaches the pending source read")
    func cancelPendingRead() async throws {
        let entered = StreamSignal()
        let cancelled = StreamSignal()
        let pending = AsyncThrowingStream<Int, Error>.makeStream()
        pending.continuation.onTermination = { _ in cancelled.signal() }
        let stream = createAsyncIterableStream(source: pending.stream)
        let consumer = Task {
            var iterator = stream.makeAsyncIterator()
            entered.signal()
            return try await iterator.next()
        }
        await entered.wait()
        consumer.cancel()
        #expect(try await consumer.value == nil)
        try await bounded { await cancelled.wait() }
    }

    @Test("cancellation settles a pending read without releasing an in-flight source cursor")
    func nonCooperativePullCancellation() async throws {
        let source = PendingPull()
        defer { source.complete() }
        let stream = createAsyncIterableStream(source: PendingSequence(source: source))
        let consumer = Task {
            var iterator = stream.makeAsyncIterator()
            return try await iterator.next()
        }
        await source.entered.wait()
        let cancelled = StreamSignal()
        let cancellation = Task { await stream.cancel(); cancelled.signal() }
        try await bounded { await cancelled.wait() }
        #expect(try await consumer.value == nil)
        #expect(!source.hasReleased)
        source.complete()
        try await bounded { await source.released.wait() }
        await cancellation.value
    }

    @Test("a competing iterator is refused without stealing source data")
    func exclusiveReader() async throws {
        let stream = createAsyncIterableStream(source: ImmediateAsyncSequence([1, 2]))
        var first = stream.makeAsyncIterator()
        var competing = stream.makeAsyncIterator()
        #expect(try await first.next() == 1)
        do { _ = try await competing.next(); Issue.record("Competing iterator was accepted") }
        catch { #expect(error is AsyncIterableStreamLockedError) }
        #expect(try await first.next() == 2)
        #expect(try await first.next() == nil)
    }

    @Test("source errors are preserved and a failed iterator releases its lease")
    func errorCleanup() async throws {
        let error = SourceFailure()
        let source = AsyncThrowingStream<Int, Error> { continuation in
            continuation.yield(1)
            continuation.finish(throwing: error)
        }
        let stream = createAsyncIterableStream(source: source)
        var iterator = stream.makeAsyncIterator()
        #expect(try await iterator.next() == 1)
        do { _ = try await iterator.next(); Issue.record("Expected source failure") }
        catch let caught { #expect(caught as? SourceFailure === error) }
        #expect(try await iterator.next() == nil)
        var replacement = stream.makeAsyncIterator()
        do { _ = try await replacement.next(); Issue.record("Expected terminal source failure") }
        catch let caught { #expect(caught as? SourceFailure === error) }
    }

    @Test("explicit cancellation reasons remain available to readers")
    func cancellationReason() async throws {
        let stream = createAsyncIterableStream(source: ImmediateAsyncSequence([1]))
        await stream.cancel("closed")
        do { _ = try await collect(stream); Issue.record("Cancellation reason was discarded") }
        catch let error as AsyncIterableStreamCancelledError { #expect(error.reason.description == "closed") }
    }

    private func firstValue(_ stream: AsyncIterableStream<Int>) async throws -> Int? {
        for try await value in stream { return value }
        return nil
    }
}

private struct ImmediateAsyncSequence<Element: Sendable>: AsyncSequence, Sendable {
    let elements: [Element]
    init(_ elements: [Element]) { self.elements = elements }
    func makeAsyncIterator() -> Iterator { Iterator(elements: elements) }

    struct Iterator: AsyncIteratorProtocol {
        let elements: [Element]
        var index = 0
        mutating func next() async -> Element? {
            guard index < elements.count else { return nil }
            defer { index += 1 }
            return elements[index]
        }
    }
}

private final class PullSource: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var didRelease = false
    var reads: Int { lock.lock(); defer { lock.unlock() }; return count }
    var released: Bool { lock.lock(); defer { lock.unlock() }; return didRelease }
    func next() -> Int? { lock.lock(); defer { lock.unlock() }; count += 1; return count <= 2 ? count : nil }
    func release() { lock.lock(); didRelease = true; lock.unlock() }
}

private struct PullSequence: AsyncSequence, Sendable {
    let source: PullSource
    func makeAsyncIterator() -> Iterator { Iterator(source: source) }

    final class Iterator: AsyncIteratorProtocol {
        let source: PullSource
        init(source: PullSource) { self.source = source }
        func next() async -> Int? { source.next() }
        deinit { source.release() }
    }
}

private final class PendingPull: @unchecked Sendable {
    let entered = StreamSignal()
    let released = StreamSignal()
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Int?, Never>?
    private var didRelease = false
    var hasReleased: Bool { lock.lock(); defer { lock.unlock() }; return didRelease }
    func release() { lock.lock(); didRelease = true; lock.unlock(); released.signal() }
    func read() async -> Int? {
        await withCheckedContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
            entered.signal()
        }
    }
    func complete() {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: 1)
    }
}

private struct PendingSequence: AsyncSequence, Sendable {
    let source: PendingPull
    func makeAsyncIterator() -> Iterator { Iterator(source: source) }
    final class Iterator: AsyncIteratorProtocol {
        let source: PendingPull
        init(source: PendingPull) { self.source = source }
        func next() async -> Int? { await source.read() }
        deinit { source.release() }
    }
}

private final class SourceFailure: Error, @unchecked Sendable {}

private final class StreamSignal: Sendable {
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation
    init() { (stream, continuation) = AsyncStream.makeStream() }
    func signal() { continuation.yield(()); continuation.finish() }
    func wait() async { for await _ in stream {} }
}

private struct StreamTestTimeout: Error {}

private func bounded(_ operation: @escaping @Sendable () async throws -> Void) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask { try await operation() }
        group.addTask { try await Task.sleep(nanoseconds: 1_000_000_000); throw StreamTestTimeout() }
        try await group.next()
        group.cancelAll()
    }
}

private func collect<S: AsyncSequence>(_ sequence: S) async throws -> [S.Element] {
    var values: [S.Element] = []
    for try await value in sequence { values.append(value) }
    return values
}
