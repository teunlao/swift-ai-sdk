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

    @Test("converts messages with image parts")
    func convertsImageParts() throws {
        let imageData = Data([0, 1, 2, 3])
        let prompt: LanguageModelV3Prompt = [
            .user(
                content: [
                    .text(LanguageModelV3TextPart(text: "Hello")),
                    .file(LanguageModelV3FilePart(
                        data: .data(imageData),
                        mediaType: "image/png",
                        providerOptions: nil
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
        #expect(result == expected)
    }

    @Test("converts messages with image parts from Uint8Array")
    func convertsImagePartsFromUint8Array() throws {
        let imageData = Data([0, 1, 2, 3])
        let prompt: LanguageModelV3Prompt = [
            .user(
                content: [
                    .text(LanguageModelV3TextPart(text: "Hi")),
                    .file(LanguageModelV3FilePart(
                        data: .data(imageData),
                        mediaType: "image/png",
                        providerOptions: nil
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
                        "text": .string("Hi")
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
        #expect(result == expected)
    }

    @Test("handles URL-based images")
    func handlesURLImages() throws {
        let imageURL = URL(string: "https://example.com/image.jpg")!
        let prompt: LanguageModelV3Prompt = [
            .user(
                content: [
                    .file(LanguageModelV3FilePart(
                        data: .url(imageURL),
                        mediaType: "image/*",
                        providerOptions: nil
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
                        "type": .string("image_url"),
                        "image_url": .object([
                            "url": .string("https://example.com/image.jpg")
                        ])
                    ])
                ])
            ])
        ]
        #expect(result == expected)
    }

    @Test("handles text output type in tool results")
    func handlesTextToolResults() throws {
        let prompt: LanguageModelV3Prompt = [
            .assistant(
                content: [
                    .toolCall(LanguageModelV3ToolCallPart(
                        toolCallId: "call-1",
                        toolName: "getWeather",
                        input: .object(["query": .string("weather")])
                    ))
                ],
                providerOptions: nil
            ),
            .tool(
                content: [
                    LanguageModelV3ToolResultPart(
                        toolCallId: "call-1",
                        toolName: "getWeather",
                        output: .text(value: "It is sunny today")
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
                        "id": .string("call-1"),
                        "function": .object([
                            "name": .string("getWeather"),
                            "arguments": .string("{\"query\":\"weather\"}")
                        ])
                    ])
                ])
            ]),
            .object([
                "role": .string("tool"),
                "tool_call_id": .string("call-1"),
                "content": .string("It is sunny today")
            ])
        ]
        #expect(result == expected)
    }

    @Test("merges system message metadata")
    func mergesSystemMetadata() throws {
        let prompt: LanguageModelV3Prompt = [
            .system(
                content: "You are a helpful assistant.",
                providerOptions: [
                    "openaiCompatible": ["cacheControl": .object(["type": .string("ephemeral")])]
                ]
            )
        ]

        let result = try convertToOpenAICompatibleChatMessages(prompt: prompt)
        let expected: [JSONValue] = [
            .object([
                "role": .string("system"),
                "content": .string("You are a helpful assistant."),
                "cacheControl": .object(["type": .string("ephemeral")])
            ])
        ]
        #expect(result == expected)
    }

    @Test("merges user message content metadata")
    func mergesUserContentMetadata() throws {
        let prompt: LanguageModelV3Prompt = [
            .user(
                content: [
                    .text(LanguageModelV3TextPart(
                        text: "Hello",
                        providerOptions: [
                            "openaiCompatible": ["cacheControl": .object(["type": .string("ephemeral")])]
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
                "content": .string("Hello"),
                "cacheControl": .object(["type": .string("ephemeral")])
            ])
        ]
        #expect(result == expected)
    }

    @Test("handles tool calls with metadata")
    func handlesToolCallsWithMetadata() throws {
        let prompt: LanguageModelV3Prompt = [
            .assistant(
                content: [
                    .toolCall(LanguageModelV3ToolCallPart(
                        toolCallId: "call1",
                        toolName: "calculator",
                        input: .object(["x": .number(1), "y": .number(2)]),
                        providerOptions: [
                            "openaiCompatible": ["cacheControl": .object(["type": .string("ephemeral")])]
                        ]
                    ))
                ],
                providerOptions: nil
            )
        ]

        let result = try convertToOpenAICompatibleChatMessages(prompt: prompt)

        // Verify structure without relying on JSON key order
        #expect(result.count == 1)
        guard case .object(let msg) = result[0] else {
            Issue.record("Expected object")
            return
        }

        #expect(msg["role"] == .string("assistant"))
        #expect(msg["content"] == .string(""))

        guard case .array(let toolCalls) = msg["tool_calls"] else {
            Issue.record("Expected tool_calls array")
            return
        }

        #expect(toolCalls.count == 1)
        guard case .object(let toolCall) = toolCalls[0] else {
            Issue.record("Expected tool call object")
            return
        }

        #expect(toolCall["id"] == .string("call1"))
        #expect(toolCall["type"] == .string("function"))
        #expect(toolCall["cacheControl"] == .object(["type": .string("ephemeral")]))

        guard case .object(let function) = toolCall["function"] else {
            Issue.record("Expected function object")
            return
        }

        #expect(function["name"] == .string("calculator"))
        // Check arguments contain both x and y (order doesn't matter)
        if case .string(let args) = function["arguments"] {
            #expect(args.contains("\"x\":1"))
            #expect(args.contains("\"y\":2"))
        } else {
            Issue.record("Expected arguments string")
        }
    }

    @Test("handles image content with metadata")
    func handlesImageWithMetadata() throws {
        let imageURL = URL(string: "https://example.com/image.jpg")!
        let prompt: LanguageModelV3Prompt = [
            .user(
                content: [
                    .file(LanguageModelV3FilePart(
                        data: .url(imageURL),
                        mediaType: "image/*",
                        providerOptions: [
                            "openaiCompatible": ["cacheControl": .object(["type": .string("ephemeral")])]
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
                        "type": .string("image_url"),
                        "image_url": .object([
                            "url": .string("https://example.com/image.jpg")
                        ]),
                        "cacheControl": .object(["type": .string("ephemeral")])
                    ])
                ])
            ])
        ]
        #expect(result == expected)
    }

    @Test("omits non-openaiCompatible metadata")
    func omitsNonOpenAICompatibleMetadata() throws {
        let prompt: LanguageModelV3Prompt = [
            .system(
                content: "Hello",
                providerOptions: [
                    "someOtherProvider": ["shouldBeIgnored": .bool(true)]
                ]
            )
        ]

        let result = try convertToOpenAICompatibleChatMessages(prompt: prompt)
        let expected: [JSONValue] = [
            .object([
                "role": .string("system"),
                "content": .string("Hello")
            ])
        ]
        #expect(result == expected)
    }

    @Test("handles user message with multiple text parts")
    func handlesMultipleTextParts() throws {
        let prompt: LanguageModelV3Prompt = [
            .user(
                content: [
                    .text(LanguageModelV3TextPart(text: "Part 1")),
                    .text(LanguageModelV3TextPart(text: "Part 2"))
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
                        "text": .string("Part 1")
                    ]),
                    .object([
                        "type": .string("text"),
                        "text": .string("Part 2")
                    ])
                ])
            ])
        ]
        #expect(result == expected)
    }

    @Test("handles assistant message with text plus multiple tool calls")
    func handlesTextPlusMultipleToolCalls() throws {
        let prompt: LanguageModelV3Prompt = [
            .assistant(
                content: [
                    .text(LanguageModelV3TextPart(text: "Checking that now...")),
                    .toolCall(LanguageModelV3ToolCallPart(
                        toolCallId: "call1",
                        toolName: "searchTool",
                        input: .object(["query": .string("Weather")]),
                        providerOptions: [
                            "openaiCompatible": ["function_call_reason": .string("user request")]
                        ]
                    )),
                    .text(LanguageModelV3TextPart(text: "Almost there...")),
                    .toolCall(LanguageModelV3ToolCallPart(
                        toolCallId: "call2",
                        toolName: "mapsTool",
                        input: .object(["location": .string("Paris")])
                    ))
                ],
                providerOptions: nil
            )
        ]

        let result = try convertToOpenAICompatibleChatMessages(prompt: prompt)
        let expected: [JSONValue] = [
            .object([
                "role": .string("assistant"),
                "content": .string("Checking that now...Almost there..."),
                "tool_calls": .array([
                    .object([
                        "id": .string("call1"),
                        "type": .string("function"),
                        "function": .object([
                            "name": .string("searchTool"),
                            "arguments": .string("{\"query\":\"Weather\"}")
                        ]),
                        "function_call_reason": .string("user request")
                    ]),
                    .object([
                        "id": .string("call2"),
                        "type": .string("function"),
                        "function": .object([
                            "name": .string("mapsTool"),
                            "arguments": .string("{\"location\":\"Paris\"}")
                        ])
                    ])
                ])
            ])
        ]
        #expect(result == expected)
    }

    @Test("handles single tool role message with multiple tool-result parts")
    func handlesMultipleToolResults() throws {
        let prompt: LanguageModelV3Prompt = [
            .tool(
                content: [
                    LanguageModelV3ToolResultPart(
                        toolCallId: "call123",
                        toolName: "calculator",
                        output: .json(value: .object(["stepOne": .string("data chunk 1")]))
                    ),
                    LanguageModelV3ToolResultPart(
                        toolCallId: "call123",
                        toolName: "calculator",
                        output: .json(value: .object(["stepTwo": .string("data chunk 2")])),
                        providerOptions: [
                            "openaiCompatible": ["partial": .bool(true)]
                        ]
                    )
                ],
                providerOptions: [
                    // This message-level metadata gets omitted as we prioritize content-level
                    "openaiCompatible": ["responseTier": .string("detailed")]
                ]
            )
        ]

        let result = try convertToOpenAICompatibleChatMessages(prompt: prompt)

        // Verify we got 2 separate tool messages
        #expect(result.count == 2)

        // First tool result - no content-level metadata, so no extra fields
        guard case .object(let first) = result[0] else {
            Issue.record("Expected first result to be object")
            return
        }
        #expect(first["role"] == .string("tool"))
        #expect(first["tool_call_id"] == .string("call123"))
        #expect(first["content"] == .string("{\"stepOne\":\"data chunk 1\"}"))

        // Second tool result - has content-level metadata (partial)
        guard case .object(let second) = result[1] else {
            Issue.record("Expected second result to be object")
            return
        }
        #expect(second["role"] == .string("tool"))
        #expect(second["tool_call_id"] == .string("call123"))
        #expect(second["content"] == .string("{\"stepTwo\":\"data chunk 2\"}"))
        #expect(second["partial"] == .bool(true))
    }

    @Test("handles multiple content parts with multiple metadata layers")
    func handlesMultipleMetadataLayers() throws {
        let imageData = Data([9, 8, 7, 6])
        let prompt: LanguageModelV3Prompt = [
            .user(
                content: [
                    .text(LanguageModelV3TextPart(
                        text: "Part A",
                        providerOptions: [
                            "openaiCompatible": ["textPartLevel": .string("localized")],
                            "leftoverForText": ["info": .string("text leftover")]
                        ]
                    )),
                    .file(LanguageModelV3FilePart(
                        data: .data(imageData),
                        mediaType: "image/png",
                        providerOptions: [
                            "openaiCompatible": ["imagePartLevel": .string("image-data")]
                        ]
                    ))
                ],
                providerOptions: [
                    "openaiCompatible": ["messageLevel": .string("global-metadata")],
                    "leftoverForMessage": ["x": .number(123)]
                ]
            )
        ]

        let result = try convertToOpenAICompatibleChatMessages(prompt: prompt)
        let expected: [JSONValue] = [
            .object([
                "role": .string("user"),
                "messageLevel": .string("global-metadata"),
                "content": .array([
                    .object([
                        "type": .string("text"),
                        "text": .string("Part A"),
                        "textPartLevel": .string("localized")
                    ]),
                    .object([
                        "type": .string("image_url"),
                        "image_url": .object([
                            "url": .string("data:image/png;base64,CQgHBg==")
                        ]),
                        "imagePartLevel": .string("image-data")
                    ])
                ])
            ])
        ]
        #expect(result == expected)
    }

    @Test("handles different tool metadata vs message-level metadata")
    func handlesToolVsMessageMetadata() throws {
        let prompt: LanguageModelV3Prompt = [
            .assistant(
                content: [
                    .text(LanguageModelV3TextPart(text: "Initiating tool calls...")),
                    .toolCall(LanguageModelV3ToolCallPart(
                        toolCallId: "callXYZ",
                        toolName: "awesomeTool",
                        input: .object(["param": .string("someValue")]),
                        providerOptions: [
                            "openaiCompatible": ["toolPriority": .string("critical")]
                        ]
                    ))
                ],
                providerOptions: [
                    "openaiCompatible": ["globalPriority": .string("high")]
                ]
            )
        ]

        let result = try convertToOpenAICompatibleChatMessages(prompt: prompt)
        let expected: [JSONValue] = [
            .object([
                "role": .string("assistant"),
                "globalPriority": .string("high"),
                "content": .string("Initiating tool calls..."),
                "tool_calls": .array([
                    .object([
                        "id": .string("callXYZ"),
                        "type": .string("function"),
                        "function": .object([
                            "name": .string("awesomeTool"),
                            "arguments": .string("{\"param\":\"someValue\"}")
                        ]),
                        "toolPriority": .string("critical")
                    ])
                ])
            ])
        ]
        #expect(result == expected)
    }

    @Test("handles metadata collisions and overwrites in tool calls")
    func handlesMetadataCollisionsInToolCalls() throws {
        let prompt: LanguageModelV3Prompt = [
            .assistant(
                content: [
                    .toolCall(LanguageModelV3ToolCallPart(
                        toolCallId: "collisionToolCall",
                        toolName: "collider",
                        input: .object(["num": .number(42)]),
                        providerOptions: [
                            "openaiCompatible": [
                                "cacheControl": .object(["type": .string("ephemeral")]),
                                "sharedKey": .string("toolLevel")
                            ]
                        ]
                    ))
                ],
                providerOptions: [
                    "openaiCompatible": [
                        "cacheControl": .object(["type": .string("default")]),
                        "sharedKey": .string("assistantLevel")
                    ]
                ]
            )
        ]

        let result = try convertToOpenAICompatibleChatMessages(prompt: prompt)
        let expected: [JSONValue] = [
            .object([
                "role": .string("assistant"),
                "cacheControl": .object(["type": .string("default")]),
                "sharedKey": .string("assistantLevel"),
                "content": .string(""),
                "tool_calls": .array([
                    .object([
                        "id": .string("collisionToolCall"),
                        "type": .string("function"),
                        "function": .object([
                            "name": .string("collider"),
                            "arguments": .string("{\"num\":42}")
                        ]),
                        "cacheControl": .object(["type": .string("ephemeral")]),
                        "sharedKey": .string("toolLevel")
                    ])
                ])
            ])
        ]
        #expect(result == expected)
    }
}
