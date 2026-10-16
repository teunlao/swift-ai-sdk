import Foundation
import Testing
@testable import SwiftAISDK
import AISDKProvider
import AISDKProviderUtils

@Suite("StreamText – approval integration", .serialized)
struct StreamTextApprovalIntegrationTests {
    private func model(toolCallId: String, toolName: String, input: String) -> MockLanguageModelV3 {
        let parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "id-0", modelId: "mock", timestamp: Date(timeIntervalSince1970: 0)),
            .toolCall(LanguageModelV3ToolCall(toolCallId: toolCallId, toolName: toolName, input: input)),
            .finish(
                finishReason: LanguageModelV3FinishReason(unified: .toolCalls),
                usage: LanguageModelV3Usage(inputTokens: .init(total: 1), outputTokens: .init(total: 1)),
                providerMetadata: nil
            )
        ]
        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { continuation in
            parts.forEach { continuation.yield($0) }
            continuation.finish()
        }
        return MockLanguageModelV3(doStream: .singleValue(LanguageModelV3StreamResult(stream: stream)))
    }

    @Test("a tool that needs approval emits an approval request and is not executed")
    func toolNeedingApprovalEmitsRequest() async throws {
        let tools: ToolSet = [
            "search": tool(
                description: "Search",
                inputSchema: FlexibleSchema(jsonSchema(.object([:]))),
                needsApproval: .always,
                execute: { _, _ in .value(.string("should-not-run")) }
            )
        ]

        let result = try streamText(
            model: .v3(model(toolCallId: "c1", toolName: "search", input: #"{"q":"hi"}"#)),
            tools: tools,
            prompt: "hello"
        )

        let chunks = try await result.collectFullStream()
        let request = chunks.compactMap { part -> ToolApprovalRequestOutput? in
            if case .toolApprovalRequest(let request) = part { return request }
            return nil
        }
        #expect(request.map(\.toolCall.toolCallId) == ["c1"])
        #expect(request.first?.isAutomatic != true)
        #expect(!chunks.contains { if case .toolResult = $0 { return true } else { return false } })
    }

    @Test("an automatically approved tool call is executed")
    func approvedToolIsExecuted() async throws {
        let tools: ToolSet = [
            "echo": tool(
                description: "Echo",
                inputSchema: FlexibleSchema(jsonSchema(.object([:]))),
                needsApproval: .always,
                execute: { input, _ in .value(input) }
            )
        ]

        let result = try streamText(
            model: .v3(model(toolCallId: "exec", toolName: "echo", input: #"{"value":1}"#)),
            tools: tools,
            prompt: "hi",
            toolApproval: .perTool(["echo": .status(.approved())])
        )

        let chunks = try await result.collectFullStream()
        #expect(chunks.contains { chunk in
            if case .toolApprovalResponse(let response) = chunk {
                return response.toolCall.toolCallId == "exec" && response.approved
            }
            return false
        })
        #expect(chunks.contains { chunk in
            if case .toolResult(let result) = chunk {
                return result.toolCallId == "exec" && result.preliminary != true
            }
            return false
        })
    }

    @Test("a failing streaming tool emits its preliminary result, then a tool error")
    func failingStreamingToolEmitsToolError() async throws {
        struct ToolStreamFailure: Error {}

        let tools: ToolSet = [
            "streamer": tool(
                description: "Streaming tool",
                inputSchema: FlexibleSchema(jsonSchema(.object([:]))),
                execute: { _, _ in
                    let (stream, continuation) = AsyncThrowingStream<JSONValue, Error>.makeStream()
                    continuation.yield(.string("chunk"))
                    continuation.finish(throwing: ToolStreamFailure())
                    return .stream(stream)
                }
            )
        ]

        let result = try streamText(
            model: .v3(model(toolCallId: "err", toolName: "streamer", input: "{}")),
            tools: tools,
            prompt: "hi"
        )

        let chunks = try await result.collectFullStream()
        let results = chunks.compactMap { chunk -> TypedToolResult? in
            if case .toolResult(let result) = chunk, result.toolCallId == "err" { return result }
            return nil
        }
        #expect(results.map { $0.preliminary == true } == [true])
        #expect(chunks.contains { chunk in
            if case .toolError(let error) = chunk { return error.toolCallId == "err" }
            return false
        })
    }

    @Test("a denied tool call emits tool-output-denied and is not executed")
    func deniedToolIsNotExecuted() async throws {
        let tools: ToolSet = [
            "guard": tool(
                description: "Guard",
                inputSchema: FlexibleSchema(jsonSchema(.object([:]))),
                execute: { _, _ in .value(.string("should-not-run")) }
            )
        ]

        let result = try streamText(
            model: .v3(model(toolCallId: "deny", toolName: "guard", input: "{}")),
            tools: tools,
            prompt: "hi",
            toolApproval: .perTool(["guard": .status(.denied(reason: "not allowed"))])
        )

        let chunks = try await result.collectFullStream()
        #expect(chunks.contains { part in
            if case .toolOutputDenied(let denied) = part { return denied.toolCallId == "deny" }
            return false
        })
        #expect(!chunks.contains { if case .toolResult = $0 { return true } else { return false } })
    }
}
