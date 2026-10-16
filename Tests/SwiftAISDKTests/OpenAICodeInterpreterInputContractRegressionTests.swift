import Testing
import AISDKProvider
@testable import SwiftAISDK
@testable import OpenAIProvider

@Suite("OpenAI code interpreter input contract regression")
struct OpenAICodeInterpreterInputContractRegressionTests {
    @Test("parseToolCall accepts upstream-normalized containerId payload")
    func parseToolCallAcceptsUpstreamNormalizedContainerIdPayload() async throws {
        let tools: ToolSet = [
            "code_interpreter": openaiTools.codeInterpreter()
        ]

        let result = try await parseToolCall(
            toolCall: LanguageModelV4ToolCall(
                toolCallId: "ci_1",
                toolName: "code_interpreter",
                input: #"{"code":"print(\"hi\")","containerId":"cntr_test"}"#,
                providerExecuted: true
            ),
            tools: tools,
            repairToolCall: nil,
            instructions: nil,
            messages: []
        )

        guard case .static(let toolCall) = result else {
            Issue.record("Expected a valid provider tool call, got \(result)")
            return
        }

        #expect(toolCall.providerExecuted == true)
        #expect(toolCall.input == .object([
            "code": .string(#"print("hi")"#),
            "containerId": .string("cntr_test")
        ]))
    }
}
