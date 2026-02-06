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
    _ delayInMs: Int? = nil,
    abortSignal: (@Sendable () -> Bool)? = nil
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

    // Mirror upstream semantics: abortSignal cancels the delay.
    if let abortSignal {
        if abortSignal() {
            throw CancellationError()
        }

        return try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                let maxMs = Int(UInt64.max / 1_000_000)
                let clamped = min(delayInMs, maxMs)
                try await Task.sleep(nanoseconds: UInt64(clamped) * 1_000_000)
            }

            group.addTask {
                while true {
                    if abortSignal() {
                        throw CancellationError()
                    }
                    try await Task.sleep(nanoseconds: 50_000_000)
                }
            }

            do {
                guard let result = try await group.next() else {
                    throw CancellationError()
                }
                _ = result
                group.cancelAll()
                while let _ = try? await group.next() {}
            } catch {
                group.cancelAll()
                while let _ = try? await group.next() {}
                throw error
            }
        }
    }

    // Convert milliseconds to nanoseconds (no abortSignal; rely on Task cancellation).
    let maxMs = Int(UInt64.max / 1_000_000)
    let clamped = min(delayInMs, maxMs)
    let nanoseconds = UInt64(clamped) * 1_000_000
    try await Task.sleep(nanoseconds: nanoseconds)
}
