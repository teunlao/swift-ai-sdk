import Foundation
import Testing
@testable import SwiftAISDK
import AISDKProvider
import AISDKProviderUtils

@Suite("StreamTextV2 – approval resolver")
struct StreamTextV2ApprovalResolverTests {
    @Test("resolver approve executes tool and emits tool-result (V2)")
    func resolverApproveEmitsResult() async throws {
        // Provider: client tool call then finish(toolCalls)
        let call = LanguageModelV3ToolCall(
            toolCallId: "c1",
            toolName: "echo",
            input: "{\"v\":\"OK\"}",
            providerExecuted: false,
            providerMetadata: nil
        )
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "id-0", modelId: "mock", timestamp: Date(timeIntervalSince1970: 0)),
            .toolCall(call),
            .finish(finishReason: .toolCalls, usage: LanguageModelV3Usage(inputTokens: 1, outputTokens: 1, totalTokens: 2), providerMetadata: nil)
        ]
        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { c in
            parts.forEach { c.yield($0) }; c.finish()
        }
        let model = MockLanguageModelV3(doStream: .singleValue(LanguageModelV3StreamResult(stream: stream)))

        // Tool: echo returns value
        let tools: ToolSet = [
            "echo": tool(
                description: "Echo",
                inputSchema: FlexibleSchema(jsonSchema(.object([:]))),
                needsApproval: .always,
                execute: { input, _ in .value(input) }
            )
        ]

        let result: DefaultStreamTextV2Result<JSONValue, JSONValue> = try streamTextV2(
            model: .v3(model),
            prompt: "hi",
            tools: tools,
            experimentalApprove: { _ in .approve }
        )

        let chunks = try await result.collectFullStream()
        // Expect tool-result and no approval-request
        let sawApproval = chunks.contains { if case .toolApprovalRequest = $0 { return true } else { return false } }
        let sawToolResult = chunks.contains { if case .toolResult = $0 { return true } else { return false } }
        #expect(!sawApproval && sawToolResult)
    }

    @Test("resolver approve streams preliminary then final (V2)")
    func resolverApproveStreamsPreliminary() async throws {
        // Provider: client tool call then finish(toolCalls)
        let call = LanguageModelV3ToolCall(
            toolCallId: "c1",
            toolName: "streamer",
            input: "{}",
            providerExecuted: false,
            providerMetadata: nil
        )
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "id-0", modelId: "mock", timestamp: Date(timeIntervalSince1970: 0)),
            .toolCall(call),
            .finish(finishReason: .toolCalls, usage: LanguageModelV3Usage(inputTokens: 1, outputTokens: 1, totalTokens: 2), providerMetadata: nil)
        ]
        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { c in
            parts.forEach { c.yield($0) }; c.finish()
        }
        let model = MockLanguageModelV3(doStream: .singleValue(LanguageModelV3StreamResult(stream: stream)))

        // Tool: emits 3 chunks, then completes
        let streamingTool = tool(
            description: "Streamer",
            inputSchema: FlexibleSchema(jsonSchema(.object([:]))),
            needsApproval: .always,
            execute: { _, _ in
                let (s, cont) = AsyncThrowingStream<JSONValue, Error>.makeStream()
                Task {
                    cont.yield(.string("a"))
                    cont.yield(.string("b"))
                    cont.yield(.string("c"))
                    cont.finish()
                }
                return .stream(s)
            }
        )
        let tools: ToolSet = ["streamer": streamingTool]

        let result: DefaultStreamTextV2Result<JSONValue, JSONValue> = try streamTextV2(
            model: .v3(model),
            prompt: "hi",
            tools: tools,
            experimentalApprove: { _ in .approve }
        )

        let chunks = try await result.collectFullStream()
        // Count preliminary results and ensure final exists
        var prelimCount = 0
        var sawFinal = false
        for part in chunks {
            if case let .toolResult(res) = part {
                switch res {
                case .static(let r):
                    if r.preliminary == true { prelimCount += 1 } else { sawFinal = true }
                case .dynamic(let r):
                    if r.preliminary == true { prelimCount += 1 } else { sawFinal = true }
                }
            }
        }
        #expect(prelimCount == 3)
        #expect(sawFinal)
    }

    @Test("resolver deny emits tool-output-denied (V2)")
    func resolverDenyEmitsDenied() async throws {
        let call = LanguageModelV3ToolCall(
            toolCallId: "c1",
            toolName: "noop",
            input: "{}",
            providerExecuted: false,
            providerMetadata: nil
        )
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "id-0", modelId: "mock", timestamp: Date(timeIntervalSince1970: 0)),
            .toolCall(call),
            .finish(finishReason: .toolCalls, usage: LanguageModelV3Usage(inputTokens: 1, outputTokens: 1, totalTokens: 2), providerMetadata: nil)
        ]
        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { c in
            parts.forEach { c.yield($0) }; c.finish()
        }
        let model = MockLanguageModelV3(doStream: .singleValue(LanguageModelV3StreamResult(stream: stream)))

        let tools: ToolSet = [
            "noop": tool(
                description: "No-op",
                inputSchema: FlexibleSchema(jsonSchema(.object([:]))),
                needsApproval: .always
            )
        ]

        let result: DefaultStreamTextV2Result<JSONValue, JSONValue> = try streamTextV2(
            model: .v3(model),
            prompt: "hi",
            tools: tools,
            experimentalApprove: { _ in .deny }
        )

        let chunks = try await result.collectFullStream()
        let sawDenied = chunks.contains { if case .toolOutputDenied = $0 { return true } else { return false } }
        #expect(sawDenied)
    }
}
