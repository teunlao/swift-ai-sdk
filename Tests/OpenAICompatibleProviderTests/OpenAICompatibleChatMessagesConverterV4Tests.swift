import Foundation
import Testing

@testable import AISDKProvider
@testable import OpenAICompatibleProvider

@Suite("OpenAI-compatible V4 chat message conversion")
struct OpenAICompatibleChatMessagesConverterV4Tests {
    @Test("converts native V4 audio PDF and text file parts")
    func convertsNativeV4FileParts() throws {
        let prompt: LanguageModelV4Prompt = [
            .user(
                content: [
                    .text(.init(text: "Inspect these files")),
                    .file(.init(
                        data: .data(Data([0, 1, 2, 3])),
                        mediaType: "audio/wav",
                        providerOptions: [
                            "openaiCompatible": ["audioTag": .string("voice")]
                        ]
                    )),
                    .file(.init(
                        data: .data(Data([0, 1, 2, 3])),
                        mediaType: "application/pdf"
                    )),
                    .file(.init(
                        data: .base64("SGVsbG8="),
                        mediaType: "text/plain"
                    ))
                ],
                providerOptions: [
                    "openaiCompatible": ["requestTag": .string("files")]
                ]
            )
        ]

        let messages = try convertToOpenAICompatibleChatMessages(prompt: prompt)

        guard messages.count == 1,
              case .object(let message) = messages[0],
              case .array(let content) = message["content"],
              content.count == 4 else {
            Issue.record("Expected one multipart user message")
            return
        }

        #expect(message["role"] == .string("user"))
        #expect(message["requestTag"] == .string("files"))

        #expect(content[1] == .object([
            "type": .string("input_audio"),
            "input_audio": .object([
                "data": .string("AAECAw=="),
                "format": .string("wav")
            ]),
            "audioTag": .string("voice")
        ]))
        #expect(content[2] == .object([
            "type": .string("file"),
            "file": .object([
                "filename": .string("document.pdf"),
                "file_data": .string("data:application/pdf;base64,AAECAw==")
            ])
        ]))
        #expect(content[3] == .object([
            "type": .string("text"),
            "text": .string("Hello")
        ]))
    }

    @Test("preserves reasoning thought signatures and V4 tool result semantics")
    func preservesNativeV4AssistantAndToolParts() throws {
        let prompt: LanguageModelV4Prompt = [
            .assistant(
                content: [
                    .reasoning(.init(text: "Need weather data")),
                    .toolCall(.init(
                        toolCallId: "call-1",
                        toolName: "weather",
                        input: .object(["city": .string("Paris")]),
                        providerOptions: [
                            "openaiCompatible": ["parallel": .bool(true)],
                            "google": ["thoughtSignature": .string("signature-1")]
                        ]
                    ))
                ],
                providerOptions: nil
            ),
            .tool(
                content: [
                    .toolApprovalResponse(.init(
                        approvalId: "approval-1",
                        approved: true
                    )),
                    .toolResult(.init(
                        toolCallId: "call-1",
                        toolName: "weather",
                        output: .executionDenied(reason: nil)
                    ))
                ],
                providerOptions: nil
            )
        ]

        let messages = try convertToOpenAICompatibleChatMessages(prompt: prompt)

        guard messages.count == 2,
              case .object(let assistant) = messages[0],
              case .array(let toolCalls) = assistant["tool_calls"],
              toolCalls.count == 1,
              case .object(let toolCall) = toolCalls[0],
              case .object(let function) = toolCall["function"],
              case .string(let arguments) = function["arguments"],
              case .object(let toolResult) = messages[1] else {
            Issue.record("Expected assistant tool call followed by one tool result")
            return
        }

        #expect(assistant["content"] == .null)
        #expect(assistant["reasoning_content"] == .string("Need weather data"))
        #expect(toolCall["parallel"] == .bool(true))
        #expect(toolCall["extra_content"] == .object([
            "google": .object([
                "thought_signature": .string("signature-1")
            ])
        ]))

        let decodedArguments = try JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: String]
        #expect(decodedArguments == ["city": "Paris"])
        #expect(toolResult["tool_call_id"] == .string("call-1"))
        #expect(toolResult["content"] == .string("Tool call execution denied."))
    }
}
