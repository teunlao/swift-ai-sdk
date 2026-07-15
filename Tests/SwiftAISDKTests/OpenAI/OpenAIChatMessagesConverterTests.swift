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

    @Test("V4 image top-level media types use data URLs and URL values")
    func v4ImageTopLevelMediaTypesUseDataURLsAndURLValues() throws {
        let prompt: LanguageModelV4Prompt = [
            .user(
                content: [
                    .file(.init(
                        data: .base64("iVBORw0KGgo="),
                        mediaType: "image"
                    )),
                    .file(.init(
                        data: .url(URL(string: "https://example.com/x.png")!),
                        mediaType: "image/*"
                    ))
                ],
                providerOptions: nil
            )
        ]

        let result = try OpenAIChatMessagesConverter.convertV4(prompt: prompt, systemMessageMode: .system)

        let expected: [JSONValue] = [
            .object([
                "role": .string("user"),
                "content": .array([
                    .object([
                        "type": .string("image_url"),
                        "image_url": .object([
                            "url": .string("data:image/png;base64,iVBORw0KGgo=")
                        ])
                    ]),
                    .object([
                        "type": .string("image_url"),
                        "image_url": .object([
                            "url": .string("https://example.com/x.png")
                        ])
                    ])
                ])
            ])
        ]

        #expect(result.messages == expected)
    }

    @Test("V4 prompt cache breakpoints map across message content")
    func v4PromptCacheBreakpointsMapAcrossMessageContent() throws {
        let breakpoint: SharedV4ProviderOptions = [
            "openai": [
                "promptCacheBreakpoint": .object(["mode": .string("explicit")])
            ]
        ]
        let prompt: LanguageModelV4Prompt = [
            .system(content: "System", providerOptions: breakpoint),
            .user(content: [
                .text(.init(text: "User", providerOptions: breakpoint))
            ], providerOptions: nil),
            .assistant(content: [
                .text(.init(text: "First", providerOptions: nil)),
                .text(.init(text: "Second", providerOptions: breakpoint))
            ], providerOptions: nil),
            .tool(content: [
                .toolResult(.init(
                    toolCallId: "call-1",
                    toolName: "lookup",
                    output: .text(value: "Result", providerOptions: breakpoint)
                ))
            ], providerOptions: nil)
        ]

        let result = try OpenAIChatMessagesConverter.convertV4(prompt: prompt, systemMessageMode: .developer)
        let explicit: JSONValue = .object(["mode": .string("explicit")])

        guard case .object(let system) = result.messages[0],
              case .array(let systemContent)? = system["content"],
              case .object(let systemText)? = systemContent.first,
              case .object(let user) = result.messages[1],
              case .array(let userContent)? = user["content"],
              case .object(let userText)? = userContent.first,
              case .object(let assistant) = result.messages[2],
              case .array(let assistantContent)? = assistant["content"],
              case .object(let assistantSecond) = assistantContent.last,
              case .object(let tool) = result.messages[3],
              case .array(let toolContent)? = tool["content"],
              case .object(let toolText)? = toolContent.first else {
            Issue.record("Expected cache-aware OpenAI chat content arrays")
            return
        }

        #expect(system["role"] == .string("developer"))
        #expect(systemText["prompt_cache_breakpoint"] == explicit)
        #expect(userText["prompt_cache_breakpoint"] == explicit)
        #expect(assistantContent.count == 2)
        #expect(assistantSecond["prompt_cache_breakpoint"] == explicit)
        #expect(toolText["prompt_cache_breakpoint"] == explicit)
    }

    @Test("V4 provider reference file parts map to OpenAI file ids")
    func v4ProviderReferenceFilePartsMapToOpenAIFileIds() throws {
        let prompt: LanguageModelV4Prompt = [
            .user(
                content: [
                    .file(.init(
                        data: .reference(["openai": "file-img-12345"]),
                        mediaType: "image/png"
                    ))
                ],
                providerOptions: nil
            )
        ]

        let result = try OpenAIChatMessagesConverter.convertV4(prompt: prompt, systemMessageMode: .system)

        guard case .object(let message)? = result.messages.first,
              case .array(let parts)? = message["content"],
              case .object(let part)? = parts.first,
              case .object(let file)? = part["file"] else {
            Issue.record("Expected V4 provider reference file content")
            return
        }

        #expect(part["type"] == .string("file"))
        #expect(file["file_id"] == .string("file-img-12345"))
    }

    @Test("V4 provider reference missing OpenAI id throws")
    func v4ProviderReferenceMissingOpenAIIdThrows() throws {
        let prompt: LanguageModelV4Prompt = [
            .user(
                content: [
                    .file(.init(
                        data: .reference(["anthropic": "file-xyz"]),
                        mediaType: "application/pdf"
                    ))
                ],
                providerOptions: nil
            )
        ]

        do {
            _ = try OpenAIChatMessagesConverter.convertV4(prompt: prompt, systemMessageMode: .system)
            Issue.record("Expected NoSuchProviderReferenceError")
        } catch let error as NoSuchProviderReferenceError {
            #expect(error.provider == "openai")
            #expect(error.reference == ["anthropic": "file-xyz"])
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("V4 top-level application URL file parts require inline bytes")
    func v4TopLevelApplicationURLFilePartsRequireInlineBytes() throws {
        let prompt: LanguageModelV4Prompt = [
            .user(
                content: [
                    .file(.init(
                        data: .url(URL(string: "https://example.com/x.pdf")!),
                        mediaType: "application"
                    ))
                ],
                providerOptions: nil
            )
        ]

        do {
            _ = try OpenAIChatMessagesConverter.convertV4(prompt: prompt, systemMessageMode: .system)
            Issue.record("Expected UnsupportedFunctionalityError")
        } catch let error as UnsupportedFunctionalityError {
            #expect(error.functionality.contains("media type \"application\""))
            #expect(error.functionality.contains("not passed as inline bytes"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("V4 assistant tool calls without text use null content")
    func v4AssistantToolCallsWithoutTextUseNullContent() throws {
        let prompt: LanguageModelV4Prompt = [
            .assistant(
                content: [
                    .toolCall(.init(
                        toolCallId: "quux",
                        toolName: "thwomp",
                        input: .object(["foo": .string("bar123")])
                    ))
                ],
                providerOptions: nil
            )
        ]

        let result = try OpenAIChatMessagesConverter.convertV4(prompt: prompt, systemMessageMode: .system)

        guard case .object(let message)? = result.messages.first else {
            Issue.record("Expected assistant message")
            return
        }

        #expect(message["content"] == .null)
        guard case .array(let toolCalls)? = message["tool_calls"],
              case .object(let toolCall)? = toolCalls.first,
              case .object(let function)? = toolCall["function"] else {
            Issue.record("Expected tool call payload")
            return
        }

        #expect(function["arguments"] == .string("{\"foo\":\"bar123\"}"))
    }

    @Test("V4 execution denied tool result uses upstream default text")
    func v4ExecutionDeniedToolResultUsesUpstreamDefaultText() throws {
        let prompt: LanguageModelV4Prompt = [
            .tool(
                content: [
                    .toolResult(.init(
                        toolCallId: "denied-tool",
                        toolName: "denied-tool",
                        output: .executionDenied(reason: nil)
                    ))
                ],
                providerOptions: nil
            )
        ]

        let result = try OpenAIChatMessagesConverter.convertV4(prompt: prompt, systemMessageMode: .system)

        guard case .object(let message)? = result.messages.first else {
            Issue.record("Expected tool message")
            return
        }

        #expect(message["content"] == .string("Tool call execution denied."))
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

    @Test("tool result json string fragment is serialized without crashing")
    func toolResultJSONStringFragmentDoesNotCrash() throws {
        let toolResultPart = LanguageModelV3ToolResultPart(
            toolCallId: "string-tool",
            toolName: "string-tool",
            output: .json(value: .string("plain-string"))
        )

        let prompt: LanguageModelV3Prompt = [
            .tool(content: [.toolResult(toolResultPart)], providerOptions: nil)
        ]

        let result = try OpenAIChatMessagesConverter.convert(prompt: prompt, systemMessageMode: .system)
        #expect(result.messages.count == 1)

        guard case .object(let message)? = result.messages.first else {
            Issue.record("Expected tool message")
            return
        }

        #expect(message["role"] == .string("tool"))
        #expect(message["tool_call_id"] == .string("string-tool"))
        #expect(message["content"] == .string("\"plain-string\""))
    }

    @Test("tool result json number fragment is serialized without crashing")
    func toolResultJSONNumberFragmentDoesNotCrash() throws {
        let toolResultPart = LanguageModelV3ToolResultPart(
            toolCallId: "number-tool",
            toolName: "number-tool",
            output: .json(value: .number(42))
        )

        let prompt: LanguageModelV3Prompt = [
            .tool(content: [.toolResult(toolResultPart)], providerOptions: nil)
        ]

        let result = try OpenAIChatMessagesConverter.convert(prompt: prompt, systemMessageMode: .system)
        #expect(result.messages.count == 1)

        guard case .object(let message)? = result.messages.first else {
            Issue.record("Expected tool message")
            return
        }

        #expect(message["role"] == .string("tool"))
        #expect(message["tool_call_id"] == .string("number-tool"))
        #expect(message["content"] == .string("42"))
    }

    @Test("tool result json null fragment is serialized without crashing")
    func toolResultJSONNullFragmentDoesNotCrash() throws {
        let toolResultPart = LanguageModelV3ToolResultPart(
            toolCallId: "null-tool",
            toolName: "null-tool",
            output: .errorJson(value: .null)
        )

        let prompt: LanguageModelV3Prompt = [
            .tool(content: [.toolResult(toolResultPart)], providerOptions: nil)
        ]

        let result = try OpenAIChatMessagesConverter.convert(prompt: prompt, systemMessageMode: .system)
        #expect(result.messages.count == 1)

        guard case .object(let message)? = result.messages.first else {
            Issue.record("Expected tool message")
            return
        }

        #expect(message["role"] == .string("tool"))
        #expect(message["tool_call_id"] == .string("null-tool"))
        #expect(message["content"] == .string("null"))
    }
}
