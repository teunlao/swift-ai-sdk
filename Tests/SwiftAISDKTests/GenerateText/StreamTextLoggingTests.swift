import AISDKProvider
import AISDKProviderUtils
import Foundation
import Testing

@testable import SwiftAISDK

@Suite("StreamText – logging", .serialized)
struct StreamTextLoggingTests {
    private func sampleStream() -> AsyncThrowingStream<TextStreamPart, Error> {
        let usage = LanguageModelV3Usage(inputTokens: 1, outputTokens: 3, totalTokens: 4)
        let parts: [TextStreamPart] = [
            .start,
            .startStep(request: LanguageModelRequestMetadata(body: nil), warnings: []),
            .textDelta(id: "a", text: "Hi", providerMetadata: nil),
            .textEnd(id: "a", providerMetadata: nil),
            .finish(finishReason: .stop, rawFinishReason: nil, totalUsage: usage),
        ]
        return AsyncThrowingStream { continuation in
            for part in parts { continuation.yield(part) }
            continuation.finish()
        }
    }

    @Test("log stream formats lines")
    func logStreamFormatsLines() async throws {
        let stream = sampleStream()
        let logs = try await convertReadableStreamToArray(makeStreamTextLogStream(from: stream))
        #expect(logs.contains { $0.contains("stream:start") })
        #expect(logs.contains { $0.contains("text[a] += Hi") })
        #expect(logs.contains { $0.contains("stream:finish") })
    }

    @Test("log function forwards to callback with timestamps")
    func logFunctionForwardsLines() async throws {
        let stream = sampleStream()
        let (lineStream, continuation) = AsyncStream.makeStream(of: String.self)
        let options = StreamTextLogOptions(
            includeTimestamps: true, clock: { Date(timeIntervalSince1970: 0) })
        try await logStreamTextEvents(from: stream, options: options) { line in
            continuation.yield(line)
        }
        continuation.finish()
        var received: [String] = []
        for await line in lineStream {
            received.append(line)
        }
        #expect(!received.isEmpty)
        #expect(received.first?.contains("0.000") == true)
    }

    @Test("log stream preserves prefix")
    func logStreamPreservesPrefix() async throws {
        let stream = sampleStream()
        let options = StreamTextLogOptions(prefix: "[test]")
        let logs = try await convertReadableStreamToArray(
            makeStreamTextLogStream(from: stream, options: options))
        #expect(logs.allSatisfy { $0.hasPrefix("[test]") })
    }

    @Test("log stream marks preliminary tool results")
    func logStreamMarksPreliminaryToolResults() async throws {
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
	            .toolCall(.static(StaticToolCall(
	                toolCallId: "c1",
	                toolName: "streamer",
	                input: .null,
	                providerExecuted: false,
	                providerMetadata: nil
	            ))),
	            .toolResult(prelim),
	            .toolResult(final),
	            .finish(finishReason: .stop, rawFinishReason: nil, totalUsage: LanguageModelUsage())
	        ]

        let stream = AsyncThrowingStream<TextStreamPart, Error> { continuation in
            parts.forEach { continuation.yield($0) }
            continuation.finish()
        }

        let logs = try await convertReadableStreamToArray(makeStreamTextLogStream(from: stream))
        #expect(logs.contains { $0.contains("tool-result (prelim) streamer [c1]") })
        #expect(logs.contains { $0.contains("tool-result streamer [c1]") && !$0.contains("(prelim)") })
    }

    // @Test("log stream includes tool events")
    // func logStreamIncludesToolEvents() async throws {
    //     // Build a synthetic full stream with tool events
    //     let call = TypedToolCall.dynamic(
    //         DynamicToolCall(
    //             toolCallId: "c1",
    //             toolName: "search",
    //             input: .object(["q": .string("hi")]),
    //             providerExecuted: false,
    //             providerMetadata: nil,
    //             invalid: nil,
    //             error: nil
    //         ))
    //     let toolErr = TypedToolError.dynamic(
    //         DynamicToolError(
    //             toolCallId: "c1",
    //             toolName: "search",
    //             input: .null,
    //             error: NSError(domain: "x", code: 1),
    //             providerExecuted: false
    //         ))
    //     let approval = ToolApprovalRequestOutput(approvalId: "a1", toolCall: call)
    //     let denied = ToolOutputDenied(toolCallId: "c1", toolName: "search")

    //     let parts: [TextStreamPart] = [
    //         .start,
    //         .startStep(request: LanguageModelRequestMetadata(body: nil), warnings: []),
    //         .toolCall(call),
    //         .toolError(toolErr),
    //         .toolApprovalRequest(approval),
    //         .toolOutputDenied(denied),
    //         .finish(finishReason: .stop, totalUsage: LanguageModelUsage()),
    //     ]
    //     let stream = AsyncThrowingStream<TextStreamPart, Error> { c in
    //         parts.forEach { c.yield($0) }
    //         c.finish()
    //     }
    //     let logs = try await convertReadableStreamToArray(makeStreamTextLogStream(from: stream))
    //     #expect(logs.contains { $0.contains("tool-call") })
    //     #expect(logs.contains { $0.contains("tool-error") })
    //     #expect(logs.contains { $0.contains("tool-approval-request") })
    //     #expect(logs.contains { $0.contains("tool-output-denied") })
    // }
}
