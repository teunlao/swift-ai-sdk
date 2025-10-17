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

        let result: DefaultStreamTextV2Result<JSONValue, JSONValue> = try streamTextV2(
            model: .v3(model),
            prompt: "hello"
        )

        let chunks = try await convertReadableStreamToArray(result.textStream)
        #expect(chunks == ["Hello", " ", "World", "!"])
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
}
