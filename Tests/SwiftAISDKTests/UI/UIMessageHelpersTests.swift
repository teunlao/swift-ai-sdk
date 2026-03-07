import Testing
@testable import SwiftAISDK

@Suite("UIMessage helpers")
struct UIMessageHelpersTests {
    @Test("isTextUIPart returns true only for text parts")
    func isTextUIPartReturnsTrueOnlyForTextParts() throws {
        let textPart: UIMessagePart = .text(TextUIPart(text: "some text", state: .done))
        let filePart: UIMessagePart = .file(FileUIPart(mediaType: "text/plain", filename: nil, url: "https://example.com/file.txt"))

        #expect(isTextUIPart(textPart) == true)
        #expect(isTextUIPart(filePart) == false)
    }

    @Test("isFileUIPart returns true only for file parts")
    func isFileUIPartReturnsTrueOnlyForFileParts() throws {
        let filePart: UIMessagePart = .file(FileUIPart(mediaType: "text/plain", filename: nil, url: "https://example.com/file.txt"))
        let reasoningPart: UIMessagePart = .reasoning(ReasoningUIPart(text: "thinking", state: .done))

        #expect(isFileUIPart(filePart) == true)
        #expect(isFileUIPart(reasoningPart) == false)
    }

    @Test("isReasoningUIPart returns true only for reasoning parts")
    func isReasoningUIPartReturnsTrueOnlyForReasoningParts() throws {
        let reasoningPart: UIMessagePart = .reasoning(ReasoningUIPart(text: "thinking", state: .done))
        let textPart: UIMessagePart = .text(TextUIPart(text: "some text", state: .done))

        #expect(isReasoningUIPart(reasoningPart) == true)
        #expect(isReasoningUIPart(textPart) == false)
    }

    @Test("isDataUIPart returns true only for data parts")
    func isDataUIPartReturnsTrueOnlyForDataParts() throws {
        let dataPart: UIMessagePart = .data(
            DataUIPart(
                typeIdentifier: "data-someDataPart",
                id: nil,
                data: .string("some data")
            )
        )
        let textPart: UIMessagePart = .text(TextUIPart(text: "some text", state: .done))

        #expect(isDataUIPart(dataPart) == true)
        #expect(isDataUIPart(textPart) == false)
    }

    @Test("isToolUIPart returns true for static and dynamic tool parts")
    func isToolUIPartReturnsTrueForStaticAndDynamicToolParts() throws {
        let staticPart: UIMessagePart = .tool(
            UIToolUIPart(
                toolName: "getLocation",
                toolCallId: "tool1",
                state: .outputAvailable,
                input: .object([:]),
                output: .string("result")
            )
        )
        let dynamicPart: UIMessagePart = .dynamicTool(
            UIDynamicToolUIPart(
                toolName: "lookupWeather",
                toolCallId: "tool2",
                state: .outputAvailable,
                input: .object([:]),
                output: .string("sunny")
            )
        )

        #expect(isToolUIPart(staticPart) == true)
        #expect(isToolUIPart(dynamicPart) == true)
    }

    @Test("isStaticToolUIPart distinguishes static and dynamic tool parts")
    func isStaticToolUIPartDistinguishesToolKinds() throws {
        let staticPart: UIMessagePart = .tool(
            UIToolUIPart(
                toolName: "getLocation",
                toolCallId: "tool1",
                state: .outputAvailable,
                input: .object([:]),
                output: .string("result")
            )
        )
        let dynamicPart: UIMessagePart = .dynamicTool(
            UIDynamicToolUIPart(
                toolName: "lookupWeather",
                toolCallId: "tool2",
                state: .outputAvailable,
                input: .object([:]),
                output: .string("sunny")
            )
        )

        #expect(isStaticToolUIPart(staticPart) == true)
        #expect(isStaticToolUIPart(dynamicPart) == false)
    }

    @Test("returns tool name without prefix")
    func returnsToolName() throws {
        let part: UIMessagePart = .tool(
            UIToolUIPart(
                toolName: "getLocation",
                toolCallId: "tool1",
                state: .outputAvailable,
                input: .object([:]),
                output: .string("result")
            )
        )

        #expect(getToolName(part) == "getLocation")
    }

    @Test("returns static tool name with dash preserved")
    func returnsStaticToolNameWithDash() throws {
        let part = UIToolUIPart(
            toolName: "get-location",
            toolCallId: "tool1",
            state: .outputAvailable,
            input: .object([:]),
            output: .string("result")
        )

        #expect(getStaticToolName(part) == "get-location")
    }

    @Test("returns dynamic tool name")
    func returnsDynamicToolName() throws {
        let part: UIMessagePart = .dynamicTool(
            UIDynamicToolUIPart(
                toolName: "lookupWeather",
                toolCallId: "tool1",
                state: .outputAvailable,
                input: .object([:]),
                output: .string("sunny")
            )
        )

        #expect(getToolName(part) == "lookupWeather")
    }

    @Test("last assistant message complete with tool calls returns true for completed dynamic tool")
    func lastAssistantMessageCompleteWithToolCallsForDynamicTool() throws {
        let messages = [
            UIMessage(
                id: "1",
                role: .assistant,
                parts: [
                    .stepStart,
                    .dynamicTool(
                        UIDynamicToolUIPart(
                            toolName: "getDynamicWeather",
                            toolCallId: "call_dynamic_123",
                            state: .outputAvailable,
                            input: .object(["location": .string("San Francisco")]),
                            output: .string("sunny")
                        )
                    )
                ]
            )
        ]

        #expect(lastAssistantMessageIsCompleteWithToolCalls(messages: messages) == true)
    }

    @Test("last assistant message complete with tool calls returns false when last step only has text")
    func lastAssistantMessageCompleteWithToolCallsFalseForTextOnlyLastStep() throws {
        let messages = [
            UIMessage(
                id: "1",
                role: .assistant,
                parts: [
                    .stepStart,
                    .tool(
                        UIToolUIPart(
                            toolName: "getLocation",
                            toolCallId: "call_location_123",
                            state: .outputAvailable,
                            input: .object([:]),
                            output: .string("New York")
                        )
                    ),
                    .stepStart,
                    .text(TextUIPart(text: "The current weather in New York is windy.", state: .done))
                ]
            )
        ]

        #expect(lastAssistantMessageIsCompleteWithToolCalls(messages: messages) == false)
    }

    @Test("last assistant message complete with tool calls ignores provider executed tools")
    func lastAssistantMessageCompleteWithToolCallsIgnoresProviderExecutedTools() throws {
        let messages = [
            UIMessage(
                id: "1",
                role: .assistant,
                parts: [
                    .stepStart,
                    .tool(
                        UIToolUIPart(
                            toolName: "web_search",
                            toolCallId: "srvtoolu_01KSMqkKSbgKhCwGZHQDaV48",
                            state: .outputAvailable,
                            input: .object(["query": .string("New York weather")]),
                            output: .array([]),
                            providerExecuted: true
                        )
                    ),
                    .text(TextUIPart(text: "The current weather in New York is windy.", state: .done))
                ]
            )
        ]

        #expect(lastAssistantMessageIsCompleteWithToolCalls(messages: messages) == false)
    }

    @Test("last assistant message complete with approval responses returns true when all local approvals are resolved")
    func lastAssistantMessageCompleteWithApprovalResponsesTrue() throws {
        let messages = [
            UIMessage(
                id: "1",
                role: .assistant,
                parts: [
                    .stepStart,
                    .tool(
                        UIToolUIPart(
                            toolName: "weather",
                            toolCallId: "call-1",
                            state: .approvalResponded,
                            input: .object(["city": .string("Tokyo")]),
                            approval: UIToolApproval(id: "approval-1", approved: true, reason: nil)
                        )
                    ),
                    .dynamicTool(
                        UIDynamicToolUIPart(
                            toolName: "lookupWeather",
                            toolCallId: "call-2",
                            state: .outputAvailable,
                            input: .object(["city": .string("Tokyo")]),
                            output: .string("sunny")
                        )
                    )
                ]
            )
        ]

        #expect(lastAssistantMessageIsCompleteWithApprovalResponses(messages: messages) == true)
    }

    @Test("last assistant message complete with approval responses returns false when approval still pending")
    func lastAssistantMessageCompleteWithApprovalResponsesFalseWhenPending() throws {
        let messages = [
            UIMessage(
                id: "1",
                role: .assistant,
                parts: [
                    .stepStart,
                    .tool(
                        UIToolUIPart(
                            toolName: "weather",
                            toolCallId: "call-1",
                            state: .approvalRequested,
                            input: .object(["city": .string("Tokyo")]),
                            approval: UIToolApproval(id: "approval-1")
                        )
                    )
                ]
            )
        ]

        #expect(lastAssistantMessageIsCompleteWithApprovalResponses(messages: messages) == false)
    }

    @Test("last assistant message complete with approval responses ignores provider executed approvals")
    func lastAssistantMessageCompleteWithApprovalResponsesIgnoresProviderExecutedApprovals() throws {
        let messages = [
            UIMessage(
                id: "1",
                role: .assistant,
                parts: [
                    .stepStart,
                    .tool(
                        UIToolUIPart(
                            toolName: "shell",
                            toolCallId: "call-1",
                            state: .approvalResponded,
                            input: .object(["command": .string("ls")]),
                            providerExecuted: true,
                            approval: UIToolApproval(id: "approval-1", approved: true, reason: nil)
                        )
                    )
                ]
            )
        ]

        #expect(lastAssistantMessageIsCompleteWithApprovalResponses(messages: messages) == false)
    }
}
