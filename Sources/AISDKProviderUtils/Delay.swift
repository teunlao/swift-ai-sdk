import Foundation

/**
 Creates a Task that completes after a specified delay.

 Port of `@ai-sdk/provider-utils/src/delay.ts`

 - Parameters:
   - delayInMs: The delay duration in milliseconds. If `nil`, resolves immediately.
   - abortSignal: Optional closure to check if the delay should be cancelled.

 - Throws: `CancellationError` when the task is cancelled.

 - Note: This function uses Swift's structured concurrency. If called within a Task,
         cancellation will be handled automatically via `Task.checkCancellation()`.
 */
public func delay(
    _ delayInMs: Int? = nil
) async throws {
    // Resolve immediately if delay is nil
    guard let delayInMs = delayInMs else {
        return
    }

    // Treat negative or zero delay as immediate (matches TypeScript behavior)
    guard delayInMs > 0 else {
        return
    }

    // Check if already cancelled
    try Task.checkCancellation()

    // Convert milliseconds to nanoseconds
    let nanoseconds = UInt64(delayInMs) * 1_000_000

    // Sleep with cancellation support
    try await Task.sleep(nanoseconds: nanoseconds)
}
