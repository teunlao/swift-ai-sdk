import Foundation
import Testing
import AISDKProvider
@testable import AmazonBedrockProvider

@Suite("ConvertToBedrockChatMessages")
struct ConvertToBedrockChatMessagesTests {
    @Test("combines multiple leading system messages")
    func combinesLeadingSystemMessages() async throws {
        let prompt: LanguageModelV3Prompt = [
            .system(content: "Hello", providerOptions: nil),
            .system(content: "World", providerOptions: nil),
        ]

        let result = try await convertToBedrockChatMessages(prompt)
        #expect(result.messages.isEmpty)
        #expect(result.system == [
            .object(["text": .string("Hello")]),
            .object(["text": .string("World")]),
        ])
    }

    @Test("throws when a system message appears after a non-system message")
    func throwsWhenSystemAfterUser() async throws {
        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil),
            .system(content: "World", providerOptions: nil),
        ]

        await #expect(throws: Error.self) {
            _ = try await convertToBedrockChatMessages(prompt)
        }
    }

    @Test("adds cachePoint to system messages")
    func addsCachePointToSystemMessages() async throws {
        let prompt: LanguageModelV3Prompt = [
            .system(
                content: "Hello",
                providerOptions: [
                    "bedrock": [
                        "cachePoint": .object(["type": .string("default")])
                    ]
                ]
            ),
        ]

        let result = try await convertToBedrockChatMessages(prompt)
        #expect(result.messages.isEmpty)
        #expect(result.system == [
            .object(["text": .string("Hello")]),
            .object(["cachePoint": .object(["type": .string("default")])]),
        ])
    }

    @Test("includes cachePoint ttl for system messages")
    func includesCachePointTTLForSystemMessages() async throws {
        let prompt: LanguageModelV3Prompt = [
            .system(
                content: "Hello",
                providerOptions: [
                    "bedrock": [
                        "cachePoint": .object([
                            "type": .string("default"),
                            "ttl": .string("5m"),
                        ])
                    ]
                ]
            ),
        ]

        let result = try await convertToBedrockChatMessages(prompt)
        #expect(result.system == [
            .object(["text": .string("Hello")]),
            .object(["cachePoint": .object(["type": .string("default"), "ttl": .string("5m")])]),
        ])
    }

    @Test("converts assistant tool-call input as JSON object and normalizes toolUseId for Mistral")
    func convertsAssistantToolCallAndNormalizesIdForMistral() async throws {
        let rawToolCallId = "tooluse_bpe71yCfRu2b5i-nKGDr5g"
        let prompt: LanguageModelV3Prompt = [
            .assistant(
                content: [
                    .toolCall(.init(
                        toolCallId: rawToolCallId,
                        toolName: "test",
                        input: .object(["value": .string("Sparkle Day")])
                    ))
                ],
                providerOptions: nil
            )
        ]

        let result = try await convertToBedrockChatMessages(prompt, isMistral: true)
        #expect(result.system.isEmpty)
        #expect(result.messages == [
            .object([
                "role": .string("assistant"),
                "content": .array([
                    .object([
                        "toolUse": .object([
                            "toolUseId": .string("toolusebp"),
                            "name": .string("test"),
                            "input": .object(["value": .string("Sparkle Day")]),
                        ])
                    ])
                ])
            ])
        ])
    }

    @Test("converts tool results and normalizes toolUseId for Mistral")
    func convertsToolResultsAndNormalizesIdForMistral() async throws {
        let rawToolCallId = "tooluse_bpe71yCfRu2b5i-nKGDr5g"
        let prompt: LanguageModelV3Prompt = [
            .tool(
                content: [
                    .toolResult(.init(
                        toolCallId: rawToolCallId,
                        toolName: "calculator",
                        output: .json(value: .object(["value": .number(42)]))
                    ))
                ],
                providerOptions: nil
            )
        ]

        let result = try await convertToBedrockChatMessages(prompt, isMistral: true)
        #expect(result.system.isEmpty)
        #expect(result.messages == [
            .object([
                "role": .string("user"),
                "content": .array([
                    .object([
                        "toolResult": .object([
                            "toolUseId": .string("toolusebp"),
                            "content": .array([
                                .object(["text": .string("{\"value\":42}")])
                            ])
                        ])
                    ])
                ])
            ])
        ])
    }

    @Test("converts reasoning content when Bedrock reasoning metadata is present")
    func convertsReasoningContentWithSignature() async throws {
        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Explain your reasoning"))], providerOptions: nil),
            .assistant(
                content: [
                    .reasoning(.init(
                        text: "My reasoning",
                        providerOptions: [
                            "bedrock": ["signature": .string("test-signature")]
                        ]
                    ))
                ],
                providerOptions: nil
            )
        ]

        let result = try await convertToBedrockChatMessages(prompt)
        #expect(result.messages == [
            .object([
                "role": .string("user"),
                "content": .array([.object(["text": .string("Explain your reasoning")])])
            ]),
            .object([
                "role": .string("assistant"),
                "content": .array([
                    .object([
                        "reasoningContent": .object([
                            "reasoningText": .object([
                                "text": .string("My reasoning"),
                                "signature": .string("test-signature"),
                            ])
                        ])
                    ])
                ])
            ]),
        ])
    }

    @Test("preserves reasoning content without Bedrock metadata")
    func preservesReasoningContentWithoutMetadata() async throws {
        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Explain your reasoning"))], providerOptions: nil),
            .assistant(
                content: [
                    .reasoning(.init(text: "My reasoning"))
                ],
                providerOptions: nil
            )
        ]

        let result = try await convertToBedrockChatMessages(prompt)
        #expect(result.messages == [
            .object([
                "role": .string("user"),
                "content": .array([.object(["text": .string("Explain your reasoning")])])
            ]),
            .object([
                "role": .string("assistant"),
                "content": .array([
                    .object([
                        "reasoningContent": .object([
                            "reasoningText": .object([
                                "text": .string("My reasoning"),
                            ])
                        ])
                    ])
                ])
            ]),
        ])
    }

    @Test("does not trim reasoning text when Bedrock signature is present")
    func doesNotTrimReasoningTextWhenSignaturePresent() async throws {
        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Explain your reasoning"))], providerOptions: nil),
            .assistant(
                content: [
                    .reasoning(.init(
                        text: "Reasoning with trailing spaces    ",
                        providerOptions: [
                            "bedrock": ["signature": .string("test-signature")]
                        ]
                    ))
                ],
                providerOptions: nil
            )
        ]

        let result = try await convertToBedrockChatMessages(prompt)
        #expect(result.messages == [
            .object([
                "role": .string("user"),
                "content": .array([.object(["text": .string("Explain your reasoning")])])
            ]),
            .object([
                "role": .string("assistant"),
                "content": .array([
                    .object([
                        "reasoningContent": .object([
                            "reasoningText": .object([
                                "text": .string("Reasoning with trailing spaces    "),
                                "signature": .string("test-signature"),
                            ])
                        ])
                    ])
                ])
            ]),
        ])
    }
}
