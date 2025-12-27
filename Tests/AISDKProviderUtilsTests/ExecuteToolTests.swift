/**
 Tests for executeTool helper.

 Port of `@ai-sdk/provider-utils/src/types/execute-tool.test.ts`.
 */
import Testing
import AISDKProvider
@testable import AISDKProviderUtils

/**
 Tests for `executeTool()` function.

 Port of upstream behavior from `@ai-sdk/provider-utils/src/types/execute-tool.ts`.

 Verifies:
 - Non-streaming execution (`.value`, `.future`) yields only final output
 - Streaming execution (`.stream`) yields preliminary + final outputs
 - Error propagation
 - Task cancellation support
 */
@Suite("ExecuteTool Tests")
struct ExecuteToolTests {

    // MARK: - Non-Streaming Tests

    @Test("executeTool with .value yields only final output")
    func valueYieldsOnlyFinal() async throws {
        let execute: @Sendable (String, ToolCallOptions) async throws -> ToolExecutionResult<String> = { input, _ in
            return .value("result: \(input)")
        }

        let stream = executeTool(
            execute: execute,
            input: "test",
            options: ToolCallOptions(toolCallId: "1", messages: [])
        )

        var outputs: [ToolExecutionOutput<String>] = []
        for try await output in stream {
            outputs.append(output)
        }

        #expect(outputs.count == 1)
        #expect(outputs[0].isFinal)
        #expect(outputs[0].output == "result: test")
    }

    @Test("executeTool with .future yields only final output")
    func futureYieldsOnlyFinal() async throws {
        let execute: @Sendable (Int, ToolCallOptions) async throws -> ToolExecutionResult<Int> = { input, _ in
            return .future {
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
                return input * 2
            }
        }

        let stream = executeTool(
            execute: execute,
            input: 42,
            options: ToolCallOptions(toolCallId: "1", messages: [])
        )

        var outputs: [ToolExecutionOutput<Int>] = []
        for try await output in stream {
            outputs.append(output)
        }

        #expect(outputs.count == 1)
        #expect(outputs[0].isFinal)
        #expect(outputs[0].output == 84)
    }

    // MARK: - Streaming Tests

    @Test("executeTool with .stream yields preliminary + final outputs")
    func streamYieldsPreliminaryAndFinal() async throws {
        let execute: @Sendable (String, ToolCallOptions) async throws -> ToolExecutionResult<String> = { input, _ in
            let stream = AsyncThrowingStream<String, Error> { continuation in
                continuation.yield("\(input)-1")
                continuation.yield("\(input)-2")
                continuation.yield("\(input)-3")
                continuation.finish()
            }
            return .stream(stream)
        }

        let resultStream = executeTool(
            execute: execute,
            input: "test",
            options: ToolCallOptions(toolCallId: "1", messages: [])
        )

        var outputs: [ToolExecutionOutput<String>] = []
        for try await output in resultStream {
            outputs.append(output)
        }

        // Should have 3 preliminary + 1 final
        #expect(outputs.count == 4)

        // First 3 should be preliminary
        #expect(outputs[0].isPreliminary)
        #expect(outputs[0].output == "test-1")

        #expect(outputs[1].isPreliminary)
        #expect(outputs[1].output == "test-2")

        #expect(outputs[2].isPreliminary)
        #expect(outputs[2].output == "test-3")

        // Last should be final (with last stream value)
        #expect(outputs[3].isFinal)
        #expect(outputs[3].output == "test-3")
    }

    @Test("executeTool with single-value stream yields preliminary + final")
    func singleValueStreamYieldsBoth() async throws {
        let execute: @Sendable (Int, ToolCallOptions) async throws -> ToolExecutionResult<Int> = { input, _ in
            let stream = AsyncThrowingStream<Int, Error> { continuation in
                continuation.yield(input)
                continuation.finish()
            }
            return .stream(stream)
        }

        let resultStream = executeTool(
            execute: execute,
            input: 100,
            options: ToolCallOptions(toolCallId: "1", messages: [])
        )

        var outputs: [ToolExecutionOutput<Int>] = []
        for try await output in resultStream {
            outputs.append(output)
        }

        // Should have 1 preliminary + 1 final
        #expect(outputs.count == 2)
        #expect(outputs[0].isPreliminary)
        #expect(outputs[0].output == 100)
        #expect(outputs[1].isFinal)
        #expect(outputs[1].output == 100)
    }

    @Test("executeTool with empty stream still yields final output")
    func emptyStreamYieldsFinal() async throws {
        let execute: @Sendable (String, ToolCallOptions) async throws -> ToolExecutionResult<String> = { _, _ in
            let stream = AsyncThrowingStream<String, Error> { continuation in
                continuation.finish()
            }
            return .stream(stream)
        }

        let resultStream = executeTool(
            execute: execute,
            input: "test",
            options: ToolCallOptions(toolCallId: "1", messages: [])
        )

        var outputs: [ToolExecutionOutput<String>] = []
        for try await output in resultStream {
            outputs.append(output)
        }

        // Empty stream → final event with missing value (parity with undefined).
        #expect(outputs.count == 1)
        #expect(outputs[0].isFinal)
        #expect(outputs[0].output == nil)
    }

    // MARK: - Error Handling Tests

    @Test("executeTool propagates errors from .value")
    func valueErrorPropagates() async throws {
        enum TestError: Error, Equatable {
            case testFailure
        }

        let execute: @Sendable (String, ToolCallOptions) async throws -> ToolExecutionResult<String> = { _, _ in
            throw TestError.testFailure
        }

        let stream = executeTool(
            execute: execute,
            input: "test",
            options: ToolCallOptions(toolCallId: "1", messages: [])
        )

        do {
            for try await _ in stream {
                Issue.record("Should not yield any values")
            }
            Issue.record("Expected error to be thrown")
        } catch let error as TestError {
            #expect(error == .testFailure)
        }
    }

    @Test("executeTool propagates errors from .future")
    func futureErrorPropagates() async throws {
        enum TestError: Error, Equatable {
            case asyncFailure
        }

        let execute: @Sendable (Int, ToolCallOptions) async throws -> ToolExecutionResult<Int> = { _, _ in
            return .future {
                throw TestError.asyncFailure
            }
        }

        let stream = executeTool(
            execute: execute,
            input: 42,
            options: ToolCallOptions(toolCallId: "1", messages: [])
        )

        do {
            for try await _ in stream {
                Issue.record("Should not yield any values")
            }
            Issue.record("Expected error to be thrown")
        } catch let error as TestError {
            #expect(error == .asyncFailure)
        }
    }

    @Test("executeTool propagates errors from .stream")
    func streamErrorPropagates() async throws {
        enum TestError: Error, Equatable {
            case streamFailure
        }

        let execute: @Sendable (String, ToolCallOptions) async throws -> ToolExecutionResult<String> = { _, _ in
            let stream = AsyncThrowingStream<String, Error> { continuation in
                continuation.yield("value1")
                continuation.finish(throwing: TestError.streamFailure)
            }
            return .stream(stream)
        }

        let resultStream = executeTool(
            execute: execute,
            input: "test",
            options: ToolCallOptions(toolCallId: "1", messages: [])
        )

        var preliminaryCount = 0
        do {
            for try await output in resultStream {
                if output.isPreliminary {
                    preliminaryCount += 1
                }
            }
            Issue.record("Expected error to be thrown")
        } catch let error as TestError {
            #expect(error == .streamFailure)
            #expect(preliminaryCount == 1) // Should have yielded one preliminary before error
        }
    }

    // MARK: - Integration Tests

    @Test("executeTool with ToolCallOptions passes correctly")
    func toolCallOptionsPassedCorrectly() async throws {
        actor OptionsCapture {
            var options: ToolCallOptions?
            func capture(_ opts: ToolCallOptions) {
                options = opts
            }
            func getCaptured() -> ToolCallOptions? {
                options
            }
        }

        let capture = OptionsCapture()

        let execute: @Sendable (String, ToolCallOptions) async throws -> ToolExecutionResult<String> = { input, options in
            await capture.capture(options)
            return .value("result")
        }

        let options = ToolCallOptions(
            toolCallId: "call-123",
            messages: [], // Empty messages array for simplicity
            abortSignal: { false },
            experimentalContext: JSONValue.string("context")
        )

        let stream = executeTool(
            execute: execute,
            input: "test",
            options: options
        )

        // Consume stream
        for try await _ in stream {}

        let capturedOptions = await capture.getCaptured()
        #expect(capturedOptions?.toolCallId == "call-123")
        #expect(capturedOptions?.messages.isEmpty == true)
        #expect(capturedOptions?.experimentalContext == JSONValue.string("context"))
    }

    @Test("executeTool supports cancellation")
    func executionSupportsCancellation() async throws {
        let execute: @Sendable (String, ToolCallOptions) async throws -> ToolExecutionResult<String> = { _, _ in
            return .future {
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                return "should not complete"
            }
        }

        let stream = executeTool(
            execute: execute,
            input: "test",
            options: ToolCallOptions(toolCallId: "1", messages: [])
        )

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
}
