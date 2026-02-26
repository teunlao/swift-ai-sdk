import Foundation
import Testing
@testable import AISDKProvider
@testable import XAIProvider

/**
 Tests for convertToXAIResponsesInput.

 Port of `@ai-sdk/xai/src/responses/convert-to-xai-responses-input.test.ts`.
 */
@Suite("convertToXAIResponsesInput")
struct ConvertToXAIResponsesInputTests {
    @Test("converts system messages")
    func convertsSystemMessages() async throws {
        let prompt: LanguageModelV3Prompt = [
            .system(content: "you are a helpful assistant", providerOptions: nil)
        ]

        let (input, warnings) = try await convertToXAIResponsesInput(prompt: prompt)

        #expect(warnings.isEmpty)
        #expect(input == [
            .object([
                "role": .string("system"),
                "content": .string("you are a helpful assistant")
            ])
        ])
    }

    @Test("converts user single text part")
    func convertsUserSingleTextPart() async throws {
        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "hello"))], providerOptions: nil)
        ]

        let (input, _) = try await convertToXAIResponsesInput(prompt: prompt)

        #expect(input == [
            .object([
                "role": .string("user"),
                "content": .array([
                    .object([
                        "type": .string("input_text"),
                        "text": .string("hello")
                    ])
                ])
            ])
        ])
    }

    @Test("converts user multiple text parts")
    func convertsUserMultipleTextParts() async throws {
        let prompt: LanguageModelV3Prompt = [
            .user(content: [
                .text(.init(text: "hello ")),
                .text(.init(text: "world"))
            ], providerOptions: nil)
        ]

        let (input, _) = try await convertToXAIResponsesInput(prompt: prompt)

        #expect(input == [
            .object([
                "role": .string("user"),
                "content": .array([
                    .object([
                        "type": .string("input_text"),
                        "text": .string("hello ")
                    ]),
                    .object([
                        "type": .string("input_text"),
                        "text": .string("world")
                    ])
                ])
            ])
        ])
    }

    @Test("converts image file parts with URL")
    func convertsImageFilePartsWithURL() async throws {
        let prompt: LanguageModelV3Prompt = [
            .user(content: [
                .text(.init(text: "what is in this image")),
                .file(.init(
                    data: .url(URL(string: "https://example.com/image.jpg")!),
                    mediaType: "image/jpeg"
                ))
            ], providerOptions: nil)
        ]

        let (input, warnings) = try await convertToXAIResponsesInput(prompt: prompt)

        #expect(warnings.isEmpty)
        #expect(input == [
            .object([
                "role": .string("user"),
                "content": .array([
                    .object([
                        "type": .string("input_text"),
                        "text": .string("what is in this image")
                    ]),
                    .object([
                        "type": .string("input_image"),
                        "image_url": .string("https://example.com/image.jpg")
                    ])
                ])
            ])
        ])
    }

    @Test("converts image file parts with base64 data")
    func convertsImageFilePartsWithBase64Data() async throws {
        let prompt: LanguageModelV3Prompt = [
            .user(content: [
                .text(.init(text: "describe this")),
                .file(.init(
                    data: .data(Data([1, 2, 3])),
                    mediaType: "image/png"
                ))
            ], providerOptions: nil)
        ]

        let (input, _) = try await convertToXAIResponsesInput(prompt: prompt)

        #expect(input == [
            .object([
                "role": .string("user"),
                "content": .array([
                    .object([
                        "type": .string("input_text"),
                        "text": .string("describe this")
                    ]),
                    .object([
                        "type": .string("input_image"),
                        "image_url": .string("data:image/png;base64,AQID")
                    ])
                ])
            ])
        ])
    }

    @Test("throws for unsupported file types")
    func throwsForUnsupportedFileTypes() async throws {
        let prompt: LanguageModelV3Prompt = [
            .user(content: [
                .text(.init(text: "check this file")),
                .file(.init(
                    data: .data(Data([1, 2, 3])),
                    mediaType: "application/pdf"
                ))
            ], providerOptions: nil)
        ]

        await #expect(throws: UnsupportedFunctionalityError.self) {
            _ = try await convertToXAIResponsesInput(prompt: prompt)
        }
    }

    @Test("converts assistant text content")
    func convertsAssistantTextContent() async throws {
        let prompt: LanguageModelV3Prompt = [
            .assistant(content: [.text(.init(text: "hi there"))], providerOptions: nil)
        ]

        let (input, _) = try await convertToXAIResponsesInput(prompt: prompt)

        #expect(input == [
            .object([
                "role": .string("assistant"),
                "content": .string("hi there")
            ])
        ])
    }

    @Test("handles client-side tool-call parts")
    func handlesClientSideToolCallParts() async throws {
        let prompt: LanguageModelV3Prompt = [
            .assistant(content: [
                .toolCall(.init(
                    toolCallId: "call_123",
                    toolName: "weather",
                    input: .object(["location": .string("sf")])
                ))
            ], providerOptions: nil)
        ]

        let (input, _) = try await convertToXAIResponsesInput(prompt: prompt)

        #expect(input == [
            .object([
                "type": .string("function_call"),
                "id": .string("call_123"),
                "call_id": .string("call_123"),
                "name": .string("weather"),
                "arguments": .string("{\"location\":\"sf\"}"),
                "status": .string("completed")
            ])
        ])
    }

    @Test("skips server-side tool-call parts")
    func skipsServerSideToolCallParts() async throws {
        let prompt: LanguageModelV3Prompt = [
            .assistant(content: [
                .toolCall(.init(
                    toolCallId: "ws_123",
                    toolName: "web_search",
                    input: .object([:]),
                    providerExecuted: true
                ))
            ], providerOptions: nil)
        ]

        let (input, _) = try await convertToXAIResponsesInput(prompt: prompt)
        #expect(input.isEmpty)
    }

    @Test("converts tool-result to function_call_output with json")
    func convertsToolResultToFunctionCallOutputJSON() async throws {
        let prompt: LanguageModelV3Prompt = [
            .tool(content: [
                .toolResult(.init(
                    toolCallId: "call_123",
                    toolName: "weather",
                    output: .json(value: .object(["temp": .number(72)]))
                ))
            ], providerOptions: nil)
        ]

        let (input, _) = try await convertToXAIResponsesInput(prompt: prompt)

        #expect(input == [
            .object([
                "type": .string("function_call_output"),
                "call_id": .string("call_123"),
                "output": .string("{\"temp\":72}")
            ])
        ])
    }

    @Test("handles tool-result text output")
    func handlesToolResultTextOutput() async throws {
        let prompt: LanguageModelV3Prompt = [
            .tool(content: [
                .toolResult(.init(
                    toolCallId: "call_123",
                    toolName: "weather",
                    output: .text(value: "sunny, 72 degrees")
                ))
            ], providerOptions: nil)
        ]

        let (input, _) = try await convertToXAIResponsesInput(prompt: prompt)

        #expect(input == [
            .object([
                "type": .string("function_call_output"),
                "call_id": .string("call_123"),
                "output": .string("sunny, 72 degrees")
            ])
        ])
    }

    @Test("handles full conversation with client-side tool calls")
    func handlesFullConversationClientSideTools() async throws {
        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "whats the weather"))], providerOptions: nil),
            .assistant(content: [
                .toolCall(.init(
                    toolCallId: "call_123",
                    toolName: "weather",
                    input: .object(["location": .string("sf")])
                ))
            ], providerOptions: nil),
            .tool(content: [
                .toolResult(.init(
                    toolCallId: "call_123",
                    toolName: "weather",
                    output: .json(value: .object(["temp": .number(72)]))
                ))
            ], providerOptions: nil),
            .assistant(content: [.text(.init(text: "its 72 degrees"))], providerOptions: nil)
        ]

        let (input, _) = try await convertToXAIResponsesInput(prompt: prompt)

        #expect(input.count == 4)
        #expect(input[0] == .object([
            "role": .string("user"),
            "content": .array([
                .object([
                    "type": .string("input_text"),
                    "text": .string("whats the weather")
                ])
            ])
        ]))
        #expect(input[1] == .object([
            "type": .string("function_call"),
            "id": .string("call_123"),
            "call_id": .string("call_123"),
            "name": .string("weather"),
            "arguments": .string("{\"location\":\"sf\"}"),
            "status": .string("completed")
        ]))
        #expect(input[2] == .object([
            "type": .string("function_call_output"),
            "call_id": .string("call_123"),
            "output": .string("{\"temp\":72}")
        ]))
        #expect(input[3] == .object([
            "role": .string("assistant"),
            "content": .string("its 72 degrees")
        ]))
    }

    @Test("handles conversation with server-side tool calls and item references")
    func handlesConversationServerSideTools() async throws {
        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "search for ai news"))], providerOptions: nil),
            .assistant(content: [
                .toolCall(.init(
                    toolCallId: "ws_123",
                    toolName: "web_search",
                    input: .object([:]),
                    providerExecuted: true
                )),
                .toolResult(.init(
                    toolCallId: "ws_123",
                    toolName: "web_search",
                    output: .json(value: .object([:]))
                )),
                .text(.init(text: "here are the results"))
            ], providerOptions: nil)
        ]

        let (input, _) = try await convertToXAIResponsesInput(prompt: prompt, store: true)

        #expect(input == [
            .object([
                "role": .string("user"),
                "content": .array([
                    .object([
                        "type": .string("input_text"),
                        "text": .string("search for ai news")
                    ])
                ])
            ]),
            .object([
                "role": .string("assistant"),
                "content": .string("here are the results")
            ])
        ])
    }
}

