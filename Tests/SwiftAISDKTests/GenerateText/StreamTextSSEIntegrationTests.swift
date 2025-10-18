import Foundation
import Testing
@testable import SwiftAISDK
import AISDKProvider
import AISDKProviderUtils

@Suite("StreamText – SSE stream", .serialized)
struct StreamTextSSEIntegrationTests {
    private func decodeEvents(_ events: [String]) throws -> [NSDictionary] {
        try events.compactMap { line in
            guard line.hasPrefix("data: ") else { return nil }
            let jsonPart = String(line.dropFirst(6))
            let data = Data(jsonPart.utf8)
            let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            return object as? NSDictionary
        }
    }

    @Test("toSSEStream mirrors encoder output")
    func toSSEStreamMatchesEncoder() async throws {
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "id", modelId: "mock", timestamp: Date(timeIntervalSince1970: 0)),
            .textDelta(id: "a", delta: "Hi", providerMetadata: nil),
            .finish(
                finishReason: .stop,
                usage: LanguageModelV3Usage(inputTokens: 1, outputTokens: 1, totalTokens: 2),
                providerMetadata: nil
            )
        ]
        let providerStream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { continuation in
            parts.forEach { continuation.yield($0) }
            continuation.finish()
        }
        let model = MockLanguageModelV3(doStream: .singleValue(LanguageModelV3StreamResult(stream: providerStream)))
        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
            model: .v3(model),
            prompt: "hi"
        )

        let encoder = makeStreamTextSSEStream(from: result.fullStream, includeUsage: true)
        let direct = result.toSSEStream(includeUsage: true)

        let lhs = try await decodeEvents(convertReadableStreamToArray(encoder))
        let rhs = try await decodeEvents(convertReadableStreamToArray(direct))
        #expect(lhs == rhs)
    }

    @Test("SSE omits usage when includeUsage is false")
    func sseOmitsUsageWhenFlagDisabled() async throws {
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .textDelta(id: "t", delta: "Hi", providerMetadata: nil),
            .finish(
                finishReason: .stop,
                usage: LanguageModelV3Usage(inputTokens: 10, outputTokens: 5, totalTokens: 15),
                providerMetadata: nil
            )
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

        let events = try await decodeEvents(convertReadableStreamToArray(result.toSSEStream(includeUsage: false)))
        let finish = try #require(events.first(where: { $0["type"] as? String == "finish" }))
        #expect(finish["usage"] == nil)
    }

    @Test("SSE emits tool events in order")
    func sseEmitsToolEvents() async throws {
        let parts: [TextStreamPart] = [
            .start,
            .toolCall(.static(StaticToolCall(
                toolCallId: "call-1",
                toolName: "demo",
                input: .object(["value": 1]),
                providerExecuted: false,
                providerMetadata: nil
            ))),
            .toolInputStart(id: "call-1", toolName: "demo", providerMetadata: nil, providerExecuted: false, dynamic: nil),
            .toolInputDelta(id: "call-1", delta: "{", providerMetadata: nil),
            .toolInputDelta(id: "call-1", delta: "}", providerMetadata: nil),
            .toolInputEnd(id: "call-1", providerMetadata: nil),
            .toolResult(TypedToolResult.static(StaticToolResult(
                toolCallId: "call-1",
                toolName: "demo",
                input: .null,
                output: .object(["ok": .bool(true)]),
                providerExecuted: false,
                preliminary: false,
                providerMetadata: nil
            ))),
            .finish(finishReason: .stop, totalUsage: LanguageModelUsage())
        ]

        let stream = AsyncThrowingStream<TextStreamPart, Error> { c in
            parts.forEach { c.yield($0) }
            c.finish()
        }
        let encoderEvents = try await decodeEvents(convertReadableStreamToArray(makeStreamTextSSEStream(from: stream)))

        let types = encoderEvents.compactMap { $0["type"] as? String }
        #expect(types.contains("tool-call"))
        #expect(types.contains("tool-input-start"))
        #expect(types.contains("tool-input-delta"))
        #expect(types.contains("tool-input-end"))
        #expect(types.contains("tool-result"))
    }
}
