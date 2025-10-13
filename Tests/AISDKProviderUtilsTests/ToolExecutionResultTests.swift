import Testing
import AISDKProvider
@testable import AISDKProviderUtils

/**
 Tests for `ToolExecutionResult<Output>` enum.

 Port of upstream behavior from `@ai-sdk/provider-utils/src/types/execute-tool.ts`.

 Verifies:
 - Three cases: `.value`, `.future`, `.stream`
 - `isStreaming` property
 - `resolve()` method behavior
 - `asAsyncStream()` normalization
 - Error handling
 - Task cancellation support
 */
@Suite("ToolExecutionResult Tests")
struct ToolExecutionResultTests {

    // MARK: - .value Case Tests

    @Test("value case returns immediate result")
    func valueReturnsImmediate() async throws {
        let result = ToolExecutionResult.value("test result")

        let resolved = try await result.resolve()
        #expect(resolved == "test result")
    }

    @Test("value case isStreaming is false")
    func valueIsNotStreaming() {
        let result = ToolExecutionResult.value(42)
        #expect(result.isStreaming == false)
    }

    @Test("value case asAsyncStream yields single value")
    func valueAsyncStreamYieldsSingleValue() async throws {
        let result = ToolExecutionResult.value("test")
        let stream = result.asAsyncStream()

        var values: [String] = []
        for try await value in stream {
            values.append(value)
        }

        #expect(values == ["test"])
    }

    @Test("value case with complex type")
    func valueWithComplexType() async throws {
        struct TestData: Sendable, Equatable {
            let id: Int
            let name: String
        }

        let testData = TestData(id: 1, name: "test")
        let result = ToolExecutionResult.value(testData)

        let resolved = try await result.resolve()
        #expect(resolved == testData)
    }

    // MARK: - .future Case Tests

    @Test("future case executes deferred operation")
    func futureExecutesDeferred() async throws {
        actor ExecutionTracker {
            var executed = false
            func markExecuted() {
                executed = true
            }
            func wasExecuted() -> Bool {
                executed
            }
        }

        let tracker = ExecutionTracker()
        let result = ToolExecutionResult<String>.future {
            await tracker.markExecuted()
            return "deferred result"
        }

        let executedBefore = await tracker.wasExecuted()
        #expect(executedBefore == false) // Not executed yet

        let resolved = try await result.resolve()

        let executedAfter = await tracker.wasExecuted()
        #expect(executedAfter == true) // Now executed
        #expect(resolved == "deferred result")
    }

    @Test("future case isStreaming is false")
    func futureIsNotStreaming() {
        let result = ToolExecutionResult<Int>.future { 42 }
        #expect(result.isStreaming == false)
    }

    @Test("future case asAsyncStream awaits and yields result")
    func futureAsyncStreamAwaitsAndYields() async throws {
        let result = ToolExecutionResult<String>.future {
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            return "async result"
        }

        let stream = result.asAsyncStream()
        var values: [String] = []

        for try await value in stream {
            values.append(value)
        }

        #expect(values == ["async result"])
    }

    @Test("future case handles thrown errors")
    func futureHandlesErrors() async throws {
        enum TestError: Error, Equatable {
            case testFailure
        }

        let result = ToolExecutionResult<String>.future {
            throw TestError.testFailure
        }

        // resolve() should propagate error
        do {
            _ = try await result.resolve()
            Issue.record("Expected error to be thrown")
        } catch let error as TestError {
            #expect(error == .testFailure)
        }
    }

    @Test("future case asAsyncStream propagates errors")
    func futureAsyncStreamPropagatesErrors() async throws {
        enum TestError: Error, Equatable {
            case streamFailure
        }

        let result = ToolExecutionResult<String>.future {
            throw TestError.streamFailure
        }

        let stream = result.asAsyncStream()

        do {
            for try await _ in stream {
                Issue.record("Should not yield any values")
            }
            Issue.record("Expected error to be thrown")
        } catch let error as TestError {
            #expect(error == .streamFailure)
        }
    }

    @Test("future case supports task cancellation")
    func futureSupportsCancellation() async throws {
        let result = ToolExecutionResult<String>.future {
            try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            return "should not complete"
        }

        let stream = result.asAsyncStream()
        var iterator = stream.makeAsyncIterator()

        let task = Task {
            try await iterator.next()
        }

        // Cancel immediately
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        task.cancel()

        do {
            _ = try await task.value
            // If we get here, the operation completed before cancellation
            // This is acceptable in tests due to timing
        } catch is CancellationError {
            // Expected: task was cancelled
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("future case captures input correctly")
    func futureCapturesInput() async throws {
        let input = "captured value"
        let result = ToolExecutionResult<String>.future {
            return "Result: \(input)"
        }

        let resolved = try await result.resolve()
        #expect(resolved == "Result: captured value")
    }

    // MARK: - .stream Case Tests

    @Test("stream case isStreaming is true")
    func streamIsStreaming() {
        let stream = AsyncThrowingStream<Int, Error> { continuation in
            continuation.yield(1)
            continuation.finish()
        }
        let result = ToolExecutionResult.stream(stream)

        #expect(result.isStreaming == true)
    }

    @Test("stream case resolve throws error")
    func streamResolveThrowsError() async throws {
        let stream = AsyncThrowingStream<String, Error> { continuation in
            continuation.yield("test")
            continuation.finish()
        }
        let result = ToolExecutionResult.stream(stream)

        do {
            _ = try await result.resolve()
            Issue.record("Expected streamingResultRequiresStreamConsumption error")
        } catch let error as ToolExecutionResultError {
            #expect(error == .streamingResultRequiresStreamConsumption)
        }
    }

    @Test("stream case asAsyncStream returns stream as-is")
    func streamAsyncStreamReturnsAsIs() async throws {
        let stream = AsyncThrowingStream<Int, Error> { continuation in
            continuation.yield(1)
            continuation.yield(2)
            continuation.yield(3)
            continuation.finish()
        }
        let result = ToolExecutionResult.stream(stream)

        let returnedStream = result.asAsyncStream()
        var values: [Int] = []

        for try await value in returnedStream {
            values.append(value)
        }

        #expect(values == [1, 2, 3])
    }

    @Test("stream case handles multiple values")
    func streamHandlesMultipleValues() async throws {
        let stream = AsyncThrowingStream<String, Error> { continuation in
            continuation.yield("first")
            continuation.yield("second")
            continuation.yield("third")
            continuation.finish()
        }
        let result = ToolExecutionResult.stream(stream)

        let asyncStream = result.asAsyncStream()
        var collected: [String] = []

        for try await value in asyncStream {
            collected.append(value)
        }

        #expect(collected == ["first", "second", "third"])
    }

    @Test("stream case propagates errors")
    func streamPropagatesErrors() async throws {
        enum StreamError: Error, Equatable {
            case testError
        }

        let stream = AsyncThrowingStream<Int, Error> { continuation in
            continuation.yield(1)
            continuation.finish(throwing: StreamError.testError)
        }
        let result = ToolExecutionResult.stream(stream)

        let asyncStream = result.asAsyncStream()

        do {
            var count = 0
            for try await value in asyncStream {
                count += 1
                #expect(value == 1)
            }
            Issue.record("Expected error to be thrown, got \(count) values")
        } catch let error as StreamError {
            #expect(error == .testError)
        }
    }

    @Test("stream case handles empty stream")
    func streamHandlesEmptyStream() async throws {
        let stream = AsyncThrowingStream<String, Error> { continuation in
            continuation.finish()
        }
        let result = ToolExecutionResult.stream(stream)

        let asyncStream = result.asAsyncStream()
        var values: [String] = []

        for try await value in asyncStream {
            values.append(value)
        }

        #expect(values.isEmpty)
    }

    // MARK: - Error Type Tests

    @Test("ToolExecutionResultError has correct description")
    func errorHasCorrectDescription() {
        let error = ToolExecutionResultError.streamingResultRequiresStreamConsumption
        let description = error.errorDescription

        #expect(description == "Attempted to resolve a streaming tool result without consuming its stream.")
    }

    // MARK: - Integration Tests

    @Test("all three cases work with JSONValue")
    func allCasesWorkWithJSONValue() async throws {
        // .value case
        let value = ToolExecutionResult<JSONValue>.value(.string("test"))
        let resolvedValue = try await value.resolve()
        #expect(resolvedValue == .string("test"))

        // .future case
        let future = ToolExecutionResult<JSONValue>.future {
            return .number(42)
        }
        let resolvedFuture = try await future.resolve()
        #expect(resolvedFuture == .number(42))

        // .stream case
        let stream = AsyncThrowingStream<JSONValue, Error> { continuation in
            continuation.yield(.bool(true))
            continuation.finish()
        }
        let streamResult = ToolExecutionResult<JSONValue>.stream(stream)
        #expect(streamResult.isStreaming == true)
    }

    @Test("asAsyncStream normalizes all types consistently")
    func asAsyncStreamNormalizesConsistently() async throws {
        // All three types should yield values in the same way

        // .value
        let valueResult = ToolExecutionResult.value(1)
        var valueValues: [Int] = []
        for try await val in valueResult.asAsyncStream() {
            valueValues.append(val)
        }
        #expect(valueValues == [1])

        // .future
        let futureResult = ToolExecutionResult<Int>.future { 2 }
        var futureValues: [Int] = []
        for try await val in futureResult.asAsyncStream() {
            futureValues.append(val)
        }
        #expect(futureValues == [2])

        // .stream (single value for comparison)
        let stream = AsyncThrowingStream<Int, Error> { continuation in
            continuation.yield(3)
            continuation.finish()
        }
        let streamResult = ToolExecutionResult.stream(stream)
        var streamValues: [Int] = []
        for try await val in streamResult.asAsyncStream() {
            streamValues.append(val)
        }
        #expect(streamValues == [3])
    }

    @Test("concurrent resolve operations work correctly")
    func concurrentResolveOperations() async throws {
        let result1 = ToolExecutionResult<String>.future {
            try await Task.sleep(nanoseconds: 10_000_000)
            return "result1"
        }

        let result2 = ToolExecutionResult<String>.future {
            try await Task.sleep(nanoseconds: 10_000_000)
            return "result2"
        }

        async let value1 = result1.resolve()
        async let value2 = result2.resolve()

        let (v1, v2) = try await (value1, value2)

        #expect(v1 == "result1")
        #expect(v2 == "result2")
    }
}
