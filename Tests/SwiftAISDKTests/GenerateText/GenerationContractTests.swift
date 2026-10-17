import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
@testable import SwiftAISDK

private final class LockedValue<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    init(initial: Value) {
        value = initial
    }

    func withValue<R>(_ body: (inout Value) -> R) -> R {
        lock.withLock { body(&value) }
    }
}

/// Records the lifecycle events an integration receives, in order.
private final class EventRecorder: Telemetry, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []

    var events: [String] { lock.withLock { recorded } }

    private func record(_ name: String) { lock.withLock { recorded.append(name) } }

    func onStart(_ event: TelemetryEvent<TelemetryStartEvent>) async throws { record("start:\(event.event.operationId)") }
    func onStepStart(_ event: TelemetryEvent<GenerateTextStepStartEvent>) async throws { record("stepStart") }
    func onLanguageModelCallStart(_ event: TelemetryEvent<LanguageModelCallStartEvent>) async throws { record("modelCallStart") }
    func onLanguageModelCallEnd(_ event: TelemetryEvent<LanguageModelCallEndEvent>) async throws { record("modelCallEnd") }
    func onToolExecutionStart(_ event: TelemetryEvent<ToolExecutionStartEvent>) async throws { record("toolStart") }
    func onToolExecutionEnd(_ event: TelemetryEvent<ToolExecutionEndEvent>) async throws { record("toolEnd") }
    func onStepEnd(_ event: TelemetryEvent<any StepResult>) async throws { record("stepEnd") }
    func onObjectStepStart(_ event: TelemetryEvent<GenerateObjectStepStartEvent>) async throws { record("objectStepStart") }
    func onObjectStepEnd(_ event: TelemetryEvent<GenerateObjectStepEndEvent>) async throws { record("objectStepEnd") }
    func onEmbedStart(_ event: TelemetryEvent<EmbeddingModelCallStartEvent>) async throws { record("embedStart") }
    func onEmbedEnd(_ event: TelemetryEvent<EmbeddingModelCallEndEvent>) async throws { record("embedEnd") }
    func onEnd(_ event: TelemetryEvent<TelemetryEndEvent>) async throws { record("end") }
    func onError(_ event: TelemetryEvent<TelemetryErrorEvent>) async throws { record("error") }
}

@Suite("Generation contracts")
struct GenerationContractTests {
    private let usage = LanguageModelV4Usage(inputTokens: .init(total: 1), outputTokens: .init(total: 1))

    private func generateResult(_ content: [LanguageModelV4Content], finishReason: LanguageModelV4FinishReason.Unified = .stop) -> LanguageModelV4GenerateResult {
        LanguageModelV4GenerateResult(content: content, finishReason: LanguageModelV4FinishReason(unified: finishReason), usage: usage)
    }

    private func toolCall(_ id: String, _ name: String = "tool") -> LanguageModelV4Content {
        .toolCall(LanguageModelV4ToolCall(toolCallId: id, toolName: name, input: "{}"))
    }

    private func stream(_ parts: [LanguageModelV4StreamPart], finish: Bool = true) -> LanguageModelV4StreamResult {
        LanguageModelV4StreamResult(stream: AsyncThrowingStream { continuation in
            parts.forEach { continuation.yield($0) }
            if finish { continuation.finish() }
        })
    }

    private var objectSchema: FlexibleSchema<JSONValue> {
        FlexibleSchema(jsonSchema(.object(["type": .string("object")])))
    }

    // MARK: - Tool results

    @Test("tool results follow tool call order, not completion order")
    func toolResultsFollowCallOrder() async throws {
        let model = MockLanguageModelV4(doGenerate: .singleValue(generateResult(
            [toolCall("slow"), toolCall("fast")],
            finishReason: .toolCalls
        )))
        let tools: ToolSet = ["tool": tool(
            inputSchema: objectSchema,
            execute: { _, options in
                if options.toolCallId == "slow" { try await Task.sleep(nanoseconds: 50_000_000) }
                return .value(.string(options.toolCallId))
            }
        )]

        let result = try await generateText(model: model, tools: tools, prompt: "go")

        #expect(result.toolResults.map(\.toolCallId) == ["slow", "fast"])
        guard case .tool(let toolMessage)? = result.response.messages.last else {
            Issue.record("Expected a tool message")
            return
        }
        let resultIds = toolMessage.content.compactMap { part -> String? in
            if case .toolResult(let result) = part { return result.toolCallId }
            return nil
        }
        #expect(resultIds == ["slow", "fast"])
    }

    // MARK: - Retries

    @Test("retryable provider errors are retried up to maxRetries; others are thrown at once")
    func retries() async throws {
        func failure(retryable: Bool) -> APICallError {
            APICallError(
                message: "busy",
                url: "https://example.com",
                requestBodyValues: nil,
                statusCode: retryable ? 503 : 400,
                responseHeaders: ["retry-after-ms": "0"],
                isRetryable: retryable
            )
        }
        let attempts = LockedValue(initial: 0)
        let flaky = MockLanguageModelV4(doGenerate: .function { _ in
            let attempt = attempts.withValue { value -> Int in value += 1; return value }
            if attempt == 1 { throw failure(retryable: true) }
            return self.generateResult([.text(LanguageModelV4Text(text: "ok"))])
        })
        let result = try await generateText(model: flaky, prompt: "go", settings: CallSettings(maxRetries: 1))
        #expect(result.text == "ok")
        #expect(flaky.doGenerateCalls.count == 2)

        let rejecting = MockLanguageModelV4(doGenerate: .function { _ in throw failure(retryable: false) })
        await #expect(throws: APICallError.self) {
            try await generateText(model: rejecting, prompt: "go", settings: CallSettings(maxRetries: 2))
        }
        #expect(rejecting.doGenerateCalls.count == 1)
    }

    // MARK: - Timeouts

    @Test("a stream without content within firstChunkMs is aborted with a timeout reason")
    func firstContentTimeout() async throws {
        let model = MockLanguageModelV4(doStream: .singleValue(stream([.streamStart(warnings: [])], finish: false)))
        let result = try streamText(
            model: model,
            prompt: "go",
            settings: CallSettings(timeout: .configuration(firstChunkMs: 20))
        )

        let parts = try await convertReadableStreamToArray(result.fullStream)
        guard case .abort(let reason)? = parts.last else {
            Issue.record("Expected the stream to end with an abort part, got \(String(describing: parts.last))")
            return
        }
        #expect(reason?.contains("First chunk timeout of 20ms exceeded") == true)
    }

    // MARK: - Tool choice

    @Test("a response that violates a forced tool choice is an error")
    func toolChoiceViolations() async throws {
        let tools: ToolSet = [
            "weather": tool(inputSchema: objectSchema),
            "search": tool(inputSchema: objectSchema),
        ]

        let textOnly = MockLanguageModelV4(doGenerate: .singleValue(generateResult([.text(LanguageModelV4Text(text: "no tools"))])))
        let required = await #expect(throws: ToolChoiceViolationError.self) {
            try await generateText(model: textOnly, tools: tools, toolChoice: .required, prompt: "go")
        }
        #expect(required?.toolChoice == .required)

        let wrongTool = MockLanguageModelV4(doGenerate: .singleValue(generateResult([toolCall("c1", "search")], finishReason: .toolCalls)))
        let named = await #expect(throws: ToolChoiceViolationError.self) {
            try await generateText(model: wrongTool, tools: tools, toolChoice: .tool(toolName: "weather"), prompt: "go")
        }
        #expect(named?.toolChoice == .tool(toolName: "weather"))
    }

    // MARK: - Stream errors

    @Test("provider stream errors reach the stream and onError as one normalized error")
    func streamErrorNormalization() async throws {
        let model = MockLanguageModelV4(doStream: .singleValue(stream([
            .streamStart(warnings: []),
            .error(error: .value(.object([
                "type": .string("error"),
                "error": .object(["type": .string("overloaded_error"), "message": .string("Overloaded")]),
            ]))),
        ])))
        let reported = LockedValue<[any Error]>(initial: [])
        let result = try streamText(model: model, prompt: "go", onError: { error in
            reported.withValue { $0.append(error) }
            return nil
        })

        let parts = try await convertReadableStreamToArray(result.fullStream)
        let streamed = parts.compactMap { part -> StreamProviderError? in
            if case .error(let error) = part { return error as? StreamProviderError }
            return nil
        }
        let error = try #require(streamed.first)
        #expect(streamed.count == 1)
        #expect(error.message == "Overloaded")
        #expect(error.type == "overloaded_error")
        #expect(error.statusCode == 503)
        #expect(error.isRetryable)
        #expect((reported.withValue { $0 }.first as? StreamProviderError)?.message == "Overloaded")
    }

    // MARK: - Citations

    @Test("citations on text are kept in generated content and streamed text ends")
    func citations() async throws {
        let citation = LanguageModelV4Citation(
            source: .url(id: "s1", url: "https://example.com", title: "Example", providerMetadata: nil),
            startIndex: 0,
            endIndex: 5,
            citedText: "Hello"
        )

        let generating = MockLanguageModelV4(doGenerate: .singleValue(generateResult([
            .text(LanguageModelV4Text(text: "Hello world", citations: [citation])),
        ])))
        let generated = try await generateText(model: generating, prompt: "go")
        guard case .text(_, let citations, _)? = generated.content.first else {
            Issue.record("Expected text content")
            return
        }
        #expect(citations == [citation])

        let streaming = MockLanguageModelV4(doStream: .singleValue(stream([
            .streamStart(warnings: []),
            .textStart(id: "t", providerMetadata: nil),
            .textDelta(id: "t", delta: "Hello world", providerMetadata: nil),
            .textEnd(id: "t", providerMetadata: nil, citations: [citation]),
            .finish(finishReason: LanguageModelV4FinishReason(unified: .stop), usage: usage, providerMetadata: nil),
        ])))
        let streamed = try streamText(model: streaming, prompt: "go")
        let parts = try await convertReadableStreamToArray(streamed.fullStream)
        let streamedCitations = parts.compactMap { part -> [Citation]? in
            if case .textEnd(_, _, let citations) = part { return citations }
            return nil
        }
        #expect(streamedCitations == [[citation]])
    }

    // MARK: - Telemetry

    @Test("integrations receive text generation events in lifecycle order")
    func textTelemetryOrder() async throws {
        let recorder = EventRecorder()
        let model = MockLanguageModelV4(doGenerate: .array([
            generateResult([toolCall("c1")], finishReason: .toolCalls),
            generateResult([.text(LanguageModelV4Text(text: "done"))]),
        ]))
        let tools: ToolSet = ["tool": tool(inputSchema: objectSchema, execute: { _, _ in .value(.string("ok")) })]

        _ = try await generateText(
            model: model,
            tools: tools,
            prompt: "go",
            stopWhen: [isStepCount(2)],
            telemetry: TelemetryOptions(integrations: [recorder])
        )

        let step: [String] = ["stepStart", "modelCallStart", "modelCallEnd"]
        let toolStep: [String] = step + ["toolStart", "toolEnd", "stepEnd"]
        let finalStep: [String] = step + ["stepEnd", "end"]
        let expected: [String] = ["start:ai.generateText"] + toolStep + finalStep
        #expect(recorder.events == expected)
    }

    @Test("integrations receive object, embedding and error events in order; disabled telemetry receives none")
    func otherOperationsTelemetryOrder() async throws {
        let objectRecorder = EventRecorder()
        let objectModel = MockLanguageModelV4(doGenerate: .singleValue(generateResult([.text(LanguageModelV4Text(text: "{}"))])))
        _ = try await generateObjectNoSchema(
            model: objectModel,
            prompt: "go",
            telemetry: TelemetryOptions(integrations: [objectRecorder])
        )
        #expect(objectRecorder.events == ["start:ai.generateObject", "objectStepStart", "objectStepEnd", "end"])

        let embedRecorder = EventRecorder()
        let embeddingModel = TestEmbeddingModelV4 { _ in EmbeddingModelV4Result(embeddings: [[1, 2]]) }
        _ = try await embed(model: embeddingModel, value: "x", telemetry: TelemetryOptions(integrations: [embedRecorder]))
        #expect(embedRecorder.events == ["start:ai.embed", "embedStart", "embedEnd", "end"])

        let failingRecorder = EventRecorder()
        let failing = MockLanguageModelV4(doGenerate: .function { _ in throw CancellationError() })
        _ = try? await generateObjectNoSchema(
            model: failing,
            prompt: "go",
            telemetry: TelemetryOptions(integrations: [failingRecorder]),
            settings: CallSettings(maxRetries: 0)
        )
        #expect(failingRecorder.events == ["start:ai.generateObject", "objectStepStart", "error"])

        let disabled = EventRecorder()
        _ = try await generateObjectNoSchema(
            model: objectModel,
            prompt: "go",
            telemetry: TelemetryOptions(isEnabled: false, integrations: [disabled])
        )
        #expect(disabled.events.isEmpty)
    }

    // MARK: - Object streaming

    @Test("streamObject without a schema still requests JSON output")
    func schemaLessStreamObjectRequestsJSON() async throws {
        let model = MockLanguageModelV4(doStream: .singleValue(stream([
            .streamStart(warnings: []),
            .textDelta(id: "t", delta: #"{"a":1}"#, providerMetadata: nil),
            .finish(finishReason: LanguageModelV4FinishReason(unified: .stop), usage: usage, providerMetadata: nil),
        ])))

        let result = try streamObjectNoSchema(model: model, prompt: "go")

        #expect(try await result.object == .object(["a": .number(1)]))
        #expect(model.doStreamCalls.first?.responseFormat == .json(schema: nil, name: nil, description: nil))
    }
}
