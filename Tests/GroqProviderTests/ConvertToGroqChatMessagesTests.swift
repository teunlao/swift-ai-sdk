import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import GroqProvider

@Suite("convertToGroqChatMessages")
struct ConvertToGroqChatMessagesTests {
    @Test("system message maps to string content")
    func systemMessage() throws {
        let prompt: LanguageModelV3Prompt = [
            .system(content: "behave", providerOptions: nil)
        ]

        let messages = try convertToGroqChatMessages(prompt)
        #expect(messages.count == 1)
        if case let .object(object) = messages[0] {
            #expect(object["role"] == .string("system"))
            #expect(object["content"] == .string("behave"))
        } else {
            Issue.record("Expected object message")
        }
    }

    @Test("user image files converted to inline data")
    func userImage() throws {
        let data = Data([0x01, 0x02])
        let prompt: LanguageModelV3Prompt = [
            .user(content: [
                .file(.init(data: .data(data), mediaType: "image/png"))
            ], providerOptions: nil)
        ]

        let messages = try convertToGroqChatMessages(prompt)
        guard case let .object(message) = messages.first,
              case let .array(contentParts)? = message["content"],
              case let .object(part) = contentParts.first,
              case let .object(imageURL)? = part["image_url"] else {
            Issue.record("Unexpected message structure")
            return
        }

        #expect(part["type"] == .string("image_url"))
        if case let .string(url)? = imageURL["url"] {
            #expect(url.starts(with: "data:image/png;base64,"))
        } else {
            Issue.record("Missing image URL")
        }
    }

    @Test("assistant supports reasoning and tool calls")
    func assistantMessages() throws {
        let toolCall = LanguageModelV3ToolCallPart(
            toolCallId: "tool-1",
            toolName: "lookup",
            input: .object(["q": .string("rain")]),
            providerExecuted: nil,
            providerOptions: nil
        )

        let prompt: LanguageModelV3Prompt = [
            .assistant(content: [
                .reasoning(.init(text: "thinking")),
                .text(.init(text: "answer")),
                .toolCall(toolCall)
            ], providerOptions: nil)
        ]

        let messages = try convertToGroqChatMessages(prompt)
        guard case let .object(message) = messages.first else {
            Issue.record("Expected assistant message object")
            return
        }

        #expect(message["role"] == .string("assistant"))
        #expect(message["content"] == .string("answer"))
        #expect(message["reasoning"] == .string("thinking"))
        if case let .array(toolCalls)? = message["tool_calls"],
           case let .object(call)? = toolCalls.first {
            #expect(call["type"] == .string("function"))
            if case let .object(function)? = call["function"] {
                #expect(function["name"] == .string("lookup"))
            } else {
                Issue.record("Missing function payload")
            }
        } else {
            Issue.record("Missing tool calls")
        }
    }

    @Test("tool result content serializes to string")
    func toolResultMapping() throws {
        let toolResult = LanguageModelV3ToolResultPart(
            toolCallId: "call-1",
            toolName: "lookup",
            output: .json(value: .object(["value": .string("42")])),
            providerOptions: nil
        )

        let prompt: LanguageModelV3Prompt = [
            .tool(content: [toolResult], providerOptions: nil)
        ]

        let messages = try convertToGroqChatMessages(prompt)
        guard case let .object(message) = messages.first else {
            Issue.record("Expected tool message")
            return
        }

        #expect(message["role"] == .string("tool"))
        #expect(message["tool_call_id"] == .string("call-1"))
        if case let .string(content)? = message["content"] {
            #expect(content.contains("\"value\":\"42\""))
        } else {
            Issue.record("Expected string content")
        }
    }
}
