import Foundation
import Testing
@testable import AISDKProviderUtils
import AISDKProvider

// MARK: - ModelMessage Codable Round-Trip Tests

@Suite("ModelMessage Codable")
struct ModelMessageCodableTests {

    private func roundTrip(_ message: ModelMessage) throws -> ModelMessage {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(message)
        return try JSONDecoder().decode(ModelMessage.self, from: data)
    }

    // MARK: - System

    @Test func systemMessage() throws {
        let msg = ModelMessage.system(SystemModelMessage(content: "You are helpful"))
        let decoded = try roundTrip(msg)
        #expect(decoded == msg)
    }

    // MARK: - User

    @Test func userTextMessage() throws {
        let msg = ModelMessage.user(UserModelMessage(content: .text("Hello")))
        let decoded = try roundTrip(msg)
        #expect(decoded == msg)
    }

    @Test func userPartsMessage() throws {
        let msg = ModelMessage.user(UserModelMessage(content: .parts([
            .text(TextPart(text: "Look at this")),
            .image(ImagePart(image: .string("iVBOR"), mediaType: "image/png")),
        ])))
        let decoded = try roundTrip(msg)
        #expect(decoded == msg)
    }

    // MARK: - Assistant

    @Test func assistantTextMessage() throws {
        let msg = ModelMessage.assistant(AssistantModelMessage(content: .text("Hi there")))
        let decoded = try roundTrip(msg)
        #expect(decoded == msg)
    }

    @Test func assistantWithReasoningAndToolCall() throws {
        let msg = ModelMessage.assistant(AssistantModelMessage(content: .parts([
            .reasoning(ReasoningPart(
                text: "Let me think...",
                providerOptions: ["anthropic": ["signature": .string("sig123")]]
            )),
            .text(TextPart(text: "I'll use a tool")),
            .toolCall(ToolCallPart(
                toolCallId: "call_1",
                toolName: "bash",
                input: .object(["command": .string("ls")])
            )),
        ])))
        let decoded = try roundTrip(msg)
        #expect(decoded == msg)
    }

    @Test func assistantWithProviderExecutedToolResult() throws {
        let msg = ModelMessage.assistant(AssistantModelMessage(content: .parts([
            .toolResult(ToolResultPart(
                toolCallId: "call_1",
                toolName: "web_search",
                output: .json(value: .object(["results": .array([])]))
            )),
        ])))
        let decoded = try roundTrip(msg)
        #expect(decoded == msg)
    }

    // MARK: - Tool

    @Test func toolResultMessage() throws {
        let msg = ModelMessage.tool(ToolModelMessage(content: [
            .toolResult(ToolResultPart(
                toolCallId: "call_1",
                toolName: "bash",
                output: .text(value: "file1.txt\nfile2.txt")
            )),
        ]))
        let decoded = try roundTrip(msg)
        #expect(decoded == msg)
    }

    @Test func toolResultWithJsonOutput() throws {
        let msg = ModelMessage.tool(ToolModelMessage(content: [
            .toolResult(ToolResultPart(
                toolCallId: "call_1",
                toolName: "mcp_tool",
                output: .json(value: .object([
                    "structuredContent": .object(["result": .string("OK")]),
                    "content": .array([.object(["type": .string("text"), "text": .string("OK")])]),
                    "isError": .bool(false),
                ]))
            )),
        ]))
        let decoded = try roundTrip(msg)
        #expect(decoded == msg)
    }

    @Test func toolResultWithContentParts() throws {
        let msg = ModelMessage.tool(ToolModelMessage(content: [
            .toolResult(ToolResultPart(
                toolCallId: "call_1",
                toolName: "screenshot",
                output: .content(value: [
                    .text(text: "Screenshot captured"),
                    .media(data: "iVBOR", mediaType: "image/png"),
                ])
            )),
        ]))
        let decoded = try roundTrip(msg)
        #expect(decoded == msg)
    }

    @Test func toolResultWithErrorOutput() throws {
        let msg = ModelMessage.tool(ToolModelMessage(content: [
            .toolResult(ToolResultPart(
                toolCallId: "call_1",
                toolName: "bash",
                output: .errorText(value: "Command failed with exit code 1")
            )),
        ]))
        let decoded = try roundTrip(msg)
        #expect(decoded == msg)
    }

    // MARK: - Byte stability

    @Test func encodingIsByteStableAcrossMultipleCalls() throws {
        let msg = ModelMessage.assistant(AssistantModelMessage(content: .parts([
            .reasoning(ReasoningPart(
                text: "Thinking",
                providerOptions: ["anthropic": ["signature": .string("sig")]]
            )),
            .text(TextPart(text: "Response")),
            .toolCall(ToolCallPart(
                toolCallId: "call_1",
                toolName: "test",
                input: .object(["zebra": .string("z"), "alpha": .string("a")])
            )),
        ])))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        var results: [Data] = []
        for _ in 0..<10 {
            results.append(try encoder.encode(msg))
        }

        let first = results[0]
        for (i, data) in results.enumerated().dropFirst() {
            #expect(data == first, "Encoding \(i) differs from first")
        }
    }

    // MARK: - Full conversation round-trip

    @Test func fullConversationRoundTrip() throws {
        let conversation: [ModelMessage] = [
            .user(UserModelMessage(content: .text("Hello"))),
            .assistant(AssistantModelMessage(content: .parts([
                .reasoning(ReasoningPart(text: "User said hello")),
                .text(TextPart(text: "Hi! Let me help you.")),
                .toolCall(ToolCallPart(
                    toolCallId: "call_1",
                    toolName: "bash",
                    input: .object(["command": .string("echo hello")])
                )),
            ]))),
            .tool(ToolModelMessage(content: [
                .toolResult(ToolResultPart(
                    toolCallId: "call_1",
                    toolName: "bash",
                    output: .text(value: "hello")
                )),
            ])),
            .assistant(AssistantModelMessage(content: .text("Done!"))),
        ]

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(conversation)
        let decoded = try JSONDecoder().decode([ModelMessage].self, from: data)
        #expect(decoded == conversation)
    }

    // MARK: - JSON shape snapshot

    @Test func fullConversationEncodesToUpstreamShape() throws {
        let conversation: [ModelMessage] = [
            .system(SystemModelMessage(content: "You are helpful")),
            .user(UserModelMessage(content: .text("Hello"))),
            .user(UserModelMessage(content: .parts([
                .text(TextPart(text: "Look at this")),
                .image(ImagePart(image: .string("iVBOR"), mediaType: "image/png")),
            ]))),
            .assistant(AssistantModelMessage(content: .text("Sure!"))),
            .assistant(AssistantModelMessage(content: .parts([
                .reasoning(ReasoningPart(text: "Let me think")),
                .text(TextPart(text: "I'll use a tool")),
                .toolCall(ToolCallPart(
                    toolCallId: "call_1", toolName: "bash",
                    input: .object(["command": .string("ls")])
                )),
            ]))),
            .tool(ToolModelMessage(content: [
                .toolResult(ToolResultPart(
                    toolCallId: "call_1", toolName: "bash",
                    output: .text(value: "file1.txt")
                )),
            ])),
        ]

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(conversation)
        let json = String(data: data, encoding: .utf8)!

        // Verify the JSON matches the upstream TypeScript shape exactly:
        // - Messages are objects with "role" + "content"
        // - User text content is a bare string, not {"type":"text","value":"..."}
        // - User parts content is a bare array, not {"type":"parts","parts":[...]}
        // - Image data is a bare string, not {"type":"string","value":"..."}
        // - Part objects have "type" discriminator fields
        // - Tool call type is "tool-call" (hyphenated)
        // - Tool result type is "tool-result" (hyphenated)
        let expected = """
        [
          {
            "content" : "You are helpful",
            "role" : "system"
          },
          {
            "content" : "Hello",
            "role" : "user"
          },
          {
            "content" : [
              {
                "text" : "Look at this",
                "type" : "text"
              },
              {
                "image" : "iVBOR",
                "mediaType" : "image\\/png",
                "type" : "image"
              }
            ],
            "role" : "user"
          },
          {
            "content" : "Sure!",
            "role" : "assistant"
          },
          {
            "content" : [
              {
                "text" : "Let me think",
                "type" : "reasoning"
              },
              {
                "text" : "I'll use a tool",
                "type" : "text"
              },
              {
                "input" : {
                  "command" : "ls"
                },
                "toolCallId" : "call_1",
                "toolName" : "bash",
                "type" : "tool-call"
              }
            ],
            "role" : "assistant"
          },
          {
            "content" : [
              {
                "output" : {
                  "type" : "text",
                  "value" : "file1.txt"
                },
                "toolCallId" : "call_1",
                "toolName" : "bash",
                "type" : "tool-result"
              }
            ],
            "role" : "tool"
          }
        ]
        """
        #expect(json == expected)
    }

    // MARK: - Upstream JSON shape decoding

    @Test func decodesUserMessageWithStringContent() throws {
        let json = """
        {"role":"user","content":"Hello"}
        """
        let msg = try JSONDecoder().decode(ModelMessage.self, from: Data(json.utf8))
        guard case .user(let user) = msg,
              case .text(let text) = user.content else {
            Issue.record("Expected user message with text content")
            return
        }
        #expect(text == "Hello")
    }

    @Test func decodesUserMessageWithPartsArray() throws {
        let json = """
        {"role":"user","content":[{"type":"text","text":"Look"},{"type":"image","image":"iVBOR","mediaType":"image/png"}]}
        """
        let msg = try JSONDecoder().decode(ModelMessage.self, from: Data(json.utf8))
        guard case .user(let user) = msg,
              case .parts(let parts) = user.content else {
            Issue.record("Expected user message with parts content")
            return
        }
        #expect(parts.count == 2)
    }

    @Test func decodesAssistantMessageWithStringContent() throws {
        let json = """
        {"role":"assistant","content":"Hi there"}
        """
        let msg = try JSONDecoder().decode(ModelMessage.self, from: Data(json.utf8))
        guard case .assistant(let asst) = msg,
              case .text(let text) = asst.content else {
            Issue.record("Expected assistant message with text content")
            return
        }
        #expect(text == "Hi there")
    }

    @Test func decodesImagePartWithDirectStringData() throws {
        let json = """
        {"role":"user","content":[{"type":"image","image":"iVBORbase64data","mediaType":"image/png"}]}
        """
        let msg = try JSONDecoder().decode(ModelMessage.self, from: Data(json.utf8))
        guard case .user(let user) = msg,
              case .parts(let parts) = user.content,
              case .image(let imagePart) = parts.first,
              case .string(let data) = imagePart.image else {
            Issue.record("Expected image part with string data")
            return
        }
        #expect(data == "iVBORbase64data")
    }

    @Test func encodesUserTextContentAsBareString() throws {
        let msg = ModelMessage.user(UserModelMessage(content: .text("Hello")))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(msg)
        let json = try JSONDecoder().decode([String: JSONValue].self, from: data)
        guard case .string(let content) = json["content"] else {
            Issue.record("Expected content to be a bare string, got \(String(describing: json["content"]))")
            return
        }
        #expect(content == "Hello")
    }

    @Test func encodesUserPartsContentAsBareArray() throws {
        let msg = ModelMessage.user(UserModelMessage(content: .parts([
            .text(TextPart(text: "Look")),
        ])))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(msg)
        let json = try JSONDecoder().decode([String: JSONValue].self, from: data)
        guard case .array = json["content"] else {
            Issue.record("Expected content to be a bare array, got \(String(describing: json["content"]))")
            return
        }
    }

    @Test func encodesImageDataAsBareString() throws {
        let msg = ModelMessage.user(UserModelMessage(content: .parts([
            .image(ImagePart(image: .string("iVBOR"), mediaType: "image/png")),
        ])))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(msg)
        let str = String(data: data, encoding: .utf8)!
        #expect(str.contains("\"image\":\"iVBOR\""))
    }
}
