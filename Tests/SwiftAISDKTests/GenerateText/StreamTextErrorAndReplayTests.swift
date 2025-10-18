import Foundation
import Testing
@testable import SwiftAISDK
import AISDKProvider
import AISDKProviderUtils

@Suite("StreamText – error & replay")
struct StreamTextErrorAndReplayTests {
    private let defaultUsage = LanguageModelV3Usage(
        inputTokens: 1,
        outputTokens: 2,
        totalTokens: 3,
        reasoningTokens: nil,
        cachedInputTokens: nil
    )

    @Test("provider error terminates with error and no finish")
    func providerErrorTerminates() async throws {
        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { c in
            c.yield(.streamStart(warnings: []))
            c.yield(.responseMetadata(id: "id-0", modelId: "mock", timestamp: Date(timeIntervalSince1970: 0)))
            c.yield(.textStart(id: "A", providerMetadata: nil))
            c.yield(.textDelta(id: "A", delta: "X", providerMetadata: nil))
            c.yield(.error(error: .string("boom")))
            c.finish()
        }
        let model = MockLanguageModelV3(doStream: .singleValue(LanguageModelV3StreamResult(stream: stream)))
        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(model: .v3(model), prompt: "hi")

        var gotError = false
        do {
            _ = try await result.collectFullStream()
        } catch { gotError = true }
        #expect(gotError)
    }

    @Test("late subscriber gets replay and terminal")
    func lateSubscriberGetsReplay() async throws {
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "id-0", modelId: "mock", timestamp: Date(timeIntervalSince1970: 0)),
            .textStart(id: "A", providerMetadata: nil),
            .textDelta(id: "A", delta: "X", providerMetadata: nil),
            .textEnd(id: "A", providerMetadata: nil),
            .finish(finishReason: .stop, usage: defaultUsage, providerMetadata: nil)
        ]
        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { c in
            for p in parts { c.yield(p) }
            c.finish()
        }
        let model = MockLanguageModelV3(doStream: .singleValue(LanguageModelV3StreamResult(stream: stream)))
        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(model: .v3(model), prompt: "hi")

        // Drain fully first
        _ = try await result.collectFullStream()
        // Late subscribe
        let replay = try await result.collectFullStream()
        // Expect full framing present
        let hasStart = replay.contains { if case .start = $0 { return true } else { return false } }
       let hasFinish = replay.contains { if case .finish = $0 { return true } else { return false } }
        #expect(hasStart && hasFinish)
    }

    @Test("consumeStream routes errors to handler")
    func consumeStreamRoutesErrors() async throws {
        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { c in
            c.yield(.streamStart(warnings: []))
            c.yield(.responseMetadata(id: "id-err", modelId: "mock", timestamp: Date(timeIntervalSince1970: 0)))
            c.yield(.error(error: .string("boom")))
            c.finish()
        }
        let model = MockLanguageModelV3(doStream: .singleValue(LanguageModelV3StreamResult(stream: stream)))
        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(model: .v3(model), prompt: "hi")

        let (errorStream, continuation) = AsyncStream.makeStream(of: Error.self)
        await result.consumeStream(options: ConsumeStreamOptions(onError: { error in
            continuation.yield(error)
            continuation.finish()
        }))
        continuation.finish()
        var iterator = errorStream.makeAsyncIterator()
        let captured = await iterator.next()
        #expect(captured != nil)
    }

    @Test("pipeTextStreamToResponse writes plain text")
    func pipeTextStreamToResponseWritesPlainText() async throws {
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "id-1", modelId: "mock", timestamp: Date(timeIntervalSince1970: 0)),
            .textStart(id: "A", providerMetadata: nil),
            .textDelta(id: "A", delta: "Hello", providerMetadata: nil),
            .textEnd(id: "A", providerMetadata: nil),
            .finish(finishReason: .stop, usage: defaultUsage, providerMetadata: nil)
        ]
        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { c in
            for part in parts { c.yield(part) }
            c.finish()
        }
        let model = MockLanguageModelV3(doStream: .singleValue(LanguageModelV3StreamResult(stream: stream)))
        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(model: .v3(model), prompt: "hi")

        let writer = MockStreamTextResponseWriter()
        let initOptions = TextStreamResponseInit(headers: ["X-Test": "1"], status: 202, statusText: "Accepted")
        result.pipeTextStreamToResponse(writer, init: initOptions)
        await writer.waitForEnd()

        #expect(writer.statusCode == 202)
        #expect(writer.statusMessage == "Accepted")
        #expect(writer.headers["x-test"] == "1")
        #expect(writer.decodedChunks().joined() == "Hello")
    }

    @Test("toTextStreamResponse exposes stream")
    func toTextStreamResponseExposesStream() async throws {
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "id-2", modelId: "mock", timestamp: Date(timeIntervalSince1970: 0)),
            .textStart(id: "A", providerMetadata: nil),
            .textDelta(id: "A", delta: "Hi", providerMetadata: nil),
            .textEnd(id: "A", providerMetadata: nil),
            .finish(finishReason: .stop, usage: defaultUsage, providerMetadata: nil)
        ]
        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { c in
            for part in parts { c.yield(part) }
            c.finish()
        }
        let model = MockLanguageModelV3(doStream: .singleValue(LanguageModelV3StreamResult(stream: stream)))
        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(model: .v3(model), prompt: "hi")

        let response = result.toTextStreamResponse(init: TextStreamResponseInit(status: 201, statusText: "Created"))
        let textChunks = try await convertReadableStreamToArray(response.stream)
        #expect(textChunks == ["Hi"])
        #expect(response.initOptions?.status == 201)
        #expect(response.initOptions?.statusText == "Created")
    }
}

@Suite("StreamText – SSE encoding")
struct StreamTextSSEEncodingTests {
    private let defaultUsage = LanguageModelV3Usage(
        inputTokens: 1,
        outputTokens: 2,
        totalTokens: 3,
        reasoningTokens: nil,
        cachedInputTokens: nil
    )

    @Test("SSE encoder emits text and finish events")
    func sseEncoderEmitsTextAndFinish() async throws {
        let parts: [TextStreamPart] = [
            .start,
            .startStep(request: LanguageModelRequestMetadata(body: nil), warnings: []),
            .textStart(id: "A", providerMetadata: nil),
            .textDelta(id: "A", text: "Hello", providerMetadata: nil),
            .textEnd(id: "A", providerMetadata: nil),
            .finish(finishReason: .stop, totalUsage: defaultUsage)
        ]
        let stream = AsyncThrowingStream<TextStreamPart, Error> { c in
            for part in parts { c.yield(part) }
            c.finish()
        }

        let sseStream = makeStreamTextSSEStream(from: stream, includeUsage: true)
        var payloads: [String] = []
        for try await payload in sseStream { payloads.append(payload) }

        #expect(payloads.contains(where: { $0.contains("\"type\":\"text-delta\"") && $0.contains("Hello") }))
        #expect(payloads.contains(where: { $0.contains("\"type\":\"finish\"") && $0.contains("\"totalTokens\":3") }))
    }

    @Test("SSE encoder omits usage when disabled")
    func sseEncoderOmitsUsageWhenDisabled() async throws {
        let parts: [TextStreamPart] = [
            .start,
            .finish(finishReason: .stop, totalUsage: defaultUsage)
        ]
        let stream = AsyncThrowingStream<TextStreamPart, Error> { c in
            for part in parts { c.yield(part) }
            c.finish()
        }

        let sseStream = makeStreamTextSSEStream(from: stream, includeUsage: false)
        var payloads: [String] = []
        for try await payload in sseStream { payloads.append(payload) }
        #expect(!payloads.contains(where: { $0.contains("\"usage\"") }))
    }

    @Test("SSE encoder emits tool events (error/approval/denied)")
    func sseEncoderEmitsToolEvents() async throws {
        let call = TypedToolCall.dynamic(DynamicToolCall(
            toolCallId: "c1",
            toolName: "search",
            input: .object(["q": .string("hi")]),
            providerExecuted: false,
            providerMetadata: nil,
            invalid: nil,
            error: nil
        ))
        let toolErr = TypedToolError.dynamic(DynamicToolError(
            toolCallId: "c1",
            toolName: "search",
            input: .null,
            error: NSError(domain: "x", code: 1),
            providerExecuted: false
        ))
        let approval = ToolApprovalRequestOutput(approvalId: "a1", toolCall: call)
        let denied = ToolOutputDenied(toolCallId: "c1", toolName: "search")

        let parts: [TextStreamPart] = [
            .start,
            .startStep(request: LanguageModelRequestMetadata(body: nil), warnings: []),
            .toolError(toolErr),
            .toolApprovalRequest(approval),
            .toolOutputDenied(denied),
            .finish(finishReason: .stop, totalUsage: defaultUsage)
        ]
        let stream = AsyncThrowingStream<TextStreamPart, Error> { c in
            parts.forEach { c.yield($0) }
            c.finish()
        }
        let sse = makeStreamTextSSEStream(from: stream)
        let lines = try await convertReadableStreamToArray(sse)
        #expect(lines.contains { $0.contains("\"type\":\"tool-error\"") })
        #expect(lines.contains { $0.contains("\"type\":\"tool-approval-request\"") })
        #expect(lines.contains { $0.contains("\"type\":\"tool-output-denied\"") })
    }

    @Test("SSE encoder marks preliminary tool results")
    func sseEncoderMarksPreliminaryResults() async throws {
        let prelim = TypedToolResult.static(StaticToolResult(
            toolCallId: "c1",
            toolName: "streamer",
            input: .null,
            output: .string("chunk"),
            providerExecuted: false,
            preliminary: true
        ))
        let final = TypedToolResult.static(StaticToolResult(
            toolCallId: "c1",
            toolName: "streamer",
            input: .null,
            output: .string("done"),
            providerExecuted: false,
            preliminary: false
        ))

        let parts: [TextStreamPart] = [
            .start,
            .startStep(request: LanguageModelRequestMetadata(body: nil), warnings: []),
            .toolResult(prelim),
            .toolResult(final),
            .finish(finishReason: .stop, totalUsage: defaultUsage)
        ]

        let stream = AsyncThrowingStream<TextStreamPart, Error> { continuation in
            parts.forEach { continuation.yield($0) }
            continuation.finish()
        }

        let lines = try await convertReadableStreamToArray(makeStreamTextSSEStream(from: stream))
        #expect(lines.contains { $0.contains("\"type\":\"tool-result\"") && $0.contains("\"preliminary\":true") })
        #expect(lines.contains { $0.contains("\"type\":\"tool-result\"") && $0.contains("\"preliminary\":false") })
    }
}
