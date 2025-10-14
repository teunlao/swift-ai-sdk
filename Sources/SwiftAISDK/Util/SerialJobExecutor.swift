/**
 Executes jobs serially (one at a time) in FIFO order.

 Port of `@ai-sdk/ai/src/util/serial-job-executor.ts`.

 Maintains a queue of jobs and processes them sequentially in the exact
 order they were submitted. Uses an explicit FIFO queue protected by an
 `NSLock` to guarantee ordering even under concurrent `run()` calls,
 matching TypeScript behavior.

 **FIFO Guarantee**: Unlike Swift actors (which don't guarantee message
 processing order), this implementation keeps an explicit queue and
 processes jobs one-by-one on a helper task. This ensures jobs execute
 in submission order, which upstream code depends on to prevent race
 conditions (e.g., chat.ts:615).
 */

import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Executes jobs serially in a queue with guaranteed FIFO ordering.
///
/// Jobs are processed one at a time in strict submission order.
/// Multiple concurrent `run()` calls will queue jobs in the exact
/// order the calls were made, matching upstream TypeScript behavior.
public final class SerialJobExecutor: @unchecked Sendable {
    private struct QueuedJob {
        let job: Job
        let continuation: CheckedContinuation<Void, Error>
    }

    private let lock = NSLock()
    private var queue: [QueuedJob] = []
    private var isProcessing = false

    /// Creates a new serial job executor.
    public init() {}

    /// Runs a job in the serial queue.
    ///
    /// The job will be queued and executed when all previously
    /// queued jobs have completed. Jobs execute in strict FIFO
    /// order regardless of how quickly they're submitted.
    ///
    /// - Parameter job: The job to execute.
    /// - Throws: Any error thrown by the job.
    public func run(_ job: @escaping Job) async throws {
        try await withCheckedThrowingContinuation { continuation in
            enqueue(job: job, continuation: continuation)
        }
    }

    private func enqueue(
        job: @escaping Job,
        continuation: CheckedContinuation<Void, Error>
    ) {
        lock.lock()
        queue.append(QueuedJob(job: job, continuation: continuation))
        let shouldStartProcessing = !isProcessing
        if shouldStartProcessing {
            isProcessing = true
        }
        lock.unlock()

        if shouldStartProcessing {
            Task {
                await processQueue()
            }
        }
    }

    private func dequeue() -> QueuedJob? {
        lock.lock()
        defer { lock.unlock() }
        guard !queue.isEmpty else {
            isProcessing = false
            return nil
        }
        return queue.removeFirst()
    }

    private func processQueue() async {
        while let queuedJob = dequeue() {
            do {
                try await queuedJob.job()
                queuedJob.continuation.resume()
            } catch {
                queuedJob.continuation.resume(throwing: error)
            }
        }
    }
}
