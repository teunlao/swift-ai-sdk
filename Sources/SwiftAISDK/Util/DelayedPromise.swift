/**
 Delayed promise implementation.

 Port of `@ai-sdk/ai/src/util/delayed-promise.ts`.

 A promise-like construct that is only created when accessed.
 This is useful to avoid unhandled task cancellation when the
 continuation is created but not accessed.
 */

import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Status of the delayed promise.
enum DelayedPromiseStatus<T: Sendable>: Sendable {
    case pending
    case resolved(T)
    case rejected(any Error)
}

/// Delayed promise that constructs the Task only when accessed.
///
/// This is useful to avoid unhandled promise rejections when the
/// promise is created but not immediately awaited.
public final class DelayedPromise<T: Sendable>: @unchecked Sendable {
    private var status: DelayedPromiseStatus<T> = .pending
    private var _continuation: CheckedContinuation<T, Error>?
    private var _task: Task<T, Error>?
    private let lock = NSLock()

    /// Creates a new delayed promise.
    public init() {}

    /// The task representing the promise.
    ///
    /// Creates the task on first access if not already created.
    public var task: Task<T, Error> {
        lock.lock()
        defer { lock.unlock() }

        if let existingTask = _task {
            return existingTask
        }

        let newTask = Task<T, Error> {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                defer { lock.unlock() }

                switch status {
                case .pending:
                    _continuation = continuation
                case .resolved(let value):
                    continuation.resume(returning: value)
                case .rejected(let error):
                    continuation.resume(throwing: error)
                }
            }
        }

        _task = newTask
        return newTask
    }

    /// Resolves the promise with a value.
    ///
    /// - Parameter value: The value to resolve with
    public func resolve(_ value: T) {
        lock.lock()
        defer { lock.unlock() }

        status = .resolved(value)

        if let continuation = _continuation {
            continuation.resume(returning: value)
            _continuation = nil
        }
    }

    /// Rejects the promise with an error.
    ///
    /// - Parameter error: The error to reject with
    public func reject(_ error: any Error) {
        lock.lock()
        defer { lock.unlock() }

        status = .rejected(error)

        if let continuation = _continuation {
            continuation.resume(throwing: error)
            _continuation = nil
        }
    }
}
