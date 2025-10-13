import Foundation

/**
 Serializes tests that mutate `AI_SDK_LOG_WARNINGS` to avoid race conditions.

 Uses a simple async lock to ensure only one critical section executes at a time
 even across suspension points.
 */
actor LogWarningsTestLock {
    static let shared = LogWarningsTestLock()

    private var isLocked = false
    private var waitQueue: [CheckedContinuation<Void, Never>] = []

    func withLock<T: Sendable>(_ operation: @Sendable () async throws -> T) async rethrows -> T {
        await acquire()
        defer { release() }
        return try await operation()
    }

    private func acquire() async {
        if !isLocked {
            isLocked = true
            return
        }

        await withCheckedContinuation { continuation in
            waitQueue.append(continuation)
        }
    }

    private func release() {
        if let continuation = waitQueue.first {
            waitQueue.removeFirst()
            continuation.resume()
        } else {
            isLocked = false
        }
    }
}
