import Foundation
import AISDKProviderUtils

public final class AsyncIterableStream<Element: Sendable>: AsyncSequence, @unchecked Sendable {
    public struct AsyncIterator: AsyncIteratorProtocol, Sendable {
        private let lease: StreamIteratorLease<Element>

        fileprivate init(lease: StreamIteratorLease<Element>) { self.lease = lease }

        public func next() async throws -> Element? { try await lease.next() }
    }

    private let reader: PullStreamReader<Element>
    private let lock = NSLock()
    private var leased = false

    init(
        unfolding: @escaping @Sendable () async throws -> Element?,
        onCancel: @escaping @Sendable (AsyncIterableStreamCancellationReason) async -> Void,
        release: @escaping @Sendable () -> Void = {}
    ) {
        reader = PullStreamReader(pull: unfolding, onCancel: onCancel, release: release)
    }

    public func makeAsyncIterator() -> AsyncIterator {
        lock.lock()
        let available = !leased
        if available { leased = true }
        lock.unlock()
        return AsyncIterator(lease: StreamIteratorLease(reader: reader, ownsReader: available, release: {
            self.releaseLease()
        }))
    }

    public func cancel(_ reason: AsyncIterableStreamCancellationReason = .none) async {
        await reader.cancel(reason)
    }

    private func releaseLease() {
        lock.lock()
        leased = false
        lock.unlock()
    }

    deinit {
        let reader = reader
        Task { await reader.cancel(.none) }
    }
}

public struct AsyncIterableStreamLockedError: Error, LocalizedError, Sendable {
    public init() {}
    public var errorDescription: String? { "AsyncIterableStream already has an active iterator." }
}

public enum AsyncIterableStreamCancellationReason: Sendable, ExpressibleByStringLiteral {
    case none
    case message(String)
    case error(AnySendableError)

    public init(stringLiteral value: String) { self = .message(value) }

    public var description: String {
        switch self {
        case .none: return "cancelled"
        case .message(let message): return message
        case .error(let error): return error.description
        }
    }
}

public struct AsyncIterableStreamCancelledError: Error, CustomStringConvertible, Sendable {
    public let reason: AsyncIterableStreamCancellationReason
    public init(reason: AsyncIterableStreamCancellationReason) { self.reason = reason }
    public var description: String { "AsyncIterableStream was cancelled (\(reason.description))" }
}

public struct AnySendableError: Error, CustomStringConvertible, @unchecked Sendable {
    public let underlying: any Error
    public init(_ underlying: any Error) { self.underlying = underlying }
    public var description: String { String(describing: underlying) }
}

/// Lifecycle cancellation for composed streams.
public struct AsyncIterableStreamInternalOptions: Sendable {
    public let onCancel: @Sendable (AsyncIterableStreamCancellationReason) async -> Void
    public init(onCancel: @escaping @Sendable (AsyncIterableStreamCancellationReason) async -> Void) {
        self.onCancel = onCancel
    }
}

public func createAsyncIterableStream<S: AsyncSequence & Sendable>(
    source: S,
    _internal: AsyncIterableStreamInternalOptions? = nil
) -> AsyncIterableStream<S.Element> where S.Element: Sendable {
    let cancelSource: @Sendable (AsyncIterableStreamCancellationReason) async -> Void
    if let stream = source as? AsyncThrowingStream<S.Element, Error> {
        cancelSource = { _ in await cancelStream(stream) }
    } else if let stream = source as? AsyncStream<S.Element> {
        cancelSource = { _ in await cancelStream(stream) }
    } else if let stream = source as? AsyncIterableStream<S.Element> {
        cancelSource = { await stream.cancel($0) }
    } else {
        cancelSource = { _ in }
    }
    return wrapSequence(source, onCancel: { reason in
        await cancelSource(reason)
        await _internal?.onCancel(reason)
    })
}

public func asAsyncIterableStream<Element: Sendable>(
    source: AsyncThrowingStream<Element, Error>
) -> AsyncIterableStream<Element> {
    createAsyncIterableStream(source: source)
}

public func asAsyncIterableStream<Element: Sendable>(
    source: AsyncIterableStream<Element>
) -> AsyncIterableStream<Element> {
    source
}

private func wrapSequence<S: AsyncSequence & Sendable>(
    _ source: S,
    onCancel: @escaping @Sendable (AsyncIterableStreamCancellationReason) async -> Void
) -> AsyncIterableStream<S.Element> where S.Element: Sendable {
    let cursor = SequenceCursor(source)
    return AsyncIterableStream(unfolding: { try await cursor.next() }, onCancel: onCancel, release: { cursor.release() })
}

// The reader serializes pulls and releases the cursor only after its active pull ends.
private final class SequenceCursor<Source: AsyncSequence>: @unchecked Sendable {
    private var source: Source?
    private var iterator: Source.AsyncIterator?

    init(_ source: Source) { self.source = source }

    func next() async throws -> Source.Element? {
        if iterator == nil { iterator = source?.makeAsyncIterator(); source = nil }
        return try await iterator?.next()
    }

    func release() { iterator = nil; source = nil }
}

private final class StreamCancellationRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var requested: AsyncIterableStreamCancellationReason?
    var reason: AsyncIterableStreamCancellationReason? { lock.lock(); defer { lock.unlock() }; return requested }
    func request(_ reason: AsyncIterableStreamCancellationReason) {
        lock.lock()
        if requested == nil { requested = reason }
        lock.unlock()
    }
}

private actor PullStreamReader<Element: Sendable> {
    private enum End {
        case complete
        case failed(Error)
        case cancelled(AsyncIterableStreamCancellationReason)
    }

    nonisolated let cancellation = StreamCancellationRequest()
    private var pull: (@Sendable () async throws -> Element?)?
    private var onCancel: (@Sendable (AsyncIterableStreamCancellationReason) async -> Void)?
    private var release: (@Sendable () -> Void)?
    private var end: End?
    private var active: Task<Void, Never>?
    private var waiters: [CheckedContinuation<Element?, Error>] = []

    init(
        pull: @escaping @Sendable () async throws -> Element?,
        onCancel: @escaping @Sendable (AsyncIterableStreamCancellationReason) async -> Void,
        release: @escaping @Sendable () -> Void
    ) {
        self.pull = pull
        self.onCancel = onCancel
        self.release = release
    }

    func next() async throws -> Element? {
        if let reason = cancellation.reason { await cancel(reason) }
        if let end { return try terminal(end) }
        return try await withCheckedThrowingContinuation { continuation in
            waiters.append(continuation)
            startPull()
        }
    }

    func cancel(_ reason: AsyncIterableStreamCancellationReason) async {
        cancellation.request(reason)
        guard end == nil else { return }
        let reason = cancellation.reason ?? reason
        end = .cancelled(reason)
        active?.cancel()
        settleWaiters()
        let onCancel = onCancel
        self.onCancel = nil
        await onCancel?(reason)
        if active == nil { releaseSource() }
    }

    private func startPull() {
        guard active == nil, !waiters.isEmpty, let pull else { return }
        active = Task {
            let result: Result<Element?, Error>
            do { result = .success(try await pull()) }
            catch { result = .failure(error) }
            completePull(result)
        }
    }

    private func completePull(_ result: Result<Element?, Error>) {
        active = nil
        if end == nil, let reason = cancellation.reason {
            Task { await cancel(reason) }
            return
        }
        if end != nil { releaseSource(); return }
        switch result {
        case .success(let value?):
            waiters.removeFirst().resume(returning: value)
            startPull()
        case .success(nil):
            end = .complete
            releaseSource()
            settleWaiters()
        case .failure(let error):
            end = .failed(error)
            releaseSource()
            settleWaiters()
        }
    }

    private func terminal(_ end: End) throws -> Element? {
        switch end {
        case .complete, .cancelled(.none): return nil
        case .failed(let error): throw error
        case .cancelled(let reason): throw AsyncIterableStreamCancelledError(reason: reason)
        }
    }

    private func releaseSource() {
        release?()
        release = nil
        pull = nil
        onCancel = nil
    }

    private func settleWaiters() {
        guard let end else { return }
        let waiters = waiters
        self.waiters.removeAll()
        for waiter in waiters {
            do { waiter.resume(returning: try terminal(end)) }
            catch { waiter.resume(throwing: error) }
        }
    }
}

private final class StreamIteratorLease<Element: Sendable>: @unchecked Sendable {
    private let reader: PullStreamReader<Element>
    private let ownsReader: Bool
    private let release: @Sendable () -> Void
    private let lock = NSLock()
    private var finished = false

    init(reader: PullStreamReader<Element>, ownsReader: Bool, release: @escaping @Sendable () -> Void) {
        self.reader = reader
        self.ownsReader = ownsReader
        self.release = release
    }

    func next() async throws -> Element? {
        if isFinished() { return nil }
        guard ownsReader else { finish(); throw AsyncIterableStreamLockedError() }
        do {
            let value = try await withTaskCancellationHandler {
                if Task.isCancelled { await reader.cancel(.none) }
                return try await reader.next()
            } onCancel: {
                self.reader.cancellation.request(.none)
                Task { await self.reader.cancel(.none) }
            }
            if value == nil { finish() }
            return value
        } catch { finish(); throw error }
    }

    private func isFinished() -> Bool { lock.lock(); defer { lock.unlock() }; return finished }

    private func finish() {
        lock.lock()
        let wasFinished = finished
        finished = true
        lock.unlock()
        if !wasFinished && ownsReader { release() }
    }

    deinit {
        guard !finished && ownsReader else { return }
        reader.cancellation.request(.none)
        release()
        let reader = reader
        Task { await reader.cancel(.none) }
    }
}
