import Foundation
import Testing
@testable import AISDKProvider
@testable import OpenAICompatibleProvider

@Suite("OpenAICompatible chat message conversion")
struct OpenAICompatibleChatMessagesConverterTests {
    @Test("collapses user single text to string content")
    func userTextCollapsesToString() throws {
        let prompt: LanguageModelV3Prompt = [
            .user(
                content: [.text(LanguageModelV3TextPart(text: "Hello"))],
                providerOptions: nil
            )
        ]

        let result = try convertToOpenAICompatibleChatMessages(prompt: prompt)
        let expected: [JSONValue] = [
            .object([
                "role": .string("user"),
                "content": .string("Hello")
            ])
        ]
        #expect(result == expected)
    }

    @Test("converts user mixed text and image content with metadata")
    func userTextAndImage() throws {
        let imageData = Data([0, 1, 2, 3])
        let prompt: LanguageModelV3Prompt = [
            .user(
                content: [
                    .text(LanguageModelV3TextPart(
                        text: "Hello",
                        providerOptions: [
                            "openaiCompatible": ["sentiment": .string("positive")]
                        ]
                    )),
                    .file(LanguageModelV3FilePart(
                        data: .data(imageData),
                        mediaType: "image/png",
                        providerOptions: [
                            "openaiCompatible": ["alt_text": .string("Sample")]
                        ]
                    ))
                ],
                providerOptions: nil
            )
        ]

        let result = try convertToOpenAICompatibleChatMessages(prompt: prompt)
        let expected: [JSONValue] = [
            .object([
                "role": .string("user"),
                "content": .array([
                    .object([
                        "type": .string("text"),
                        "text": .string("Hello"),
                        "sentiment": .string("positive")
                    ]),
                    .object([
                        "type": .string("image_url"),
                        "image_url": .object([
                            "url": .string("data:image/png;base64,AAECAw==")
                        ]),
                        "alt_text": .string("Sample")
                    ])
                ])
            ])
        ]
        #expect(result == expected)
    }

    @Test("converts assistant tool calls and tool results")
    func toolCallsAndResults() throws {
        let prompt: LanguageModelV3Prompt = [
            .assistant(
                content: [
                    .toolCall(LanguageModelV3ToolCallPart(
                        toolCallId: "quux",
                        toolName: "thwomp",
                        input: .object(["foo": .string("bar123")])
                    ))
                ],
                providerOptions: nil
            ),
            .tool(
                content: [
                    LanguageModelV3ToolResultPart(
                        toolCallId: "quux",
                        toolName: "thwomp",
                        output: .json(value: .object(["oof": .string("321rab")]))
                    )
                ],
                providerOptions: nil
            )
        ]

        let result = try convertToOpenAICompatibleChatMessages(prompt: prompt)
        let expected: [JSONValue] = [
            .object([
                "role": .string("assistant"),
                "content": .string(""),
                "tool_calls": .array([
                    .object([
                        "type": .string("function"),
                        "id": .string("quux"),
                        "function": .object([
                            "name": .string("thwomp"),
                            "arguments": .string("{\"foo\":\"bar123\"}")
                        ])
                    ])
                ])
            ]),
            .object([
                "role": .string("tool"),
                "tool_call_id": .string("quux"),
                "content": .string("{\"oof\":\"321rab\"}")
            ])
        ]
        #expect(result == expected)
    }

    @Test("prefers content metadata over message metadata")
    func metadataPriority() throws {
        let prompt: LanguageModelV3Prompt = [
            .user(
                content: [
                    .text(LanguageModelV3TextPart(
                        text: "Hello",
                        providerOptions: [
                            "openaiCompatible": ["contentLevel": .bool(true)]
                        ]
                    ))
                ],
                providerOptions: [
                    "openaiCompatible": ["messageLevel": .bool(true)]
                ]
            )
        ]

        let result = try convertToOpenAICompatibleChatMessages(prompt: prompt)
        let expected: [JSONValue] = [
            .object([
                "role": .string("user"),
                "content": .string("Hello"),
                "contentLevel": .bool(true)
            ])
        ]
        #expect(result == expected)
    }
}
