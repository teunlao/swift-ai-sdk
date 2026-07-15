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

    @Test("matches JavaScript truthiness and string coercion for thought signatures")
    func matchesThoughtSignatureCoercion() throws {
        let cases: [(value: JSONValue, expected: String?)] = [
            (.string(""), nil),
            (.bool(false), nil),
            (.number(0), nil),
            (.string("signature"), "signature"),
            (.bool(true), "true"),
            (.number(12), "12"),
            (.array([.string("a"), .string("b")]), "a,b"),
            (.object(["key": .string("value")]), "[object Object]")
        ]

        for testCase in cases {
            let prompt: LanguageModelV4Prompt = [
                .assistant(
                    content: [
                        .toolCall(.init(
                            toolCallId: "call-1",
                            toolName: "lookup",
                            input: .object([:]),
                            providerOptions: [
                                "google": ["thoughtSignature": testCase.value]
                            ]
                        ))
                    ],
                    providerOptions: nil
                )
            ]

            let messages = try convertToOpenAICompatibleChatMessages(prompt: prompt)
            guard case let .object(message) = try #require(messages.first),
                  case let .array(toolCalls) = message["tool_calls"],
                  case let .object(toolCall) = try #require(toolCalls.first) else {
                Issue.record("Expected one converted tool call")
                continue
            }

            let actualSignature: String?
            if case let .object(extraContent) = toolCall["extra_content"],
               case let .object(google) = extraContent["google"],
               case let .string(signature) = google["thought_signature"] {
                actualSignature = signature
            } else {
                actualSignature = nil
            }
            #expect(actualSignature == testCase.expected)
        }
    }

    @Test("converts every supported V4 file variant")
    func convertsSupportedV4FileVariants() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        let prompt: LanguageModelV4Prompt = [
            .user(
                content: [
                    .file(.init(data: .data(png), mediaType: "image/png")),
                    .file(.init(data: .data(png), mediaType: "image")),
                    .file(.init(data: .data(png), mediaType: "image/*")),
                    .file(.init(
                        data: .url(URL(string: "https://example.com/image")!),
                        mediaType: "image"
                    )),
                    .file(.init(data: .base64("AAECAw=="), mediaType: "audio/mp3")),
                    .file(.init(data: .base64("AAECAw=="), mediaType: "audio/mpeg")),
                    .file(.init(
                        data: .base64("JVBERg=="),
                        mediaType: "application/pdf",
                        filename: "report.pdf"
                    )),
                    .file(.init(data: .data(Data("plain".utf8)), mediaType: "text/plain")),
                    .file(.init(data: .base64("IyBUaXRsZQ=="), mediaType: "text/markdown")),
                    .file(.init(
                        data: .url(URL(string: "https://example.com/readme.txt")!),
                        mediaType: "text/plain"
                    ))
                ],
                providerOptions: nil
            )
        ]

        let messages = try convertToOpenAICompatibleChatMessages(prompt: prompt)
        guard case let .object(message) = try #require(messages.first),
              case let .array(content) = message["content"] else {
            Issue.record("Expected multipart user content")
            return
        }

        #expect(content.count == 10)
        #expect(content[0] == .object([
            "type": .string("image_url"),
            "image_url": .object(["url": .string("data:image/png;base64,iVBORw==")])
        ]))
        #expect(content[1] == content[0])
        #expect(content[2] == content[0])
        #expect(content[3] == .object([
            "type": .string("image_url"),
            "image_url": .object(["url": .string("https://example.com/image")])
        ]))
        #expect(content[4] == .object([
            "type": .string("input_audio"),
            "input_audio": .object([
                "data": .string("AAECAw=="),
                "format": .string("mp3")
            ])
        ]))
        #expect(content[5] == content[4])
        #expect(content[6] == .object([
            "type": .string("file"),
            "file": .object([
                "filename": .string("report.pdf"),
                "file_data": .string("data:application/pdf;base64,JVBERg==")
            ])
        ]))
        #expect(content[7] == .object([
            "type": .string("text"),
            "text": .string("plain")
        ]))
        #expect(content[8] == .object([
            "type": .string("text"),
            "text": .string("# Title")
        ]))
        #expect(content[9] == .object([
            "type": .string("text"),
            "text": .string("https://example.com/readme.txt")
        ]))
    }

    @Test("rejects unsupported V4 file sources and media types")
    func rejectsUnsupportedV4FileInputs() throws {
        let cases: [(part: LanguageModelV4FilePart, functionality: String)] = [
            (
                .init(
                    data: .url(URL(string: "https://example.com/audio.wav")!),
                    mediaType: "audio/wav"
                ),
                "audio file parts with URLs"
            ),
            (
                .init(data: .data(Data([0, 1])), mediaType: "audio/ogg"),
                "audio media type audio/ogg"
            ),
            (
                .init(
                    data: .url(URL(string: "https://example.com/document.pdf")!),
                    mediaType: "application/pdf"
                ),
                "PDF file parts with URLs"
            ),
            (
                .init(data: .data(Data([0, 1])), mediaType: "video/mp4"),
                "file part media type video/mp4"
            ),
            (
                .init(
                    data: .reference(["test-provider": "file-1"]),
                    mediaType: "application/pdf"
                ),
                "file parts with provider references"
            ),
            (
                .init(data: .text("provider text"), mediaType: "text/plain"),
                "text file parts"
            )
        ]

        for testCase in cases {
            let prompt: LanguageModelV4Prompt = [
                .user(content: [.file(testCase.part)], providerOptions: nil)
            ]
            do {
                _ = try convertToOpenAICompatibleChatMessages(prompt: prompt)
                Issue.record("Expected unsupported input: \(testCase.functionality)")
            } catch let error as UnsupportedFunctionalityError {
                #expect(error.functionality == testCase.functionality)
            } catch {
                Issue.record("Expected UnsupportedFunctionalityError, got \(error)")
            }
        }
    }
}
