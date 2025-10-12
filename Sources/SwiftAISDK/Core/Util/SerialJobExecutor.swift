/**
 Executes jobs serially (one at a time) in FIFO order.

 Port of `@ai-sdk/ai/src/util/serial-job-executor.ts`.

 Maintains a queue of jobs and processes them sequentially in the exact
 order they were submitted. Uses DispatchQueue to guarantee FIFO ordering
 even under concurrent `run()` calls, matching TypeScript behavior.

 **FIFO Guarantee**: Unlike Swift actors (which don't guarantee message
 processing order), this implementation uses a serial DispatchQueue to
 ensure jobs execute in submission order. This is critical for upstream
 code that relies on SerialJobExecutor to prevent race conditions
 (e.g., chat.ts:615).
 */

import Foundation

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

    private let queue = DispatchQueue(label: "com.swiftaisdk.serialjobexecutor")
    private let continuation: AsyncStream<QueuedJob>.Continuation
    private let processingTask: Task<Void, Never>

    /// Creates a new serial job executor.
    public init() {
        let (stream, continuation) = AsyncStream<QueuedJob>.makeStream()
        self.continuation = continuation

        // Start processing loop
        self.processingTask = Task.detached {
            // Process jobs sequentially
            for await queuedJob in stream {
                do {
                    try await queuedJob.job()
                    queuedJob.continuation.resume()
                } catch {
                    queuedJob.continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Runs a job in the serial queue.
    ///
    /// The job will be queued and executed when all previously
    /// queued jobs have completed. Jobs execute in strict FIFO
    /// order regardless of how quickly they're submitted.
    ///
    /// The key to FIFO guarantee: DispatchQueue.sync ensures FULLY synchronous
    /// enqueueing (unlike actors which don't guarantee order). The serial queue
    /// processes jobs in strict FIFO order, matching TypeScript behavior where
    /// `run()` synchronously adds to queue before returning Promise.
    ///
    /// Reference: https://forums.swift.org/t/simple-state-protection-via-actor-vs-dispatchqueue-sync/66184
    /// "tasks waiting on an actor's Serial Executor are not necessarily executed in the order they were awaited,
    /// which is a departure from the behavior of a Serial DispatchQueue, which adheres to a strict FIFO policy"
    ///
    /// - Parameter job: The job to execute
    /// - Throws: Any error thrown by the job
    public func run(_ job: @escaping Job) async throws {
        // Use DispatchQueue.sync to ensure FULLY synchronous enqueueing
        // This guarantees FIFO order even with concurrent async calls
        try await withCheckedThrowingContinuation { cont in
            queue.sync {
                continuation.yield(QueuedJob(job: job, continuation: cont))
            }
        }
    }

    deinit {
        continuation.finish()
        processingTask.cancel()
    }
}
