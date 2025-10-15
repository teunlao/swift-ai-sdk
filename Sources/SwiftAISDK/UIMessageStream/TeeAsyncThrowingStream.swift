import Foundation

/**
 Splits an `AsyncThrowingStream` into two identical streams.

 Port of `ReadableStream.prototype.tee()` used in `@ai-sdk/ai`.
 */
func teeAsyncThrowingStream<Element: Sendable>(
    _ source: AsyncThrowingStream<Element, Error>
) -> (AsyncThrowingStream<Element, Error>, AsyncThrowingStream<Element, Error>) {
    let distributor = TeeDistributor<Element>()

    let streamA = distributor.makeStream()
    let streamB = distributor.makeStream()

    let pumpTask = Task {
        do {
            for try await value in source {
                distributor.broadcast(value)
            }
            distributor.finish(error: nil)
        } catch is CancellationError {
            distributor.finish(error: nil)
        } catch {
            distributor.finish(error: error)
        }
    }

    distributor.register(task: pumpTask)

    return (streamA, streamB)
}

// MARK: - Distributor

private final class TeeDistributor<Element: Sendable> {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncThrowingStream<Element, Error>.Continuation] = [:]
    private var finished = false
    private var finishError: Error?
    private var pumpTask: Task<Void, Never>?

    func register(task: Task<Void, Never>) {
        lock.lock()
        pumpTask = task
        lock.unlock()
    }

    func makeStream() -> AsyncThrowingStream<Element, Error> {
        AsyncThrowingStream { continuation in
            let id = UUID()

            addContinuation(id: id, continuation: continuation)

            continuation.onTermination = { termination in
                switch termination {
                case .cancelled, .finished:
                    self.removeContinuation(id: id)
                @unknown default:
                    self.removeContinuation(id: id)
                }
            }
        }
    }

    func broadcast(_ value: Element) {
        let continuations = currentContinuations()
        guard !continuations.isEmpty else { return }
        for continuation in continuations {
            continuation.yield(value)
        }
    }

    func finish(error: Error?) {
        let continuations = markFinished(with: error)
        for continuation in continuations {
            if let error {
                continuation.finish(throwing: error)
            } else {
                continuation.finish()
            }
        }
    }

    // MARK: - Private helpers

    private func addContinuation(
        id: UUID,
        continuation: AsyncThrowingStream<Element, Error>.Continuation
    ) {
        lock.lock()
        if let error = finishError {
            lock.unlock()
            continuation.finish(throwing: error)
            return
        }

        if finished {
            lock.unlock()
            continuation.finish()
            return
        }

        continuations[id] = continuation
        lock.unlock()
    }

    private func removeContinuation(id: UUID) {
        lock.lock()
        continuations[id] = nil
        let shouldTerminate = continuations.isEmpty && !finished
        lock.unlock()

        if shouldTerminate {
            finish(error: nil)
        }
    }

    private func currentContinuations()
        -> [AsyncThrowingStream<Element, Error>.Continuation] {
        lock.lock()
        if finished {
            lock.unlock()
            return []
        }
        let values = Array(continuations.values)
        lock.unlock()
        return values
    }

    private func markFinished(with error: Error?)
        -> [AsyncThrowingStream<Element, Error>.Continuation] {
        lock.lock()
        if finished {
            lock.unlock()
            return []
        }

        finished = true
        finishError = error
        let values = Array(continuations.values)
        continuations.removeAll()
        let task = pumpTask
        pumpTask = nil
        lock.unlock()

        task?.cancel()
        return values
    }
}

extension TeeDistributor: @unchecked Sendable {}
