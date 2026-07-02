import Foundation

/// Status of the delayed promise.
enum DelayedPromiseStatus<T: Sendable>: Sendable {
    case pending
    case resolved(T)
    case rejected(any Error)
}

/// Promise-like value that creates its backing task only when accessed.
public final class DelayedPromise<T: Sendable>: @unchecked Sendable {
    private var status: DelayedPromiseStatus<T> = .pending
    private var continuation: CheckedContinuation<T, Error>?
    private var currentTask: Task<T, Error>?
    private let lock = NSLock()

    public init() {}

    /// The task representing the promise.
    ///
    /// Creates the task on first access if not already created.
    public var task: Task<T, Error> {
        lock.lock()
        defer { lock.unlock() }

        if let currentTask {
            return currentTask
        }

        let newTask = Task<T, Error> {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                defer { lock.unlock() }

                switch status {
                case .pending:
                    self.continuation = continuation
                case .resolved(let value):
                    continuation.resume(returning: value)
                case .rejected(let error):
                    continuation.resume(throwing: error)
                }
            }
        }

        currentTask = newTask
        return newTask
    }

    public func resolve(_ value: T) {
        lock.lock()
        defer { lock.unlock() }

        status = .resolved(value)

        if let continuation {
            continuation.resume(returning: value)
            self.continuation = nil
        }
    }

    public func reject(_ error: any Error) {
        lock.lock()
        defer { lock.unlock() }

        status = .rejected(error)

        if let continuation {
            continuation.resume(throwing: error)
            self.continuation = nil
        }
    }

    public func isResolved() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if case .resolved = status {
            return true
        }
        return false
    }

    public func isRejected() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if case .rejected = status {
            return true
        }
        return false
    }

    public func isPending() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if case .pending = status {
            return true
        }
        return false
    }
}
