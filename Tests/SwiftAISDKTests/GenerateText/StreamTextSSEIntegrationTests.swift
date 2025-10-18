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

    @Test("SSE includes start-step request body and warnings")
    func sseIncludesStartStepRequestAndWarnings() async throws {
        let req = LanguageModelRequestMetadata(body: .object(["prompt": .string("hi")]))
        let warn: [CallWarning] = [
            .unsupportedSetting(setting: "temperature", details: "not supported")
        ]
        let parts: [TextStreamPart] = [
            .start,
            .startStep(request: req, warnings: warn),
            .finish(finishReason: .stop, totalUsage: LanguageModelUsage())
        ]
        let stream = AsyncThrowingStream<TextStreamPart, Error> { c in
            parts.forEach { c.yield($0) }
            c.finish()
        }
        let events = try await decodeEvents(convertReadableStreamToArray(makeStreamTextSSEStream(from: stream)))
        let startStep = try #require(events.first(where: { $0["type"] as? String == "start-step" }))
        let request = try #require(startStep["request"] as? NSDictionary)
        let body = try #require(request["body"] as? NSDictionary)
        #expect(body["prompt"] as? String == "hi")
        let warnings = try #require(startStep["warnings"] as? [Any])
        #expect(!warnings.isEmpty)
    }

    @Test("SSE encodes source url/document and file events")
    func sseEncodesSourceAndFile() async throws {
        let urlSource: LanguageModelV3Source = .url(id: "u1", url: "https://example.com", title: "Ex", providerMetadata: ["p": ["k": .string("v")]])
        let docSource: LanguageModelV3Source = .document(id: "d1", mediaType: "text/plain", title: "Doc", filename: "a.txt", providerMetadata: nil)
        let file = DefaultGeneratedFileWithType(data: Data("X".utf8), mediaType: "text/plain")
        let parts: [TextStreamPart] = [
            .source(urlSource),
            .textStart(id: "t", providerMetadata: nil),
            .textEnd(id: "t", providerMetadata: nil),
            .source(docSource),
            .file(file),
            .finish(finishReason: .stop, totalUsage: LanguageModelUsage())
        ]
        let stream = AsyncThrowingStream<TextStreamPart, Error> { c in
            parts.forEach { c.yield($0) }
            c.finish()
        }
        let events = try await decodeEvents(convertReadableStreamToArray(makeStreamTextSSEStream(from: stream)))
        #expect(events.contains { ($0["type"] as? String) == "source" && ($0["sourceType"] as? String) == "url" })
        #expect(events.contains { ($0["type"] as? String) == "source" && ($0["sourceType"] as? String) == "document" })
        #expect(events.contains { ($0["type"] as? String) == "file" && ($0["mediaType"] as? String) == "text/plain" })
    }

    @Test("SSE encodes tool-approval-request details with providerMetadata and dynamic")
    func sseEncodesToolApprovalRequest() async throws {
        // Build a request with dynamic call and provider metadata
        let dynamicCall = DynamicToolCall(
            toolCallId: "dyn-1",
            toolName: "approveMe",
            input: .object(["arg": .string("x")]),
            providerExecuted: false,
            providerMetadata: ["prov": ["k": .string("v")]],
            invalid: nil,
            error: nil
        )
        let approval = ToolApprovalRequestOutput(approvalId: "ap-1", toolCall: .dynamic(dynamicCall))
        let parts: [TextStreamPart] = [
            .toolApprovalRequest(approval),
            .finish(finishReason: .stop, totalUsage: LanguageModelUsage())
        ]
        let stream = AsyncThrowingStream<TextStreamPart, Error> { c in
            parts.forEach { c.yield($0) }
            c.finish()
        }
        let events = try await decodeEvents(convertReadableStreamToArray(makeStreamTextSSEStream(from: stream)))
        let req = try #require(events.first(where: { $0["type"] as? String == "tool-approval-request" }))
        #expect(req["approvalId"] as? String == "ap-1")
        #expect(req["toolCallId"] as? String == "dyn-1")
        #expect(req["toolName"] as? String == "approveMe")
        #expect(req["dynamic"] as? Bool == true)
        let input = try #require(req["input"] as? NSDictionary)
        #expect(input["arg"] as? String == "x")
        let meta = try #require(req["providerMetadata"] as? NSDictionary)
        #expect(meta["prov"] != nil)
    }

    @Test("SSE preserves multi-step order and emits two finish-step before final finish")
    func sseMultiStepOrdering() async throws {
        // Simulate two steps: first finishes with tool-calls, second with stop
        let response1 = LanguageModelResponseMetadata(id: "r1", timestamp: Date(timeIntervalSince1970: 0), modelId: "m1", headers: nil)
        let usage1 = LanguageModelUsage(inputTokens: 1, outputTokens: 1, totalTokens: 2)
        let response2 = LanguageModelResponseMetadata(id: "r2", timestamp: Date(timeIntervalSince1970: 1), modelId: "m2", headers: nil)
        let usage2 = LanguageModelUsage(inputTokens: 2, outputTokens: 3, totalTokens: 5)

        let parts: [TextStreamPart] = [
            .start,
            .startStep(request: LanguageModelRequestMetadata(body: nil), warnings: []),
            .finishStep(response: response1, usage: usage1, finishReason: .toolCalls, providerMetadata: nil),
            .startStep(request: LanguageModelRequestMetadata(body: nil), warnings: []),
            .textStart(id: "t", providerMetadata: nil),
            .textDelta(id: "t", text: "ok", providerMetadata: nil),
            .textEnd(id: "t", providerMetadata: nil),
            .finishStep(response: response2, usage: usage2, finishReason: .stop, providerMetadata: nil),
            .finish(finishReason: .stop, totalUsage: LanguageModelUsage(inputTokens: 3, outputTokens: 4, totalTokens: 7))
        ]
        let stream = AsyncThrowingStream<TextStreamPart, Error> { c in
            parts.forEach { c.yield($0) }
            c.finish()
        }
        let events = try await decodeEvents(convertReadableStreamToArray(makeStreamTextSSEStream(from: stream)))
        let types = events.compactMap { $0["type"] as? String }
        // Expected subsequence
        let expected = ["start", "start-step", "finish-step", "start-step", "text-start", "text-delta", "text-end", "finish-step", "finish"]
        #expect(types == expected)
    }

    @Test("SSE emits end when stream ends without finish/abort")
    func sseEmitsEndWithoutFinish() async throws {
        let stream = AsyncThrowingStream<TextStreamPart, Error> { c in
            c.yield(.textStart(id: "t", providerMetadata: nil))
            c.yield(.textEnd(id: "t", providerMetadata: nil))
            c.finish()
        }
        let lines = try await convertReadableStreamToArray(makeStreamTextSSEStream(from: stream))
        // Last line should be an end event
        #expect(lines.last == "data: {\"type\":\"end\"}\n\n")
    }

    @Test("SSE ignores raw chunks from provider")
    func sseIgnoresRaw() async throws {
        let stream = AsyncThrowingStream<TextStreamPart, Error> { c in
            c.yield(.raw(rawValue: .string("x")))
            c.yield(.finish(finishReason: .stop, totalUsage: LanguageModelUsage()))
            c.finish()
        }
        let lines = try await convertReadableStreamToArray(makeStreamTextSSEStream(from: stream))
        // Only a finish event should appear
        #expect(lines.contains { $0.contains("\"type\":\"finish\"") })
        #expect(!lines.contains { $0.contains("\"type\":\"raw\"") })
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
