import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 A timeout of a generation call elapsed.

 Swift counterpart of the `TimeoutError` `DOMException` upstream aborts with
 (`"Step timeout of 100ms exceeded"`).
 */
public struct TimeoutError: Error, LocalizedError, CustomStringConvertible, Sendable {
    public let message: String

    public init(message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
    public var description: String { message }
}

/**
 Aborts a streaming generation: the merged abort signal of the user signal and
 the configured timeouts, with the reason of the first abort.
 */
final class StreamAbortController: @unchecked Sendable {
    private let lock = NSLock()
    private var abortReason: (any Error)?
    private var aborted = false
    private var listeners: [@Sendable ((any Error)?) -> Void] = []

    var isAborted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return aborted
    }

    var reason: (any Error)? {
        lock.lock()
        defer { lock.unlock() }
        return abortReason
    }

    /// Aborts once; later calls are ignored.
    func abort(reason: (any Error)?) {
        lock.lock()
        guard !aborted else {
            lock.unlock()
            return
        }
        aborted = true
        abortReason = reason
        let current = listeners
        listeners = []
        lock.unlock()
        for listener in current {
            listener(reason)
        }
    }

    /// Calls `listener` on abort, immediately when already aborted.
    func onAbort(_ listener: @escaping @Sendable ((any Error)?) -> Void) {
        lock.lock()
        if aborted {
            let reason = abortReason
            lock.unlock()
            listener(reason)
            return
        }
        listeners.append(listener)
        lock.unlock()
    }
}

/// A timer that aborts the controller when it fires; re-arming replaces the previous timer.
final class AbortTimer: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private let controller: StreamAbortController
    private let label: String

    init(controller: StreamAbortController, label: String) {
        self.controller = controller
        self.label = label
    }

    func arm(_ timeoutMs: Int?) {
        guard let timeoutMs else { return }
        let controller = controller
        let label = label
        let newTask = Task {
            do {
                try await sleepMs(timeoutMs)
            } catch {
                return
            }
            controller.abort(reason: TimeoutError(message: "\(label) timeout of \(timeoutMs)ms exceeded"))
        }
        lock.lock()
        let previous = task
        task = newTask
        lock.unlock()
        previous?.cancel()
    }

    func clear() {
        lock.lock()
        let previous = task
        task = nil
        lock.unlock()
        previous?.cancel()
    }
}

/// Polls a caller abort signal and aborts the controller when it fires.
final class AbortSignalWatcher: @unchecked Sendable {
    private let task: Task<Void, Never>

    init(signal: @escaping @Sendable () -> Bool, controller: StreamAbortController) {
        task = Task {
            while !Task.isCancelled, !controller.isAborted {
                if signal() {
                    controller.abort(reason: CancellationError())
                    return
                }
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
        }
    }

    func stop() {
        task.cancel()
    }
}

/**
 Buffers every element of a source and replays it to any number of consumers.

 Port of the `tee` semantics upstream's stream result uses: every consumer sees
 all elements from the start. The source starts on the first consumption.
 */
final class ReplayBuffer<Element: Sendable>: @unchecked Sendable {
    private enum Terminal {
        case finished
        case failed(any Error)
    }

    private let lock = NSLock()
    private var elements: [Element] = []
    private var terminal: Terminal?
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    private var started = false
    private let onStart: @Sendable () -> Void

    init(onStart: @escaping @Sendable () -> Void) {
        self.onStart = onStart
    }

    func append(_ element: Element) {
        lock.lock()
        guard terminal == nil else {
            lock.unlock()
            return
        }
        elements.append(element)
        let current = waiters
        waiters = [:]
        lock.unlock()
        current.values.forEach { $0.resume() }
    }

    func finish(throwing error: (any Error)? = nil) {
        lock.lock()
        guard terminal == nil else {
            lock.unlock()
            return
        }
        terminal = error.map(Terminal.failed) ?? .finished
        let current = waiters
        waiters = [:]
        lock.unlock()
        current.values.forEach { $0.resume() }
    }

    func start() {
        lock.lock()
        let shouldStart = !started
        started = true
        lock.unlock()
        if shouldStart {
            onStart()
        }
    }

    /// The element at `index`, waiting for it; `nil` when the source finished before it.
    func element(at index: Int) async throws -> Element? {
        start()
        while true {
            let (element, end) = snapshot(index)
            if let element {
                return element
            }
            switch end {
            case .finished:
                return nil
            case .failed(let error):
                throw error
            case nil:
                break
            }

            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                lock.lock()
                if index < elements.count || terminal != nil {
                    lock.unlock()
                    continuation.resume()
                    return
                }
                waiters[UUID()] = continuation
                lock.unlock()
            }
        }
    }

    private func snapshot(_ index: Int) -> (Element?, Terminal?) {
        lock.lock()
        defer { lock.unlock() }
        if index < elements.count {
            return (elements[index], nil)
        }
        return (nil, terminal)
    }

    /// A stream of all elements from the start.
    func stream() -> AsyncThrowingStream<Element, Error> {
        let counter = ReplayCursor()
        return AsyncThrowingStream(unfolding: { [self] in
            let index = counter.next()
            return try await self.element(at: index)
        })
    }
}

/**
 A pull-based stream transform: each pull reads the upstream until the
 transform produced output, so nothing is read before it is consumed.

 Counterpart of a `TransformStream` with `transform` and `flush`; the consumer
 must be a single iterator.
 */
func pullTransform<Input: Sendable, Output: Sendable>(
    _ upstream: AsyncThrowingStream<Input, Error>,
    transform: @escaping @Sendable (Input) async throws -> [Output],
    flush: (@Sendable () async throws -> [Output])? = nil
) -> AsyncThrowingStream<Output, Error> {
    let state = PullTransformState<Input, Output>(upstream: upstream)
    return AsyncThrowingStream(unfolding: {
        try await state.next(transform: transform, flush: flush)
    })
}

private final class PullTransformState<Input: Sendable, Output: Sendable>: @unchecked Sendable {
    private var iterator: AsyncThrowingStream<Input, Error>.AsyncIterator
    private var pending: [Output] = []
    private var upstreamDone = false
    private var finished = false

    init(upstream: AsyncThrowingStream<Input, Error>) {
        self.iterator = upstream.makeAsyncIterator()
    }

    func next(
        transform: @Sendable (Input) async throws -> [Output],
        flush: (@Sendable () async throws -> [Output])?
    ) async throws -> Output? {
        while pending.isEmpty {
            if finished {
                return nil
            }
            if upstreamDone {
                finished = true
                pending.append(contentsOf: try await flush?() ?? [])
                continue
            }
            guard let input = try await iterator.next() else {
                upstreamDone = true
                continue
            }
            pending.append(contentsOf: try await transform(input))
        }
        return pending.removeFirst()
    }
}

/**
 A pull-based stream transform whose transform may emit output while it is
 still running (e.g. preliminary tool results during tool execution); emitted
 output is readable before the transform of that input completes.
 */
func pullTransformLive<Input: Sendable, Output: Sendable>(
    _ upstream: AsyncThrowingStream<Input, Error>,
    transform: @escaping @Sendable (Input, _ emit: @escaping @Sendable (Output) -> Void) async throws -> Void,
    flush: (@Sendable (_ emit: @escaping @Sendable (Output) -> Void) async throws -> Void)? = nil
) -> AsyncThrowingStream<Output, Error> {
    let state = LivePullTransformState<Input, Output>(upstream: upstream, transform: transform, flush: flush)
    return AsyncThrowingStream(unfolding: { try await state.next() })
}

private final class LivePullTransformState<Input: Sendable, Output: Sendable>: @unchecked Sendable {
    typealias Emit = @Sendable (Output) -> Void

    private var iterator: AsyncThrowingStream<Input, Error>.AsyncIterator
    private let transform: @Sendable (Input, @escaping Emit) async throws -> Void
    private let flush: (@Sendable (@escaping Emit) async throws -> Void)?
    private var current: AsyncThrowingStream<Output, Error>.AsyncIterator?
    private var upstreamDone = false
    private var flushed = false

    init(
        upstream: AsyncThrowingStream<Input, Error>,
        transform: @escaping @Sendable (Input, @escaping Emit) async throws -> Void,
        flush: (@Sendable (@escaping Emit) async throws -> Void)?
    ) {
        self.iterator = upstream.makeAsyncIterator()
        self.transform = transform
        self.flush = flush
    }

    func next() async throws -> Output? {
        while true {
            if var running = current {
                let output = try await running.next()
                current = running
                if let output {
                    return output
                }
                current = nil
                continue
            }

            if upstreamDone {
                guard !flushed, let flush else { return nil }
                flushed = true
                current = run { emit in try await flush(emit) }
                continue
            }

            guard let input = try await iterator.next() else {
                upstreamDone = true
                continue
            }

            let transform = self.transform
            current = run { emit in try await transform(input, emit) }
        }
    }

    private func run(
        _ body: @escaping @Sendable (@escaping Emit) async throws -> Void
    ) -> AsyncThrowingStream<Output, Error>.AsyncIterator {
        let (stream, continuation) = AsyncThrowingStream<Output, Error>.makeStream()
        let task = Task {
            do {
                try await body { continuation.yield($0) }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream.makeAsyncIterator()
    }
}

/**
 A stream assembled from inner streams added over time, read one after another.

 Port of `@ai-sdk/ai/src/util/create-stitchable-stream.ts`.
 */
final class StreamStitcher<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [AsyncThrowingStream<Element, Error>] = []
    private var closed = false
    private var terminated = false
    private var waiter: CheckedContinuation<Void, Never>?
    private var current: AsyncThrowingStream<Element, Error>.AsyncIterator?

    func addStream(_ stream: AsyncThrowingStream<Element, Error>) {
        lock.lock()
        guard !closed else {
            lock.unlock()
            return
        }
        queue.append(stream)
        let pending = waiter
        waiter = nil
        lock.unlock()
        pending?.resume()
    }

    /// Ends the stream once the added streams are read.
    func close() {
        lock.lock()
        closed = true
        let pending = waiter
        waiter = nil
        lock.unlock()
        pending?.resume()
    }

    /// Ends the stream immediately, dropping streams not read yet.
    func terminate() {
        lock.lock()
        closed = true
        terminated = true
        queue = []
        let pending = waiter
        waiter = nil
        lock.unlock()
        pending?.resume()
    }

    var stream: AsyncThrowingStream<Element, Error> {
        AsyncThrowingStream(unfolding: { [self] in try await self.next() })
    }

    private func next() async throws -> Element? {
        while true {
            if isTerminated { return nil }

            if var iterator = current {
                let element = try await iterator.next()
                current = iterator
                if isTerminated { return nil }
                if let element { return element }
                current = nil
                continue
            }

            let next: AsyncThrowingStream<Element, Error>?? = await withCheckedContinuation { continuation in
                lock.lock()
                if !queue.isEmpty {
                    let stream = queue.removeFirst()
                    lock.unlock()
                    continuation.resume(returning: .some(stream))
                    return
                }
                if closed {
                    lock.unlock()
                    continuation.resume(returning: .some(nil))
                    return
                }
                lock.unlock()
                continuation.resume(returning: nil)
            }

            switch next {
            case .some(.some(let stream)):
                current = stream.makeAsyncIterator()
            case .some(.none):
                return nil
            case .none:
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    lock.lock()
                    if !queue.isEmpty || closed {
                        lock.unlock()
                        continuation.resume()
                        return
                    }
                    waiter = continuation
                    lock.unlock()
                }
            }
        }
    }

    private var isTerminated: Bool {
        lock.lock()
        defer { lock.unlock() }
        return terminated
    }
}

private final class ReplayCursor: @unchecked Sendable {
    private let lock = NSLock()
    private var index = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let current = index
        index += 1
        return current
    }
}
