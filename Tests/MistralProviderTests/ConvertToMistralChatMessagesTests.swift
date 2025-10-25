import Foundation
import Testing
@testable import AISDKProvider
@testable import MistralProvider

@Suite("ConvertToMistralChatMessages")
struct ConvertToMistralChatMessagesTests {
    @Test("user image parts produce image_url entries")
    func imageParts() throws {
        let prompt: LanguageModelV3Prompt = [
            .user(
                content: [
                    .text(.init(text: "Hello")),
                    .file(.init(data: .base64("AAECAw=="), mediaType: "image/png"))
                ],
                providerOptions: nil
            )
        ]

        let result = try convertToMistralChatMessages(prompt: prompt)

        #expect(result == [
            .object([
                "role": .string("user"),
                "content": .array([
                    .object([
                        "type": .string("text"),
                        "text": .string("Hello")
                    ]),
                    .object([
                        "type": .string("image_url"),
                        "image_url": .string("data:image/png;base64,AAECAw==")
                    ])
                ])
            ])
        ])
    }

    @Test("user image parts from Data produce base64 content")
    func imagePartsFromData() throws {
        let data = Data([0, 1, 2, 3])
        let prompt: LanguageModelV3Prompt = [
            .user(
                content: [
                    .text(.init(text: "Hi")),
                    .file(.init(data: .data(data), mediaType: "image/png"))
                ],
                providerOptions: nil
            )
        ]

        let result = try convertToMistralChatMessages(prompt: prompt)
        #expect(result == [
            .object([
                "role": .string("user"),
                "content": .array([
                    .object([
                        "type": .string("text"),
                        "text": .string("Hi")
                    ]),
                    .object([
                        "type": .string("image_url"),
                        "image_url": .string("data:image/png;base64,AAECAw==")
                    ])
                ])
            ])
        ])
    }

    @Test("PDF files require URLs")
    func pdfFiles() throws {
        let prompt: LanguageModelV3Prompt = [
            .user(
                content: [
                    .text(.init(text: "Please analyze this document")),
                    .file(.init(data: .url(URL(string: "https://example.com/document.pdf")!), mediaType: "application/pdf"))
                ],
                providerOptions: nil
            )
        ]

        let result = try convertToMistralChatMessages(prompt: prompt)
        #expect(result == [
            .object([
                "role": .string("user"),
                "content": .array([
                    .object([
                        "type": .string("text"),
                        "text": .string("Please analyze this document")
                    ]),
                    .object([
                        "type": .string("document_url"),
                        "document_url": .string("https://example.com/document.pdf")
                    ])
                ])
            ])
        ])
    }

    @Test("assistant messages concatenate reasoning and text")
    func reasoningContent() throws {
        let prompt: LanguageModelV3Prompt = [
            .assistant(
                content: [
                    .reasoning(.init(text: "Let me think about this...")),
                    .text(.init(text: "The answer is 42."))
                ],
                providerOptions: nil
            )
        ]

        let result = try convertToMistralChatMessages(prompt: prompt)
        #expect(result == [
            .object([
                "role": .string("assistant"),
                "content": .string("Let me think about this...The answer is 42."),
                "prefix": .bool(true)
            ])
        ])
    }

    @Test("tool calls are stringified")
    func toolCallArguments() throws {
        let prompt: LanguageModelV3Prompt = [
            .assistant(
                content: [
                    .toolCall(.init(toolCallId: "tool-call-id-1", toolName: "tool-1", input: .object(["key": .string("arg-value")])))
                ],
                providerOptions: nil
            ),
            .tool(
                content: [
                    .init(
                        toolCallId: "tool-call-id-1",
                        toolName: "tool-1",
                        output: .json(value: .object(["key": .string("result-value")]))
                    )
                ],
                providerOptions: nil
            )
        ]

        let result = try convertToMistralChatMessages(prompt: prompt)
        #expect(result == [
            .object([
                "role": .string("assistant"),
                "content": .string(""),
                "tool_calls": .array([
                    .object([
                        "id": .string("tool-call-id-1"),
                        "type": .string("function"),
                        "function": .object([
                            "name": .string("tool-1"),
                            "arguments": .string("{\"key\":\"arg-value\"}")
                        ])
                    ])
                ])
            ]),
            .object([
                "role": .string("tool"),
                "tool_call_id": .string("tool-call-id-1"),
                "name": .string("tool-1"),
                "content": .string("{\"key\":\"result-value\"}")
            ])
        ])
    }

    @Test("content tool results are JSON-stringified")
    func toolContentOutput() throws {
        let prompt: LanguageModelV3Prompt = [
            .assistant(
                content: [
                    .toolCall(.init(toolCallId: "tool-call-id-3", toolName: "image-tool", input: .object(["query": .string("generate image")])))
                ],
                providerOptions: nil
            ),
            .tool(
                content: [
                    .init(
                        toolCallId: "tool-call-id-3",
                        toolName: "image-tool",
                        output: .content(
                            value: [
                                .text(text: "Here is the result:"),
                                .media(data: "base64data", mediaType: "image/png")
                            ]
                        )
                    )
                ],
                providerOptions: nil
            )
        ]

        let result = try convertToMistralChatMessages(prompt: prompt)
        #expect(result == [
            .object([
                "role": .string("assistant"),
                "content": .string(""),
                "tool_calls": .array([
                    .object([
                        "id": .string("tool-call-id-3"),
                        "type": .string("function"),
                        "function": .object([
                            "name": .string("image-tool"),
                            "arguments": .string("{\"query\":\"generate image\"}")
                        ])
                    ])
                ])
            ]),
            .object([
                "role": .string("tool"),
                "tool_call_id": .string("tool-call-id-3"),
                "name": .string("image-tool"),
                "content": .string("[{\"type\":\"text\",\"text\":\"Here is the result:\"},{\"type\":\"image-data\",\"data\":\"base64data\",\"mediaType\":\"image/png\"}]")
            ])
        ])
    }


    @Test("error tool output uses error message")
    func toolErrorOutput() throws {
        let prompt: LanguageModelV3Prompt = [
            .assistant(
                content: [
                    .toolCall(.init(toolCallId: "tool-call-id-4", toolName: "error-tool", input: .object(["query": .string("test")])) )
                ],
                providerOptions: nil
            ),
            .tool(
                content: [
                    .init(
                        toolCallId: "tool-call-id-4",
                        toolName: "error-tool",
                        output: .errorText(value: "Invalid input provided")
                    )
                ],
                providerOptions: nil
            )
        ]

        let result = try convertToMistralChatMessages(prompt: prompt)
        #expect(result == [
            .object([
                "role": .string("assistant"),
                "content": .string(""),
                "tool_calls": .array([
                    .object([
                        "id": .string("tool-call-id-4"),
                        "type": .string("function"),
                        "function": .object([
                            "name": .string("error-tool"),
                            "arguments": .string("{\"query\":\"test\"}")
                        ])
                    ])
                ])
            ]),
            .object([
                "role": .string("tool"),
                "tool_call_id": .string("tool-call-id-4"),
                "name": .string("error-tool"),
                "content": .string("Invalid input provided")
            ])
        ])
    }

    @Test("trailing assistant message adds prefix flag")
    func trailingAssistantPrefix() throws {
        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil),
            .assistant(content: [.text(.init(text: "Hello!"))], providerOptions: nil)
        ]

        let result = try convertToMistralChatMessages(prompt: prompt)
        #expect(result == [
            .object([
                "role": .string("user"),
                "content": .array([
                    .object([
                        "type": .string("text"),
                        "text": .string("Hello")
                    ])
                ])
            ]),
            .object([
                "role": .string("assistant"),
                "content": .string("Hello!"),
                "prefix": .bool(true)
            ])
        ])
    }

    @Test("text output format")
    func textOutputFormat() throws {
        let prompt: LanguageModelV3Prompt = [
            .assistant(
                content: [
                    .toolCall(.init(toolCallId: "tool-call-id-2", toolName: "text-tool", input: .object(["query": .string("test")])))
                ],
                providerOptions: nil
            ),
            .tool(
                content: [
                    .init(
                        toolCallId: "tool-call-id-2",
                        toolName: "text-tool",
                        output: .text(value: "This is a text response")
                    )
                ],
                providerOptions: nil
            )
        ]

        let result = try convertToMistralChatMessages(prompt: prompt)
        #expect(result == [
            .object([
                "role": .string("assistant"),
                "content": .string(""),
                "tool_calls": .array([
                    .object([
                        "id": .string("tool-call-id-2"),
                        "type": .string("function"),
                        "function": .object([
                            "name": .string("text-tool"),
                            "arguments": .string("{\"query\":\"test\"}")
                        ])
                    ])
                ])
            ]),
            .object([
                "role": .string("tool"),
                "tool_call_id": .string("tool-call-id-2"),
                "name": .string("text-tool"),
                "content": .string("This is a text response")
            ])
        ])
    }
}
