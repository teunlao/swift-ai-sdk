/**
 Tests for createResolvablePromise utility.
 */

import Testing
@testable import SwiftAISDK

@Suite("ResolvablePromise Tests")
struct CreateResolvablePromiseTests {
    @Test("resolves value when resolved asynchronously")
    func resolvesWhenResolvedLater() async throws {
        let promise = createResolvablePromise(of: Int.self)

        Task {
            try await Task.sleep(nanoseconds: 100_000)
            promise.resolve(42)
        }

        let value = try await promise.task.value
        #expect(value == 42)
    }

    @Test("resolves value even if resolve is called before awaiting")
    func resolvesWhenResolvedImmediately() async throws {
        let promise = createResolvablePromise(of: String.self)
        promise.resolve("ready")

        let value = try await promise.task.value
        #expect(value == "ready")
    }

    @Test("rejects with error and ignores further resolution")
    func rejectsAndIgnoresFurtherCalls() async throws {
        struct TestError: Error, Sendable {}
        let promise = createResolvablePromise(of: Int.self)
        promise.reject(TestError())

        await #expect(throws: TestError.self) {
            _ = try await promise.task.value
        }

        // Subsequent resolve should have no effect and must not crash.
        promise.resolve(7)
    }

    @Test("returns first resolved value when resolve is called multiple times")
    func returnsFirstValueOnMultipleResolves() async throws {
        let promise = createResolvablePromise(of: Int.self)
        promise.resolve(1)
        promise.resolve(2)

        let value = try await promise.task.value
        #expect(value == 1)
    }
    @Test("returns first error when reject is called multiple times")
    func rejectsWithFirstErrorOnMultipleRejects() async throws {
        struct FirstError: Error, Sendable {}
        struct SecondError: Error, Sendable {}
        let promise = createResolvablePromise(of: Int.self)
        promise.reject(FirstError())
        promise.reject(SecondError())

        await #expect(throws: FirstError.self) {
            _ = try await promise.task.value
        }
    }

    @Test("resolve result is stable even if reject is called later")
    func resolveIgnoresSubsequentReject() async throws {
        struct LateError: Error, Sendable {}
        let promise = createResolvablePromise(of: String.self)
        promise.resolve("done")
        promise.reject(LateError())

        let value = try await promise.task.value
        #expect(value == "done")
    }

}
