import Foundation
import AISDKProvider
import AISDKProviderUtils

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

    private let _resolve: @Sendable (T) -> Void
    private let _reject: ErrorHandler

    public init() {
        var resolve: (@Sendable (T) -> Void)!
        var reject: ErrorHandler!

        self.task = Task {
            try await withCheckedThrowingContinuation { continuation in
                resolve = { value in
                    continuation.resume(returning: value)
                }
                reject = { error in
                    continuation.resume(throwing: error)
                }
            }
        }

        self._resolve = resolve
        self._reject = reject
    }

    /// Resolves the promise with the given value.
    public func resolve(_ value: T) {
        _resolve(value)
    }

    /// Rejects the promise with the given error.
    public func reject(_ error: Error) {
        _reject(error)
    }
}
