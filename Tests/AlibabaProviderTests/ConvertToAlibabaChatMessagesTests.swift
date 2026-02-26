import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import AlibabaProvider

@Suite("convertToAlibabaChatMessages")
struct ConvertToAlibabaChatMessagesTests {
    private let ephemeralCacheControl: SharedV3ProviderOptions = [
        "alibaba": ["cacheControl": .object(["type": .string("ephemeral")])]
    ]

    private func parseJSONString(_ text: String) throws -> JSONValue {
        let data = Data(text.utf8)
        let raw = try JSONSerialization.jsonObject(with: data, options: [])
        return try jsonValue(from: raw)
    }

    @Test("uses string format for single text user message")
    func singleTextUserMessage() throws {
        let result = try convertToAlibabaChatMessages(prompt: [
            .user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)
        ])

        #expect(result == [
            .object([
                "role": .string("user"),
                "content": .string("Hello"),
            ])
        ])
    }

    @Test("uses array format for multi-part user message with image")
    func multiPartUserMessageWithImage() throws {
        let result = try convertToAlibabaChatMessages(prompt: [
            .user(content: [
                .text(LanguageModelV3TextPart(text: "What is in this image?")),
                .file(LanguageModelV3FilePart(
                    data: .data(Data([0, 1, 2, 3])),
                    mediaType: "image/png"
                )),
            ], providerOptions: nil)
        ])

        #expect(result == [
            .object([
                "role": .string("user"),
                "content": .array([
                    .object([
                        "type": .string("text"),
                        "text": .string("What is in this image?"),
                    ]),
                    .object([
                        "type": .string("image_url"),
                        "image_url": .object([
                            "url": .string("data:image/png;base64,AAECAw=="),
                        ]),
                    ]),
                ]),
            ])
        ])
    }

    @Test("converts assistant message with tool calls")
    func assistantToolCalls() throws {
        let result = try convertToAlibabaChatMessages(prompt: [
            .assistant(content: [
                .toolCall(LanguageModelV3ToolCallPart(
                    toolCallId: "call-1",
                    toolName: "get_weather",
                    input: .object(["location": .string("San Francisco")])
                )),
            ], providerOptions: nil)
        ])

        #expect(result == [
            .object([
                "role": .string("assistant"),
                "content": .null,
                "tool_calls": .array([
                    .object([
                        "id": .string("call-1"),
                        "type": .string("function"),
                        "function": .object([
                            "name": .string("get_weather"),
                            "arguments": .string("{\"location\":\"San Francisco\"}"),
                        ]),
                    ]),
                ]),
            ])
        ])
    }

    @Test("converts tool results")
    func toolResults() throws {
        let result = try convertToAlibabaChatMessages(prompt: [
            .tool(content: [
                .toolResult(LanguageModelV3ToolResultPart(
                    toolCallId: "call-1",
                    toolName: "get_weather",
                    output: .json(value: .object([
                        "temperature": .number(72),
                        "condition": .string("sunny"),
                    ]))
                )),
            ], providerOptions: nil),
        ])

        guard result.count == 1, case let .object(obj) = result[0] else {
            Issue.record("Expected a single tool message object")
            return
        }

        #expect(obj["role"] == .string("tool"))
        #expect(obj["tool_call_id"] == .string("call-1"))

        guard case let .string(text) = obj["content"] else {
            Issue.record("Expected tool content to be a string")
            return
        }

        let parsed = try parseJSONString(text)
        #expect(parsed == .object([
            "temperature": .number(72),
            "condition": .string("sunny"),
        ]))
    }

    @Test("injects cache control into system message content block")
    func systemMessageCacheControl() throws {
        let validator = CacheControlValidator()

        let result = try convertToAlibabaChatMessages(
            prompt: [
                .system(
                    content: "You are a helpful assistant.",
                    providerOptions: ephemeralCacheControl
                ),
            ],
            cacheControlValidator: validator
        )

        #expect(result == [
            .object([
                "role": .string("system"),
                "content": .array([
                    .object([
                        "type": .string("text"),
                        "text": .string("You are a helpful assistant."),
                        "cache_control": .object(["type": .string("ephemeral")]),
                    ]),
                ]),
            ])
        ])
    }

    @Test("injects cache control into single text user message")
    func singleTextUserCacheControl() throws {
        let validator = CacheControlValidator()

        let result = try convertToAlibabaChatMessages(
            prompt: [
                .user(
                    content: [.text(LanguageModelV3TextPart(text: "Hello"))],
                    providerOptions: ephemeralCacheControl
                ),
            ],
            cacheControlValidator: validator
        )

        #expect(result == [
            .object([
                "role": .string("user"),
                "content": .array([
                    .object([
                        "type": .string("text"),
                        "text": .string("Hello"),
                        "cache_control": .object(["type": .string("ephemeral")]),
                    ]),
                ]),
            ])
        ])
    }

    @Test("uses part-level cache control for multi-part user message")
    func multiPartUserPartCacheControl() throws {
        let validator = CacheControlValidator()

        let result = try convertToAlibabaChatMessages(
            prompt: [
                .user(content: [
                    .text(LanguageModelV3TextPart(text: "What is in this image?")),
                    .file(LanguageModelV3FilePart(
                        data: .data(Data([0, 1, 2, 3])),
                        mediaType: "image/png",
                        providerOptions: ephemeralCacheControl
                    )),
                ], providerOptions: nil),
            ],
            cacheControlValidator: validator
        )

        #expect(result == [
            .object([
                "role": .string("user"),
                "content": .array([
                    .object([
                        "type": .string("text"),
                        "text": .string("What is in this image?"),
                    ]),
                    .object([
                        "type": .string("image_url"),
                        "image_url": .object([
                            "url": .string("data:image/png;base64,AAECAw=="),
                        ]),
                        "cache_control": .object(["type": .string("ephemeral")]),
                    ]),
                ]),
            ])
        ])
    }

    @Test("injects cache control into assistant message")
    func assistantCacheControl() throws {
        let validator = CacheControlValidator()

        let result = try convertToAlibabaChatMessages(
            prompt: [
                .assistant(
                    content: [.text(LanguageModelV3TextPart(text: "Hello, how can I help?"))],
                    providerOptions: ephemeralCacheControl
                ),
            ],
            cacheControlValidator: validator
        )

        #expect(result == [
            .object([
                "role": .string("assistant"),
                "content": .array([
                    .object([
                        "type": .string("text"),
                        "text": .string("Hello, how can I help?"),
                        "cache_control": .object(["type": .string("ephemeral")]),
                    ]),
                ]),
            ])
        ])
    }

    @Test("injects cache control into single-part tool message")
    func singleToolMessageCacheControl() throws {
        let validator = CacheControlValidator()

        let result = try convertToAlibabaChatMessages(
            prompt: [
                .tool(
                    content: [
                        .toolResult(LanguageModelV3ToolResultPart(
                            toolCallId: "call-1",
                            toolName: "get_weather",
                            output: .json(value: .object([
                                "temperature": .number(72),
                                "condition": .string("sunny"),
                            ]))
                        )),
                    ],
                    providerOptions: ephemeralCacheControl
                ),
            ],
            cacheControlValidator: validator
        )

        guard result.count == 1, case let .object(obj) = result[0] else {
            Issue.record("Expected a single tool message object")
            return
        }

        #expect(obj["role"] == .string("tool"))
        #expect(obj["tool_call_id"] == .string("call-1"))
        guard case let .array(contentParts) = obj["content"] else {
            Issue.record("Expected tool content to be an array")
            return
        }
        #expect(contentParts.count == 1)
        guard case let .object(textObj) = contentParts[0] else {
            Issue.record("Expected tool content part object")
            return
        }
        #expect(textObj["type"] == .string("text"))
        #expect(textObj["cache_control"] == .object(["type": .string("ephemeral")]))
        guard case let .string(text) = textObj["text"] else {
            Issue.record("Expected tool content part text string")
            return
        }
        let parsed = try parseJSONString(text)
        #expect(parsed == .object([
            "temperature": .number(72),
            "condition": .string("sunny"),
        ]))
    }

    @Test("uses part-level cache control for multi-part tool message")
    func multiToolMessagePartCacheControl() throws {
        let validator = CacheControlValidator()

        let result = try convertToAlibabaChatMessages(
            prompt: [
                .tool(content: [
                    .toolResult(LanguageModelV3ToolResultPart(
                        toolCallId: "call-1",
                        toolName: "get_weather",
                        output: .json(value: .object([
                            "temperature": .number(72),
                            "condition": .string("sunny"),
                        ]))
                    )),
                    .toolResult(LanguageModelV3ToolResultPart(
                        toolCallId: "call-2",
                        toolName: "get_time",
                        output: .text(value: "2:30 PM"),
                        providerOptions: ephemeralCacheControl
                    )),
                ], providerOptions: nil),
            ],
            cacheControlValidator: validator
        )

        #expect(result.count == 2)

        // First tool response: no cache control => content as string
        if case let .object(first) = result[0] {
            #expect(first["role"] == .string("tool"))
            #expect(first["tool_call_id"] == .string("call-1"))
            #expect(first["content"] != nil)
        } else {
            Issue.record("Expected first tool message object")
        }

        // Second tool response: part-level cache control => content as array with cache_control
        if case let .object(second) = result[1] {
            #expect(second["role"] == .string("tool"))
            #expect(second["tool_call_id"] == .string("call-2"))
            guard case let .array(parts) = second["content"] else {
                Issue.record("Expected second tool message content array")
                return
            }
            #expect(parts == [
                .object([
                    "type": .string("text"),
                    "text": .string("2:30 PM"),
                    "cache_control": .object(["type": .string("ephemeral")]),
                ])
            ])
        } else {
            Issue.record("Expected second tool message object")
        }
    }
}
