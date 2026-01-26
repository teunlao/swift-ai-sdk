import Foundation
import Testing
@testable import AISDKProvider
@testable import OpenAIProvider

@Suite("OpenAIChatMessagesConverter")
struct OpenAIChatMessagesConverterTests {
    @Test("system message forwarded")
    func systemMessageForwarded() throws {
        let result = try OpenAIChatMessagesConverter.convert(
            prompt: [
                .system(content: "You are a helpful assistant.", providerOptions: nil)
            ],
            systemMessageMode: .system
        )

        let expected: [JSONValue] = [
            .object([
                "role": .string("system"),
                "content": .string("You are a helpful assistant.")
            ])
        ]

        #expect(result.messages == expected)
        #expect(result.warnings.isEmpty)
    }

    @Test("system message converted to developer")
    func systemMessageConvertedToDeveloper() throws {
        let result = try OpenAIChatMessagesConverter.convert(
            prompt: [
                .system(content: "Stay on task", providerOptions: nil)
            ],
            systemMessageMode: .developer
        )

        let expected: [JSONValue] = [
            .object([
                "role": .string("developer"),
                "content": .string("Stay on task")
            ])
        ]

        #expect(result.messages == expected)
        #expect(result.warnings.isEmpty)
    }

    @Test("system message removal emits warning")
    func systemMessageRemovalEmitsWarning() throws {
        let result = try OpenAIChatMessagesConverter.convert(
            prompt: [
                .system(content: "Follow instructions", providerOptions: nil)
            ],
            systemMessageMode: .remove
        )

        #expect(result.messages.isEmpty)
        #expect(result.warnings.count == 1)
        if let warning = result.warnings.first {
            if case .other(let message) = warning {
                #expect(message == "system messages are removed for this model")
            } else {
                Issue.record("Unexpected warning type: \(warning)")
            }
        }
    }

    @Test("single text user message becomes string content")
    func userTextMessageToString() throws {
        let prompt: LanguageModelV3Prompt = [
            .user(
                content: [
                    .text(LanguageModelV3TextPart(text: "Hello"))
                ],
                providerOptions: nil
            )
        ]

        let result = try OpenAIChatMessagesConverter.convert(prompt: prompt, systemMessageMode: .system)
        let expected: [JSONValue] = [
            .object([
                "role": .string("user"),
                "content": .string("Hello")
            ])
        ]

        #expect(result.messages == expected)
    }

    @Test("user message with image part")
    func userMessageWithImagePart() throws {
        let imagePart = LanguageModelV3FilePart(
            data: .base64("AAECAw=="),
            mediaType: "image/png"
        )

        let prompt: LanguageModelV3Prompt = [
            .user(
                content: [
                    .text(LanguageModelV3TextPart(text: "Hello")),
                    .file(imagePart)
                ],
                providerOptions: nil
            )
        ]

        let result = try OpenAIChatMessagesConverter.convert(prompt: prompt, systemMessageMode: .system)

        let expected: [JSONValue] = [
            .object([
                "role": .string("user"),
                "content": .array([
                    .object([
                        "type": .string("text"),
                        "text": .string("Hello")
                    ]),
                    .object([
                        "type": .string("image_url"),
                        "image_url": .object([
                            "url": .string("data:image/png;base64,AAECAw==")
                        ])
                    ])
                ])
            ])
        ]

        #expect(result.messages == expected)
    }

    @Test("image detail from provider options")
    func imageDetailFromProviderOptions() throws {
        let providerOptions: SharedV3ProviderOptions = [
            "openai": ["imageDetail": .string("low")]
        ]
        let imagePart = LanguageModelV3FilePart(
            data: .base64("AAECAw=="),
            mediaType: "image/png",
            filename: nil,
            providerOptions: providerOptions
        )
        let prompt: LanguageModelV3Prompt = [
            .user(content: [.file(imagePart)], providerOptions: nil)
        ]

        let result = try OpenAIChatMessagesConverter.convert(prompt: prompt, systemMessageMode: .system)

        guard case .object(let message) = result.messages.first else {
            Issue.record("Expected object message")
            return
        }
        guard case .array(let parts)? = message["content"], parts.count == 1 else {
            Issue.record("Expected single content part")
            return
        }
        guard case .object(let part) = parts.first, case .object(let imageURL)? = part["image_url"] else {
            Issue.record("Expected image_url object")
            return
        }
        #expect(imageURL["detail"] == .string("low"))
    }

    // Port of convert-to-openai-chat-messages.test.ts: "should throw for unsupported mime types" (nested in file parts)
    @Test("unsupported mime type throws")
    func unsupportedMimeTypeThrows() throws {
        let filePart = LanguageModelV3FilePart(
            data: .base64("AAECAw=="),
            mediaType: "application/something"
        )
        let prompt: LanguageModelV3Prompt = [
            .user(content: [.file(filePart)], providerOptions: nil)
        ]

        do {
            _ = try OpenAIChatMessagesConverter.convert(prompt: prompt, systemMessageMode: .system)
            Issue.record("Expected UnsupportedFunctionalityError")
        } catch let error as UnsupportedFunctionalityError {
            #expect(error.functionality == "file part media type application/something")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // Port of convert-to-openai-chat-messages.test.ts: "should throw error for unsupported file types" (top level)
    @Test("unsupported file type text/plain throws")
    func unsupportedFileTypeTextPlainThrows() throws {
        let filePart = LanguageModelV3FilePart(
            data: .base64("AQIDBAU="),
            mediaType: "text/plain"
        )
        let prompt: LanguageModelV3Prompt = [
            .user(content: [.file(filePart)], providerOptions: nil)
        ]

        do {
            _ = try OpenAIChatMessagesConverter.convert(prompt: prompt, systemMessageMode: .system)
            Issue.record("Expected UnsupportedFunctionalityError")
        } catch let error as UnsupportedFunctionalityError {
            #expect(error.functionality.contains("file part media type text/plain"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("audio file part with URL throws")
    func audioFilePartWithURLThrows() throws {
        let filePart = LanguageModelV3FilePart(
            data: .url(URL(string: "https://example.com/foo.wav")!),
            mediaType: "audio/wav"
        )
        let prompt: LanguageModelV3Prompt = [
            .user(content: [.file(filePart)], providerOptions: nil)
        ]

        do {
            _ = try OpenAIChatMessagesConverter.convert(prompt: prompt, systemMessageMode: .system)
            Issue.record("Expected UnsupportedFunctionalityError")
        } catch let error as UnsupportedFunctionalityError {
            #expect(error.functionality == "audio file parts with URLs")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("audio wav file part converted to input_audio")
    func audioWavFilePartConverted() throws {
        let filePart = LanguageModelV3FilePart(
            data: .base64("AAECAw=="),
            mediaType: "audio/wav"
        )
        let prompt: LanguageModelV3Prompt = [
            .user(content: [.file(filePart)], providerOptions: nil)
        ]
        let result = try OpenAIChatMessagesConverter.convert(prompt: prompt, systemMessageMode: .system)

        guard case .object(let message) = result.messages.first else {
            Issue.record("Expected object message")
            return
        }
        guard case .array(let parts)? = message["content"], parts.count == 1 else {
            Issue.record("Expected single content part")
            return
        }
        guard case .object(let audioPart) = parts.first else {
            Issue.record("Expected object part")
            return
        }
        #expect(audioPart["type"] == .string("input_audio"))
        if case .object(let payload)? = audioPart["input_audio"] {
            #expect(payload["data"] == .string("AAECAw=="))
            #expect(payload["format"] == .string("wav"))
        } else {
            Issue.record("Expected input_audio payload")
        }
    }

    @Test("audio mpeg file part converted to input_audio")
    func audioMpegFilePartConverted() throws {
        let filePart = LanguageModelV3FilePart(
            data: .base64("AAECAw=="),
            mediaType: "audio/mpeg"
        )
        let prompt: LanguageModelV3Prompt = [
            .user(content: [.file(filePart)], providerOptions: nil)
        ]
        let result = try OpenAIChatMessagesConverter.convert(prompt: prompt, systemMessageMode: .system)

        guard case .object(let message) = result.messages.first else {
            Issue.record("Expected object message")
            return
        }
        guard case .array(let parts)? = message["content"], parts.count == 1 else {
            Issue.record("Expected single content part")
            return
        }
        if case .object(let audioPart) = parts.first,
           case .object(let payload)? = audioPart["input_audio"] {
            #expect(payload["format"] == .string("mp3"))
        } else {
            Issue.record("Expected input_audio payload")
        }
    }

    // Port of convert-to-openai-chat-messages.test.ts: "should add audio content for audio/mp3 file parts"
    @Test("audio mp3 file part converted to input_audio")
    func audioMp3FilePartConverted() throws {
        let filePart = LanguageModelV3FilePart(
            data: .base64("AAECAw=="),
            mediaType: "audio/mp3"  // not official but sometimes used
        )
        let prompt: LanguageModelV3Prompt = [
            .user(content: [.file(filePart)], providerOptions: nil)
        ]
        let result = try OpenAIChatMessagesConverter.convert(prompt: prompt, systemMessageMode: .system)

        guard case .object(let message) = result.messages.first else {
            Issue.record("Expected object message")
            return
        }
        guard case .array(let parts)? = message["content"], parts.count == 1 else {
            Issue.record("Expected single content part")
            return
        }
        if case .object(let audioPart) = parts.first,
           case .object(let payload)? = audioPart["input_audio"] {
            #expect(payload["format"] == .string("mp3"))
        } else {
            Issue.record("Expected input_audio payload")
        }
    }

    @Test("pdf base64 file part converted to file data")
    func pdfBase64FilePartConverted() throws {
        let filePart = LanguageModelV3FilePart(
            data: .base64("AQIDBAU="),
            mediaType: "application/pdf",
            filename: "document.pdf"
        )
        let prompt: LanguageModelV3Prompt = [
            .user(content: [.file(filePart)], providerOptions: nil)
        ]

        let result = try OpenAIChatMessagesConverter.convert(prompt: prompt, systemMessageMode: .system)

        guard case .object(let message) = result.messages.first else {
            Issue.record("Expected object message")
            return
        }
        guard case .array(let parts)? = message["content"], parts.count == 1 else {
            Issue.record("Expected single content part")
            return
        }
        if case .object(let part) = parts.first,
           case .object(let fileObject)? = part["file"] {
            #expect(fileObject["filename"] == .string("document.pdf"))
            #expect(fileObject["file_data"] == .string("data:application/pdf;base64,AQIDBAU="))
        } else {
            Issue.record("Expected file payload")
        }
    }

    @Test("pdf binary data converted to file data")
    func pdfBinaryDataConverted() throws {
        let filePart = LanguageModelV3FilePart(
            data: .data(Data([1, 2, 3, 4, 5])),
            mediaType: "application/pdf",
            filename: "document.pdf"
        )
        let prompt: LanguageModelV3Prompt = [
            .user(content: [.file(filePart)], providerOptions: nil)
        ]

        let result = try OpenAIChatMessagesConverter.convert(prompt: prompt, systemMessageMode: .system)

        guard case .object(let message) = result.messages.first,
              case .array(let parts)? = message["content"],
              case .object(let part) = parts.first,
              case .object(let fileObject)? = part["file"] else {
            Issue.record("Unexpected message structure")
            return
        }

        #expect(fileObject["file_data"] == .string("data:application/pdf;base64,AQIDBAU="))
    }

    @Test("pdf file id preserved")
    func pdfFileIdPreserved() throws {
        let filePart = LanguageModelV3FilePart(
            data: .base64("file-pdf-12345"),
            mediaType: "application/pdf"
        )
        let prompt: LanguageModelV3Prompt = [
            .user(content: [.file(filePart)], providerOptions: nil)
        ]

        let result = try OpenAIChatMessagesConverter.convert(prompt: prompt, systemMessageMode: .system)

        guard case .object(let message) = result.messages.first,
              case .array(let parts)? = message["content"],
              case .object(let part) = parts.first,
              case .object(let fileObject)? = part["file"] else {
            Issue.record("Unexpected message structure")
            return
        }

        #expect(fileObject["file_id"] == .string("file-pdf-12345"))
    }

    @Test("pdf default filename when missing")
    func pdfDefaultFilenameWhenMissing() throws {
        let filePart = LanguageModelV3FilePart(
            data: .base64("AQIDBAU="),
            mediaType: "application/pdf"
        )
        let prompt: LanguageModelV3Prompt = [
            .user(content: [.file(filePart)], providerOptions: nil)
        ]

        let result = try OpenAIChatMessagesConverter.convert(prompt: prompt, systemMessageMode: .system)

        guard case .object(let message) = result.messages.first,
              case .array(let parts)? = message["content"],
              case .object(let part) = parts.first,
              case .object(let fileObject)? = part["file"] else {
            Issue.record("Unexpected message structure")
            return
        }

        #expect(fileObject["filename"] == .string("part-0.pdf"))
    }

    @Test("pdf file part with URL throws")
    func pdfFilePartWithURLThrows() throws {
        let filePart = LanguageModelV3FilePart(
            data: .url(URL(string: "https://example.com/document.pdf")!),
            mediaType: "application/pdf"
        )
        let prompt: LanguageModelV3Prompt = [
            .user(content: [.file(filePart)], providerOptions: nil)
        ]

        do {
            _ = try OpenAIChatMessagesConverter.convert(prompt: prompt, systemMessageMode: .system)
            Issue.record("Expected UnsupportedFunctionalityError")
        } catch let error as UnsupportedFunctionalityError {
            #expect(error.functionality == "PDF file parts with URLs")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("tool call arguments stringified")
    func toolCallArgumentsStringified() throws {
        let toolCallPart = LanguageModelV3ToolCallPart(
            toolCallId: "quux",
            toolName: "thwomp",
            input: .object(["foo": .string("bar123")])
        )
        let toolResultPart = LanguageModelV3ToolResultPart(
            toolCallId: "quux",
            toolName: "thwomp",
            output: .json(value: .object(["oof": .string("321rab")]))
        )

        let prompt: LanguageModelV3Prompt = [
            .assistant(content: [.toolCall(toolCallPart)], providerOptions: nil),
            .tool(content: [.toolResult(toolResultPart)], providerOptions: nil)
        ]

        let result = try OpenAIChatMessagesConverter.convert(prompt: prompt, systemMessageMode: .system)
        #expect(result.messages.count == 2)

        if case .object(let assistant)? = result.messages.first {
            #expect(assistant["role"] == .string("assistant"))
            #expect(assistant["content"] == .string(""))
            if case .array(let toolCalls)? = assistant["tool_calls"],
               case .object(let payload) = toolCalls.first,
               case .object(let function)? = payload["function"] {
                #expect(function["name"] == .string("thwomp"))
                #expect(function["arguments"] == .string("{\"foo\":\"bar123\"}"))
            } else {
                Issue.record("Expected tool call payload")
            }
        } else {
            Issue.record("Expected assistant message")
        }

        if case .object(let toolMessage)? = result.messages.dropFirst().first {
            #expect(toolMessage["role"] == .string("tool"))
            #expect(toolMessage["tool_call_id"] == .string("quux"))
            #expect(toolMessage["content"] == .string("{\"oof\":\"321rab\"}"))
        } else {
            Issue.record("Expected tool message")
        }
    }

    @Test("tool results map different output types")
    func toolResultsMapDifferentOutputs() throws {
        let textResult = LanguageModelV3ToolResultPart(
            toolCallId: "text-tool",
            toolName: "text-tool",
            output: .text(value: "Hello world")
        )
        let errorResult = LanguageModelV3ToolResultPart(
            toolCallId: "error-tool",
            toolName: "error-tool",
            output: .errorText(value: "Something went wrong")
        )

        let prompt: LanguageModelV3Prompt = [
            .tool(content: [.toolResult(textResult), .toolResult(errorResult)], providerOptions: nil)
        ]

        let result = try OpenAIChatMessagesConverter.convert(prompt: prompt, systemMessageMode: .system)
        #expect(result.messages.count == 2)

        if case .object(let first)? = result.messages.first {
            #expect(first["content"] == .string("Hello world"))
            #expect(first["tool_call_id"] == .string("text-tool"))
        } else {
            Issue.record("Expected first tool message")
        }

        if case .object(let second)? = result.messages.dropFirst().first {
            #expect(second["content"] == .string("Something went wrong"))
            #expect(second["tool_call_id"] == .string("error-tool"))
        } else {
            Issue.record("Expected second tool message")
        }
    }
}
