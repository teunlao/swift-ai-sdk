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
        #expect(toolResult.providerOptions?["openai"]?["mode"] == .string("strict"))
        if case let .json(value: value, providerOptions: _) = toolResult.output {
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
        #expect(approvalResponse.providerExecuted == false)
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

    @Test("provider-executed tool results prefer result provider metadata")
    func providerExecutedToolResultsPreferResultProviderMetadata() throws {
        let toolPart = UIToolUIPart(
            toolName: "calculator",
            toolCallId: "call-3",
            state: .outputAvailable,
            input: .object([
                "operation": .string("multiply"),
                "numbers": .array([.number(3), .number(4)])
            ]),
            output: .string("12"),
            rawInput: nil,
            errorText: nil,
            providerExecuted: true,
            callProviderMetadata: ["testProvider": ["itemId": .string("call-item")]],
            resultProviderMetadata: ["testProvider": ["itemId": .string("result-item")]],
            preliminary: nil,
            approval: nil
        )

        let message = UIMessage(
            id: "assistant-3",
            role: .assistant,
            parts: [
                .stepStart,
                .tool(toolPart)
            ]
        )

        let result = try convertToModelMessages(messages: [message])
        #expect(result.count == 1)

        guard case let .assistant(assistantMessage) = result.first else {
            Issue.record("Expected assistant message")
            return
        }

        guard case let .parts(parts) = assistantMessage.content else {
            Issue.record("Expected assistant parts")
            return
        }

        #expect(parts.count == 2)

        guard case let .toolCall(toolCallPart) = parts.first else {
            Issue.record("Expected tool call part")
            return
        }

        #expect(toolCallPart.providerOptions?["testProvider"]?["itemId"] == .string("call-item"))

        guard case let .toolResult(toolResultPart) = parts.last else {
            Issue.record("Expected tool result part")
            return
        }

        #expect(toolResultPart.providerOptions?["testProvider"]?["itemId"] == .string("result-item"))
    }

    @Test("client-executed dynamic tool results stay in tool messages with provider metadata")
    func clientExecutedDynamicToolResultsStayInToolMessages() throws {
        let metadata: ProviderMetadata = [
            "testProvider": ["itemId": .string("call-item")]
        ]

        let dynamicPart = UIDynamicToolUIPart(
            toolName: "screenshot",
            toolCallId: "call-4",
            state: .outputAvailable,
            input: .object(["value": .string("value-1")]),
            output: .string("result-1"),
            errorText: nil,
            providerExecuted: false,
            callProviderMetadata: metadata,
            preliminary: nil,
            approval: nil
        )

        let message = UIMessage(
            id: "assistant-4",
            role: .assistant,
            parts: [
                .stepStart,
                .dynamicTool(dynamicPart)
            ]
        )

        let result = try convertToModelMessages(messages: [message])
        #expect(result.count == 2)

        guard case let .assistant(assistantMessage) = result.first else {
            Issue.record("Expected assistant message")
            return
        }

        guard case let .parts(assistantParts) = assistantMessage.content else {
            Issue.record("Expected assistant parts")
            return
        }

        #expect(assistantParts.count == 1)

        guard case let .toolCall(toolCallPart) = assistantParts.first else {
            Issue.record("Expected dynamic tool call part")
            return
        }

        #expect(toolCallPart.providerExecuted == false)
        #expect(toolCallPart.providerOptions?["testProvider"]?["itemId"] == .string("call-item"))

        guard case let .tool(toolMessage) = result.last else {
            Issue.record("Expected tool message")
            return
        }

        guard case let .toolResult(toolResultPart) = toolMessage.content.first else {
            Issue.record("Expected tool result part")
            return
        }

        #expect(toolResultPart.providerOptions?["testProvider"]?["itemId"] == .string("call-item"))
    }

    @Test("provider-executed dynamic tool results stay in assistant message")
    func providerExecutedDynamicToolResultsStayInAssistantMessage() throws {
        let callMetadata: ProviderMetadata = [
            "testProvider": ["itemId": .string("call-item")]
        ]
        let resultMetadata: ProviderMetadata = [
            "testProvider": ["itemId": .string("result-item")]
        ]

        let dynamicPart = UIDynamicToolUIPart(
            toolName: "screenshot",
            toolCallId: "call-5",
            state: .outputAvailable,
            input: .object(["value": .string("value-1")]),
            output: .string("result-1"),
            errorText: nil,
            providerExecuted: true,
            callProviderMetadata: callMetadata,
            resultProviderMetadata: resultMetadata,
            preliminary: nil,
            approval: nil
        )

        let message = UIMessage(
            id: "assistant-5",
            role: .assistant,
            parts: [
                .stepStart,
                .dynamicTool(dynamicPart)
            ]
        )

        let result = try convertToModelMessages(messages: [message])
        #expect(result.count == 1)

        guard case let .assistant(assistantMessage) = result.first else {
            Issue.record("Expected assistant message")
            return
        }

        guard case let .parts(parts) = assistantMessage.content else {
            Issue.record("Expected assistant parts")
            return
        }

        #expect(parts.count == 2)

        guard case let .toolCall(toolCallPart) = parts.first else {
            Issue.record("Expected tool call part")
            return
        }

        #expect(toolCallPart.providerExecuted == true)
        #expect(toolCallPart.providerOptions?["testProvider"]?["itemId"] == .string("call-item"))

        guard case let .toolResult(toolResultPart) = parts.last else {
            Issue.record("Expected tool result part")
            return
        }

        #expect(toolResultPart.providerOptions?["testProvider"]?["itemId"] == .string("result-item"))
    }

    @Test("dynamic approval responses include providerExecuted in tool messages")
    func dynamicApprovalResponsesIncludeProviderExecuted() throws {
        let dynamicPart = UIDynamicToolUIPart(
            toolName: "weather",
            toolCallId: "call-6",
            state: .approvalResponded,
            input: .object(["city": .string("Tokyo")]),
            output: nil,
            errorText: nil,
            providerExecuted: false,
            callProviderMetadata: nil,
            preliminary: nil,
            approval: UIToolApproval(id: "approval-1", approved: true, reason: nil)
        )

        let message = UIMessage(
            id: "assistant-6",
            role: .assistant,
            parts: [
                .stepStart,
                .dynamicTool(dynamicPart)
            ]
        )

        let result = try convertToModelMessages(messages: [message])
        #expect(result.count == 2)

        guard case let .assistant(assistantMessage) = result.first else {
            Issue.record("Expected assistant message")
            return
        }

        guard case let .parts(assistantParts) = assistantMessage.content else {
            Issue.record("Expected assistant parts")
            return
        }

        #expect(assistantParts.count == 2)

        guard case let .toolApprovalRequest(approvalRequest) = assistantParts.last else {
            Issue.record("Expected tool approval request")
            return
        }

        #expect(approvalRequest.approvalId == "approval-1")

        guard case let .tool(toolMessage) = result.last else {
            Issue.record("Expected tool message")
            return
        }

        guard case let .toolApprovalResponse(approvalResponse) = toolMessage.content.first else {
            Issue.record("Expected tool approval response")
            return
        }

        #expect(approvalResponse.approvalId == "approval-1")
        #expect(approvalResponse.providerExecuted == false)
    }
}
