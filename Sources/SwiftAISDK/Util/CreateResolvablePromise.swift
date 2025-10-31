import Foundation
import _Concurrency

/**
 Creates a task with externally accessible resolve and reject functions.

 Port of `@ai-sdk/ai/src/util/create-resolvable-promise.ts`.

 In Swift, this is implemented using `CheckedContinuation` wrapped in a Task.
 The resolve/reject functions can be called from outside to complete the task.

 Example:
 ```swift
 let resolvable = createResolvablePromise(of: String.self)

 Task {
     resolvable.resolve("Done!")
 }

 let result = try await resolvable.task.value
 // result == "Done!"
 ```
 */
public func createResolvablePromise<T: Sendable>(of type: T.Type = T.self) -> ResolvablePromise<T> {
    return ResolvablePromise<T>()
}

/// A promise that can be resolved or rejected externally.
public final class ResolvablePromise<T: Sendable>: @unchecked Sendable {
    /// The task that will complete when resolve or reject is called.
    public let task: Task<T, Error>

    private let storage = Storage()

    public init() {
        let storage = self.storage
        self.task = Task {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
                if let pending = storage.prepareContinuation(continuation) {
                    storage.resumeContinuation(continuation, with: pending)
                }
            }
        }
    }

    /// Resolves the promise with the given value.
    public func resolve(_ value: T) {
        resume(.success(value))
    }

    /// Rejects the promise with the given error.
    public func reject(_ error: Error) {
        resume(.failure(error))
    }

    private func resume(_ result: Result<T, Error>) {
        if let continuation = storage.takeContinuation() {
            storage.resumeContinuation(continuation, with: result)
        } else {
            storage.storePendingResultIfNeeded(result)
        }
    }

    private final class Storage: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<T, Error>?
        private var pendingResult: Result<T, Error>?
        private var isCompleted = false

        func prepareContinuation(_ continuation: CheckedContinuation<T, Error>) -> Result<T, Error>? {
            lock.lock()
            defer { lock.unlock() }

            if let result = pendingResult {
                pendingResult = nil
                return result
            }

            guard !isCompleted else {
                return nil
            }

            self.continuation = continuation
            return nil
        }

        func takeContinuation() -> CheckedContinuation<T, Error>? {
            lock.lock()
            defer { lock.unlock() }

            guard !isCompleted, let continuation else {
                return nil
            }

            self.continuation = nil
            isCompleted = true
            return continuation
        }

        func storePendingResultIfNeeded(_ result: Result<T, Error>) {
            lock.lock()
            defer { lock.unlock() }

            guard !isCompleted else {
                return
            }

            pendingResult = result
            isCompleted = true
        }

        func resumeContinuation(_ continuation: CheckedContinuation<T, Error>, with result: Result<T, Error>) {
            switch result {
            case .success(let value):
                continuation.resume(returning: value)
            case .failure(let error):
                continuation.resume(throwing: error)
            }
        }
    }
}
