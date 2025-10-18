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

    @Test("SSE includes providerMetadata for tool-input and tool-error/result")
    func sseIncludesToolMetadataAndFields() async throws {
        let meta: ProviderMetadata = ["prov": ["tag": .string("m")]]
        // Build a stream of low-level TextStreamPart events to feed the encoder directly.
        let parts: [TextStreamPart] = [
            .toolInputStart(id: "c1", toolName: "demo", providerMetadata: meta, providerExecuted: false, dynamic: true),
            .toolInputDelta(id: "c1", delta: "{}", providerMetadata: meta),
            .toolInputEnd(id: "c1", providerMetadata: meta),
            .toolError(.static(StaticToolError(toolCallId: "c1", toolName: "demo", input: .object([:]), error: NSError(domain: "x", code: 1)))),
            .toolResult(.static(StaticToolResult(toolCallId: "c1", toolName: "demo", input: .null, output: .object(["ok": .bool(true)]), providerExecuted: false, preliminary: false, providerMetadata: meta))),
            .finish(finishReason: .stop, totalUsage: LanguageModelUsage())
        ]

        let stream = AsyncThrowingStream<TextStreamPart, Error> { c in
            parts.forEach { c.yield($0) }
            c.finish()
        }

        let events = try await decodeEvents(convertReadableStreamToArray(makeStreamTextSSEStream(from: stream)))
        let inputStart = try #require(events.first(where: { $0["type"] as? String == "tool-input-start" }))
        #expect((inputStart["providerMetadata"] as? NSDictionary)?["prov"] != nil)
        #expect(inputStart["dynamic"] as? Bool == true)

        let inputDelta = try #require(events.first(where: { $0["type"] as? String == "tool-input-delta" }))
        #expect((inputDelta["providerMetadata"] as? NSDictionary)?["prov"] != nil)

        let inputEnd = try #require(events.first(where: { $0["type"] as? String == "tool-input-end" }))
        #expect((inputEnd["providerMetadata"] as? NSDictionary)?["prov"] != nil)

        let toolError = try #require(events.first(where: { $0["type"] as? String == "tool-error" }))
        #expect(toolError["input"] != nil)

        let toolResult = try #require(events.first(where: { $0["type"] as? String == "tool-result" }))
        #expect(toolResult["input"] != nil)
        #expect((toolResult["providerMetadata"] as? NSDictionary)?["prov"] != nil)
    }

    @Test("SSE includes finish-step payload and finish usage when enabled")
    func sseIncludesFinishStepAndUsage() async throws {
        let request = LanguageModelRequestMetadata(body: .object(["prompt": .string("hi")] ))
        let response = LanguageModelResponseMetadata(
            id: "resp",
            timestamp: Date(timeIntervalSince1970: 0),
            modelId: "mock-model",
            headers: ["x-id": "123"]
        )
        let usage = LanguageModelUsage(inputTokens: 2, outputTokens: 4, totalTokens: 6)
        let providerMetadata: ProviderMetadata = ["mock": ["latency": .number(12)]]

        let parts: [TextStreamPart] = [
            .start,
            .startStep(request: request, warnings: []),
            .finishStep(response: response, usage: usage, finishReason: .stop, providerMetadata: providerMetadata),
            .finish(finishReason: .stop, totalUsage: usage)
        ]

        let stream = AsyncThrowingStream<TextStreamPart, Error> { c in
            parts.forEach { c.yield($0) }
            c.finish()
        }

        let events = try await decodeEvents(convertReadableStreamToArray(makeStreamTextSSEStream(from: stream, includeUsage: true)))
        let finishStep = try #require(events.first(where: { $0["type"] as? String == "finish-step" }))
        let resp = try #require(finishStep["response"] as? NSDictionary)
        #expect(resp["id"] as? String == "resp")
        let usageObj = try #require(finishStep["usage"] as? NSDictionary)
        #expect(usageObj["totalTokens"] as? Int == 6)
        let metaObj = try #require(finishStep["providerMetadata"] as? NSDictionary)
        #expect(metaObj["mock"] != nil)

        let finish = try #require(events.first(where: { $0["type"] as? String == "finish" }))
        let total = try #require(finish["usage"] as? NSDictionary)
        #expect(total["outputTokens"] as? Int == 4)
    }

    @Test("SSE includes reasoning start/delta/end with providerMetadata")
    func sseIncludesReasoningBlocks() async throws {
        let meta: ProviderMetadata = ["prov": ["trace": .string("r1")]]
        let parts: [TextStreamPart] = [
            .reasoningStart(id: "r", providerMetadata: meta),
            .reasoningDelta(id: "r", text: "think", providerMetadata: meta),
            .reasoningEnd(id: "r", providerMetadata: meta),
            .finish(finishReason: .stop, totalUsage: LanguageModelUsage())
        ]
        let stream = AsyncThrowingStream<TextStreamPart, Error> { c in
            parts.forEach { c.yield($0) }
            c.finish()
        }

        let events = try await decodeEvents(convertReadableStreamToArray(makeStreamTextSSEStream(from: stream)))
        let start = try #require(events.first(where: { $0["type"] as? String == "reasoning-start" }))
        let delta = try #require(events.first(where: { $0["type"] as? String == "reasoning-delta" }))
        let end = try #require(events.first(where: { $0["type"] as? String == "reasoning-end" }))
        #expect((start["providerMetadata"] as? NSDictionary)?["prov"] != nil)
        #expect(delta["delta"] as? String == "think")
        #expect((end["providerMetadata"] as? NSDictionary)?["prov"] != nil)
    }

    @Test("SSE finish-step response timestamp is ISO8601")
    func sseFinishStepTimestampIso8601() async throws {
        let response = LanguageModelResponseMetadata(
            id: "r",
            timestamp: Date(timeIntervalSince1970: 0),
            modelId: "m",
            headers: nil
        )
        let usage = LanguageModelUsage()
        let parts: [TextStreamPart] = [
            .start,
            .startStep(request: LanguageModelRequestMetadata(body: nil), warnings: []),
            .finishStep(response: response, usage: usage, finishReason: .stop, providerMetadata: nil),
            .finish(finishReason: .stop, totalUsage: usage)
        ]
        let stream = AsyncThrowingStream<TextStreamPart, Error> { c in
            parts.forEach { c.yield($0) }
            c.finish()
        }
        let events = try await decodeEvents(convertReadableStreamToArray(makeStreamTextSSEStream(from: stream)))
        let finishStep = try #require(events.first(where: { $0["type"] as? String == "finish-step" }))
        let resp = try #require(finishStep["response"] as? NSDictionary)
        let ts = try #require(resp["timestamp"] as? String)
        #expect(ts.contains("1970-01-01"))
    }

    @Test("SSE emits abort event")
    func sseEmitsAbort() async throws {
        let stream = AsyncThrowingStream<TextStreamPart, Error> { c in
            c.yield(.abort)
            c.finish()
        }
        let events = try await decodeEvents(convertReadableStreamToArray(makeStreamTextSSEStream(from: stream)))
        let abort = try #require(events.first)
        #expect(abort["type"] as? String == "abort")
    }

    @Test("SSE includes providerMetadata for text blocks")
    func sseIncludesTextProviderMetadata() async throws {
        let meta: ProviderMetadata = ["prov": ["m": .string("x")]]
        let parts: [TextStreamPart] = [
            .textStart(id: "t", providerMetadata: meta),
            .textDelta(id: "t", text: "A", providerMetadata: meta),
            .textEnd(id: "t", providerMetadata: meta),
            .finish(finishReason: .stop, totalUsage: LanguageModelUsage())
        ]
        let stream = AsyncThrowingStream<TextStreamPart, Error> { c in
            parts.forEach { c.yield($0) }
            c.finish()
        }
        let events = try await decodeEvents(convertReadableStreamToArray(makeStreamTextSSEStream(from: stream)))
        let start = try #require(events.first(where: { $0["type"] as? String == "text-start" }))
        let delta = try #require(events.first(where: { $0["type"] as? String == "text-delta" }))
        let end = try #require(events.first(where: { $0["type"] as? String == "text-end" }))
        #expect((start["providerMetadata"] as? NSDictionary)?["prov"] != nil)
        #expect((delta["providerMetadata"] as? NSDictionary)?["prov"] != nil)
        #expect((end["providerMetadata"] as? NSDictionary)?["prov"] != nil)
    }
}
