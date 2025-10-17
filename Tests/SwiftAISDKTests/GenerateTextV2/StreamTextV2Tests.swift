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

        #expect(chunks.count == 8) // start, startStep, textStart, 3 deltas, textEnd, finishStep, finish → actually 9; but finishStep+finish makes 2, so total 9
        // Adjust count assertion to actual events (9)
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
