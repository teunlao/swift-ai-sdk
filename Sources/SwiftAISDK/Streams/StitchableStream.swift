import Foundation

/**
 Creates a stitchable stream that pipes one inner stream after another.

 Port of `@ai-sdk/ai/src/util/create-stitchable-stream.ts`.

 The controller mirrors the upstream pull-based `ReadableStream` behaviour:
 - `addStream` enqueues another `AsyncIterableStream` (throws if the outer stream is closed)
 - `close` lets already enqueued streams drain before finishing the outer stream
 - `terminate` cancels all pending streams immediately and closes the outer stream
 */
public struct StitchableStream<Element: Sendable>: Sendable {
    public let stream: AsyncIterableStream<Element>
    public let addStream: @Sendable (AsyncIterableStream<Element>) async throws -> Void
    public let close: @Sendable () -> Void
    public let terminate: @Sendable () -> Void
}

/// Error thrown when attempting to add a stream after the outer stream has been closed.
enum StitchableStreamError: Error, LocalizedError {
    case outerStreamClosed

    var errorDescription: String? {
        "Cannot add inner stream: outer stream is closed"
    }
}

public func createStitchableStream<Element: Sendable>() -> StitchableStream<Element> {
    let controller = StitchableStreamController<Element>()

    let rawStream = AsyncThrowingStream<Element, Error> { continuation in
        Task {
            await controller.initialize(continuation: continuation)
        }

        continuation.onTermination = { termination in
            Task {
                await controller.handleTermination(termination)
            }
        }
    }

    let stream = createAsyncIterableStream(
        source: rawStream,
        _internal: AsyncIterableStreamInternalOptions { reason in
            await controller.handleCancel(reason: reason)
        }
    )

    return StitchableStream(
        stream: stream,
        addStream: { innerStream in
            try await controller.enqueue(stream: innerStream)
        },
        close: {
            Task {
                await controller.close()
            }
        },
        terminate: {
            Task {
                await controller.terminate()
            }
        }
    )
}

// MARK: - Controller

actor StitchableStreamController<Element: Sendable> {
    private var continuation: AsyncThrowingStream<Element, Error>.Continuation?
    private var pendingStreams: [AsyncIterableStream<Element>] = []
    private var currentStream: AsyncIterableStream<Element>?
    private var isClosed = false
    private var isTerminated = false
    private var hasFinished = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var pumpTask: Task<Void, Never>?

    func initialize(
        continuation: AsyncThrowingStream<Element, Error>.Continuation
    ) async {
        guard self.continuation == nil else { return }
        self.continuation = continuation

        if pumpTask == nil {
            pumpTask = Task {
                await self.pump()
            }
        }

        if isClosed && pendingStreams.isEmpty {
            finishIfNeeded()
        }
    }

    func handleTermination(
        _ termination: AsyncThrowingStream<Element, Error>.Continuation.Termination
    ) async {
        switch termination {
        case .finished:
            await close()
        case .cancelled:
            await terminate()
        @unknown default:
            break
        }
    }

    func handleCancel(
        reason: AsyncIterableStreamCancellationReason
    ) async {
        switch reason {
        case .none:
            await terminate()
        case .message, .error:
            await terminate()
        }
    }

    func enqueue(
        stream: AsyncIterableStream<Element>
    ) async throws {
        guard !isClosed else {
            throw StitchableStreamError.outerStreamClosed
        }

        pendingStreams.append(stream)
        resolveWaiters()
    }

    func close() async {
        guard !isClosed else { return }
        isClosed = true

        if pendingStreams.isEmpty && currentStream == nil {
            finishIfNeeded()
        }

        resolveWaiters()
    }

    func terminate() async {
        guard !isTerminated else { return }
        isTerminated = true
        isClosed = true

        let activeStream = currentStream
        currentStream = nil
        let remainingStreams = pendingStreams
        pendingStreams.removeAll()

        resolveWaiters()
        pumpTask?.cancel()
        pumpTask = nil

        if let activeStream {
            await activeStream.cancel()
        }

        await cancelStreams(remainingStreams)

        finishIfNeeded()
    }

    // MARK: - Pumping

    private func pump() async {
        while let stream = await nextStream() {
            currentStream = stream
            do {
                var iterator = stream.makeAsyncIterator()
                while let value = try await iterator.next() {
                    continuation?.yield(value)
                    if isTerminated {
                        return
                    }
                }
            } catch {
                finishIfNeeded(error: error)
                await terminate()
                return
            }
            currentStream = nil
        }
    }

    private func nextStream() async -> AsyncIterableStream<Element>? {
        while true {
            if isTerminated {
                return nil
            }

            if let first = pendingStreams.first {
                pendingStreams.removeFirst()
                return first
            }

            if isClosed {
                finishIfNeeded()
                return nil
            }

            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
    }

    private func cancelStreams(
        _ streams: [AsyncIterableStream<Element>]
    ) async {
        for stream in streams {
            await stream.cancel()
        }
    }

    private func resolveWaiters() {
        guard !waiters.isEmpty else { return }
        let waiters = self.waiters
        self.waiters.removeAll()

        for waiter in waiters {
            waiter.resume(returning: ())
        }
    }

    private func finishIfNeeded(error: Error? = nil) {
        guard !hasFinished else { return }
        hasFinished = true

        if let error {
            continuation?.finish(throwing: error)
        } else {
            continuation?.finish()
        }
    }
}
