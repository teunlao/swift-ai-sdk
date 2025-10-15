/**
 Tests for SerialJobExecutor.

 Port of `@ai-sdk/ai/src/util/serial-job-executor.test.ts`.
 */

import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import SwiftAISDK

/// Actor for tracking execution order in tests
actor ExecutionTracker {
    private(set) var executionOrder: [Int] = []
    private(set) var startOrder: [Int] = []
    private(set) var results: [String] = []
    private(set) var concurrentJobs = 0
    private(set) var maxConcurrentJobs = 0

    func appendExecution(_ value: Int) {
        executionOrder.append(value)
    }

    func appendStart(_ value: Int) {
        startOrder.append(value)
    }

    func appendResult(_ value: String) {
        results.append(value)
    }

    func incrementConcurrent() {
        concurrentJobs += 1
        maxConcurrentJobs = max(maxConcurrentJobs, concurrentJobs)
    }

    func decrementConcurrent() {
        concurrentJobs -= 1
    }
}

@Suite("SerialJobExecutor Tests")
struct SerialJobExecutorTests {
    @Test("should execute a single job successfully")
    func executeSingleJob() async throws {
        let executor = SerialJobExecutor()
        let result = DelayedPromise<String>()

        try await executor.run {
            result.resolve("done")
        }

        let value = try await result.task.value
        #expect(value == "done")
    }

    @Test("should execute multiple jobs in serial order")
    func executeMultipleJobsInOrder() async throws {
        let executor = SerialJobExecutor()
        let tracker = ExecutionTracker()
        let job1Promise = DelayedPromise<Void>()
        let job2Promise = DelayedPromise<Void>()
        let job3Promise = DelayedPromise<Void>()

        // Start all jobs - mimic TypeScript array construction
        // In TypeScript: const promises = [run(...), run(...), run(...)]
        // Array is built synchronously, so run() calls happen in sequence
        let promise1 = Task {
            try? await executor.run {
                await tracker.appendExecution(1)
                job1Promise.resolve(())
            }
        }
        await Task.yield()

        let promise2 = Task {
            try? await executor.run {
                await tracker.appendExecution(2)
                job2Promise.resolve(())
            }
        }
        await Task.yield()

        let promise3 = Task {
            try? await executor.run {
                await tracker.appendExecution(3)
                job3Promise.resolve(())
            }
        }

        let promises = [promise1, promise2, promise3]

        // Wait for all tasks to complete
        for task in promises {
            _ = await task.value
        }

        // Verify execution order
        let executionOrder = await tracker.executionOrder
        #expect(executionOrder == [1, 2, 3])
    }

    @Test("should handle job errors correctly")
    func handleJobErrors() async throws {
        let executor = SerialJobExecutor()
        struct TestError: Error {}
        let error = TestError()

        await #expect(throws: TestError.self) {
            try await executor.run {
                throw error
            }
        }
    }

    @Test("should execute jobs one at a time")
    func executeJobsOneAtATime() async throws {
        let executor = SerialJobExecutor()
        let tracker = ExecutionTracker()
        let job1 = DelayedPromise<Void>()
        let job2 = DelayedPromise<Void>()

        // Start two jobs
        async let promise1: Void = executor.run {
            await tracker.incrementConcurrent()
            try await job1.task.value
            await tracker.decrementConcurrent()
        }

        async let promise2: Void = executor.run {
            await tracker.incrementConcurrent()
            try await job2.task.value
            await tracker.decrementConcurrent()
        }

        // Let both jobs proceed and complete
        job1.resolve(())
        job2.resolve(())

        _ = try await (promise1, promise2)

        let maxConcurrentJobs = await tracker.maxConcurrentJobs
        #expect(maxConcurrentJobs == 1)
    }

    @Test("should handle mixed success and failure jobs")
    func handleMixedSuccessAndFailure() async throws {
        let executor = SerialJobExecutor()
        let tracker = ExecutionTracker()
        struct TestError: Error {}
        let error = TestError()

        // Queue multiple jobs with mixed success/failure
        try await executor.run {
            await tracker.appendResult("job1")
        }

        // First job should succeed
        var results = await tracker.results
        #expect(results == ["job1"])

        // Second job should fail
        await #expect(throws: TestError.self) {
            try await executor.run {
                throw error
            }
        }

        // Third job should still execute and succeed
        try await executor.run {
            await tracker.appendResult("job3")
        }

        results = await tracker.results
        #expect(results == ["job1", "job3"])
    }

    @Test("should handle concurrent calls to run()")
    func handleConcurrentCalls() async throws {
        let executor = SerialJobExecutor()
        let tracker = ExecutionTracker()

        // Create delayed promises for controlling job execution
        let job1 = DelayedPromise<Void>()
        let job2 = DelayedPromise<Void>()
        let job3 = DelayedPromise<Void>()

        // Queue run() calls using Tasks, yielding between submissions to preserve ordering.
        let firstJob = Task {
            try await executor.run {
                await tracker.appendStart(1)
                try await job1.task.value
                await tracker.appendExecution(1)
            }
        }
        try await Task.sleep(nanoseconds: 200_000)

        let secondJob = Task {
            try await executor.run {
                await tracker.appendStart(2)
                try await job2.task.value
                await tracker.appendExecution(2)
            }
        }
        try await Task.sleep(nanoseconds: 200_000)

        let thirdJob = Task {
            try await executor.run {
                await tracker.appendStart(3)
                try await job3.task.value
                await tracker.appendExecution(3)
            }
        }

        // Resolve jobs in reverse order to verify execution order is maintained
        job3.resolve(())
        job2.resolve(())
        job1.resolve(())

        // Wait for all jobs to complete
        try await firstJob.value
        try await secondJob.value
        try await thirdJob.value

        // Verify that jobs were queued in the order they were submitted
        let startOrder = await tracker.startOrder
        let executionOrder = await tracker.executionOrder
        #expect(startOrder == [1, 2, 3])
        // Verify that jobs were executed in the order they were queued
        #expect(executionOrder == [1, 2, 3])
    }
}
