import Foundation
import Testing
@testable import SwiftAISDK
import AISDKProvider
import AISDKProviderUtils

@Suite("StreamTextV2 – approval integration", .serialized)
struct StreamTextV2ApprovalIntegrationTests {
    @Test("fullStream injects approval request when tool requires approval (V2)")
    func fullStreamInjectsApproval() async throws {
        // Provider stream emits a client tool call, then finishes step.
        let call = LanguageModelV3ToolCall(
            toolCallId: "c1",
            toolName: "search",
            input: "{\"q\":\"hi\"}",
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
            parts.forEach { c.yield($0) }
            c.finish()
        }
        let model = MockLanguageModelV3(doStream: .singleValue(LanguageModelV3StreamResult(stream: stream)))

        // ToolSet requires approval.
        let tools: ToolSet = [
            "search": tool(
                description: "Search",
                inputSchema: FlexibleSchema(jsonSchema(.object([:]))),
                needsApproval: .always
            )
        ]

        let result: DefaultStreamTextV2Result<JSONValue, JSONValue> = try streamTextV2(
            model: .v3(model),
            prompt: "hello",
            tools: tools
        )

        let chunks = try await result.collectFullStream()
        // Expect that approval request is injected before finishStep/finish.
        var sawApproval = false
        var sawFinish = false
        for part in chunks {
            switch part {
            case .toolApprovalRequest:
                sawApproval = true
            case .finishStep, .finish:
                if sawApproval { sawFinish = true }
            default: break
            }
        }
        #expect(sawApproval && sawFinish)
    }
}
