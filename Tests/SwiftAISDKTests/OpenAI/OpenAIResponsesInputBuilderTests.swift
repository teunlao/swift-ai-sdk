import Foundation
import Testing
import AISDKProvider
@testable import OpenAIProvider

@Suite("OpenAIResponsesInputBuilder")
struct OpenAIResponsesInputBuilderTests {
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
}
