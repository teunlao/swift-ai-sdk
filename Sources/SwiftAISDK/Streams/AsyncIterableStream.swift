import Foundation

/**
 Creates an async iterable stream wrapper that mirrors `ReadableStream` + `AsyncIterable`.

 Port of `@ai-sdk/ai/src/util/async-iterable-stream.ts`.

 This utility converts any `AsyncSequence` into an object that can be iterated using
 `for try await` while still allowing explicit cancellation. It ensures the underlying
 source sequence is cancelled when iteration stops early, an error occurs, or when
 `cancel(_:)` is called manually.

 **Adaptations**:
 - Swift does not expose web `ReadableStream`, so we model the behaviour with `AsyncThrowingStream`.
 - Added optional `_internal` hook for tests to observe cancellation (`onCancel`), matching the
   semantics of the TypeScript implementation's `reader.cancel()` callbacks.
 */
public final class AsyncIterableStream<Element: Sendable>: AsyncSequence, @unchecked Sendable {
    public typealias AsyncIterator = AsyncThrowingStream<Element, Error>.AsyncIterator

    private let stream: AsyncThrowingStream<Element, Error>
    private let state: AsyncIterableStreamState<Element>

    init(
        stream: AsyncThrowingStream<Element, Error>,
        state: AsyncIterableStreamState<Element>
    ) {
        self.stream = stream
        self.state = state
    }

    public func makeAsyncIterator() -> AsyncIterator {
        stream.makeAsyncIterator()
    }

    /**
     Cancels the stream.

     - Parameter reason: Optional cancellation reason. Passing `.none` mirrors calling `cancel()`
       without a reason; any other value results in an `AsyncIterableStreamCancelledError`.
     */
    public func cancel(_ reason: AsyncIterableStreamCancellationReason = .none) async {
        await state.requestCancel(reason: reason)
    }
}

/// Cancellation reason used when stopping an `AsyncIterableStream`.
public enum AsyncIterableStreamCancellationReason: Sendable, ExpressibleByStringLiteral {
    case none
    case message(String)
    case error(AnySendableError)

    public init(stringLiteral value: String) {
        self = .message(value)
    }

    public var description: String {
        switch self {
        case .none:
            return "cancelled"
        case .message(let message):
            return message
        case .error(let error):
            return error.description
        }
    }
}

/// Error thrown when the stream is cancelled with a non-empty reason.
public struct AsyncIterableStreamCancelledError: Error, CustomStringConvertible, Sendable {
    public let reason: AsyncIterableStreamCancellationReason

    public init(reason: AsyncIterableStreamCancellationReason) {
        self.reason = reason
    }

    public var description: String {
        "AsyncIterableStream was cancelled (\(reason.description))"
    }
}

/// Type-erased wrapper for a sendable error.
public struct AnySendableError: Error, CustomStringConvertible, @unchecked Sendable {
    public let underlying: any Error

    public init(_ underlying: any Error) {
        self.underlying = underlying
    }

    public var description: String {
        String(describing: underlying)
    }
}

/// Internal hook used for testing.
public struct AsyncIterableStreamInternalOptions: Sendable {
    public let onCancel: @Sendable (AsyncIterableStreamCancellationReason) async -> Void

    public init(onCancel: @escaping @Sendable (AsyncIterableStreamCancellationReason) async -> Void) {
        self.onCancel = onCancel
    }
}

/**
 Wraps an async sequence in an `AsyncIterableStream`.
 */
public func createAsyncIterableStream<S: AsyncSequence & Sendable>(
    source: S,
    _internal: AsyncIterableStreamInternalOptions? = nil
) -> AsyncIterableStream<S.Element> where S.Element: Sendable {
    let onCancel: @Sendable (AsyncIterableStreamCancellationReason) async -> Void
    if let customOnCancel = _internal?.onCancel {
        onCancel = customOnCancel
    } else {
        onCancel = { (_: AsyncIterableStreamCancellationReason) async in }
    }

    let state = AsyncIterableStreamState<S.Element>(onCancel: onCancel)

    let stream = AsyncThrowingStream<S.Element, Error> { continuation in
        let producerTask = Task {
            do {
                var iterator = source.makeAsyncIterator()
                while let element = try await iterator.next() {
                    continuation.yield(element)
                }
                await state.finishIfNeeded()
            } catch is CancellationError {
                await state.didCancel()
            } catch {
                await state.finishIfNeeded(error: error)
            }
        }

        Task {
            await state.initialize(continuation: continuation, task: producerTask)
        }

        continuation.onTermination = { termination in
            Task {
                await state.handleTermination(termination)
            }
        }
    }

    return AsyncIterableStream(stream: stream, state: state)
}

// MARK: - State Management

actor AsyncIterableStreamState<Element: Sendable> {
    private enum Status {
        case initializing
        case active
        case finishing
        case finished
    }

    private var status: Status = .initializing
    private var continuation: AsyncThrowingStream<Element, Error>.Continuation?
    private var producerTask: Task<Void, Never>?
    private var pendingCancel: AsyncIterableStreamCancellationReason?
    private let onCancel: @Sendable (AsyncIterableStreamCancellationReason) async -> Void

    init(onCancel: @escaping @Sendable (AsyncIterableStreamCancellationReason) async -> Void) {
        self.onCancel = onCancel
    }

    func initialize(
        continuation: AsyncThrowingStream<Element, Error>.Continuation,
        task: Task<Void, Never>
    ) async {
        self.continuation = continuation
        self.producerTask = task
        if status == .initializing {
            status = .active
        }

        if let pendingCancel {
            self.pendingCancel = nil
            await requestCancel(reason: pendingCancel)
        }
    }

    func requestCancel(reason: AsyncIterableStreamCancellationReason) async {
        switch status {
        case .initializing:
            pendingCancel = reason
        case .active:
            status = .finishing
            let task = producerTask
            producerTask = nil
            task?.cancel()

            await onCancel(reason)

            switch reason {
            case .none:
                continuation?.finish()
            default:
                continuation?.finish(throwing: AsyncIterableStreamCancelledError(reason: reason))
            }

            continuation = nil

            if let task {
                await task.value
            }

            status = .finished
        case .finishing, .finished:
            break
        }
    }

    func finishIfNeeded() async {
        switch status {
        case .initializing:
            status = .finished
            pendingCancel = nil
        case .active:
            status = .finished
            continuation?.finish()
            continuation = nil
            producerTask = nil
        case .finishing, .finished:
            break
        }
    }

    func finishIfNeeded(error: Error) async {
        switch status {
        case .initializing:
            status = .finished
            pendingCancel = nil
        case .active:
            status = .finished
            continuation?.finish(throwing: error)
            continuation = nil
            producerTask = nil
        case .finishing, .finished:
            break
        }
    }

    func didCancel() async {
        if status == .finishing {
            status = .finished
        }
        producerTask = nil
        continuation = nil
    }

    func handleTermination(_ termination: AsyncThrowingStream<Element, Error>.Continuation.Termination) async {
        switch termination {
        case .finished:
            if status == .active {
                status = .finished
            }
            producerTask = nil
            continuation = nil
        case .cancelled:
            switch status {
            case .initializing:
                status = .finishing
                pendingCancel = .some(.none)
            case .active:
                status = .finishing
                let task = producerTask
                producerTask = nil
                task?.cancel()
                await onCancel(.none)
                if let task {
                    await task.value
                }
                status = .finished
                continuation = nil
            case .finishing, .finished:
                break
            }
        @unknown default:
            break
        }
    }
}
