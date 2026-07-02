import Foundation
import Testing
@testable import AISDKProviderUtils

@Suite("DelayedPromise")
struct DelayedPromiseTests {
    @Test("resolves when accessed after resolution")
    func resolvesWhenAccessedAfterResolution() async throws {
        let promise = DelayedPromise<String>()
        promise.resolve("success")

        let value = try await promise.task.value

        #expect(value == "success")
        #expect(promise.isResolved())
        #expect(!promise.isPending())
        #expect(!promise.isRejected())
    }

    @Test("rejects when accessed after rejection")
    func rejectsWhenAccessedAfterRejection() async {
        let promise = DelayedPromise<String>()
        promise.reject(DelayedPromiseTestError.failure)

        await #expect(throws: DelayedPromiseTestError.failure) {
            _ = try await promise.task.value
        }
        #expect(promise.isRejected())
        #expect(!promise.isPending())
        #expect(!promise.isResolved())
    }

    @Test("resolves when accessed before resolution")
    func resolvesWhenAccessedBeforeResolution() async throws {
        let promise = DelayedPromise<String>()
        let task = promise.task

        promise.resolve("success")

        #expect(try await task.value == "success")
    }

    @Test("rejects when accessed before rejection")
    func rejectsWhenAccessedBeforeRejection() async {
        let promise = DelayedPromise<String>()
        let task = promise.task

        promise.reject(DelayedPromiseTestError.failure)

        await #expect(throws: DelayedPromiseTestError.failure) {
            _ = try await task.value
        }
    }

    @Test("maintains resolved state after multiple accesses")
    func maintainsResolvedStateAfterMultipleAccesses() async throws {
        let promise = DelayedPromise<String>()
        promise.resolve("success")

        #expect(try await promise.task.value == "success")
        #expect(try await promise.task.value == "success")
    }

    @Test("maintains rejected state after multiple accesses")
    func maintainsRejectedStateAfterMultipleAccesses() async {
        let promise = DelayedPromise<String>()
        promise.reject(DelayedPromiseTestError.failure)

        await #expect(throws: DelayedPromiseTestError.failure) {
            _ = try await promise.task.value
        }
        await #expect(throws: DelayedPromiseTestError.failure) {
            _ = try await promise.task.value
        }
    }

    @Test("blocks until resolved when accessed before resolution")
    func blocksUntilResolvedWhenAccessedBeforeResolution() async throws {
        let promise = DelayedPromise<String>()
        let probe = DelayedPromiseProbe<String>()

        let task = Task {
            let value = try await promise.task.value
            await probe.record(value)
            return value
        }

        try await Task.sleep(nanoseconds: 10_000_000)
        #expect(await probe.value == nil)

        promise.resolve("delayed-success")

        #expect(try await task.value == "delayed-success")
        #expect(await probe.value == "delayed-success")
    }

    @Test("blocks until rejected when accessed before rejection")
    func blocksUntilRejectedWhenAccessedBeforeRejection() async {
        let promise = DelayedPromise<String>()
        let probe = DelayedPromiseProbe<Bool>()

        let task = Task {
            do {
                _ = try await promise.task.value
            } catch {
                await probe.record(true)
                throw error
            }
        }

        try? await Task.sleep(nanoseconds: 10_000_000)
        #expect(await probe.value == nil)

        promise.reject(DelayedPromiseTestError.failure)

        await #expect(throws: DelayedPromiseTestError.failure) {
            _ = try await task.value
        }
        #expect(await probe.value == true)
    }

    @Test("resolves all pending task accesses")
    func resolvesAllPendingTaskAccesses() async throws {
        let promise = DelayedPromise<String>()
        let first = promise.task
        let second = promise.task

        promise.resolve("success")

        #expect(try await first.value == "success")
        #expect(try await second.value == "success")
    }
}

private actor DelayedPromiseProbe<T: Sendable> {
    private var storedValue: T?

    var value: T? {
        storedValue
    }

    func record(_ value: T) {
        storedValue = value
    }
}

private enum DelayedPromiseTestError: Error, Equatable {
    case failure
}
