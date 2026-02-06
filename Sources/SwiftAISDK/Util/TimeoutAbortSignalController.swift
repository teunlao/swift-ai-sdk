import Foundation

/// Thread-safe timeout state used to back an abort signal closure.
///
/// SwiftAI SDK models timeouts as abort signals for parity with upstream
/// `AbortSignal.timeout(...)` and related merged signals.
final class TimeoutAbortSignalController: @unchecked Sendable {
    private let lock = NSLock()
    private var totalTimedOut = false
    private var stepTimedOut = false
    private var chunkTimedOut = false

    func markTotalTimedOut() {
        lock.lock()
        totalTimedOut = true
        lock.unlock()
    }

    func markStepTimedOut() {
        lock.lock()
        stepTimedOut = true
        lock.unlock()
    }

    func markChunkTimedOut() {
        lock.lock()
        chunkTimedOut = true
        lock.unlock()
    }

    func isAborted() -> Bool {
        lock.lock()
        let value = totalTimedOut || stepTimedOut || chunkTimedOut
        lock.unlock()
        return value
    }
}

func sleepMs(_ milliseconds: Int) async throws {
    guard milliseconds > 0 else { return }
    let maxMs = Int(UInt64.max / 1_000_000)
    let clamped = min(milliseconds, maxMs)
    try await Task.sleep(nanoseconds: UInt64(clamped) * 1_000_000)
}

