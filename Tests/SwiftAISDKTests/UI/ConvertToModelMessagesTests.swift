import AISDKProviderUtils
import SwiftAISDK
import Testing

@Suite("convertToModelMessages")
struct ConvertToModelMessagesTests {
    @Test("system message merges provider metadata")
    func systemMessageMetadata() throws {
        let message = UIMessage(
            id: "sys-1",
            role: .system,
            parts: [
                .text(TextUIPart(text: "Hello", providerMetadata: ["openai": ["cache": .string("ephemeral")]])),
                .text(TextUIPart(text: " World", providerMetadata: ["openai": ["priority": .string("high")]]))
            ]
        )

        let result = try convertToModelMessages(messages: [message])
        #expect(result.count == 1)

        guard case let .system(systemMessage) = result.first else {
            Issue.record("Expected system message")
            return
        }

        #expect(systemMessage.content == "Hello World")
        #expect(systemMessage.providerOptions?["openai"]?["cache"] == .string("ephemeral"))
        #expect(systemMessage.providerOptions?["openai"]?["priority"] == .string("high"))
    }

    @Test("assistant tool invocations create tool messages")
    func assistantToolConversion() throws {
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
            approval: UIToolApproval(id: "approval-1", approved: true, reason: "ok")
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
        let options = ConvertToModelMessagesOptions(tools: ["calculator": tool])

        let result = try convertToModelMessages(messages: [message], options: options)
        #expect(result.count == 2)

        guard case let .assistant(assistantMessage) = result.first else {
            Issue.record("Expected assistant message")
            return
        }

        guard case let .parts(parts) = assistantMessage.content else {
            Issue.record("Expected assistant parts")
            return
        }

        #expect(parts.count == 3)

        guard case let .toolCall(toolCallPart) = parts.first(where: { part in
            if case .toolCall = part { return true } else { return false }
        }) else {
            Issue.record("Expected tool call part")
            return
        }
        #expect(toolCallPart.toolCallId == "call-1")
        #expect(toolCallPart.toolName == "calculator")
        #expect(toolCallPart.input == .object(["expression": .string("2+2")]))

        guard case let .tool(messageToolContent) = result.last else {
            Issue.record("Expected tool message")
            return
        }

        #expect(messageToolContent.content.count == 2)
        guard case let .toolResult(toolResult) = messageToolContent.content.first(where: { part in
            if case .toolResult = part { return true } else { return false }
        }) else {
            Issue.record("Expected tool result part")
            return
        }
        if case let .json(value) = toolResult.output {
            #expect(value == .string("4"))
        } else {
            Issue.record("Expected JSON output result")
        }

        guard case let .toolApprovalResponse(approvalResponse) = messageToolContent.content.first(where: { part in
            if case .toolApprovalResponse = part { return true } else { return false }
        }) else {
            Issue.record("Expected tool approval response")
            return
        }
        #expect(approvalResponse.approvalId == "approval-1")
        #expect(approvalResponse.approved == true)
    }

    @Test("ignoring incomplete tool calls removes pending inputs")
    func ignoreIncompleteToolCalls() throws {
        let pendingTool = UIToolUIPart(
            toolName: "browser",
            toolCallId: "call-2",
            state: .inputAvailable,
            input: .object(["query": .string("news")]),
            output: nil,
            rawInput: nil,
            errorText: nil,
            providerExecuted: false,
            callProviderMetadata: nil,
            preliminary: nil,
            approval: nil
        )

        let message = UIMessage(
            id: "assistant-2",
            role: .assistant,
            parts: [
                .tool(pendingTool)
            ]
        )

        let withoutFiltering = try convertToModelMessages(messages: [message])
        #expect(withoutFiltering.count == 1)

        guard case let .assistant(assistantMessage) = withoutFiltering.first else {
            Issue.record("Expected assistant message")
            return
        }
        guard case let .parts(parts) = assistantMessage.content else {
            Issue.record("Expected assistant parts")
            return
        }
        #expect(parts.count == 1)

        let filtered = try convertToModelMessages(
            messages: [message],
            options: ConvertToModelMessagesOptions(ignoreIncompleteToolCalls: true)
        )
        #expect(filtered.isEmpty)
    }
}
