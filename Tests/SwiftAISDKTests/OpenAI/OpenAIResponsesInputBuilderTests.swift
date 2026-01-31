import Foundation
import Testing
import AISDKProvider
@testable import OpenAIProvider

@Suite("OpenAIResponsesInputBuilder")
struct OpenAIResponsesInputBuilderTests {
    // MARK: - System Messages

    @Test("should convert system messages to system role")
    func systemMessagesToSystemRole() async throws {
        let prompt: LanguageModelV3Prompt = [
            .system(content: "Hello", providerOptions: nil)
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            store: true,
            hasLocalShellTool: false
        )

        let expected: OpenAIResponsesInput = [
            .object([
                "role": .string("system"),
                "content": .string("Hello")
            ])
        ]

        #expect(result.input == expected)
    }

    @Test("should convert system messages to developer role")
    func systemMessagesToDeveloperRole() async throws {
        let prompt: LanguageModelV3Prompt = [
            .system(content: "Hello", providerOptions: nil)
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .developer,
            store: true,
            hasLocalShellTool: false
        )

        let expected: OpenAIResponsesInput = [
            .object([
                "role": .string("developer"),
                "content": .string("Hello")
            ])
        ]

        #expect(result.input == expected)
    }

    @Test("should remove system messages")
    func removeSystemMessages() async throws {
        let prompt: LanguageModelV3Prompt = [
            .system(content: "Hello", providerOptions: nil)
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .remove,
            store: true,
            hasLocalShellTool: false
        )

        #expect(result.input.isEmpty)
    }

    // MARK: - User Messages - Images

    @Test("should convert messages with only a text part to a string content")
    func userMessageTextPartToStringContent() async throws {
        let prompt: LanguageModelV3Prompt = [
            .user(
                content: [.text(LanguageModelV3TextPart(text: "Hello"))],
                providerOptions: nil
            )
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            store: true,
            hasLocalShellTool: false
        )

        let expected: OpenAIResponsesInput = [
            .object([
                "role": .string("user"),
                "content": .array([
                    .object([
                        "type": .string("input_text"),
                        "text": .string("Hello")
                    ])
                ])
            ])
        ]

        #expect(result.input == expected)
    }

    @Test("should convert messages with image parts using URL")
    func userImageUsingURL() async throws {
        let prompt: LanguageModelV3Prompt = [
            .user(
                content: [
                    .text(LanguageModelV3TextPart(text: "Hello")),
                    .file(LanguageModelV3FilePart(
                        data: .url(URL(string: "https://example.com/image.jpg")!),
                        mediaType: "image/*",
                        filename: nil,
                        providerOptions: nil
                    ))
                ],
                providerOptions: nil
            )
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            store: true,
            hasLocalShellTool: false
        )

        let expected: OpenAIResponsesInput = [
            .object([
                "role": .string("user"),
                "content": .array([
                    .object([
                        "type": .string("input_text"),
                        "text": .string("Hello")
                    ]),
                    .object([
                        "type": .string("input_image"),
                        "image_url": .string("https://example.com/image.jpg")
                    ])
                ])
            ])
        ]

        #expect(result.input == expected)
    }

    @Test("should convert messages with image parts using binary data")
    func userImageUsingBinaryData() async throws {
        let prompt: LanguageModelV3Prompt = [
            .user(
                content: [
                    .file(LanguageModelV3FilePart(
                        data: .base64("AAECAw=="),
                        mediaType: "image/png",
                        filename: nil,
                        providerOptions: nil
                    ))
                ],
                providerOptions: nil
            )
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            store: true,
            hasLocalShellTool: false
        )

        let expected: OpenAIResponsesInput = [
            .object([
                "role": .string("user"),
                "content": .array([
                    .object([
                        "type": .string("input_image"),
                        "image_url": .string("data:image/png;base64,AAECAw==")
                    ])
                ])
            ])
        ]

        #expect(result.input == expected)
    }

    @Test("should convert messages with image parts using Uint8Array")
    func userImageUsingUint8Array() async throws {
        let data = Data([0, 1, 2, 3])
        let prompt: LanguageModelV3Prompt = [
            .user(
                content: [
                    .file(LanguageModelV3FilePart(
                        data: .data(data),
                        mediaType: "image/png",
                        filename: nil,
                        providerOptions: nil
                    ))
                ],
                providerOptions: nil
            )
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            store: true,
            hasLocalShellTool: false
        )

        let expected: OpenAIResponsesInput = [
            .object([
                "role": .string("user"),
                "content": .array([
                    .object([
                        "type": .string("input_image"),
                        "image_url": .string("data:image/png;base64,AAECAw==")
                    ])
                ])
            ])
        ]

        #expect(result.input == expected)
    }

    @Test("should convert messages with image parts using file_id")
    func userImageUsingFileId() async throws {
        let prompt: LanguageModelV3Prompt = [
            .user(
                content: [
                    .file(LanguageModelV3FilePart(
                        data: .base64("file-12345"),
                        mediaType: "image/png",
                        filename: nil,
                        providerOptions: nil
                    ))
                ],
                providerOptions: nil
            )
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            fileIdPrefixes: ["file-"],
            store: true,
            hasLocalShellTool: false
        )

        let expected: OpenAIResponsesInput = [
            .object([
                "role": .string("user"),
                "content": .array([
                    .object([
                        "type": .string("input_image"),
                        "file_id": .string("file-12345")
                    ])
                ])
            ])
        ]

        #expect(result.input == expected)
    }

    @Test("should use default mime type for binary images")
    func defaultMimeTypeForBinaryImages() async throws {
        let prompt: LanguageModelV3Prompt = [
            .user(
                content: [
                    .file(LanguageModelV3FilePart(
                        data: .base64("AAECAw=="),
                        mediaType: "image/*",
                        filename: nil,
                        providerOptions: nil
                    ))
                ],
                providerOptions: nil
            )
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            store: true,
            hasLocalShellTool: false
        )

        let expected: OpenAIResponsesInput = [
            .object([
                "role": .string("user"),
                "content": .array([
                    .object([
                        "type": .string("input_image"),
                        "image_url": .string("data:image/jpeg;base64,AAECAw==")
                    ])
                ])
            ])
        ]

        #expect(result.input == expected)
    }

    @Test("should add image detail when specified through extension")
    func imageDetailWhenSpecifiedThroughExtension() async throws {
        let filePart = LanguageModelV3FilePart(
            data: .base64("AAECAw=="),
            mediaType: "image/png",
            filename: nil,
            providerOptions: [
                "openai": [
                    "imageDetail": .string("low")
                ]
            ]
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.file(filePart)], providerOptions: nil)
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            store: true,
            hasLocalShellTool: false
        )

        let expected: OpenAIResponsesInput = [
            .object([
                "role": .string("user"),
                "content": .array([
                    .object([
                        "type": .string("input_image"),
                        "image_url": .string("data:image/png;base64,AAECAw=="),
                        "detail": .string("low")
                    ])
                ])
            ])
        ]

        #expect(result.input == expected)
    }

    @Test("should convert image parts with assistant- prefix")
    func imageWithAssistantPrefix() async throws {
        let prompt: LanguageModelV3Prompt = [
            .user(
                content: [
                    .file(LanguageModelV3FilePart(
                        data: .base64("assistant-img-abc123"),
                        mediaType: "image/png",
                        filename: nil,
                        providerOptions: nil
                    ))
                ],
                providerOptions: nil
            )
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            fileIdPrefixes: ["assistant-"],
            store: true,
            hasLocalShellTool: false
        )

        let expected: OpenAIResponsesInput = [
            .object([
                "role": .string("user"),
                "content": .array([
                    .object([
                        "type": .string("input_image"),
                        "file_id": .string("assistant-img-abc123")
                    ])
                ])
            ])
        ]

        #expect(result.input == expected)
    }

    @Test("should support multiple file ID prefixes")
    func multipleFileIdPrefixes() async throws {
        let prompt: LanguageModelV3Prompt = [
            .user(
                content: [
                    .file(LanguageModelV3FilePart(
                        data: .base64("assistant-img-abc123"),
                        mediaType: "image/png",
                        filename: nil,
                        providerOptions: nil
                    )),
                    .file(LanguageModelV3FilePart(
                        data: .base64("file-pdf-xyz789"),
                        mediaType: "application/pdf",
                        filename: nil,
                        providerOptions: nil
                    ))
                ],
                providerOptions: nil
            )
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            fileIdPrefixes: ["assistant-", "file-"],
            store: true,
            hasLocalShellTool: false
        )

        let expected: OpenAIResponsesInput = [
            .object([
                "role": .string("user"),
                "content": .array([
                    .object([
                        "type": .string("input_image"),
                        "file_id": .string("assistant-img-abc123")
                    ]),
                    .object([
                        "type": .string("input_file"),
                        "file_id": .string("file-pdf-xyz789")
                    ])
                ])
            ])
        ]

        #expect(result.input == expected)
    }

    // MARK: - User Messages - PDF Files

    @Test("should convert messages with PDF file parts")
    func userPDFFileParts() async throws {
        let prompt: LanguageModelV3Prompt = [
            .user(
                content: [
                    .file(LanguageModelV3FilePart(
                        data: .base64("AQIDBAU="),
                        mediaType: "application/pdf",
                        filename: "document.pdf",
                        providerOptions: nil
                    ))
                ],
                providerOptions: nil
            )
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            store: true,
            hasLocalShellTool: false
        )

        let expected: OpenAIResponsesInput = [
            .object([
                "role": .string("user"),
                "content": .array([
                    .object([
                        "type": .string("input_file"),
                        "filename": .string("document.pdf"),
                        "file_data": .string("data:application/pdf;base64,AQIDBAU=")
                    ])
                ])
            ])
        ]

        #expect(result.input == expected)
    }

    @Test("should convert messages with PDF file parts using file_id")
    func userPDFFileUsingFileId() async throws {
        let prompt: LanguageModelV3Prompt = [
            .user(
                content: [
                    .file(LanguageModelV3FilePart(
                        data: .base64("file-pdf-12345"),
                        mediaType: "application/pdf",
                        filename: nil,
                        providerOptions: nil
                    ))
                ],
                providerOptions: nil
            )
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            fileIdPrefixes: ["file-"],
            store: true,
            hasLocalShellTool: false
        )

        let expected: OpenAIResponsesInput = [
            .object([
                "role": .string("user"),
                "content": .array([
                    .object([
                        "type": .string("input_file"),
                        "file_id": .string("file-pdf-12345")
                    ])
                ])
            ])
        ]

        #expect(result.input == expected)
    }

    @Test("should use default filename for PDF file parts when not provided")
    func defaultFilenameForPDF() async throws {
        let prompt: LanguageModelV3Prompt = [
            .user(
                content: [
                    .file(LanguageModelV3FilePart(
                        data: .base64("AQIDBAU="),
                        mediaType: "application/pdf",
                        filename: nil,
                        providerOptions: nil
                    ))
                ],
                providerOptions: nil
            )
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            store: true,
            hasLocalShellTool: false
        )

        let expected: OpenAIResponsesInput = [
            .object([
                "role": .string("user"),
                "content": .array([
                    .object([
                        "type": .string("input_file"),
                        "filename": .string("part-0.pdf"),
                        "file_data": .string("data:application/pdf;base64,AQIDBAU=")
                    ])
                ])
            ])
        ]

        #expect(result.input == expected)
    }

    @Test("should throw error for unsupported file types")
    func unsupportedFileTypeError() async throws {
        let prompt: LanguageModelV3Prompt = [
            .user(
                content: [
                    .file(LanguageModelV3FilePart(
                        data: .base64("AQIDBAU="),
                        mediaType: "text/plain",
                        filename: nil,
                        providerOptions: nil
                    ))
                ],
                providerOptions: nil
            )
        ]

        await #expect(throws: Error.self) {
            try await OpenAIResponsesInputBuilder.makeInput(
                prompt: prompt,
                systemMessageMode: .system,
                store: true,
                hasLocalShellTool: false
            )
        }
    }

    @Test("should convert PDF file parts with URL to input_file with file_url")
    func pdfWithURLToFileUrl() async throws {
        let prompt: LanguageModelV3Prompt = [
            .user(
                content: [
                    .file(LanguageModelV3FilePart(
                        data: .url(URL(string: "https://example.com/document.pdf")!),
                        mediaType: "application/pdf",
                        filename: nil,
                        providerOptions: nil
                    ))
                ],
                providerOptions: nil
            )
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            store: true,
            hasLocalShellTool: false
        )

        let expected: OpenAIResponsesInput = [
            .object([
                "role": .string("user"),
                "content": .array([
                    .object([
                        "type": .string("input_file"),
                        "file_url": .string("https://example.com/document.pdf")
                    ])
                ])
            ])
        ]

        #expect(result.input == expected)
    }

    @Test("should convert PDF parts with assistant- prefix")
    func pdfWithAssistantPrefix() async throws {
        let prompt: LanguageModelV3Prompt = [
            .user(
                content: [
                    .file(LanguageModelV3FilePart(
                        data: .base64("assistant-pdf-abc123"),
                        mediaType: "application/pdf",
                        filename: nil,
                        providerOptions: nil
                    ))
                ],
                providerOptions: nil
            )
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            fileIdPrefixes: ["assistant-"],
            store: true,
            hasLocalShellTool: false
        )

        let expected: OpenAIResponsesInput = [
            .object([
                "role": .string("user"),
                "content": .array([
                    .object([
                        "type": .string("input_file"),
                        "file_id": .string("assistant-pdf-abc123")
                    ])
                ])
            ])
        ]

        #expect(result.input == expected)
    }

    @Test("should treat all file data as base64 when fileIdPrefixes is undefined")
    func fileIdPrefixesUndefinedBehavior() async throws {
        let prompt: LanguageModelV3Prompt = [
            .user(
                content: [
                    .file(LanguageModelV3FilePart(
                        data: .base64("file-12345"),
                        mediaType: "image/png",
                        filename: nil,
                        providerOptions: nil
                    )),
                    .file(LanguageModelV3FilePart(
                        data: .base64("assistant-abc123"),
                        mediaType: "application/pdf",
                        filename: "test.pdf",
                        providerOptions: nil
                    ))
                ],
                providerOptions: nil
            )
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            fileIdPrefixes: nil,
            store: true,
            hasLocalShellTool: false
        )

        let expected: OpenAIResponsesInput = [
            .object([
                "role": .string("user"),
                "content": .array([
                    .object([
                        "type": .string("input_image"),
                        "image_url": .string("data:image/png;base64,file-12345")
                    ]),
                    .object([
                        "type": .string("input_file"),
                        "filename": .string("test.pdf"),
                        "file_data": .string("data:application/pdf;base64,assistant-abc123")
                    ])
                ])
            ])
        ]

        #expect(result.input == expected)
    }

    @Test("should handle empty fileIdPrefixes array")
    func emptyFileIdPrefixesArray() async throws {
        let prompt: LanguageModelV3Prompt = [
            .user(
                content: [
                    .file(LanguageModelV3FilePart(
                        data: .base64("file-12345"),
                        mediaType: "image/png",
                        filename: nil,
                        providerOptions: nil
                    ))
                ],
                providerOptions: nil
            )
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            fileIdPrefixes: [],
            store: true,
            hasLocalShellTool: false
        )

        let expected: OpenAIResponsesInput = [
            .object([
                "role": .string("user"),
                "content": .array([
                    .object([
                        "type": .string("input_image"),
                        "image_url": .string("data:image/png;base64,file-12345")
                    ])
                ])
            ])
        ]

        #expect(result.input == expected)
    }

    // MARK: - Previously implemented tests

    @Test("store=false skips provider tool results and produces warning")
    func storeFalseSkipsProviderToolResults() async throws {
        let prompt: LanguageModelV3Prompt = [
            .assistant(
                content: [
                    .toolResult(
                        LanguageModelV3ToolResultPart(
                            toolCallId: "ws_call",
                            toolName: "web_search",
                            output: .json(value: .array([
                                .object(["url": .string("https://example.com")])
                            ]))
                        )
                    )
                ],
                providerOptions: nil
            )
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            store: false,
            hasLocalShellTool: false
        )

        #expect(result.input.isEmpty)
        #expect(
            result.warnings == [
                .other(message: "Results for OpenAI tool web_search are not sent to the API when store is false")
            ]
        )
    }

    // MARK: - Assistant Messages - Basic

    @Test("should convert messages with only a text part to a string content")
    func assistantMessageTextPartToStringContent() async throws {
        let prompt: LanguageModelV3Prompt = [
            .assistant(
                content: [.text(LanguageModelV3TextPart(text: "Hello"))],
                providerOptions: nil
            )
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            store: true,
            hasLocalShellTool: false
        )

        let expected: OpenAIResponsesInput = [
            .object([
                "role": .string("assistant"),
                "content": .array([
                    .object([
                        "type": .string("output_text"),
                        "text": .string("Hello")
                    ])
                ])
            ])
        ]

        #expect(result.input == expected)
    }

    @Test("should convert messages with tool call parts")
    func assistantMessagesWithToolCallParts() async throws {
        let prompt: LanguageModelV3Prompt = [
            .assistant(
                content: [
                    .text(LanguageModelV3TextPart(text: "I will search for that information.")),
                    .toolCall(LanguageModelV3ToolCallPart(
                        toolCallId: "call_123",
                        toolName: "search",
                        input: .object(["query": .string("weather in San Francisco")])
                    ))
                ],
                providerOptions: nil
            )
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            store: true,
            hasLocalShellTool: false
        )

        let expected: OpenAIResponsesInput = [
            .object([
                "role": .string("assistant"),
                "content": .array([
                    .object([
                        "type": .string("output_text"),
                        "text": .string("I will search for that information.")
                    ])
                ])
            ]),
            .object([
                "type": .string("function_call"),
                "call_id": .string("call_123"),
                "name": .string("search"),
                "arguments": .string("{\"query\":\"weather in San Francisco\"}")
            ])
        ]

        #expect(result.input == expected)
    }

    @Test("should convert messages with tool call parts that have ids")
    func assistantToolCallWithIds() async throws {
        let textPart = LanguageModelV3TextPart(
            text: "I will search for that information.",
            providerOptions: ["openai": ["itemId": .string("id_123")]]
        )

        let toolCallPart = LanguageModelV3ToolCallPart(
            toolCallId: "call_123",
            toolName: "search",
            input: .object(["query": .string("weather in San Francisco")]),
            providerOptions: ["openai": ["itemId": .string("id_456")]]
        )

        let prompt: LanguageModelV3Prompt = [
            .assistant(content: [.text(textPart), .toolCall(toolCallPart)], providerOptions: nil)
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            store: true,
            hasLocalShellTool: false
        )

        let expected: OpenAIResponsesInput = [
            .object([
                "type": .string("item_reference"),
                "id": .string("id_123")
            ]),
            .object([
                "type": .string("item_reference"),
                "id": .string("id_456")
            ])
        ]

        #expect(result.input == expected)
    }

    @Test("tool call itemId supports providerMetadata fallback")
    func toolCallItemIdFromProviderMetadataFallback() async throws {
        let toolCallPart = LanguageModelV3ToolCallPart(
            toolCallId: "call_123",
            toolName: "search",
            input: .object(["query": .string("weather in San Francisco")]),
            providerMetadata: ["openai": ["itemId": .string("id_456")]],
            providerOptions: nil
        )

        let prompt: LanguageModelV3Prompt = [
            .assistant(content: [.toolCall(toolCallPart)], providerOptions: nil)
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            store: true,
            hasLocalShellTool: false
        )

        let expected: OpenAIResponsesInput = [
            .object([
                "type": .string("item_reference"),
                "id": .string("id_456")
            ])
        ]

        #expect(result.input == expected)
    }

    @Test("should use item_reference for tool calls with itemId when store=true (pairs with reasoning)")
    func toolCallWithReasoningIdsStoreTrue() async throws {
        let reasoningPart = LanguageModelV3ReasoningPart(
            text: "Thinking step by step",
            providerOptions: [
                "openai": [
                    "itemId": .string("rs_123")
                ]
            ]
        )

        let toolCallPart = LanguageModelV3ToolCallPart(
            toolCallId: "call_123",
            toolName: "search",
            input: .object(["query": .string("weather in San Francisco")]),
            providerOptions: [
                "openai": [
                    "itemId": .string("fc_456")
                ]
            ]
        )

        let prompt: LanguageModelV3Prompt = [
            .assistant(
                content: [
                    .reasoning(reasoningPart),
                    .toolCall(toolCallPart)
                ],
                providerOptions: nil
            )
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            store: true,
            hasLocalShellTool: false
        )

        let expected: OpenAIResponsesInput = [
            .object([
                "type": .string("item_reference"),
                "id": .string("rs_123")
            ]),
            .object([
                "type": .string("item_reference"),
                "id": .string("fc_456")
            ])
        ]

        #expect(result.input == expected)
    }

    @Test("hasConversation=true skips assistant text parts with itemId")
    func hasConversationSkipsAssistantTextPartsWithItemId() async throws {
        let textPart = LanguageModelV3TextPart(
            text: "Hello",
            providerOptions: ["openai": ["itemId": .string("id_123")]]
        )

        let prompt: LanguageModelV3Prompt = [
            .assistant(content: [.text(textPart)], providerOptions: nil)
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            store: true,
            hasConversation: true,
            hasLocalShellTool: false
        )

        #expect(result.input.isEmpty)
        #expect(result.warnings.isEmpty)
    }

    @Test("hasConversation=true skips assistant tool-call parts with itemId")
    func hasConversationSkipsAssistantToolCallPartsWithItemId() async throws {
        let toolCallPart = LanguageModelV3ToolCallPart(
            toolCallId: "call_123",
            toolName: "search",
            input: .object(["query": .string("weather")]),
            providerOptions: ["openai": ["itemId": .string("fc_456")]]
        )

        let prompt: LanguageModelV3Prompt = [
            .assistant(content: [.toolCall(toolCallPart)], providerOptions: nil)
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            store: true,
            hasConversation: true,
            hasLocalShellTool: false
        )

        #expect(result.input.isEmpty)
        #expect(result.warnings.isEmpty)
    }

    @Test("execution-denied tool results are skipped")
    func executionDeniedToolResultsAreSkipped() async throws {
        let prompt: LanguageModelV3Prompt = [
            .assistant(
                content: [
                    .toolResult(
                        LanguageModelV3ToolResultPart(
                            toolCallId: "tool_call_1",
                            toolName: "web_search",
                            output: .executionDenied(reason: "Denied")
                        )
                    )
                ],
                providerOptions: nil
            )
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            store: true,
            hasLocalShellTool: false
        )

        #expect(result.input.isEmpty)
        #expect(result.warnings.isEmpty)
    }

    @Test("store=true uses tool result itemId when available")
    func storeTrueToolResultUsesItemIdWhenAvailable() async throws {
        let toolResult = LanguageModelV3ToolResultPart(
            toolCallId: "call_1",
            toolName: "web_search",
            output: .json(value: .array([])),
            providerOptions: ["openai": ["itemId": .string("tr_123")]]
        )

        let prompt: LanguageModelV3Prompt = [
            .assistant(content: [.toolResult(toolResult)], providerOptions: nil)
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            store: true,
            hasLocalShellTool: false
        )

        let expected: OpenAIResponsesInput = [
            .object([
                "type": .string("item_reference"),
                "id": .string("tr_123")
            ])
        ]

        #expect(result.input == expected)
    }

    @Test("should convert multiple tool call parts in a single message")
    func multipleToolCallPartsInSingleMessage() async throws {
        let prompt: LanguageModelV3Prompt = [
            .assistant(
                content: [
                    .toolCall(LanguageModelV3ToolCallPart(
                        toolCallId: "call_123",
                        toolName: "search",
                        input: .object(["query": .string("weather in San Francisco")])
                    )),
                    .toolCall(LanguageModelV3ToolCallPart(
                        toolCallId: "call_456",
                        toolName: "calculator",
                        input: .object(["expression": .string("2 + 2")])
                    ))
                ],
                providerOptions: nil
            )
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            store: true,
            hasLocalShellTool: false
        )

        let expected: OpenAIResponsesInput = [
            .object([
                "type": .string("function_call"),
                "call_id": .string("call_123"),
                "name": .string("search"),
                "arguments": .string("{\"query\":\"weather in San Francisco\"}")
            ]),
            .object([
                "type": .string("function_call"),
                "call_id": .string("call_456"),
                "name": .string("calculator"),
                "arguments": .string("{\"expression\":\"2 + 2\"}")
            ])
        ]

        #expect(result.input == expected)
    }

    // MARK: - Assistant Messages - Reasoning (Basic)

    @Test("should convert single reasoning part with text (store: false)")
    func singleReasoningPartWithTextStoreFalse() async throws {
        let prompt: LanguageModelV3Prompt = [
            .assistant(
                content: [
                    .reasoning(LanguageModelV3ReasoningPart(
                        text: "Analyzing the problem step by step",
                        providerOptions: [
                            "openai": [
                                "itemId": .string("reasoning_001")
                            ]
                        ]
                    ))
                ],
                providerOptions: nil
            )
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            store: false,
            hasLocalShellTool: false
        )

        let expected: OpenAIResponsesInput = [
            .object([
                "type": .string("reasoning"),
                "id": .string("reasoning_001"),
                "summary": .array([
                    .object([
                        "type": .string("summary_text"),
                        "text": .string("Analyzing the problem step by step")
                    ])
                ])
            ])
        ]

        #expect(result.input == expected)
        #expect(result.warnings.isEmpty)
    }

    @Test("should convert single reasoning part with encrypted content (store: false)")
    func singleReasoningPartWithEncryptedContentStoreFalse() async throws {
        let prompt: LanguageModelV3Prompt = [
            .assistant(
                content: [
                    .reasoning(LanguageModelV3ReasoningPart(
                        text: "Analyzing the problem step by step",
                        providerOptions: [
                            "openai": [
                                "itemId": .string("reasoning_001"),
                                "reasoningEncryptedContent": .string("encrypted_content_001")
                            ]
                        ]
                    ))
                ],
                providerOptions: nil
            )
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            store: false,
            hasLocalShellTool: false
        )

        let expected: OpenAIResponsesInput = [
            .object([
                "type": .string("reasoning"),
                "id": .string("reasoning_001"),
                "encrypted_content": .string("encrypted_content_001"),
                "summary": .array([
                    .object([
                        "type": .string("summary_text"),
                        "text": .string("Analyzing the problem step by step")
                    ])
                ])
            ])
        ]

        #expect(result.input == expected)
        #expect(result.warnings.isEmpty)
    }

    @Test("should convert single reasoning part with null encrypted content (store: false)")
    func singleReasoningPartWithNullEncryptedContentStoreFalse() async throws {
        let prompt: LanguageModelV3Prompt = [
            .assistant(
                content: [
                    .reasoning(LanguageModelV3ReasoningPart(
                        text: "Analyzing the problem step by step",
                        providerOptions: [
                            "openai": [
                                "itemId": .string("reasoning_001"),
                                "reasoningEncryptedContent": .null
                            ]
                        ]
                    ))
                ],
                providerOptions: nil
            )
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            store: false,
            hasLocalShellTool: false
        )

        #expect(result.input.count == 1)
        guard case .object(let obj) = result.input[0],
              case .string("reasoning") = obj["type"],
              case .string("reasoning_001") = obj["id"],
              case .array(let summary) = obj["summary"] else {
            Issue.record("Unexpected output structure")
            return
        }

        #expect(summary.count == 1)
        #expect(result.warnings.isEmpty)
    }

    // MARK: - Assistant Messages - Reasoning (Empty Text)

    @Test("should create empty summary for initial empty text (store: false)")
    func initialEmptyTextEmptySummaryStoreFalse() async throws {
        let prompt: LanguageModelV3Prompt = [
            .assistant(
                content: [
                    .reasoning(LanguageModelV3ReasoningPart(
                        text: "",
                        providerOptions: [
                            "openai": [
                                "itemId": .string("reasoning_001")
                            ]
                        ]
                    ))
                ],
                providerOptions: nil
            )
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            store: false,
            hasLocalShellTool: false
        )

        let expected: OpenAIResponsesInput = [
            .object([
                "type": .string("reasoning"),
                "id": .string("reasoning_001"),
                "summary": .array([])
            ])
        ]

        #expect(result.input == expected)
        #expect(result.warnings.isEmpty)
    }

    @Test("should create empty summary for initial empty text with encrypted content (store: false)")
    func initialEmptyTextWithEncryptedContentStoreFalse() async throws {
        let prompt: LanguageModelV3Prompt = [
            .assistant(
                content: [
                    .reasoning(LanguageModelV3ReasoningPart(
                        text: "",
                        providerOptions: [
                            "openai": [
                                "itemId": .string("reasoning_001"),
                                "reasoningEncryptedContent": .string("encrypted_content_001")
                            ]
                        ]
                    ))
                ],
                providerOptions: nil
            )
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            store: false,
            hasLocalShellTool: false
        )

        let expected: OpenAIResponsesInput = [
            .object([
                "type": .string("reasoning"),
                "id": .string("reasoning_001"),
                "encrypted_content": .string("encrypted_content_001"),
                "summary": .array([])
            ])
        ]

        #expect(result.input == expected)
        #expect(result.warnings.isEmpty)
    }

    // (Continued in next section - this test is already implemented above)
    // "should warn when appending empty text to existing sequence" is already implemented

    // MARK: - Assistant Messages - Reasoning (Merging and Sequencing)

    @Test("should merge consecutive parts with same reasoning ID (store: false)")
    func mergeConsecutivePartsWithSameReasoningId() async throws {
        let prompt: LanguageModelV3Prompt = [
            .assistant(
                content: [
                    .reasoning(LanguageModelV3ReasoningPart(
                        text: "First reasoning step",
                        providerOptions: ["openai": ["itemId": .string("reasoning_001")]]
                    )),
                    .reasoning(LanguageModelV3ReasoningPart(
                        text: "Second reasoning step",
                        providerOptions: ["openai": ["itemId": .string("reasoning_001")]]
                    ))
                ],
                providerOptions: nil
            )
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            store: false,
            hasLocalShellTool: false
        )

        let expected: OpenAIResponsesInput = [
            .object([
                "type": .string("reasoning"),
                "id": .string("reasoning_001"),
                "summary": .array([
                    .object(["type": .string("summary_text"), "text": .string("First reasoning step")]),
                    .object(["type": .string("summary_text"), "text": .string("Second reasoning step")])
                ])
            ])
        ]

        #expect(result.input == expected)
        #expect(result.warnings.isEmpty)
    }

    @Test("should create separate messages for different reasoning IDs (store: false)")
    func separateMessagesForDifferentReasoningIds() async throws {
        let prompt: LanguageModelV3Prompt = [
            .assistant(
                content: [
                    .reasoning(LanguageModelV3ReasoningPart(
                        text: "First reasoning block",
                        providerOptions: ["openai": ["itemId": .string("reasoning_001")]]
                    )),
                    .reasoning(LanguageModelV3ReasoningPart(
                        text: "Second reasoning block",
                        providerOptions: ["openai": ["itemId": .string("reasoning_002")]]
                    ))
                ],
                providerOptions: nil
            )
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            store: false,
            hasLocalShellTool: false
        )

        let expected: OpenAIResponsesInput = [
            .object([
                "type": .string("reasoning"),
                "id": .string("reasoning_001"),
                "summary": .array([
                    .object(["type": .string("summary_text"), "text": .string("First reasoning block")])
                ])
            ]),
            .object([
                "type": .string("reasoning"),
                "id": .string("reasoning_002"),
                "summary": .array([
                    .object(["type": .string("summary_text"), "text": .string("Second reasoning block")])
                ])
            ])
        ]

        #expect(result.input == expected)
        #expect(result.warnings.isEmpty)
    }

    @Test("user image file includes OpenAI detail provider option")
    func userImageIncludesDetail() async throws {
        let filePart = LanguageModelV3FilePart(
            data: .base64("AAECAw=="),
            mediaType: "image/png",
            filename: nil,
            providerOptions: [
                "openai": [
                    "imageDetail": .string("low")
                ]
            ]
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.file(filePart)], providerOptions: nil)
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            store: true,
            hasLocalShellTool: false
        )

        let expected: OpenAIResponsesInput = [
            .object([
                "role": .string("user"),
                "content": .array([
                    .object([
                        "type": .string("input_image"),
                        "image_url": .string("data:image/png;base64,AAECAw=="),
                        "detail": .string("low")
                    ])
                ])
            ])
        ]

        #expect(result.input == expected)
        #expect(result.warnings.isEmpty)
    }

    @Test("non-OpenAI reasoning parts emit warning")
    func nonOpenAIReasoningWarning() async throws {
        let reasoningPart = LanguageModelV3ReasoningPart(
            text: "This is a reasoning part without any provider options"
        )

        let prompt: LanguageModelV3Prompt = [
            .assistant(content: [.reasoning(reasoningPart)], providerOptions: nil)
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            store: true,
            hasLocalShellTool: false
        )

        let expectedMessage = #"Non-OpenAI reasoning parts are not supported. Skipping reasoning part: {"type":"reasoning","text":"This is a reasoning part without any provider options"}."#

        #expect(result.input.isEmpty)
        #expect(result.warnings == [.other(message: expectedMessage)])
    }

    @Test("empty reasoning part emits warning when store is false")
    func emptyReasoningPartWarning() async throws {
        let reasoningProviderOptions: SharedV3ProviderOptions = [
            "openai": [
                "itemId": .string("reasoning_001")
            ]
        ]

        let prompt: LanguageModelV3Prompt = [
            .assistant(
                content: [
                    .reasoning(
                        LanguageModelV3ReasoningPart(
                            text: "First reasoning step",
                            providerOptions: reasoningProviderOptions
                        )
                    ),
                    .reasoning(
                        LanguageModelV3ReasoningPart(
                            text: "",
                            providerOptions: reasoningProviderOptions
                        )
                    )
                ],
                providerOptions: nil
            )
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            store: false,
            hasLocalShellTool: false
        )

        let expectedInput: OpenAIResponsesInput = [
            .object([
                "type": .string("reasoning"),
                "id": .string("reasoning_001"),
                "summary": .array([
                    .object([
                        "type": .string("summary_text"),
                        "text": .string("First reasoning step")
                    ])
                ])
            ])
        ]

        let expectedWarning = #"Cannot append empty reasoning part to existing reasoning sequence. Skipping reasoning part: {"type":"reasoning","text":"","providerOptions":{"openai":{"itemId":"reasoning_001"}}}."#

        #expect(result.input == expectedInput)
        #expect(result.warnings == [.other(message: expectedWarning)])
    }

    // MARK: - Assistant Messages - Reasoning (Multi-message and Complex)

    @Test("should handle reasoning across multiple assistant messages (store: true)")
    func reasoningAcrossMultipleMessagesStoreTrue() async throws {
        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(LanguageModelV3TextPart(text: "First user question"))], providerOptions: nil),
            .assistant(
                content: [
                    .reasoning(LanguageModelV3ReasoningPart(
                        text: "First reasoning step (message 1)",
                        providerOptions: ["openai": ["itemId": .string("reasoning_001")]]
                    )),
                    .reasoning(LanguageModelV3ReasoningPart(
                        text: "Second reasoning step (message 1)",
                        providerOptions: ["openai": ["itemId": .string("reasoning_001")]]
                    )),
                    .text(LanguageModelV3TextPart(text: "First response"))
                ],
                providerOptions: nil
            ),
            .user(content: [.text(LanguageModelV3TextPart(text: "Second user question"))], providerOptions: nil),
            .assistant(
                content: [
                    .reasoning(LanguageModelV3ReasoningPart(
                        text: "First reasoning step (message 2)",
                        providerOptions: ["openai": ["itemId": .string("reasoning_002")]]
                    )),
                    .text(LanguageModelV3TextPart(text: "Second response"))
                ],
                providerOptions: nil
            )
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            store: true,
            hasLocalShellTool: false
        )

        #expect(result.input.count == 6)
        #expect(result.warnings.isEmpty)

        // Verify structure without strict equality due to potential undefined fields
        guard case .object(let userMsg1) = result.input[0],
              case .string("user") = userMsg1["role"],
              case .object(let reasoningRef1) = result.input[1],
              case .string("item_reference") = reasoningRef1["type"],
              case .string("reasoning_001") = reasoningRef1["id"],
              case .object(let assistantMsg1) = result.input[2],
              case .string("assistant") = assistantMsg1["role"],
              case .object(let userMsg2) = result.input[3],
              case .string("user") = userMsg2["role"],
              case .object(let reasoningRef2) = result.input[4],
              case .string("item_reference") = reasoningRef2["type"],
              case .string("reasoning_002") = reasoningRef2["id"],
              case .object(let assistantMsg2) = result.input[5],
              case .string("assistant") = assistantMsg2["role"] else {
            Issue.record("Unexpected output structure")
            return
        }
    }

    @Test("should handle reasoning across multiple assistant messages (store: false)")
    func reasoningAcrossMultipleMessagesStoreFalse() async throws {
        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(LanguageModelV3TextPart(text: "First user question"))], providerOptions: nil),
            .assistant(
                content: [
                    .reasoning(LanguageModelV3ReasoningPart(
                        text: "First reasoning step (message 1)",
                        providerOptions: ["openai": ["itemId": .string("reasoning_001")]]
                    )),
                    .reasoning(LanguageModelV3ReasoningPart(
                        text: "Second reasoning step (message 1)",
                        providerOptions: ["openai": ["itemId": .string("reasoning_001")]]
                    )),
                    .text(LanguageModelV3TextPart(text: "First response"))
                ],
                providerOptions: nil
            ),
            .user(content: [.text(LanguageModelV3TextPart(text: "Second user question"))], providerOptions: nil),
            .assistant(
                content: [
                    .reasoning(LanguageModelV3ReasoningPart(
                        text: "First reasoning step (message 2)",
                        providerOptions: ["openai": ["itemId": .string("reasoning_002")]]
                    )),
                    .text(LanguageModelV3TextPart(text: "Second response"))
                ],
                providerOptions: nil
            )
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            store: false,
            hasLocalShellTool: false
        )

        let expected: OpenAIResponsesInput = [
            .object([
                "role": .string("user"),
                "content": .array([.object(["type": .string("input_text"), "text": .string("First user question")])])
            ]),
            .object([
                "type": .string("reasoning"),
                "id": .string("reasoning_001"),
                "summary": .array([
                    .object(["type": .string("summary_text"), "text": .string("First reasoning step (message 1)")]),
                    .object(["type": .string("summary_text"), "text": .string("Second reasoning step (message 1)")])
                ])
            ]),
            .object([
                "role": .string("assistant"),
                "content": .array([.object(["type": .string("output_text"), "text": .string("First response")])])
            ]),
            .object([
                "role": .string("user"),
                "content": .array([.object(["type": .string("input_text"), "text": .string("Second user question")])])
            ]),
            .object([
                "type": .string("reasoning"),
                "id": .string("reasoning_002"),
                "summary": .array([
                    .object(["type": .string("summary_text"), "text": .string("First reasoning step (message 2)")])
                ])
            ]),
            .object([
                "role": .string("assistant"),
                "content": .array([.object(["type": .string("output_text"), "text": .string("Second response")])])
            ])
        ]

        #expect(result.input == expected)
        #expect(result.warnings.isEmpty)
    }

    @Test("should handle complex reasoning sequences with tool interactions (store: false)")
    func complexReasoningWithToolInteractions() async throws {
        let prompt: LanguageModelV3Prompt = [
            .assistant(
                content: [
                    .reasoning(LanguageModelV3ReasoningPart(
                        text: "Initial analysis step 1",
                        providerOptions: [
                            "openai": [
                                "itemId": .string("reasoning_001"),
                                "reasoningEncryptedContent": .string("encrypted_content_001")
                            ]
                        ]
                    )),
                    .reasoning(LanguageModelV3ReasoningPart(
                        text: "Initial analysis step 2",
                        providerOptions: [
                            "openai": [
                                "itemId": .string("reasoning_001"),
                                "reasoningEncryptedContent": .string("encrypted_content_001")
                            ]
                        ]
                    )),
                    .toolCall(LanguageModelV3ToolCallPart(
                        toolCallId: "call_001",
                        toolName: "search",
                        input: .object(["query": .string("initial search")])
                    ))
                ],
                providerOptions: nil
            ),
            .tool(
                content: [
                    .toolResult(LanguageModelV3ToolResultPart(
                        toolCallId: "call_001",
                        toolName: "search",
                        output: .json(value: .object([
                            "results": .array([.string("result1"), .string("result2")])
                        ]))
                    ))
                ],
                providerOptions: nil
            ),
            .assistant(
                content: [
                    .reasoning(LanguageModelV3ReasoningPart(
                        text: "Processing results step 1",
                        providerOptions: [
                            "openai": [
                                "itemId": .string("reasoning_002"),
                                "reasoningEncryptedContent": .string("encrypted_content_002")
                            ]
                        ]
                    )),
                    .reasoning(LanguageModelV3ReasoningPart(
                        text: "Processing results step 2",
                        providerOptions: [
                            "openai": [
                                "itemId": .string("reasoning_002"),
                                "reasoningEncryptedContent": .string("encrypted_content_002")
                            ]
                        ]
                    )),
                    .reasoning(LanguageModelV3ReasoningPart(
                        text: "Processing results step 3",
                        providerOptions: [
                            "openai": [
                                "itemId": .string("reasoning_002"),
                                "reasoningEncryptedContent": .string("encrypted_content_002")
                            ]
                        ]
                    )),
                    .toolCall(LanguageModelV3ToolCallPart(
                        toolCallId: "call_002",
                        toolName: "calculator",
                        input: .object(["expression": .string("2 + 2")])
                    ))
                ],
                providerOptions: nil
            ),
            .tool(
                content: [
                    .toolResult(LanguageModelV3ToolResultPart(
                        toolCallId: "call_002",
                        toolName: "calculator",
                        output: .json(value: .object(["result": .number(4)]))
                    ))
                ],
                providerOptions: nil
            ),
            .assistant(
                content: [
                    .text(LanguageModelV3TextPart(
                        text: "Based on my analysis and calculations, here is the final answer."
                    ))
                ],
                providerOptions: nil
            )
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            store: false,
            hasLocalShellTool: false
        )

        #expect(result.input.count == 7)
        #expect(result.warnings.isEmpty)

        // Verify the structure
        guard case .object(let reasoning1) = result.input[0],
              case .string("reasoning") = reasoning1["type"],
              case .string("reasoning_001") = reasoning1["id"],
              case .string("encrypted_content_001") = reasoning1["encrypted_content"],
              case .array(let summary1) = reasoning1["summary"],
              summary1.count == 2,
              case .object(let toolCall1) = result.input[1],
              case .string("function_call") = toolCall1["type"],
              case .object(let toolResult1) = result.input[2],
              case .string("function_call_output") = toolResult1["type"],
              case .object(let reasoning2) = result.input[3],
              case .string("reasoning") = reasoning2["type"],
              case .string("reasoning_002") = reasoning2["id"],
              case .array(let summary2) = reasoning2["summary"],
              summary2.count == 3,
              case .object(let toolCall2) = result.input[4],
              case .string("function_call") = toolCall2["type"],
              case .object(let toolResult2) = result.input[5],
              case .string("function_call_output") = toolResult2["type"],
              case .object(let finalMsg) = result.input[6],
              case .string("assistant") = finalMsg["role"] else {
            Issue.record("Unexpected output structure")
            return
        }
    }

    @Test("should warn when reasoning part lacks OpenAI-specific reasoning ID provider options")
    func reasoningLacksOpenAISpecificOptions() async throws {
        let prompt: LanguageModelV3Prompt = [
            .assistant(
                content: [
                    .reasoning(LanguageModelV3ReasoningPart(
                        text: "This is a reasoning part without OpenAI-specific reasoning id provider options",
                        providerOptions: [
                            "openai": [
                                "reasoning": .object([
                                    "encryptedContent": .string("encrypted_content_001")
                                ])
                            ]
                        ]
                    ))
                ],
                providerOptions: nil
            )
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            store: true,
            hasLocalShellTool: false
        )

        #expect(result.input.isEmpty)
        #expect(result.warnings.count == 1)
        guard case .other(let message) = result.warnings[0] else {
            Issue.record("Expected .other warning")
            return
        }
        #expect(message.contains("Non-OpenAI reasoning parts are not supported"))
    }

    // MARK: - Tool Messages - Results

    @Test("should convert single tool result part with json value")
    func toolResultWithJsonValue() async throws {
        let prompt: LanguageModelV3Prompt = [
            .tool(
                content: [
                    .toolResult(LanguageModelV3ToolResultPart(
                        toolCallId: "call_123",
                        toolName: "search",
                        output: .json(value: .object([
                            "temperature": .string("72°F"),
                            "condition": .string("Sunny")
                        ]))
                    ))
                ],
                providerOptions: nil
            )
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            store: true,
            hasLocalShellTool: false
        )

        #expect(result.input.count == 1)
        guard case .object(let obj) = result.input[0],
              case .string("function_call_output") = obj["type"],
              case .string("call_123") = obj["call_id"],
              case .string(let output) = obj["output"] else {
            Issue.record("Unexpected output structure")
            return
        }

        #expect(output.contains("temperature"))
        #expect(output.contains("72°F"))
        #expect(output.contains("Sunny"))
    }

    @Test("should convert single tool result part with text value")
    func toolResultWithTextValue() async throws {
        let prompt: LanguageModelV3Prompt = [
            .tool(
                content: [
                    .toolResult(LanguageModelV3ToolResultPart(
                        toolCallId: "call_123",
                        toolName: "search",
                        output: .text(value: "The weather in San Francisco is 72°F")
                    ))
                ],
                providerOptions: nil
            )
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            store: true,
            hasLocalShellTool: false
        )

        let expected: OpenAIResponsesInput = [
            .object([
                "type": .string("function_call_output"),
                "call_id": .string("call_123"),
                "output": .string("The weather in San Francisco is 72°F")
            ])
        ]

        #expect(result.input == expected)
    }

    @Test("should convert single tool result part with multipart that contains text")
    func toolResultMultipartWithText() async throws {
        let prompt: LanguageModelV3Prompt = [
            .tool(
                content: [
                    .toolResult(LanguageModelV3ToolResultPart(
                        toolCallId: "call_123",
                        toolName: "search",
                        output: .content(value: [
                            .text(text: "The weather in San Francisco is 72°F")
                        ])
                    ))
                ],
                providerOptions: nil
            )
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            store: true,
            hasLocalShellTool: false
        )

        let expected: OpenAIResponsesInput = [
            .object([
                "type": .string("function_call_output"),
                "call_id": .string("call_123"),
                "output": .array([
                    .object([
                        "type": .string("input_text"),
                        "text": .string("The weather in San Francisco is 72°F")
                    ])
                ])
            ])
        ]

        #expect(result.input == expected)
    }

    @Test("should convert single tool result part with multipart that contains image")
    func toolResultMultipartWithImage() async throws {
        let prompt: LanguageModelV3Prompt = [
            .tool(
                content: [
                    .toolResult(LanguageModelV3ToolResultPart(
                        toolCallId: "call_123",
                        toolName: "search",
                        output: .content(value: [
                            .media(data: "base64_data", mediaType: "image/png")
                        ])
                    ))
                ],
                providerOptions: nil
            )
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            store: true,
            hasLocalShellTool: false
        )

        let expected: OpenAIResponsesInput = [
            .object([
                "type": .string("function_call_output"),
                "call_id": .string("call_123"),
                "output": .array([
                    .object([
                        "type": .string("input_image"),
                        "image_url": .string("data:image/png;base64,base64_data")
                    ])
                ])
            ])
        ]

        #expect(result.input == expected)
    }

    @Test("should convert single tool result part with multipart that contains file (PDF)")
    func toolResultMultipartWithPDF() async throws {
        let prompt: LanguageModelV3Prompt = [
            .tool(
                content: [
                    .toolResult(LanguageModelV3ToolResultPart(
                        toolCallId: "call_123",
                        toolName: "search",
                        output: .content(value: [
                            .media(data: "AQIDBAU=", mediaType: "application/pdf")
                        ])
                    ))
                ],
                providerOptions: nil
            )
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            store: true,
            hasLocalShellTool: false
        )

        let expected: OpenAIResponsesInput = [
            .object([
                "type": .string("function_call_output"),
                "call_id": .string("call_123"),
                "output": .array([
                    .object([
                        "type": .string("input_file"),
                        "filename": .string("data"),
                        "file_data": .string("data:application/pdf;base64,AQIDBAU=")
                    ])
                ])
            ])
        ]

        #expect(result.input == expected)
    }

    @Test("should convert single tool result part with multipart with mixed content (text, image, file)")
    func toolResultMultipartMixedContent() async throws {
        let prompt: LanguageModelV3Prompt = [
            .tool(
                content: [
                    .toolResult(LanguageModelV3ToolResultPart(
                        toolCallId: "call_123",
                        toolName: "search",
                        output: .content(value: [
                            .text(text: "The weather in San Francisco is 72°F"),
                            .media(data: "base64_data", mediaType: "image/png"),
                            .media(data: "AQIDBAU=", mediaType: "application/pdf")
                        ])
                    ))
                ],
                providerOptions: nil
            )
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            store: true,
            hasLocalShellTool: false
        )

        let expected: OpenAIResponsesInput = [
            .object([
                "type": .string("function_call_output"),
                "call_id": .string("call_123"),
                "output": .array([
                    .object([
                        "type": .string("input_text"),
                        "text": .string("The weather in San Francisco is 72°F")
                    ]),
                    .object([
                        "type": .string("input_image"),
                        "image_url": .string("data:image/png;base64,base64_data")
                    ]),
                    .object([
                        "type": .string("input_file"),
                        "filename": .string("data"),
                        "file_data": .string("data:application/pdf;base64,AQIDBAU=")
                    ])
                ])
            ])
        ]

        #expect(result.input == expected)
    }

    @Test("should convert multiple tool result parts in a single message")
    func multipleToolResultPartsInSingleMessage() async throws {
        let prompt: LanguageModelV3Prompt = [
            .tool(
                content: [
                    .toolResult(LanguageModelV3ToolResultPart(
                        toolCallId: "call_123",
                        toolName: "search",
                        output: .json(value: .object([
                            "temperature": .string("72°F"),
                            "condition": .string("Sunny")
                        ]))
                    )),
                    .toolResult(LanguageModelV3ToolResultPart(
                        toolCallId: "call_456",
                        toolName: "calculator",
                        output: .json(value: .number(4))
                    ))
                ],
                providerOptions: nil
            )
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            store: true,
            hasLocalShellTool: false
        )

        #expect(result.input.count == 2)
        guard case .object(let obj1) = result.input[0],
              case .string("function_call_output") = obj1["type"],
              case .string("call_123") = obj1["call_id"],
              case .object(let obj2) = result.input[1],
              case .string("function_call_output") = obj2["type"],
              case .string("call_456") = obj2["call_id"],
              case .string("4") = obj2["output"] else {
            Issue.record("Unexpected output structure")
            return
        }
    }

    // MARK: - Tool Messages - Approvals

    @Test("should convert tool approval response to mcp_approval_response when store is true")
    func toolApprovalResponseToMcpApprovalResponse() async throws {
        let prompt: LanguageModelV3Prompt = [
            .tool(
                content: [
                    .toolApprovalResponse(LanguageModelV3ToolApprovalResponsePart(
                        approvalId: "approval_123",
                        approved: true,
                        reason: nil,
                        providerOptions: nil
                    ))
                ],
                providerOptions: nil
            )
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            store: true,
            hasLocalShellTool: false
        )

        let expected: OpenAIResponsesInput = [
            .object([
                "type": .string("item_reference"),
                "id": .string("approval_123")
            ]),
            .object([
                "type": .string("mcp_approval_response"),
                "approval_request_id": .string("approval_123"),
                "approve": .bool(true)
            ])
        ]

        #expect(result.input == expected)
        #expect(result.warnings.isEmpty)
    }

    @Test("should dedupe tool approval responses by approvalId")
    func toolApprovalResponseDeduped() async throws {
        let prompt: LanguageModelV3Prompt = [
            .tool(
                content: [
                    .toolApprovalResponse(LanguageModelV3ToolApprovalResponsePart(
                        approvalId: "approval_123",
                        approved: true,
                        reason: nil,
                        providerOptions: nil
                    )),
                    .toolApprovalResponse(LanguageModelV3ToolApprovalResponsePart(
                        approvalId: "approval_123",
                        approved: true,
                        reason: nil,
                        providerOptions: nil
                    ))
                ],
                providerOptions: nil
            )
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            store: true,
            hasLocalShellTool: false
        )

        #expect(result.input.count == 2)
        guard case .object(let ref) = result.input[0],
              case .string("item_reference") = ref["type"],
              case .string("approval_123") = ref["id"],
              case .object(let approval) = result.input[1],
              case .string("mcp_approval_response") = approval["type"],
              case .string("approval_123") = approval["approval_request_id"],
              case .bool(true) = approval["approve"] else {
            Issue.record("Unexpected output structure")
            return
        }
    }

    // MARK: - Tool Messages - Provider Execution

    @Test("should exclude provider-executed tool calls and results from prompt with store: false")
    func excludeProviderExecutedToolCallsStoreFalse() async throws {
        let prompt: LanguageModelV3Prompt = [
            .assistant(
                content: [
                    .text(LanguageModelV3TextPart(text: "Let me search for recent news from San Francisco.")),
                    .toolCall(LanguageModelV3ToolCallPart(
                        toolCallId: "ws_67cf2b3051e88190b006770db6fdb13d",
                        toolName: "web_search",
                        input: .object(["query": .string("San Francisco major news events June 22 2025")]),
                        providerExecuted: true
                    )),
                    .toolResult(LanguageModelV3ToolResultPart(
                        toolCallId: "ws_67cf2b3051e88190b006770db6fdb13d",
                        toolName: "web_search",
                        output: .json(value: .array([
                            .object(["url": .string("https://patch.com/california/san-francisco/calendar")])
                        ]))
                    )),
                    .text(LanguageModelV3TextPart(
                        text: "Based on the search results, several significant events took place in San Francisco yesterday (June 22, 2025)."
                    ))
                ],
                providerOptions: nil
            )
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            store: false,
            hasLocalShellTool: false
        )

        #expect(result.input.count == 2)
        #expect(result.warnings.count == 1)
        guard case .other(let message) = result.warnings[0] else {
            Issue.record("Expected .other warning")
            return
        }
        #expect(message.contains("Results for OpenAI tool web_search"))

        guard case .object(let msg1) = result.input[0],
              case .string("assistant") = msg1["role"],
              case .array(let content1) = msg1["content"],
              content1.count == 1,
              case .object(let msg2) = result.input[1],
              case .string("assistant") = msg2["role"],
              case .array(let content2) = msg2["content"],
              content2.count == 1 else {
            Issue.record("Unexpected output structure")
            return
        }
    }

    @Test("should include client-side tool calls in prompt")
    func includeClientSideToolCalls() async throws {
        let prompt: LanguageModelV3Prompt = [
            .assistant(
                content: [
                    .toolCall(LanguageModelV3ToolCallPart(
                        toolCallId: "call-1",
                        toolName: "calculator",
                        input: .object(["a": .number(1), "b": .number(2)]),
                        providerExecuted: false
                    ))
                ],
                providerOptions: nil
            )
        ]

        let result = try await OpenAIResponsesInputBuilder.makeInput(
            prompt: prompt,
            systemMessageMode: .system,
            store: true,
            hasLocalShellTool: false
        )

        #expect(result.input.count == 1)
        #expect(result.warnings.isEmpty)

        guard case .object(let obj) = result.input[0],
              case .string("function_call") = obj["type"],
              case .string("call-1") = obj["call_id"],
              case .string("calculator") = obj["name"],
              case .string(let args) = obj["arguments"],
              args.contains("\"a\":1"),
              args.contains("\"b\":2") else {
            Issue.record("Unexpected output structure")
            return
        }
    }
}
