import Foundation
import Testing
@testable import SwiftAISDK
import AISDKProvider
import AISDKProviderUtils

@Suite("StreamTextV2 – basic textStream")
struct StreamTextV2BasicTests {
    private let defaultUsage = LanguageModelV3Usage(
        inputTokens: 1,
        outputTokens: 4,
        totalTokens: 5,
        reasoningTokens: nil,
        cachedInputTokens: nil
    )

    @Test("textStream yields raw deltas in order (V2)")
    func textStreamYieldsRawDeltasV2() async throws {
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

        let result: DefaultStreamTextV2Result<JSONValue, JSONValue> = try streamTextV2(
            model: .v3(model),
            prompt: "hello",
            stopWhen: [stopCondition]
        )

        let chunks = try await convertReadableStreamToArray(result.textStream)
        #expect(chunks == ["Hello", " ", "World", "!"])
    }

    @Test("tools convert client tool calls to static variants (V2)")
    func toolsConvertClientToolCallsToStaticV2() async throws {
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

        let result: DefaultStreamTextV2Result<JSONValue, JSONValue> = try streamTextV2(
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
    @Test("toUIMessageStream emits UI chunks in order (V2)")
    func toUIMessageStreamBasicV2() async throws {
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

        let result: DefaultStreamTextV2Result<JSONValue, JSONValue> = try streamTextV2(
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

    @Test("pipeTextStreamToResponse writes plain text (V2)")
    func pipeTextStreamToResponseV2() async throws {
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
        let result: DefaultStreamTextV2Result<JSONValue, JSONValue> = try streamTextV2(
            model: .v3(model),
            prompt: "hello"
        )

        let response = MockStreamTextResponseWriter()
        result.pipeTextStreamToResponse(response, init: TextStreamResponseInit())
        await response.waitForEnd()

        let chunks = response.decodedChunks().joined()
        #expect(chunks.contains("Hello World"))
    }

    @Test("stopWhen stepCountIs(1) yields one step (V2)")
    func stopWhenSingleStepV2() async throws {
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

        let result: DefaultStreamTextV2Result<JSONValue, JSONValue> = try streamTextV2(
            model: .v3(model),
            prompt: "hello",
            stopWhen: [stepCountIs(1)]
        )

        _ = try await convertReadableStreamToArray(result.fullStream)
        let steps = try await result.steps
        #expect(steps.count == 1)
        #expect((try await result.text) == "A")
    }

    @Test("fullStream emits tool input events in order (V2)")
    func fullStreamToolInputOrderV2() async throws {
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

        let result: DefaultStreamTextV2Result<JSONValue, JSONValue> = try streamTextV2(
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

    @Test("fullStream with empty provider emits framing only (V2)")
    func fullStreamEmptyEmitsFramingOnlyV2() async throws {
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

        let result: DefaultStreamTextV2Result<JSONValue, JSONValue> = try streamTextV2(
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

    @Test("transform maps textDelta to uppercased (V2)")
    func transformMapsTextDeltaV2() async throws {
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

        let result: DefaultStreamTextV2Result<JSONValue, JSONValue> = try streamTextV2(
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

    @Test("fullStream emits framing and text events in order (V2)")
    func fullStreamFramingOrderV2() async throws {
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

        let result: DefaultStreamTextV2Result<JSONValue, JSONValue> = try streamTextV2(
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

    @Test("accessors return final values after finish (V2)")
    func accessorsAfterFinishV2() async throws {
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

        let result: DefaultStreamTextV2Result<JSONValue, JSONValue> = try streamTextV2(
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

    @Test("fullStream emits file and source events (V2)")
    func fullStreamFileAndSourceV2() async throws {
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
        let result: DefaultStreamTextV2Result<JSONValue, JSONValue> = try streamTextV2(
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

    @Test("onChunk and onFinish callbacks are invoked (V2)")
    func onChunkAndOnFinishCallbacksV2() async throws {
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

        let result: DefaultStreamTextV2Result<JSONValue, JSONValue> = try streamTextV2(
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
    @Test("tool-calls finish triggers continuation when client outputs provided (V2)")
    func toolCallsFinishTriggersContinuationV2() async throws {
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

        let result: DefaultStreamTextV2Result<JSONValue, JSONValue> = try streamTextV2(
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

    @Test("invalid tool-call JSON marks dynamic call as invalid (V2)")
    func invalidToolCallJsonMarksDynamicV2() async throws {
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

        let result: DefaultStreamTextV2Result<JSONValue, JSONValue> = try streamTextV2(
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

}
