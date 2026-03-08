import AISDKProviderUtils
import SwiftAISDK
import Testing
@testable import AISDKProvider
@testable import OpenAIProvider

@Suite("OpenAI chat tool-result crash regression")
struct OpenAIChatToolResultCrashRegressionTests {
    @Test("UI tool result string survives OpenAI chat conversion without crashing")
    func uiToolResultStringSurvivesOpenAIChatConversion() async throws {
        let toolPart = UIToolUIPart(
            toolName: "calculator",
            toolCallId: "call-1",
            state: .outputAvailable,
            input: .object(["expression": .string("2+2")]),
            output: .string("4"),
            rawInput: nil,
            errorText: nil,
            providerExecuted: false,
            callProviderMetadata: ["openai": ["mode": .string("strict")]],
            preliminary: nil,
            approval: nil
        )

        let message = UIMessage(
            id: "assistant-1",
            role: .assistant,
            parts: [
                .text(TextUIPart(text: "Let me calculate that.")),
                .tool(toolPart)
            ]
        )

        let toolSchema = FlexibleSchema(jsonSchema(.object([:])))
        let tool = Tool(description: "Calculator", inputSchema: toolSchema)
        let modelMessages = try convertToModelMessages(
            messages: [message],
            options: ConvertToModelMessagesOptions(tools: ["calculator": tool])
        )
        let prompt = try await convertToLanguageModelPrompt(
            prompt: StandardizedPrompt(system: nil, messages: modelMessages),
            supportedUrls: [:],
            download: nil
        )

        let result = try OpenAIChatMessagesConverter.convert(
            prompt: prompt,
            systemMessageMode: .system
        )

        #expect(result.messages.count == 2)
        guard case .object(let toolMessage)? = result.messages.last else {
            Issue.record("Expected tool message")
            return
        }

        #expect(toolMessage["role"] == .string("tool"))
        #expect(toolMessage["tool_call_id"] == .string("call-1"))
        #expect(toolMessage["content"] == .string("\"4\""))
    }
}
