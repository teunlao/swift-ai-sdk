
private final class LockedValue<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    init(initial: Value) {
        self.value = initial
    }

    func withValue<R>(_ body: (inout Value) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}

import Foundation
import Testing
@testable import SwiftAISDK
import AISDKProvider
import AISDKProviderUtils

@Suite("StreamText – basic textStream")
struct StreamTextBasicTests {
    private let defaultUsage = LanguageModelV3Usage(
        inputTokens: 1,
        outputTokens: 4,
        totalTokens: 5,
        reasoningTokens: nil,
        cachedInputTokens: nil
    )
    private struct SummaryOutput: Codable, Equatable, Sendable {
        let value: String
    }

    private func summarySchema() -> FlexibleSchema<SummaryOutput> {
        FlexibleSchema(
            Schema(
                jsonSchemaResolver: {
                    .object([
                        "type": .string("object"),
                        "properties": .object([
                            "value": .object(["type": .string("string")])
                        ]),
                        "required": .array([.string("value")]),
                        "additionalProperties": .bool(false)
                    ])
                },
                validator: { value in
                    do {
                        let data: Data
                        if let jsonValue = value as? JSONValue {
                            data = try JSONEncoder().encode(jsonValue)
                        } else if JSONSerialization.isValidJSONObject(value) {
                            data = try JSONSerialization.data(withJSONObject: value, options: [])
                        } else {
                            throw SchemaJSONSerializationError(value: value)
                        }
                        let decoded = try JSONDecoder().decode(SummaryOutput.self, from: data)
                        return .success(value: decoded)
                    } catch let error as SchemaJSONSerializationError {
                        let wrapped = TypeValidationError.wrap(value: value, cause: error)
                        return .failure(error: wrapped)
                    } catch {
                        let wrapped = TypeValidationError.wrap(value: value, cause: error)
                        return .failure(error: wrapped)
                    }
                }
            )
        )
    }



    @Test("textStream yields raw deltas in order")
    func textStreamYieldsRawDeltas() async throws {
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "id-0", modelId: "mock-model-id", timestamp: Date(timeIntervalSince1970: 0)),
            .textStart(id: "1", providerMetadata: nil),
            .textDelta(id: "1", delta: "Hello", providerMetadata: nil),
            .textDelta(id: "1", delta: " ", providerMetadata: nil),
            .textDelta(id: "1", delta: "World", providerMetadata: nil),
            .textDelta(id: "1", delta: "!", providerMetadata: nil),
            .textEnd(id: "1", providerMetadata: nil),
            .finish(
                finishReason: .stop,
                usage: defaultUsage,
                providerMetadata: ["provider": ["key": .string("value")]]
            )
        ]

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { continuation in
            for part in parts { continuation.yield(part) }
            continuation.finish()
        }

        let model = MockLanguageModelV3(
            doStream: .singleValue(LanguageModelV3StreamResult(stream: stream))
        )

        let stopCondition: SwiftAISDK.StopCondition = { steps in
            return steps.count == 3
        }

        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
            model: .v3(model),
            prompt: "hello",
            stopWhen: [stopCondition]
        )

        let chunks = try await convertReadableStreamToArray(result.textStream)
        #expect(chunks == ["Hello", " ", "World", "!"])
    }

    @Test("readAllText concatenates all deltas")
    func readAllTextConcatenates() async throws {
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "id-rat", modelId: "mock-model-id", timestamp: Date(timeIntervalSince1970: 0)),
            .textStart(id: "z", providerMetadata: nil),
            .textDelta(id: "z", delta: "Hi", providerMetadata: nil),
            .textDelta(id: "z", delta: "!", providerMetadata: nil),
            .textEnd(id: "z", providerMetadata: nil),
            .finish(
                finishReason: .stop,
                usage: defaultUsage,
                providerMetadata: nil
            )
        ]

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { c in
            for p in parts { c.yield(p) }
            c.finish()
        }

        let model = MockLanguageModelV3(doStream: .singleValue(LanguageModelV3StreamResult(stream: stream)))
        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
            model: .v3(model),
            prompt: "hello"
        )

        let all = try await result.readAllText()
        #expect(all == "Hi!")
    }

    @Test("fallback response metadata uses internal options when provider omits response metadata")
    func fallbackResponseMetadataUsesInternalOptions() async throws {
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .textStart(id: "step", providerMetadata: nil),
            .textDelta(id: "step", delta: "Fallback", providerMetadata: nil),
            .textEnd(id: "step", providerMetadata: nil),
            .finish(
                finishReason: .stop,
                usage: defaultUsage,
                providerMetadata: nil
            )
        ]

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { continuation in
            for part in parts { continuation.yield(part) }
            continuation.finish()
        }

        let model = MockLanguageModelV3(
            doStream: .singleValue(LanguageModelV3StreamResult(stream: stream))
        )

        let fallbackDate = Date(timeIntervalSince1970: 123)
        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
            model: .v3(model),
            prompt: "hello",
            internalOptions: StreamTextInternalOptions(
                now: { 0 },
                generateId: { "fallback-id" },
                currentDate: { fallbackDate }
            )
        )

        let emitted = try await result.collectFullStream()

        let steps = try await result.steps
        let step = try #require(steps.last)
        #expect(step.response.id == "fallback-id")
        #expect(step.response.timestamp == fallbackDate)
        #expect(step.response.modelId == "mock-model-id")

        if case let .finishStep(response, _, _, _) = emitted.first(where: { part in
            if case .finishStep = part { return true } else { return false }
        }) {
            #expect(response.id == "fallback-id")
            #expect(response.timestamp == fallbackDate)
            #expect(response.modelId == "mock-model-id")
        } else {
            Issue.record("expected finishStep event")
        }
    }


    @Test("telemetry disabled produces no spans")
    func telemetryDisabledProducesNoSpans() async throws {
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "telemetry-id", modelId: "mock-model-id", timestamp: Date(timeIntervalSince1970: 0)),
            .textStart(id: "1", providerMetadata: nil),
            .textDelta(id: "1", delta: "Telemetry", providerMetadata: nil),
            .textEnd(id: "1", providerMetadata: nil),
            .finish(
                finishReason: .stop,
                usage: defaultUsage,
                providerMetadata: nil
            )
        ]

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { continuation in
            for part in parts { continuation.yield(part) }
            continuation.finish()
        }

        let model = MockLanguageModelV3(
            doStream: .singleValue(LanguageModelV3StreamResult(stream: stream))
        )

        let tracer = MockTracer()
        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
            model: .v3(model),
            prompt: "hello",
            experimentalTelemetry: TelemetrySettings(isEnabled: false, tracer: tracer),
            internalOptions: StreamTextInternalOptions(
                now: { 0 },
                generateId: { "disabled-span" },
                currentDate: { Date(timeIntervalSince1970: 123) }
            )
        )

        _ = try await result.readAllText()
        _ = try await result.waitForFinish()

        #expect(tracer.spanRecords.isEmpty)
    }

    @Test("telemetry records first chunk timing")
    func telemetryRecordsFirstChunkTiming() async throws {
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .textDelta(id: "1", delta: "First", providerMetadata: nil),
            .textEnd(id: "1", providerMetadata: nil),
            .finish(
                finishReason: .stop,
                usage: defaultUsage,
                providerMetadata: nil
            )
        ]

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { continuation in
            for part in parts { continuation.yield(part) }
            continuation.finish()
        }

        let model = MockLanguageModelV3(
            doStream: .singleValue(LanguageModelV3StreamResult(stream: stream))
        )

        let tracer = MockTracer()
        let telemetry = TelemetrySettings(isEnabled: true, tracer: tracer)
        let nowValues: [Double] = [0.0, 123.0, 200.0]
        let nowValuesShared = LockedValue(initial: 0)
        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
            model: .v3(model),
            prompt: "hello",
            experimentalTelemetry: telemetry,
            internalOptions: StreamTextInternalOptions(
                now: {
                    let index = nowValuesShared.withValue { value -> Int in
                        let current = value
                        value = min(current + 1, nowValues.count - 1)
                        return current
                    }
                    return nowValues[index]
                },
                generateId: { "firstchunk-span" }
            )
        )

        _ = try await result.readAllText()
        _ = try await result.waitForFinish()

        let doStreamSpan = try #require(tracer.spanRecords.first { $0.name == "ai.streamText.doStream" })
        let firstEvent = try #require(doStreamSpan.events.first { $0.name == "ai.stream.firstChunk" })
        #expect(firstEvent.attributes?["ai.response.msToFirstChunk"] == .double(123.0))
        #expect(doStreamSpan.attributes["ai.response.msToFirstChunk"] == .double(123.0))
    }

    @Test("telemetry records finish timing and speed")
    func telemetryRecordsFinishTiming() async throws {
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .textDelta(id: "1", delta: "Speed", providerMetadata: nil),
            .textEnd(id: "1", providerMetadata: nil),
            .finish(
                finishReason: .stop,
                usage: LanguageModelV3Usage(inputTokens: 1, outputTokens: 4, totalTokens: 5, reasoningTokens: nil, cachedInputTokens: nil),
                providerMetadata: nil
            )
        ]

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { continuation in
            for part in parts { continuation.yield(part) }
            continuation.finish()
        }

        let model = MockLanguageModelV3(
            doStream: .singleValue(LanguageModelV3StreamResult(stream: stream))
        )

        let tracer = MockTracer()
        let telemetry = TelemetrySettings(isEnabled: true, tracer: tracer)
        let nowValues: [Double] = [0.0, 10.0, 210.0]
        let nowValuesShared = LockedValue(initial: 0)
        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
            model: .v3(model),
            prompt: "hello",
            experimentalTelemetry: telemetry,
            internalOptions: StreamTextInternalOptions(
                now: {
                    let index = nowValuesShared.withValue { value -> Int in
                        let current = value
                        value = min(current + 1, nowValues.count - 1)
                        return current
                    }
                    return nowValues[index]
                },
                generateId: { "finish-span" }
            )
        )

        _ = try await result.readAllText()
        _ = try await result.waitForFinish()

        let doStreamSpan = try #require(tracer.spanRecords.first { $0.name == "ai.streamText.doStream" })
        let finishEvent = try #require(doStreamSpan.events.first { $0.name == "ai.stream.finish" })
        #expect(finishEvent.attributes?["ai.response.msToFinish"] == .double(210.0))
        #expect(doStreamSpan.attributes["ai.response.msToFinish"] == .double(210.0))
        #expect(doStreamSpan.attributes["ai.response.avgOutputTokensPerSecond"] == .double(1000.0 * 4.0 / 210.0))
    }

    @Test("telemetry records spans when enabled")
    func telemetryRecordsSpansWhenEnabled() async throws {
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: nil, modelId: nil, timestamp: nil),
            .textStart(id: "1", providerMetadata: nil),
            .textDelta(id: "1", delta: "Hello", providerMetadata: nil),
            .textDelta(id: "1", delta: "!", providerMetadata: nil),
            .textEnd(id: "1", providerMetadata: nil),
            .finish(
                finishReason: .stop,
                usage: defaultUsage,
                providerMetadata: nil
            )
        ]

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { continuation in
            for part in parts { continuation.yield(part) }
            continuation.finish()
        }

        let model = MockLanguageModelV3(
            doStream: .singleValue(LanguageModelV3StreamResult(stream: stream))
        )

        let tracer = MockTracer()
        let fallbackDate = Date(timeIntervalSince1970: 456)
        let telemetry = TelemetrySettings(
            isEnabled: true,
            metadata: ["test-key": .string("value")],
            tracer: tracer
        )

        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
            model: .v3(model),
            prompt: "hello",
            experimentalTelemetry: telemetry,
            internalOptions: StreamTextInternalOptions(
                now: { 0 },
                generateId: { "enabled-span" },
                currentDate: { fallbackDate }
            )
        )

        _ = try await result.readAllText()
        let finish = try await result.waitForFinish()

        #expect(tracer.spanRecords.count >= 2)
        let outerSpan = try #require(tracer.spanRecords.first { $0.name == "ai.streamText" })
        #expect(outerSpan.attributes["ai.response.finishReason"] == .string("stop"))
        #expect(outerSpan.attributes["ai.response.text"] == .string("Hello!"))
        let totalTokens = try #require(defaultUsage.totalTokens)
        #expect(outerSpan.attributes["ai.usage.totalTokens"] == .int(totalTokens))
        #expect(outerSpan.attributes["ai.telemetry.metadata.test-key"] == .string("value"))
        #expect(outerSpan.attributes["ai.operationId"] == .string("ai.streamText"))

        let innerSpan = try #require(tracer.spanRecords.first { $0.name == "ai.streamText.doStream" })
        #expect(innerSpan.attributes["ai.model.provider"] == .string("mock-provider"))
        #expect(innerSpan.attributes["ai.model.id"] == .string("mock-model-id"))

        #expect(finish.totalUsage.totalTokens == defaultUsage.totalTokens)
    }

    @Test("tools convert client tool calls to static variants")
    func toolsConvertClientToolCallsToStatic() async throws {
        // Arrange a simple client-executed tool call with valid JSON input and result.
        let usage = LanguageModelV3Usage(
            inputTokens: 1, outputTokens: 1, totalTokens: 2, reasoningTokens: nil, cachedInputTokens: nil
        )

        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "step-1", modelId: "mock-model-id", timestamp: Date(timeIntervalSince1970: 0)),
            .toolCall(LanguageModelV3ToolCall(
                toolCallId: "call-1",
                toolName: "search",
                input: "{\"q\":\"swift\"}",
                providerExecuted: false,
                providerMetadata: nil
            )),
            .toolResult(LanguageModelV3ToolResult(
                toolCallId: "call-1",
                toolName: "search",
                result: .object(["items": .array([.string("result")])]),
                isError: nil,
                providerExecuted: false,
                preliminary: false,
                providerMetadata: nil
            )),
            .finish(finishReason: .stop, usage: usage, providerMetadata: nil),
        ]

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { c in
            for p in parts { c.yield(p) }
            c.finish()
        }

        let model = MockLanguageModelV3(
            doStream: .singleValue(LanguageModelV3StreamResult(stream: stream))
        )

        // Provide a ToolSet with a matching tool name, so call/result become static.
        let tools: ToolSet = [
            "search": Tool(
                description: "Search tool",
                inputSchema: FlexibleSchema(
                    jsonSchema(
                        .object([
                            "properties": .object([:]),
                            "additionalProperties": .bool(true)
                        ])
                    )
                )
            )
        ]

        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
            model: .v3(model),
            prompt: "hello",
            tools: tools
        )

        // Act: collect full stream to inspect emitted parts and then accessors.
        let partsOut = try await result.collectFullStream()

        // Assert: toolCall and toolResult are static when ToolSet contains the tool.
        let tc = partsOut.first { if case .toolCall = $0 { return true } else { return false } }
        #expect(tc != nil)
        if case let .toolCall(typed)? = tc {
            switch typed {
            case .static(let s):
                #expect(s.toolName == "search")
                #expect(s.dynamic == false)
            default: Issue.record("expected static tool call")
            }
        }

        let tr = partsOut.first { if case .toolResult = $0 { return true } else { return false } }
        #expect(tr != nil)
        if case let .toolResult(typed)? = tr {
            switch typed {
            case .static(let s):
                #expect(s.toolName == "search")
                #expect(s.dynamic == false)
                #expect(s.preliminary != true)
            default: Issue.record("expected static tool result")
            }
        }

        // Accessors reflect static variants as well.
        let step = try await result.steps.last
        #expect((try await result.staticToolCalls).count == 1)
        #expect((try await result.staticToolResults).count == 1)
        #expect(step?.finishReason == .stop)
    }
    @Test("toUIMessageStream emits UI chunks in order")
    func toUIMessageStreamBasic() async throws {
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "id-0", modelId: "mock-model-id", timestamp: Date(timeIntervalSince1970: 0)),
            .textStart(id: "1", providerMetadata: nil),
            .textDelta(id: "1", delta: "Hi", providerMetadata: nil),
            .textEnd(id: "1", providerMetadata: nil),
            .finish(
                finishReason: .stop,
                usage: defaultUsage,
                providerMetadata: nil
            )
        ]

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { continuation in
            for part in parts { continuation.yield(part) }
            continuation.finish()
        }

        let model = MockLanguageModelV3(
            doStream: .singleValue(LanguageModelV3StreamResult(stream: stream))
        )

        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
            model: .v3(model),
            prompt: "hello",
            stopWhen: [stepCountIs(3)]
        )

        let chunks = try await convertReadableStreamToArray(
            result.toUIMessageStream(options: UIMessageStreamOptions<UIMessage>())
        )

        // Expected sequence: start, startStep, textStart, textDelta("Hi"), textEnd, finishStep, finish
        let types = chunks.map { chunk -> String in
            switch chunk {
            case .start: return "start"
            case .startStep: return "startStep"
            case .textStart: return "textStart"
            case .textDelta: return "textDelta"
            case .textEnd: return "textEnd"
            case .finishStep: return "finishStep"
            case .finish: return "finish"
            default: return "other"
            }
        }

        #expect(types == ["start","startStep","textStart","textDelta","textEnd","finishStep","finish"])
    }

    @Test("pipeTextStreamToResponse writes plain text")
    func pipeTextStreamToResponse() async throws {
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "id-0", modelId: "mock-model-id", timestamp: Date(timeIntervalSince1970: 0)),
            .textStart(id: "1", providerMetadata: nil),
            .textDelta(id: "1", delta: "Hello", providerMetadata: nil),
            .textDelta(id: "1", delta: " ", providerMetadata: nil),
            .textDelta(id: "1", delta: "World", providerMetadata: nil),
            .textEnd(id: "1", providerMetadata: nil),
            .finish(
                finishReason: .stop,
                usage: defaultUsage,
                providerMetadata: nil
            )
        ]

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { c in
            for p in parts { c.yield(p) }
            c.finish()
        }

        let model = MockLanguageModelV3(doStream: .singleValue(LanguageModelV3StreamResult(stream: stream)))
        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
            model: .v3(model),
            prompt: "hello"
        )

        let response = MockStreamTextResponseWriter()
        result.pipeTextStreamToResponse(response, init: TextStreamResponseInit())
        await response.waitForEnd()

        let chunks = response.decodedChunks().joined()
        #expect(chunks.contains("Hello World"))
    }

    @Test("stopWhen stepCountIs(1) yields one step")
    func stopWhenSingleStep() async throws {
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "id-1", modelId: "mock", timestamp: Date(timeIntervalSince1970: 0)),
            .textStart(id: "1", providerMetadata: nil),
            .textDelta(id: "1", delta: "A", providerMetadata: nil),
            .textEnd(id: "1", providerMetadata: nil),
            .finish(
                finishReason: .stop,
                usage: defaultUsage,
                providerMetadata: nil
            )
        ]

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { c in
            for p in parts { c.yield(p) }
            c.finish()
        }

        let model = MockLanguageModelV3(
            doStream: .singleValue(LanguageModelV3StreamResult(stream: stream))
        )

        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
            model: .v3(model),
            prompt: "hello",
            stopWhen: [stepCountIs(1)]
        )

        _ = try await convertReadableStreamToArray(result.fullStream)
        let steps = try await result.steps
        #expect(steps.count == 1)
        #expect((try await result.text) == "A")
    }

    @Test("fullStream emits tool input events in order")
    func fullStreamToolInputOrder() async throws {
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "id-0", modelId: "mock-model-id", timestamp: Date(timeIntervalSince1970: 0)),
            .toolInputStart(id: "tool-1", toolName: "search", providerMetadata: nil, providerExecuted: false),
            .toolInputDelta(id: "tool-1", delta: "{\"q\":\"hi\"}", providerMetadata: nil),
            .toolInputEnd(id: "tool-1", providerMetadata: nil),
            .finish(
                finishReason: .stop,
                usage: defaultUsage,
                providerMetadata: nil
            )
        ]

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { continuation in
            for part in parts { continuation.yield(part) }
            continuation.finish()
        }

        let model = MockLanguageModelV3(
            doStream: .singleValue(LanguageModelV3StreamResult(stream: stream))
        )

        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
            model: .v3(model),
            prompt: "hello"
        )

        let chunks = try await convertReadableStreamToArray(result.fullStream)

        func isStart(_ p: TextStreamPart) -> Bool { if case .start = p { return true } else { return false } }
        func isStartStep(_ p: TextStreamPart) -> Bool { if case .startStep = p { return true } else { return false } }
        func isToolStart(_ p: TextStreamPart) -> Bool { if case .toolInputStart = p { return true } else { return false } }
        func toolDelta(_ p: TextStreamPart) -> String? { if case let .toolInputDelta(_, d, _) = p { return d } else { return nil } }
        func isToolEnd(_ p: TextStreamPart) -> Bool { if case .toolInputEnd = p { return true } else { return false } }
        func isFinishStep(_ p: TextStreamPart) -> Bool { if case .finishStep = p { return true } else { return false } }
        func isFinish(_ p: TextStreamPart) -> Bool { if case .finish = p { return true } else { return false } }

        #expect(isStart(chunks[0]))
        #expect(isStartStep(chunks[1]))
        #expect(isToolStart(chunks[2]))
        #expect(toolDelta(chunks[3]) == "{\"q\":\"hi\"}")
        #expect(isToolEnd(chunks[4]))
        #expect(isFinishStep(chunks[5]))
        #expect(isFinish(chunks[6]))
    }

    @Test("fullStream with empty provider emits framing only")
    func fullStreamEmptyEmitsFramingOnly() async throws {
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "id-0", modelId: "mock-model-id", timestamp: Date(timeIntervalSince1970: 0)),
            .finish(
                finishReason: .stop,
                usage: defaultUsage,
                providerMetadata: nil
            )
        ]

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { continuation in
            for part in parts { continuation.yield(part) }
            continuation.finish()
        }

        let model = MockLanguageModelV3(
            doStream: .singleValue(LanguageModelV3StreamResult(stream: stream))
        )

        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
            model: .v3(model),
            prompt: "hello"
        )

        let chunks = try await convertReadableStreamToArray(result.fullStream)

        func isStart(_ p: TextStreamPart) -> Bool { if case .start = p { return true } else { return false } }
        func isStartStep(_ p: TextStreamPart) -> Bool { if case .startStep = p { return true } else { return false } }
        func isFinishStep(_ p: TextStreamPart) -> Bool { if case .finishStep = p { return true } else { return false } }
        func isFinish(_ p: TextStreamPart) -> Bool { if case .finish = p { return true } else { return false } }

        #expect(chunks.count == 4)
        #expect(isStart(chunks[0]))
        #expect(isStartStep(chunks[1]))
        #expect(isFinishStep(chunks[2]))
        #expect(isFinish(chunks[3]))
    }

    @Test("transform maps textDelta to uppercased")
    func transformMapsTextDelta() async throws {
        // Define a simple transform that uppercases textDelta parts
        let uppercaseTransform: StreamTextTransform = { stream, _ in
            let mapped = AsyncThrowingStream<TextStreamPart, Error> { continuation in
                Task {
                    do {
                        for try await part in stream {
                            switch part {
                            case let .textDelta(id, text, meta):
                                continuation.yield(.textDelta(id: id, text: text.uppercased(), providerMetadata: meta))
                            default:
                                continuation.yield(part)
                            }
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
            return createAsyncIterableStream(source: mapped)
        }

        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "id-0", modelId: "mock-model-id", timestamp: Date(timeIntervalSince1970: 0)),
            .textStart(id: "1", providerMetadata: nil),
            .textDelta(id: "1", delta: "Hello", providerMetadata: nil),
            .textDelta(id: "1", delta: " world", providerMetadata: nil),
            .textEnd(id: "1", providerMetadata: nil),
            .finish(
                finishReason: .stop,
                usage: defaultUsage,
                providerMetadata: nil
            )
        ]

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { continuation in
            for part in parts { continuation.yield(part) }
            continuation.finish()
        }

        let model = MockLanguageModelV3(
            doStream: .singleValue(LanguageModelV3StreamResult(stream: stream))
        )

        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
            model: .v3(model),
            prompt: "hello",
            experimentalTransform: [uppercaseTransform]
        )

        let chunks = try await convertReadableStreamToArray(result.fullStream)

        // Extract only textDelta strings
        let deltas = chunks.compactMap { part -> String? in
            if case let .textDelta(_, text, _) = part { return text } else { return nil }
        }

        #expect(deltas == ["HELLO", " WORLD"])
    }

    @Test("fullStream emits framing and text events in order")
    func fullStreamFramingOrder() async throws {
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "id-0", modelId: "mock-model-id", timestamp: Date(timeIntervalSince1970: 0)),
            .textStart(id: "1", providerMetadata: nil),
            .textDelta(id: "1", delta: "Hello", providerMetadata: nil),
            .textDelta(id: "1", delta: " ", providerMetadata: nil),
            .textDelta(id: "1", delta: "World", providerMetadata: nil),
            .textEnd(id: "1", providerMetadata: nil),
            .finish(
                finishReason: .stop,
                usage: defaultUsage,
                providerMetadata: nil
            )
        ]

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { continuation in
            for part in parts { continuation.yield(part) }
            continuation.finish()
        }

        let model = MockLanguageModelV3(
            doStream: .singleValue(LanguageModelV3StreamResult(stream: stream))
        )

        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
            model: .v3(model),
            prompt: "hello"
        )

        let chunks = try await convertReadableStreamToArray(result.fullStream)

        // Validate event ordering; ignore metadata payload equality here.
        func isStart(_ p: TextStreamPart) -> Bool { if case .start = p { return true } else { return false } }
        func isStartStep(_ p: TextStreamPart) -> Bool { if case .startStep = p { return true } else { return false } }
        func isTextStart(_ p: TextStreamPart) -> Bool { if case .textStart = p { return true } else { return false } }
        func isTextDelta(_ p: TextStreamPart, _ s: String) -> Bool {
            if case let .textDelta(_, text, _) = p { return text == s } else { return false }
        }
        func isTextEnd(_ p: TextStreamPart) -> Bool { if case .textEnd = p { return true } else { return false } }
        func isFinishStep(_ p: TextStreamPart) -> Bool { if case .finishStep = p { return true } else { return false } }
        func isFinish(_ p: TextStreamPart) -> Bool { if case .finish = p { return true } else { return false } }

        #expect(chunks.count == 9)

        #expect(isStart(chunks[0]))
        #expect(isStartStep(chunks[1]))
        #expect(isTextStart(chunks[2]))
        #expect(isTextDelta(chunks[3], "Hello"))
        #expect(isTextDelta(chunks[4], " "))
        #expect(isTextDelta(chunks[5], "World"))
        #expect(isTextEnd(chunks[6]))
        #expect(isFinishStep(chunks[7]))
        #expect(isFinish(chunks[8]))
    }

    @Test("accessors return final values after finish")
    func accessorsAfterFinish() async throws {
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "id-xyz", modelId: "mock-model", timestamp: Date(timeIntervalSince1970: 0)),
            .textStart(id: "1", providerMetadata: nil),
            .textDelta(id: "1", delta: "Hi", providerMetadata: nil),
            .textEnd(id: "1", providerMetadata: nil),
            .finish(
                finishReason: .stop,
                usage: defaultUsage,
                providerMetadata: nil
            )
        ]

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { continuation in
            for part in parts { continuation.yield(part) }
            continuation.finish()
        }

        let model = MockLanguageModelV3(
            doStream: .singleValue(LanguageModelV3StreamResult(stream: stream))
        )

        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
            model: .v3(model),
            prompt: "hello"
        )

        // Drain streams to completion, then check properties
        _ = try await convertReadableStreamToArray(result.textStream)

        let text = try await result.text
        let usage = try await result.usage
        let finish = try await result.finishReason

        #expect(text == "Hi")
        #expect(usage.totalTokens == defaultUsage.totalTokens)
        #expect(finish == .stop)
    }

    @Test("fullStream emits file and source events")
    func fullStreamFileAndSource() async throws {
        let data = Data([0x01, 0x02, 0x03])
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "id-0", modelId: "mock-model-id", timestamp: Date(timeIntervalSince1970: 0)),
            .file(LanguageModelV3File(mediaType: "application/octet-stream", data: .binary(data))),
            .source(.url(id: "s1", url: "https://example.com", title: "t", providerMetadata: nil)),
            .finish(
                finishReason: .stop,
                usage: defaultUsage,
                providerMetadata: nil
            )
        ]

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { c in
            for p in parts { c.yield(p) }
            c.finish()
        }

        let model = MockLanguageModelV3(doStream: .singleValue(LanguageModelV3StreamResult(stream: stream)))
        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
            model: .v3(model),
            prompt: "hello"
        )

        let chunks = try await convertReadableStreamToArray(result.fullStream)
        var sawFile = false
        var sawSource = false
        for chunk in chunks {
            switch chunk {
            case .file(let f):
                #expect(f.mediaType == "application/octet-stream")
                #expect(!f.data.isEmpty)
                sawFile = true
            case .source(let src):
                switch src {
                case .url(_, let url, _, _): #expect(url == "https://example.com")
                default: Issue.record("unexpected source type")
                }
                sawSource = true
            default:
                break
            }
        }
        #expect(sawFile && sawSource)
    }

    @Test("onChunk and onFinish callbacks are invoked")
    func onChunkAndOnFinishCallbacks() async throws {
        actor Counter { var n = 0; func inc() { n += 1 }; func get() -> Int { n } }
        actor Flag { var v = false; func set() { v = true }; func get() -> Bool { v } }
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "id-0", modelId: "mock-model-id", timestamp: Date(timeIntervalSince1970: 0)),
            .textStart(id: "1", providerMetadata: nil),
            .textDelta(id: "1", delta: "Hi", providerMetadata: nil),
            .textEnd(id: "1", providerMetadata: nil),
            .finish(
                finishReason: .stop,
                usage: defaultUsage,
                providerMetadata: nil
            )
        ]

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { c in
            for p in parts { c.yield(p) }
            c.finish()
        }
        let model = MockLanguageModelV3(doStream: .singleValue(LanguageModelV3StreamResult(stream: stream)))

        let counter = Counter()
        let finished = Flag()

        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
            model: .v3(model),
            prompt: "hello",
            onChunk: { _ in Task { await counter.inc() } },
            onFinish: { _, _, _, _ in Task { await finished.set() } }
        )

        _ = try await convertReadableStreamToArray(result.fullStream)
        // Accessing finishReason forces finish promises to resolve
        _ = try await result.finishReason
        // Give observer task a tick to deliver onFinish
        await Task.yield(); await Task.yield()
        #expect(await counter.get() > 0)
        #expect(await finished.get())
    }
    @Test("tool-calls finish triggers continuation when client outputs provided")
    func toolCallsFinishTriggersContinuation() async throws {
        let usage = LanguageModelV3Usage(inputTokens: 2, outputTokens: 2, totalTokens: 4, reasoningTokens: nil, cachedInputTokens: nil)

        let stepOneParts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "step-1", modelId: "mock-model-id", timestamp: Date(timeIntervalSince1970: 0)),
            .toolCall(LanguageModelV3ToolCall(
                toolCallId: "call-1",
                toolName: "search",
                input: "{\"q\":\"swift\"}",
                providerExecuted: false,
                providerMetadata: nil
            )),
            .toolResult(LanguageModelV3ToolResult(
                toolCallId: "call-1",
                toolName: "search",
                result: [.string("result")],
                isError: nil,
                providerExecuted: false,
                preliminary: false,
                providerMetadata: nil
            )),
            .finish(finishReason: .toolCalls, usage: usage, providerMetadata: nil)
        ]

        let stepTwoParts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "step-2", modelId: "mock-model-id", timestamp: Date(timeIntervalSince1970: 1)),
            .textStart(id: "t-1", providerMetadata: nil),
            .textDelta(id: "t-1", delta: "Done", providerMetadata: nil),
            .textEnd(id: "t-1", providerMetadata: nil),
            .finish(finishReason: .stop, usage: usage, providerMetadata: nil)
        ]

        let stream1 = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { continuation in
            for part in stepOneParts { continuation.yield(part) }
            continuation.finish()
        }
        let stream2 = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { continuation in
            for part in stepTwoParts { continuation.yield(part) }
            continuation.finish()
        }

        let model = MockLanguageModelV3(
            doStream: .array([
                LanguageModelV3StreamResult(stream: stream1),
                LanguageModelV3StreamResult(stream: stream2)
            ])
        )

        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
            model: .v3(model),
            prompt: "hello",
            stopWhen: [stepCountIs(3)]
        )

        let deltas = try await convertReadableStreamToArray(result.textStream)
        #expect(deltas == ["Done"])

        let steps = try await result.steps
        #expect(steps.count == 2)
        #expect(steps.first?.finishReason == .toolCalls)
        #expect(steps.last?.finishReason == .stop)
        #expect(model.doStreamCalls.count == 2)
        #expect((try await result.finishReason) == .stop)
    }

    @Test("invalid tool-call JSON marks dynamic call as invalid")
    func invalidToolCallJsonMarksDynamic() async throws {
        let usage = LanguageModelV3Usage(inputTokens: 1, outputTokens: 1, totalTokens: 2, reasoningTokens: nil, cachedInputTokens: nil)
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "id-invalid", modelId: "mock-model-id", timestamp: Date(timeIntervalSince1970: 0)),
            .toolCall(LanguageModelV3ToolCall(
                toolCallId: "call-invalid",
                toolName: "search",
                input: "{invalid",
                providerExecuted: false,
                providerMetadata: nil
            )),
            .textStart(id: "t-err", providerMetadata: nil),
            .textDelta(id: "t-err", delta: "partial", providerMetadata: nil),
            .textEnd(id: "t-err", providerMetadata: nil),
            .finish(finishReason: .stop, usage: usage, providerMetadata: nil)
        ]

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { continuation in
            for part in parts { continuation.yield(part) }
            continuation.finish()
        }

        let model = MockLanguageModelV3(
            doStream: .singleValue(LanguageModelV3StreamResult(stream: stream))
        )

        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
            model: .v3(model),
            prompt: "hello"
        )

        let chunks = try await convertReadableStreamToArray(result.fullStream)
        let toolCallPart = chunks.first { part in
            if case .toolCall = part { return true }
            return false
        }
        #expect(toolCallPart != nil)
        if let part = toolCallPart, case let .toolCall(typed) = part {
            switch typed {
            case .dynamic(let dynamicCall):
                #expect(dynamicCall.invalid == true)
                #expect(dynamicCall.error != nil)
            default:
                Issue.record("expected dynamic tool call")
            }
        }
    }

    @Test("experimental_partialOutputStream yields deduplicated partials for text output")
    func experimentalPartialOutputStreamYieldsTextPartials() async throws {
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "partial-id", modelId: "mock-model-id", timestamp: Date(timeIntervalSince1970: 0)),
            .textStart(id: "txt", providerMetadata: nil),
            .textDelta(id: "txt", delta: "He", providerMetadata: nil),
            .textDelta(id: "txt", delta: "ll", providerMetadata: nil),
            .textDelta(id: "txt", delta: "o", providerMetadata: nil),
            .textEnd(id: "txt", providerMetadata: nil),
            .finish(
                finishReason: .stop,
                usage: defaultUsage,
                providerMetadata: nil
            )
        ]

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { continuation in
            for part in parts { continuation.yield(part) }
            continuation.finish()
        }

        let model = MockLanguageModelV3(
            doStream: .singleValue(LanguageModelV3StreamResult(stream: stream))
        )

        let result: DefaultStreamTextResult<String, String> = try streamText(
            model: .v3(model),
            prompt: "hello",
            experimentalOutput: Output.text()
        )

        let partials = try await convertReadableStreamToArray(result.experimentalPartialOutputStream)
        #expect(partials == ["He", "Hell", "Hello"])

        _ = try await result.waitForFinish()
    }

    @Test("experimentalOutput returns parsed object when configured")
    func experimentalOutputReturnsParsedObject() async throws {
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "output-id", modelId: "mock-model-id", timestamp: Date(timeIntervalSince1970: 0)),
            .textStart(id: "txt", providerMetadata: nil),
            .textDelta(id: "txt", delta: "{\"value\":\"", providerMetadata: nil),
            .textDelta(id: "txt", delta: "Hello", providerMetadata: nil),
            .textDelta(id: "txt", delta: "\"}", providerMetadata: nil),
            .textEnd(id: "txt", providerMetadata: nil),
            .finish(
                finishReason: .stop,
                usage: defaultUsage,
                providerMetadata: nil
            )
        ]

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { continuation in
            for part in parts { continuation.yield(part) }
            continuation.finish()
        }

        let model = MockLanguageModelV3(
            doStream: .singleValue(LanguageModelV3StreamResult(stream: stream))
        )

        let result: DefaultStreamTextResult<SummaryOutput, JSONValue> = try streamText(
            model: .v3(model),
            prompt: "hello",
            experimentalOutput: Output.object(schema: summarySchema())
        )

        async let finishTask = result.waitForFinish()
        _ = try await result.collectFullStream()
        let finish = try await finishTask
        #expect(finish.finalStep.text == "{\"value\":\"Hello\"}")
        let output = try await result.experimentalOutput
        #expect(output == SummaryOutput(value: "Hello"))
    }

    @Test("experimentalOutput throws when finish reason is tool-calls")
    func experimentalOutputThrowsOnToolCalls() async throws {
        let usage = LanguageModelV3Usage(inputTokens: 1, outputTokens: 1, totalTokens: 2, reasoningTokens: nil, cachedInputTokens: nil)
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "toolcalls", modelId: "mock-model-id", timestamp: Date(timeIntervalSince1970: 0)),
            .finish(
                finishReason: .toolCalls,
                usage: usage,
                providerMetadata: nil
            )
        ]

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { continuation in
            for part in parts { continuation.yield(part) }
            continuation.finish()
        }

        let model = MockLanguageModelV3(
            doStream: .singleValue(LanguageModelV3StreamResult(stream: stream))
        )

        let result: DefaultStreamTextResult<SummaryOutput, JSONValue> = try streamText(
            model: .v3(model),
            prompt: "hello",
            experimentalOutput: Output.object(schema: summarySchema())
        )

        _ = try await result.collectFullStream()
        await #expect(throws: NoOutputSpecifiedError.self) {
            _ = try await result.experimentalOutput
        }
    }

    @Test("tool input callbacks are invoked before execution")
    func toolInputCallbacksInvoked() async throws {
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "input-available", modelId: "mock-model-id", timestamp: Date(timeIntervalSince1970: 0)),
            .toolCall(LanguageModelV3ToolCall(
                toolCallId: "call-1",
                toolName: "demo",
                input: "{\"value\":1}",
                providerExecuted: false,
                providerMetadata: nil
            )),
            .toolInputStart(id: "call-1", toolName: "demo", providerMetadata: nil, providerExecuted: false),
            .toolInputDelta(id: "call-1", delta: "{\"", providerMetadata: nil),
            .toolInputDelta(id: "call-1", delta: "\"value\":1}", providerMetadata: nil),
            .toolInputEnd(id: "call-1", providerMetadata: nil),
            .finish(
                finishReason: .stop,
                usage: defaultUsage,
                providerMetadata: nil
            )
        ]

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { continuation in
            for part in parts { continuation.yield(part) }
            continuation.finish()
        }

        let model = MockLanguageModelV3(
            doStream: .singleValue(LanguageModelV3StreamResult(stream: stream))
        )

        let startCalls = LockedValue(initial: 0)
        let deltaCalls = LockedValue(initial: [String]())
        let availableInputs = LockedValue(initial: [JSONValue]())
        let executeCalls = LockedValue(initial: 0)

        let tool = Tool(
            description: "Demo tool",
            inputSchema: FlexibleSchema(jsonSchema(.object([:]))),
            needsApproval: .never,
            onInputStart: { _ in
                startCalls.withValue { $0 += 1 }
            },
            onInputDelta: { options in
                deltaCalls.withValue { $0.append(options.inputTextDelta) }
            },
            onInputAvailable: { options in
                availableInputs.withValue { $0.append(options.input) }
            },
            execute: { _, _ in
                executeCalls.withValue { $0 += 1 }
                return .value(.object(["ok": .bool(true)]))
            }
        )

        let tools: ToolSet = ["demo": tool]

        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
            model: .v3(model),
            prompt: "hello",
            tools: tools
        )

        let full = try await result.collectFullStream()
        #expect(startCalls.withValue { $0 } == 1)
        #expect(deltaCalls.withValue { $0 } == ["{\"", "\"value\":1}"])
        #expect(availableInputs.withValue { $0 } == [.object(["value": .number(1)])])
        #expect(executeCalls.withValue { $0 } == 1)

        let hasToolResult = full.contains { part in
            if case .toolResult = part { return true }
            return false
        }
        #expect(hasToolResult)
    }


    @Test("repairToolCall fixes invalid tool input before execution")
    func repairToolCallFixesInvalidInput() async throws {
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "repair", modelId: "mock-model-id", timestamp: Date(timeIntervalSince1970: 0)),
            .toolCall(LanguageModelV3ToolCall(
                toolCallId: "repair-1",
                toolName: "demo",
                input: "{invalid",
                providerExecuted: false,
                providerMetadata: nil
            )),
            .finish(
                finishReason: .stop,
                usage: defaultUsage,
                providerMetadata: nil
            )
        ]

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { continuation in
            for part in parts { continuation.yield(part) }
            continuation.finish()
        }

        let model = MockLanguageModelV3(
            doStream: .singleValue(LanguageModelV3StreamResult(stream: stream))
        )

        let repairCalls = LockedValue(initial: 0)
        let executeCalls = LockedValue(initial: 0)

        let tool = Tool(
            description: "Demo tool",
            inputSchema: FlexibleSchema(jsonSchema(.object([:]))),
            needsApproval: .never,
            execute: { _, _ in
                executeCalls.withValue { $0 += 1 }
                return .value(.object(["ok": .bool(true)]))
            }
        )

        let tools: ToolSet = ["demo": tool]

        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
            model: .v3(model),
            prompt: "hello",
            tools: tools,
            experimentalRepairToolCall: { options in
                repairCalls.withValue { $0 += 1 }
                return LanguageModelV3ToolCall(
                    toolCallId: options.toolCall.toolCallId,
                    toolName: options.toolCall.toolName,
                    input: "{\"value\":42}",
                    providerExecuted: options.toolCall.providerExecuted,
                    providerMetadata: options.toolCall.providerMetadata
                )
            }
        )

        let full = try await result.collectFullStream()
        #expect(repairCalls.withValue { $0 } == 1)
        #expect(executeCalls.withValue { $0 } == 1)

        let hasToolResult = full.contains { part in
            if case .toolResult = part { return true }
            return false
        }
        #expect(hasToolResult)
    }

    @Test("onStepFinish is invoked exactly once per step")
    func onStepFinishInvokedOnce() async throws {
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "step-1", modelId: "mock-model-id", timestamp: Date(timeIntervalSince1970: 0)),
            .textStart(id: "t", providerMetadata: nil),
            .textDelta(id: "t", delta: "x", providerMetadata: nil),
            .textEnd(id: "t", providerMetadata: nil),
            .finish(finishReason: .stop, usage: defaultUsage, providerMetadata: nil)
        ]

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { c in
            parts.forEach { c.yield($0) }
            c.finish()
        }
        let model = MockLanguageModelV3(doStream: .singleValue(LanguageModelV3StreamResult(stream: stream)))

        let calls = LockedValue(initial: 0)
        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
            model: .v3(model),
            prompt: "hi",
            onStepFinish: { _ in calls.withValue { $0 += 1 } }
        )

        _ = try await result.collectFullStream()
        _ = try await result.waitForFinish()

        #expect(calls.withValue { $0 } == 1)
    }

    @Test("onError invoked and onFinish not invoked on provider error")
    func onErrorInvokedOnProviderError() async throws {
        // Provider emits an error part; actor should finish with error, delivering onError
        // and never calling onFinish or onStepFinish.
        let providerStream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { c in
            c.yield(.streamStart(warnings: []))
            c.yield(.error(error: .string("boom")))
            c.finish()
        }
        let model = MockLanguageModelV3(doStream: .singleValue(LanguageModelV3StreamResult(stream: providerStream)))

        let onErrorCalls = LockedValue(initial: 0)
        let onFinishCalls = LockedValue(initial: 0)
        let onStepCalls = LockedValue(initial: 0)

        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
            model: .v3(model),
            prompt: "err",
            onStepFinish: { _ in onStepCalls.withValue { $0 += 1 } },
            onFinish: { _, _, _, _ in onFinishCalls.withValue { $0 += 1 } },
            onError: { _ in onErrorCalls.withValue { $0 += 1 } }
        )

        // Draining fullStream should throw; that's expected.
        await #expect(throws: StreamTextError.self) {
            _ = try await convertReadableStreamToArray(result.fullStream)
        }

        // Promises may still resolve; ensure we don't crash on waitForFinish.
        // If no steps were recorded, waitForFinish will throw NoOutputGeneratedError.
        await #expect(throws: NoOutputGeneratedError.self) {
            _ = try await result.waitForFinish()
        }

        #expect(onErrorCalls.withValue { $0 } == 1)
        #expect(onFinishCalls.withValue { $0 } == 0)
        #expect(onStepCalls.withValue { $0 } == 0)
    }

    @Test("onStepFinish provides correct finishReason and usage")
    func onStepFinishProvidesDetails() async throws {
        let usage = LanguageModelV3Usage(inputTokens: 2, outputTokens: 3, totalTokens: 5, reasoningTokens: nil, cachedInputTokens: nil)
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "rf-1", modelId: "mock-model-id", timestamp: Date(timeIntervalSince1970: 0)),
            .textStart(id: "t", providerMetadata: nil),
            .textDelta(id: "t", delta: "ok", providerMetadata: nil),
            .textEnd(id: "t", providerMetadata: nil),
            .finish(
                finishReason: .stop,
                usage: usage,
                providerMetadata: nil
            )
        ]

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { c in
            parts.forEach { c.yield($0) }
            c.finish()
        }
        let model = MockLanguageModelV3(doStream: .singleValue(LanguageModelV3StreamResult(stream: stream)))

        struct Snapshot: Sendable { var reason: FinishReason?; var usage: LanguageModelUsage? }
        let snap = LockedValue(initial: Snapshot(reason: nil, usage: nil))

        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
            model: .v3(model),
            prompt: "ok",
            onStepFinish: { step in
                snap.withValue { s in
                    s.reason = step.finishReason
                    s.usage = step.usage
                }
            }
        )

        _ = try await result.collectFullStream()
        _ = try await result.waitForFinish()

        let captured = snap.withValue { $0 }
        #expect(captured.reason == .stop)
        #expect(captured.usage?.totalTokens == 5)
    }

    @Test("stop() emits abort before final finish")
    func stopEmitsAbortBeforeFinish() async throws {
        let usage = LanguageModelV3Usage(inputTokens: 1, outputTokens: 1, totalTokens: 2)
        let providerStream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { c in
            c.yield(.streamStart(warnings: []))
            c.yield(.responseMetadata(id: "s", modelId: "m", timestamp: Date(timeIntervalSince1970: 0)))
            c.yield(.textStart(id: "t", providerMetadata: nil))
            // Delay finish so we can call stop() before it arrives
            Task {
                try? await delay(30)
                c.yield(.textEnd(id: "t", providerMetadata: nil))
                c.yield(.finish(finishReason: .stop, usage: usage, providerMetadata: nil))
                c.finish()
            }
        }
        let model = MockLanguageModelV3(doStream: .singleValue(LanguageModelV3StreamResult(stream: providerStream)))
        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
            model: .v3(model),
            prompt: "hi"
        )

        // Request stop immediately; actor should emit abort before session finish.
        result.stop()
        let parts = try await convertReadableStreamToArray(result.fullStream)
        let types = parts.map { part -> String in
            switch part {
            case .start: return "start"
            case .startStep: return "start-step"
            case .finishStep: return "finish-step"
            case .abort: return "abort"
            case .finish: return "finish"
            case .textStart: return "text-start"
            case .textEnd: return "text-end"
            case .textDelta: return "text-delta"
            case .reasoningStart: return "reasoning-start"
            case .reasoningEnd: return "reasoning-end"
            case .reasoningDelta: return "reasoning-delta"
            case .toolInputStart: return "tool-input-start"
            case .toolInputDelta: return "tool-input-delta"
            case .toolInputEnd: return "tool-input-end"
            case .toolCall: return "tool-call"
            case .toolResult: return "tool-result"
            case .toolError: return "tool-error"
            case .toolOutputDenied: return "tool-output-denied"
            case .toolApprovalRequest: return "tool-approval-request"
            case .source: return "source"
            case .file: return "file"
            case .raw: return "raw"
            case .error: return "error"
            }
        }
        // Ensure abort appears before finish in the sequence
        let abortIndex = types.firstIndex(of: "abort")
        let finishIndex = types.firstIndex(of: "finish")
        #expect(abortIndex != nil && finishIndex != nil && abortIndex! < finishIndex!)
    }

    @Test("AsyncIterable wrappers yield same elements as streams")
    func iterableWrappersMatchStreams() async throws {
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .textStart(id: "t", providerMetadata: nil),
            .textDelta(id: "t", delta: "A", providerMetadata: nil),
            .textDelta(id: "t", delta: "B", providerMetadata: nil),
            .textEnd(id: "t", providerMetadata: nil),
            .finish(finishReason: .stop, usage: LanguageModelV3Usage(), providerMetadata: nil)
        ]
        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { c in
            parts.forEach { c.yield($0) }
            c.finish()
        }
        let model = MockLanguageModelV3(doStream: .singleValue(LanguageModelV3StreamResult(stream: stream)))
        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
            model: .v3(model),
            prompt: "hi"
        )

        // Collect via stream and iterable wrappers
        let textChunks = try await convertReadableStreamToArray(result.textStream)
        var iterableText: [String] = []
        var iter = result.textStreamIterable.makeAsyncIterator()
        while let next = try await iter.next() { iterableText.append(next) }
        #expect(textChunks == iterableText)

        let fullChunks = try await convertReadableStreamToArray(result.fullStream)
        var iterableFull: [TextStreamPart] = []
        var iter2 = result.fullStreamIterable.makeAsyncIterator()
        while let next = try await iter2.next() { iterableFull.append(next) }
        #expect(fullChunks == iterableFull)
    }

    @Test("toUIMessageStream respects sendStart/sendFinish flags")
    func uiMessageStreamRespectsFlags() async throws {
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .textStart(id: "t", providerMetadata: nil),
            .textDelta(id: "t", delta: "A", providerMetadata: nil),
            .textEnd(id: "t", providerMetadata: nil),
            .finish(finishReason: .stop, usage: LanguageModelV3Usage(), providerMetadata: nil)
        ]
        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { c in
            parts.forEach { c.yield($0) }
            c.finish()
        }
        let model = MockLanguageModelV3(doStream: .singleValue(LanguageModelV3StreamResult(stream: stream)))

        // sendStart=false, sendFinish=true
        let result1: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
            model: .v3(model),
            prompt: "hi"
        )
        let stream1 = result1.toUIMessageStream(options: UIMessageStreamOptions<UIMessage>(sendFinish: true, sendStart: false))
        let chunks1 = try await convertReadableStreamToArray(stream1)
        let hasStart1 = chunks1.contains { $0.typeIdentifier == "start" }
        let hasFinish1 = chunks1.contains { $0.typeIdentifier == "finish" }
        #expect(!hasStart1 && hasFinish1)

        // sendStart=true, sendFinish=false
        let result2: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
            model: .v3(model),
            prompt: "hi"
        )
        let stream2 = result2.toUIMessageStream(options: UIMessageStreamOptions<UIMessage>(sendFinish: false, sendStart: true))
        let chunks2 = try await convertReadableStreamToArray(stream2)
        let hasStart2 = chunks2.contains { $0.typeIdentifier == "start" }
        let hasFinish2 = chunks2.contains { $0.typeIdentifier == "finish" }
        #expect(hasStart2 && !hasFinish2)
    }

    @Test("toUIMessageStreamResponse respects sendStart/sendFinish flags")
    func uiMessageStreamResponseRespectsFlags() async throws {
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .textStart(id: "t", providerMetadata: nil),
            .textDelta(id: "t", delta: "A", providerMetadata: nil),
            .textEnd(id: "t", providerMetadata: nil),
            .finish(finishReason: .stop, usage: LanguageModelV3Usage(), providerMetadata: nil)
        ]
        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { c in
            parts.forEach { c.yield($0) }
            c.finish()
        }
        let model = MockLanguageModelV3(doStream: .singleValue(LanguageModelV3StreamResult(stream: stream)))
        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
            model: .v3(model),
            prompt: "hi"
        )

        // Case 1: sendStart=false, sendFinish=false
        let response1 = result.toUIMessageStreamResponse(
            options: StreamTextUIResponseOptions<UIMessage>(
                responseInit: UIMessageStreamResponseInit(),
                streamOptions: UIMessageStreamOptions<UIMessage>(sendFinish: false, sendStart: false)
            )
        )
        let lines1 = try await convertReadableStreamToArray(response1.stream)
        #expect(!lines1.contains { $0.contains("\"type\":\"start\"") })
        #expect(!lines1.contains { $0.contains("\"type\":\"finish\"") })

        // Case 2: sendStart=true, sendFinish=false
        let response2 = result.toUIMessageStreamResponse(
            options: StreamTextUIResponseOptions<UIMessage>(
                responseInit: UIMessageStreamResponseInit(),
                streamOptions: UIMessageStreamOptions<UIMessage>(sendFinish: false, sendStart: true)
            )
        )
        let lines2 = try await convertReadableStreamToArray(response2.stream)
        #expect(lines2.contains { $0.contains("\"type\":\"start\"") })
        #expect(!lines2.contains { $0.contains("\"type\":\"finish\"") })
    }

    @Test("onFinish is invoked exactly once")
    func onFinishInvokedExactlyOnce() async throws {
        let usage = LanguageModelV3Usage(inputTokens: 1, outputTokens: 1, totalTokens: 2, reasoningTokens: nil, cachedInputTokens: nil)
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "fin-1", modelId: "mock-model-id", timestamp: Date(timeIntervalSince1970: 0)),
            .textStart(id: "t", providerMetadata: nil),
            .textDelta(id: "t", delta: "ok", providerMetadata: nil),
            .textEnd(id: "t", providerMetadata: nil),
            .finish(finishReason: .stop, usage: usage, providerMetadata: nil)
        ]

        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { c in
            parts.forEach { c.yield($0) }
            c.finish()
        }
        let model = MockLanguageModelV3(doStream: .singleValue(LanguageModelV3StreamResult(stream: stream)))

        let calls = LockedValue(initial: 0)
        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
            model: .v3(model),
            prompt: "hi",
            onFinish: { _, _, _, _ in calls.withValue { $0 += 1 } }
        )

        _ = try await result.collectFullStream()
        _ = try await result.waitForFinish()
        #expect(calls.withValue { $0 } == 1)
    }

}
