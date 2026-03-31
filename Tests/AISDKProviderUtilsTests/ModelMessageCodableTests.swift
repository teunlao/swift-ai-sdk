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

    private func encodedJSON<T: Encodable>(_ value: T) throws -> JSONValue {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        return try JSONDecoder().decode(JSONValue.self, from: data)
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

    @Test func assistantToolCallPreservesProviderExecutedAndProviderOptions() throws {
        let msg = ModelMessage.assistant(AssistantModelMessage(content: .parts([
            .toolCall(ToolCallPart(
                toolCallId: "call_1",
                toolName: "computer",
                input: .object(["action": .string("click")]),
                providerOptions: ["openai": ["priority": .string("high")]],
                providerExecuted: true
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

    @Test func approvalPartsPreserveProviderExecutedAndReason() throws {
        let messages: [ModelMessage] = [
            .assistant(AssistantModelMessage(content: .parts([
                .toolApprovalRequest(ToolApprovalRequest(
                    approvalId: "approval_1",
                    toolCallId: "call_1"
                )),
            ]))),
            .tool(ToolModelMessage(content: [
                .toolApprovalResponse(ToolApprovalResponse(
                    approvalId: "approval_1",
                    approved: true,
                    reason: "Approved by user",
                    providerExecuted: true
                )),
            ])),
        ]

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(messages)
        let decoded = try JSONDecoder().decode([ModelMessage].self, from: data)
        #expect(decoded == messages)
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

    // MARK: - Storage shape regressions

    @Test func userTextMessageUsesTaggedStorageContentShape() throws {
        let json = try encodedJSON(
            ModelMessage.user(UserModelMessage(content: .text("Hello")))
        )

        let expected: JSONValue = .object([
            "content": .object([
                "type": .string("text"),
                "value": .string("Hello"),
            ]),
            "role": .string("user"),
        ])

        #expect(json == expected)
    }

    @Test func dataContentOrURLUsesExplicitTaggedStorageCases() throws {
        let url = URL(string: "https://example.com/cat.png")!
        let binary = Data([0x00, 0x01, 0x02])

        let stringJSON = try encodedJSON(DataContentOrURL.string("iVBOR"))
        let urlJSON = try encodedJSON(DataContentOrURL.url(url))
        let dataJSON = try encodedJSON(DataContentOrURL.data(binary))

        #expect(stringJSON == .object([
            "type": .string("string"),
            "value": .string("iVBOR"),
        ]))
        #expect(urlJSON == .object([
            "type": .string("url"),
            "url": .string("https://example.com/cat.png"),
        ]))
        #expect(dataJSON == .object([
            "type": .string("data"),
            "data": .string("AAEC"),
        ]))
    }

    @Test func imageAndFilePartsPreserveDistinctStringURLAndDataStorageCases() throws {
        let msg = ModelMessage.user(UserModelMessage(content: .parts([
            .image(ImagePart(
                image: .url(URL(string: "https://example.com/image.png")!),
                mediaType: "image/png"
            )),
            .file(FilePart(
                data: .data(Data([0xDE, 0xAD, 0xBE, 0xEF])),
                mediaType: "application/octet-stream",
                filename: "blob.bin"
            )),
        ])))

        let json = try encodedJSON(msg)
        let expected: JSONValue = .object([
            "content": .object([
                "type": .string("parts"),
                "parts": .array([
                    .object([
                        "image": .object([
                            "type": .string("url"),
                            "url": .string("https://example.com/image.png"),
                        ]),
                        "mediaType": .string("image/png"),
                        "type": .string("image"),
                    ]),
                    .object([
                        "data": .object([
                            "type": .string("data"),
                            "data": .string("3q2+7w=="),
                        ]),
                        "filename": .string("blob.bin"),
                        "mediaType": .string("application/octet-stream"),
                        "type": .string("file"),
                    ]),
                ]),
            ]),
            "role": .string("user"),
        ])

        #expect(json == expected)
    }
}
