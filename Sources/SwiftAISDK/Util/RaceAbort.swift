import Foundation

/**
 Returns the result of `operation`, or `nil` once `abort` returns first.

 Neither side is awaited after the other wins: the loser is cancelled and left
 to end on its own, so an operation that ignores cancellation cannot hold the
 caller past an abort (upstream rejects the wait without waiting for the work).
 `abort` must return when its task is cancelled; cancelling the caller cancels
 both sides.
 */
func raceAbort<T: Sendable>(
    _ operation: @escaping @Sendable () async throws -> T,
    abort: @escaping @Sendable () async -> Void
) async throws -> T? {
    let race = AbortRace<T>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            race.install(continuation)
            let work = Task {
                do {
                    race.finish(.success(try await operation()))
                } catch {
                    race.finish(.failure(error))
                }
            }
            let aborting = Task {
                await abort()
                race.finish(.success(nil))
            }
            race.onCancel {
                work.cancel()
                aborting.cancel()
            }
        }
    } onCancel: {
        race.cancel()
    }
}

/// Polls `signal` until it fires or the task is cancelled.
func waitForAbortSignal(_ signal: @escaping @Sendable () -> Bool) async {
    while !Task.isCancelled, !signal() {
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
}

private final class AbortRace<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T?, Error>?
    private var outcome: Result<T?, Error>?
    private var cancelTasks: (@Sendable () -> Void)?
    private var cancelled = false

    func install(_ continuation: CheckedContinuation<T?, Error>) {
        lock.lock()
        if let outcome {
            lock.unlock()
            continuation.resume(with: outcome)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    /// Settles the race once; the first outcome wins and cancels both tasks.
    func finish(_ result: Result<T?, Error>) {
        lock.lock()
        guard outcome == nil else {
            lock.unlock()
            return
        }
        outcome = result
        let continuation = self.continuation
        self.continuation = nil
        let cancelTasks = self.cancelTasks
        self.cancelTasks = nil
        lock.unlock()
        continuation?.resume(with: result)
        cancelTasks?()
    }

    /// Registers the cancellation of both tasks, running it at once when the race is already settled or cancelled.
    func onCancel(_ cancelTasks: @escaping @Sendable () -> Void) {
        lock.lock()
        if outcome != nil || cancelled {
            lock.unlock()
            cancelTasks()
            return
        }
        self.cancelTasks = cancelTasks
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let cancelTasks = outcome == nil ? self.cancelTasks : nil
        lock.unlock()
        cancelTasks?()
    }
}
