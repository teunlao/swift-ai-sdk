import Foundation
import Testing
@testable import AnthropicProvider
import AISDKProvider
import AISDKProviderUtils

private actor PromptRequestCapture {
    var request: URLRequest?
    func store(_ request: URLRequest) { self.request = request }
}

private func convert(
    _ prompt: LanguageModelV4Prompt,
    sendReasoning: Bool = true,
    tools: [LanguageModelV4Tool]? = nil
) async throws -> (AnthropicPromptConversionResult, [SharedV4Warning]) {
    let capture = PromptRequestCapture()
    let response = Data(#"{"type":"message","id":"msg_test","model":"claude-sonnet-4-5","content":[],"stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1}}"#.utf8)
    let model = createAnthropic(settings: .init(apiKey: "test-key", fetch: { request in
        await capture.store(request)
        return FetchResponse(body: .data(response), urlResponse: HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["content-type": "application/json"]
        )!)
    })).messages("claude-sonnet-4-5")
    let result = try await model.doGenerate(options: .init(
        prompt: prompt,
        tools: tools,
        providerOptions: ["anthropic": ["sendReasoning": .bool(sendReasoning)]]
    ))
    let request = try #require(await capture.request)
    let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
    guard case .object(let object) = body, case .array(let messageValues) = object["messages"] else {
        throw PromptRequestError.invalidBody
    }
    let messages = try messageValues.map { value -> AnthropicMessage in
        guard case .object(let message) = value, case .string(let role) = message["role"],
              case .array(let content) = message["content"] else { throw PromptRequestError.invalidBody }
        let clearAt: String? = if case .string(let value) = message["clear_at"] { value } else { nil }
        let outputConfig: [String: JSONValue]? = if case .object(let value) = message["output_config"] { value } else { nil }
        return AnthropicMessage(role: role, content: content, clearAt: clearAt, outputConfig: outputConfig)
    }
    let system: [JSONValue]? = if case .array(let value) = object["system"] { value } else { nil }
    let betas = Set((request.value(forHTTPHeaderField: "anthropic-beta") ?? "").split(separator: ",").map {
        $0.trimmingCharacters(in: .whitespacesAndNewlines)
    })
    return (.init(prompt: .init(system: system, messages: messages), betas: betas), result.warnings)
}

private enum PromptRequestError: Error { case invalidBody }

private func jsonString(_ value: JSONValue) -> String {
    let data = try! JSONEncoder().encode(value)
    return String(data: data, encoding: .utf8)!
}

private func anthropicOptions(_ values: [String: JSONValue]) -> SharedV4ProviderOptions {
    ["anthropic": values]
}

// MARK: - System Messages

@Suite("convertToAnthropicMessagesPrompt system messages")
struct ConvertToAnthropicMessagesPromptSystemTests {
    @Test("single system message")
    func singleSystemMessage() async throws {
        let prompt: LanguageModelV4Prompt = [
            .system(content: "This is a system message", providerOptions: nil)
        ]

        let (result, warnings) = try await convert(prompt)

        #expect(warnings.isEmpty)
        #expect(result.prompt == AnthropicMessagesPrompt(
            system: [
                .object([
                    "type": .string("text"),
                    "text": .string("This is a system message")
                ])
            ],
            messages: []
        ))
        #expect(result.betas.isEmpty)
    }

    @Test("multiple system messages")
    func multipleSystemMessages() async throws {
        let prompt: LanguageModelV4Prompt = [
            .system(content: "This is a system message", providerOptions: nil),
            .system(content: "This is another system message", providerOptions: nil)
        ]

        let (result, warnings) = try await convert(prompt)

        #expect(warnings.isEmpty)
        #expect(result.prompt == AnthropicMessagesPrompt(
            system: [
                .object([
                    "type": .string("text"),
                    "text": .string("This is a system message")
                ]),
                .object([
                    "type": .string("text"),
                    "text": .string("This is another system message")
                ])
            ],
            messages: []
        ))
        #expect(result.betas.isEmpty)
    }

    @Test("mid-conversation system message is emitted inline with beta")
    func midConversationSystemMessage() async throws {
        let prompt: LanguageModelV4Prompt = [
            .system(content: "initial", providerOptions: nil),
            .user(content: [.text(.init(text: "hi"))], providerOptions: nil),
            .assistant(content: [.text(.init(text: "hello"))], providerOptions: nil),
            .system(content: "switch tone", providerOptions: nil),
            .user(content: [.text(.init(text: "go"))], providerOptions: nil),
        ]

        let (result, warnings) = try await convert(prompt)

        #expect(warnings.isEmpty)
        #expect(result.prompt.system == [
            .object(["type": .string("text"), "text": .string("initial")])
        ])
        #expect(result.prompt.messages.contains(AnthropicMessage(
            role: "system",
            content: [.object(["type": .string("text"), "text": .string("switch tone")])]
        )))
        #expect(result.betas == Set(["mid-conversation-system-2026-04-07"]))
    }

    @Test("system message uses cache control from provider options")
    func systemMessageCacheControl() async throws {
        let prompt: LanguageModelV4Prompt = [
            .system(
                content: "Cached system",
                providerOptions: anthropicOptions([
                    "cacheControl": .object([
                        "type": .string("ephemeral"),
                        "ttl": .string("5m")
                    ])
                ])
            )
        ]

        let (result, warnings) = try await convert(prompt)

        #expect(warnings.isEmpty)
        #expect(result.prompt == AnthropicMessagesPrompt(
            system: [
                .object([
                    "type": .string("text"),
                    "text": .string("Cached system"),
                    "cache_control": .object([
                        "type": .string("ephemeral"),
                        "ttl": .string("5m")
                    ])
                ])
            ],
            messages: []
        ))
    }
}

// MARK: - User Messages

@Suite("convertToAnthropicMessagesPrompt user messages")
struct ConvertToAnthropicMessagesPromptUserTests {
    @Test("image data part")
    func imageDataPart() async throws {
        let filePart = LanguageModelV4FilePart(
            data: .base64("AAECAw=="),
            mediaType: "image/png"
        )
        let prompt: LanguageModelV4Prompt = [
            .user(content: [.file(filePart)], providerOptions: nil)
        ]

        let (result, warnings) = try await convert(prompt)

        #expect(warnings.isEmpty)
        #expect(result.prompt == AnthropicMessagesPrompt(
            system: nil,
            messages: [
                AnthropicMessage(
                    role: "user",
                    content: [
                        .object([
                            "type": .string("image"),
                            "source": .object([
                                "type": .string("base64"),
                                "data": .string("AAECAw=="),
                                "media_type": .string("image/png")
                            ])
                        ])
                    ]
                )
            ]
        ))
        #expect(result.betas.isEmpty)
    }

    @Test("image url part")
    func imageURLPart() async throws {
        let filePart = LanguageModelV4FilePart(
            data: .url(URL(string: "https://example.com/image.png")!),
            mediaType: "image/*"
        )
        let prompt: LanguageModelV4Prompt = [
            .user(content: [.file(filePart)], providerOptions: nil)
        ]

        let (result, warnings) = try await convert(prompt)

        #expect(warnings.isEmpty)
        #expect(result.prompt == AnthropicMessagesPrompt(
            system: nil,
            messages: [
                AnthropicMessage(
                    role: "user",
                    content: [
                        .object([
                            "type": .string("image"),
                            "source": .object([
                                "type": .string("url"),
                                "url": .string("https://example.com/image.png")
                            ])
                        ])
                    ]
                )
            ]
        ))
        #expect(result.betas.isEmpty)
    }

    @Test("pdf document adds beta and metadata")
    func pdfDocumentAddsBeta() async throws {
        let providerOptions = anthropicOptions([
            "title": .string("Product Requirements"),
            "context": .string("Q1 scope"),
            "citations": .object(["enabled": .bool(true)])
        ])
        let filePart = LanguageModelV4FilePart(
            data: .base64("BASE64PDF=="),
            mediaType: "application/pdf",
            filename: "requirements.pdf",
            providerOptions: providerOptions
        )
        let prompt: LanguageModelV4Prompt = [
            .user(content: [.file(filePart)], providerOptions: nil)
        ]

        let (result, warnings) = try await convert(prompt)

        #expect(warnings.isEmpty)
        #expect(result.betas == Set(["pdfs-2024-09-25"]))
        #expect(result.prompt == AnthropicMessagesPrompt(
            system: nil,
            messages: [
                AnthropicMessage(
                    role: "user",
                    content: [
                        .object([
                            "type": .string("document"),
                            "source": .object([
                                "type": .string("base64"),
                                "media_type": .string("application/pdf"),
                                "data": .string("BASE64PDF==")
                            ]),
                            "title": .string("Product Requirements"),
                            "context": .string("Q1 scope"),
                            "citations": .object(["enabled": .bool(true)])
                        ])
                    ]
                )
            ]
        ))
    }

    @Test("text document adds beta and respects cache control")
    func textDocumentAddsBeta() async throws {
        let providerOptions = anthropicOptions([
            "title": .string("Doc"),
            "citations": .object(["enabled": .bool(true)])
        ])
        let messageOptions = anthropicOptions([
            "cacheControl": .object([
                "type": .string("ephemeral"),
                "ttl": .string("1h")
            ])
        ])
        let filePart = LanguageModelV4FilePart(
            data: .data("hello".data(using: .utf8)!),
            mediaType: "text/plain",
            filename: "notes.txt",
            providerOptions: providerOptions
        )
        let prompt: LanguageModelV4Prompt = [
            .user(content: [.file(filePart)], providerOptions: messageOptions)
        ]

        let (result, warnings) = try await convert(prompt)

        #expect(warnings.isEmpty)
        #expect(result.betas.isEmpty)
        #expect(result.prompt == AnthropicMessagesPrompt(
            system: nil,
            messages: [
                AnthropicMessage(
                    role: "user",
                    content: [
                        .object([
                            "type": .string("document"),
                            "source": .object([
                                "type": .string("text"),
                                "media_type": .string("text/plain"),
                                "data": .string("hello")
                            ]),
                            "title": .string("Doc"),
                            "citations": .object(["enabled": .bool(true)]),
                            "cache_control": .object([
                                "type": .string("ephemeral"),
                                "ttl": .string("1h")
                            ])
                        ])
                    ]
                )
            ]
        ))
    }
}

// MARK: - Tool Messages

@Suite("convertToAnthropicMessagesPrompt tool messages")
struct ConvertToAnthropicMessagesPromptToolTests {
    @Test("tool result with json output")
    func toolResultJSON() async throws {
        let toolPart = LanguageModelV4ToolResultPart(
            toolCallId: "call-1",
            toolName: "calculator",
            output: .json(value: .object(["answer": .number(42)]))
        )
        let prompt: LanguageModelV4Prompt = [
            .tool(content: [.toolResult(toolPart)], providerOptions: nil)
        ]

        let (result, warnings) = try await convert(prompt)

        #expect(warnings.isEmpty)
        #expect(result.prompt.messages == [
            AnthropicMessage(
                role: "user",
                content: [
                    .object([
                        "type": .string("tool_result"),
                        "tool_use_id": .string("call-1"),
                        "content": .string(jsonString(.object(["answer": .number(42)])))
                    ])
                ]
            )
        ])
    }

    @Test("tool result with content parts adds pdf beta")
    func toolResultContentAddsBeta() async throws {
        let output = LanguageModelV4ToolResultOutput.content(value: [
            .text(text: "summary", providerOptions: nil),
            .file(data: .base64("PDFDATA"), mediaType: "application/pdf", filename: nil, providerOptions: nil)
        ])
        let toolPart = LanguageModelV4ToolResultPart(
            toolCallId: "call-2",
            toolName: "aggregator",
            output: output
        )
        let prompt: LanguageModelV4Prompt = [
            .tool(content: [.toolResult(toolPart)], providerOptions: nil)
        ]

        let (result, warnings) = try await convert(prompt)

        #expect(warnings.isEmpty)
        #expect(result.betas == Set(["pdfs-2024-09-25"]))
        #expect(result.prompt.messages == [
            AnthropicMessage(
                role: "user",
                content: [
                    .object([
                        "type": .string("tool_result"),
                        "tool_use_id": .string("call-2"),
                        "content": .array([
                            .object([
                                "type": .string("text"),
                                "text": .string("summary")
                            ]),
                            .object([
                                "type": .string("document"),
                                "source": .object([
                                    "type": .string("base64"),
                                    "media_type": .string("application/pdf"),
                                    "data": .string("PDFDATA")
                                ])
                            ])
                        ])
                    ])
                ]
            )
        ])
    }
}

// MARK: - Assistant Messages

// MARK: - JSON Key Ordering Stability

@Suite("convertToAnthropicMessagesPrompt JSON key ordering")
struct ConvertToAnthropicMessagesPromptKeyOrderingTests {
    @Test("tool result with json output uses sorted keys")
    func toolResultJSONUsesSortedKeys() async throws {
        let toolPart = LanguageModelV4ToolResultPart(
            toolCallId: "call-1",
            toolName: "mcp_tool",
            output: .json(value: .object([
                "zebra": .string("last"),
                "alpha": .string("first"),
                "middle": .number(42),
            ]))
        )
        let prompt: LanguageModelV4Prompt = [
            .tool(content: [.toolResult(toolPart)], providerOptions: nil)
        ]

        let (result, _) = try await convert(prompt)
        let msg = try #require(result.prompt.messages.first)
        let block = try #require(msg.content.first)

        guard case .object(let obj) = block,
              case .string(let contentString) = obj["content"] else {
            Issue.record("Expected tool_result with string content")
            return
        }

        #expect(contentString == #"{"alpha":"first","middle":42,"zebra":"last"}"#)
    }

}

// MARK: - Assistant Messages

@Suite("convertToAnthropicMessagesPrompt assistant messages")
struct ConvertToAnthropicMessagesPromptAssistantTests {
    @Test("assistant text trims final whitespace")
    func assistantTextTrim() async throws {
        let message = LanguageModelV4Message.assistant(
            content: [
                .text(.init(text: "\u{feff}Hello world\u{0085}  \n"))
            ],
            providerOptions: nil
        )
        let prompt: LanguageModelV4Prompt = [message]

        let (result, warnings) = try await convert(prompt)

        #expect(warnings.isEmpty)
        #expect(result.prompt.messages == [
            AnthropicMessage(
                role: "assistant",
                content: [
                    .object([
                        "type": .string("text"),
                        "text": .string("Hello world\u{0085}")
                    ])
                ]
            )
        ])
    }

    @Test("assistant compaction text preserves its API discriminator")
    func assistantCompactionText() async throws {
        let prompt: LanguageModelV4Prompt = [
            .assistant(
                content: [
                    .text(.init(
                        text: "Condensed context",
                        providerOptions: anthropicOptions(["type": .string("compaction")])
                    ))
                ],
                providerOptions: nil
            )
        ]

        let (result, warnings) = try await convert(prompt)

        #expect(warnings.isEmpty)
        #expect(result.prompt.messages == [
            AnthropicMessage(
                role: "assistant",
                content: [
                    .object([
                        "type": .string("compaction"),
                        "content": .string("Condensed context"),
                    ])
                ]
            )
        ])
    }

    @Test("assistant client tool use follows provider-executed tool results")
    func clientToolUseFollowsProviderToolResults() async throws {
        let prompt: LanguageModelV4Prompt = [
            .assistant(
                content: [
                    .text(.init(text: "I will save a note and search.")),
                    .toolCall(.init(
                        toolCallId: "toolu_regular",
                        toolName: "saveNote",
                        input: .object(["note": .string("basketball news")])
                    )),
                    .toolCall(.init(
                        toolCallId: "srvtoolu_web_search",
                        toolName: "web_search",
                        input: .object(["query": .string("basketball news today")]),
                        providerExecuted: true
                    )),
                    .toolResult(.init(
                        toolCallId: "srvtoolu_web_search",
                        toolName: "web_search",
                        output: .json(value: .array([
                            .object([
                                "url": .string("https://www.nba.com/news"),
                                "title": .string("NBA News"),
                                "pageAge": .string("1 hour ago"),
                                "encryptedContent": .string("encrypted-content"),
                                "type": .string("web_search_result"),
                            ])
                        ]))
                    )),
                ],
                providerOptions: nil
            )
        ]

        let (result, warnings) = try await convert(prompt)
        let content = try #require(result.prompt.messages.first?.content)
        let types = content.compactMap { value -> String? in
            guard case .object(let object) = value,
                  case .string(let type) = object["type"] else { return nil }
            return type
        }

        #expect(warnings.isEmpty)
        #expect(types == ["text", "server_tool_use", "web_search_tool_result", "tool_use"])
    }

    @Test("assistant tool-use reordering does not cross thinking boundaries")
    func toolUseReorderingPreservesThinkingBoundaries() async throws {
        let prompt: LanguageModelV4Prompt = [
            .assistant(
                content: [
                    .reasoning(.init(
                        text: "Think before the initial note.",
                        providerOptions: anthropicOptions(["signature": .string("sig-1")])
                    )),
                    .toolCall(.init(
                        toolCallId: "toolu_initial",
                        toolName: "saveNote",
                        input: .object([:])
                    )),
                    .reasoning(.init(
                        text: "Think before the revised note.",
                        providerOptions: anthropicOptions(["signature": .string("sig-2")])
                    )),
                    .toolCall(.init(
                        toolCallId: "toolu_revised",
                        toolName: "saveNote",
                        input: .object([:])
                    )),
                ],
                providerOptions: nil
            )
        ]

        let (result, warnings) = try await convert(prompt)
        let content = try #require(result.prompt.messages.first?.content)
        let types = content.compactMap { value -> String? in
            guard case .object(let object) = value,
                  case .string(let type) = object["type"] else { return nil }
            return type
        }

        #expect(warnings.isEmpty)
        #expect(types == ["thinking", "tool_use", "thinking", "tool_use"])
    }

    @Test("assistant reasoning requires signature metadata")
    func assistantReasoningWithSignature() async throws {
        let reasoningPart = LanguageModelV4MessagePart.reasoning(
            .init(
                text: "Chain of thought",
                providerOptions: anthropicOptions([
                    "signature": .string("sig-123")
                ])
            )
        )
        let prompt: LanguageModelV4Prompt = [
            .assistant(content: [reasoningPart], providerOptions: nil)
        ]

        let (result, warnings) = try await convert(prompt)

        #expect(warnings.isEmpty)
        #expect(result.prompt.messages == [
            AnthropicMessage(
                role: "assistant",
                content: [
                    .object([
                        "type": .string("thinking"),
                        "thinking": .string("Chain of thought"),
                        "signature": .string("sig-123")
                    ])
                ]
            )
        ])
    }

    @Test("assistant reasoning disabled adds warning")
    func assistantReasoningDisabled() async throws {
        let reasoningPart = LanguageModelV4MessagePart.reasoning(
            .init(text: "Hidden thoughts", providerOptions: nil)
        )
        let prompt: LanguageModelV4Prompt = [
            .assistant(content: [reasoningPart], providerOptions: nil)
        ]

        let (_, warnings) = try await convert(prompt, sendReasoning: false)

        #expect(warnings.contains(.other(message: "sending reasoning content is disabled for this model")))
    }

    @Test("assistant provider executed tool call mapped to server tool use")
    func assistantProviderExecutedToolCall() async throws {
        let toolCall = LanguageModelV4MessagePart.toolCall(
            .init(
                toolCallId: "tool-1",
                toolName: "code_execution",
                input: .object(["code": .string("print('hi')")]),
                providerExecuted: true
            )
        )
        let prompt: LanguageModelV4Prompt = [
            .assistant(content: [toolCall], providerOptions: nil)
        ]

        let (result, warnings) = try await convert(prompt)

        #expect(warnings.isEmpty)
        #expect(result.betas.isEmpty)
        #expect(result.prompt.messages == [
            AnthropicMessage(
                role: "assistant",
                content: [
                    .object([
                        "type": .string("server_tool_use"),
                        "id": .string("tool-1"),
                        "name": .string("code_execution"),
                        "input": .object(["code": .string("print('hi')")])
                    ])
                ]
            )
        ])
    }

    @Test("assistant provider executed code_execution 20250825 maps subtool name for bash_code_execution")
    func assistantProviderExecutedCodeExecutionSubtoolBash() async throws {
        let toolCall = LanguageModelV4MessagePart.toolCall(
            .init(
                toolCallId: "tool-1",
                toolName: "code_execution",
                input: .object([
                    "type": .string("bash_code_execution"),
                    "command": .string("python /tmp/fibonacci.py"),
                ]),
                providerExecuted: true
            )
        )
        let prompt: LanguageModelV4Prompt = [
            .assistant(content: [toolCall], providerOptions: nil)
        ]

        let (result, warnings) = try await convert(prompt)

        #expect(warnings.isEmpty)
        #expect(result.betas.isEmpty)
        #expect(result.prompt.messages == [
            AnthropicMessage(
                role: "assistant",
                content: [
                    .object([
                        "type": .string("server_tool_use"),
                        "id": .string("tool-1"),
                        "name": .string("bash_code_execution"),
                        "input": .object([
                            "command": .string("python /tmp/fibonacci.py"),
                        ]),
                    ])
                ]
            )
        ])
    }

    @Test("assistant provider executed code_execution 20250825 maps subtool name for text_editor_code_execution")
    func assistantProviderExecutedCodeExecutionSubtoolTextEditor() async throws {
        let toolCall = LanguageModelV4MessagePart.toolCall(
            .init(
                toolCallId: "tool-1",
                toolName: "code_execution",
                input: .object([
                    "type": .string("text_editor_code_execution"),
                    "command": .string("view"),
                    "path": .string("/tmp/file.txt"),
                ]),
                providerExecuted: true
            )
        )
        let prompt: LanguageModelV4Prompt = [
            .assistant(content: [toolCall], providerOptions: nil)
        ]

        let (result, warnings) = try await convert(prompt)

        #expect(warnings.isEmpty)
        #expect(result.betas.isEmpty)
        #expect(result.prompt.messages == [
            AnthropicMessage(
                role: "assistant",
                content: [
                    .object([
                        "type": .string("server_tool_use"),
                        "id": .string("tool-1"),
                        "name": .string("text_editor_code_execution"),
                        "input": .object([
                            "command": .string("view"),
                            "path": .string("/tmp/file.txt"),
                        ]),
                    ])
                ]
            )
        ])
    }

    @Test("assistant provider executed code_execution 20250825 strips programmatic-tool-call type")
    func assistantProviderExecutedCodeExecutionProgrammaticToolCalling() async throws {
        let toolCall = LanguageModelV4MessagePart.toolCall(
            .init(
                toolCallId: "tool-1",
                toolName: "code_execution",
                input: .object([
                    "type": .string("programmatic-tool-call"),
                    "code": .string("print('hi')"),
                ]),
                providerExecuted: true
            )
        )
        let prompt: LanguageModelV4Prompt = [
            .assistant(content: [toolCall], providerOptions: nil)
        ]

        let (result, warnings) = try await convert(prompt)

        #expect(warnings.isEmpty)
        #expect(result.betas.isEmpty)
        #expect(result.prompt.messages == [
            AnthropicMessage(
                role: "assistant",
                content: [
                    .object([
                        "type": .string("server_tool_use"),
                        "id": .string("tool-1"),
                        "name": .string("code_execution"),
                        "input": .object([
                            "code": .string("print('hi')"),
                        ]),
                    ])
                ]
            )
        ])
    }

    @Test("assistant tool call mapped to tool use with object input")
    func assistantToolCallUsesObjectInput() async throws {
        let toolCall = LanguageModelV4MessagePart.toolCall(
            .init(
                toolCallId: "tool-1",
                toolName: "read",
                input: .object(["path": .string("hello.txt")]),
                providerExecuted: false
            )
        )
        let prompt: LanguageModelV4Prompt = [
            .assistant(content: [toolCall], providerOptions: nil)
        ]

        let (result, warnings) = try await convert(prompt)

        #expect(warnings.isEmpty)
        #expect(result.prompt.messages == [
            AnthropicMessage(
                role: "assistant",
                content: [
                    .object([
                        "type": .string("tool_use"),
                        "id": .string("tool-1"),
                        "name": .string("read"),
                        "input": .object(["path": .string("hello.txt")])
                    ])
                ]
            )
        ])
    }

    @Test("assistant tool call includes caller metadata when present in providerOptions")
    func assistantToolCallCallerMetadata() async throws {
        let toolCall = LanguageModelV4MessagePart.toolCall(
            .init(
                toolCallId: "tool-1",
                toolName: "rollDie",
                input: .object(["player": .string("player1")]),
                providerExecuted: false,
                providerOptions: anthropicOptions([
                    "caller": .object([
                        "type": .string("code_execution_20250825"),
                        "toolId": .string("srvtoolu_1"),
                    ])
                ])
            )
        )
        let prompt: LanguageModelV4Prompt = [
            .assistant(content: [toolCall], providerOptions: nil)
        ]

        let (result, warnings) = try await convert(prompt)

        #expect(warnings.isEmpty)
        #expect(result.betas.isEmpty)
        #expect(result.prompt.messages == [
            AnthropicMessage(
                role: "assistant",
                content: [
                    .object([
                        "type": .string("tool_use"),
                        "id": .string("tool-1"),
                        "name": .string("rollDie"),
                        "input": .object(["player": .string("player1")]),
                        "caller": .object([
                            "type": .string("code_execution_20250825"),
                            "tool_id": .string("srvtoolu_1"),
                        ])
                    ])
                ]
            )
        ])
    }

    @Test("assistant tool call includes 20260120 caller metadata when present in providerOptions")
    func assistantToolCallCallerMetadata20260120() async throws {
        let toolCall = LanguageModelV4MessagePart.toolCall(
            .init(
                toolCallId: "tool-1",
                toolName: "rollDie",
                input: .object(["player": .string("player1")]),
                providerExecuted: false,
                providerOptions: anthropicOptions([
                    "caller": .object([
                        "type": .string("code_execution_20260120"),
                        "toolId": .string("srvtoolu_1"),
                    ])
                ])
            )
        )
        let prompt: LanguageModelV4Prompt = [
            .assistant(content: [toolCall], providerOptions: nil)
        ]

        let (result, warnings) = try await convert(prompt)

        #expect(warnings.isEmpty)
        #expect(result.betas.isEmpty)
        #expect(result.prompt.messages == [
            AnthropicMessage(
                role: "assistant",
                content: [
                    .object([
                        "type": .string("tool_use"),
                        "id": .string("tool-1"),
                        "name": .string("rollDie"),
                        "input": .object(["player": .string("player1")]),
                        "caller": .object([
                            "type": .string("code_execution_20260120"),
                            "tool_id": .string("srvtoolu_1"),
                        ])
                    ])
                ]
            )
        ])
    }

    @Test("assistant tool call includes direct caller metadata")
    func assistantToolCallDirectCallerMetadata() async throws {
        let toolCall = LanguageModelV4MessagePart.toolCall(
            .init(
                toolCallId: "tool-1",
                toolName: "rollDie",
                input: .object(["player": .string("player1")]),
                providerExecuted: false,
                providerOptions: anthropicOptions([
                    "caller": .object([
                        "type": .string("direct"),
                    ])
                ])
            )
        )
        let prompt: LanguageModelV4Prompt = [
            .assistant(content: [toolCall], providerOptions: nil)
        ]

        let (result, warnings) = try await convert(prompt)

        #expect(warnings.isEmpty)
        #expect(result.betas.isEmpty)
        #expect(result.prompt.messages == [
            AnthropicMessage(
                role: "assistant",
                content: [
                    .object([
                        "type": .string("tool_use"),
                        "id": .string("tool-1"),
                        "name": .string("rollDie"),
                        "input": .object(["player": .string("player1")]),
                        "caller": .object([
                            "type": .string("direct"),
                        ])
                    ])
                ]
            )
        ])
    }

    @Test("assistant provider executed tool call unsupported warns")
    func assistantProviderExecutedUnsupportedToolCall() async throws {
        let toolCall = LanguageModelV4MessagePart.toolCall(
            .init(
                toolCallId: "tool-2",
                toolName: "unsupported",
                input: .object([:]),
                providerExecuted: true
            )
        )
        let prompt: LanguageModelV4Prompt = [
            .assistant(content: [toolCall], providerOptions: nil)
        ]

        let (_, warnings) = try await convert(prompt)

        #expect(warnings.contains(.other(message: "provider executed tool call for tool unsupported is not supported")))
    }

    @Test("assistant provider executed tool_search_tool_regex tool call and result parts")
    func assistantToolSearchToolRegexCallAndResult() async throws {
        let toolCall = LanguageModelV4MessagePart.toolCall(
            .init(
                toolCallId: "srvtoolu_01SACvPAnp6ucMJsstB5qb3f",
                toolName: "tool_search_tool_regex",
                input: .object([
                    "pattern": .string("weather|forecast"),
                    "limit": .number(10),
                ]),
                providerExecuted: true
            )
        )
        let toolResult = LanguageModelV4MessagePart.toolResult(
            .init(
                toolCallId: "srvtoolu_01SACvPAnp6ucMJsstB5qb3f",
                toolName: "tool_search_tool_regex",
                output: .json(value: .array([
                    .object([
                        "type": .string("tool_reference"),
                        "toolName": .string("get_weather"),
                    ])
                ]))
            )
        )
        let prompt: LanguageModelV4Prompt = [
            .assistant(content: [toolCall, toolResult], providerOptions: nil)
        ]

        let (result, warnings) = try await convert(prompt)

        #expect(warnings.isEmpty)
        #expect(result.betas.isEmpty)
        #expect(result.prompt.messages == [
            AnthropicMessage(
                role: "assistant",
                content: [
                    .object([
                        "type": .string("server_tool_use"),
                        "id": .string("srvtoolu_01SACvPAnp6ucMJsstB5qb3f"),
                        "name": .string("tool_search_tool_regex"),
                        "input": .object([
                            "pattern": .string("weather|forecast"),
                            "limit": .number(10),
                        ]),
                    ]),
                    .object([
                        "type": .string("tool_search_tool_result"),
                        "tool_use_id": .string("srvtoolu_01SACvPAnp6ucMJsstB5qb3f"),
                        "content": .object([
                            "type": .string("tool_search_tool_search_result"),
                            "tool_references": .array([
                                .object([
                                    "type": .string("tool_reference"),
                                    "tool_name": .string("get_weather"),
                                ])
                            ]),
                        ]),
                    ]),
                ]
            )
        ])
    }

    @Test("assistant advisor calls and result variants round-trip to API blocks")
    func assistantAdvisorRoundTrip() async throws {
        let prompt: LanguageModelV4Prompt = [
            .assistant(content: [
                .toolCall(.init(
                    toolCallId: "advisor-plain",
                    toolName: "advisor",
                    input: .object(["ignored": .bool(true)]),
                    providerExecuted: true
                )),
                .toolResult(.init(
                    toolCallId: "advisor-plain",
                    toolName: "advisor",
                    output: .json(value: .object([
                        "type": .string("advisor_result"),
                        "text": .string("Use a channel-based coordination pattern."),
                    ]))
                )),
                .toolCall(.init(
                    toolCallId: "advisor-redacted",
                    toolName: "advisor",
                    input: .object([:]),
                    providerExecuted: true
                )),
                .toolResult(.init(
                    toolCallId: "advisor-redacted",
                    toolName: "advisor",
                    output: .json(value: .object([
                        "type": .string("advisor_redacted_result"),
                        "encryptedContent": .string("opaque-encrypted-advice"),
                        "stopReason": .string("end_turn"),
                    ]))
                )),
                .toolCall(.init(
                    toolCallId: "advisor-error",
                    toolName: "advisor",
                    input: .object([:]),
                    providerExecuted: true
                )),
                .toolResult(.init(
                    toolCallId: "advisor-error",
                    toolName: "advisor",
                    output: .errorJson(value: .object([
                        "type": .string("advisor_tool_result_error"),
                        "errorCode": .string("max_uses_exceeded"),
                    ]))
                )),
            ], providerOptions: nil)
        ]

        let (result, warnings) = try await convert(prompt)

        #expect(warnings.isEmpty)
        #expect(result.prompt.messages == [
            AnthropicMessage(
                role: "assistant",
                content: [
                    .object([
                        "type": .string("server_tool_use"),
                        "id": .string("advisor-plain"),
                        "name": .string("advisor"),
                        "input": .object([:]),
                    ]),
                    .object([
                        "type": .string("advisor_tool_result"),
                        "tool_use_id": .string("advisor-plain"),
                        "content": .object([
                            "type": .string("advisor_result"),
                            "text": .string("Use a channel-based coordination pattern."),
                        ]),
                    ]),
                    .object([
                        "type": .string("server_tool_use"),
                        "id": .string("advisor-redacted"),
                        "name": .string("advisor"),
                        "input": .object([:]),
                    ]),
                    .object([
                        "type": .string("advisor_tool_result"),
                        "tool_use_id": .string("advisor-redacted"),
                        "content": .object([
                            "type": .string("advisor_redacted_result"),
                            "encrypted_content": .string("opaque-encrypted-advice"),
                            "stop_reason": .string("end_turn"),
                        ]),
                    ]),
                    .object([
                        "type": .string("server_tool_use"),
                        "id": .string("advisor-error"),
                        "name": .string("advisor"),
                        "input": .object([:]),
                    ]),
                    .object([
                        "type": .string("advisor_tool_result"),
                        "tool_use_id": .string("advisor-error"),
                        "content": .object([
                            "type": .string("advisor_tool_result_error"),
                            "error_code": .string("max_uses_exceeded"),
                        ]),
                    ]),
                ]
            )
        ])
    }

    @Test("assistant mcp tool use call and result parts")
    func assistantMcpToolUseCallAndResult() async throws {
        let toolCall = LanguageModelV4MessagePart.toolCall(
            .init(
                toolCallId: "mcptoolu_01HXPYHs79HH36fBbKHysCrp",
                toolName: "echo",
                input: .object([:]),
                providerExecuted: true,
                providerOptions: anthropicOptions([
                    "type": .string("mcp-tool-use"),
                    "serverName": .string("echo"),
                ])
            )
        )
        let toolResult = LanguageModelV4MessagePart.toolResult(
            .init(
                toolCallId: "mcptoolu_01HXPYHs79HH36fBbKHysCrp",
                toolName: "echo",
                output: .json(value: .array([
                    .object([
                        "type": .string("text"),
                        "text": .string("Tool echo: hello world"),
                    ])
                ]))
            )
        )
        let text = LanguageModelV4MessagePart.text(
            .init(text: "The echo tool responded back.")
        )
        let prompt: LanguageModelV4Prompt = [
            .assistant(content: [toolCall, toolResult, text], providerOptions: nil)
        ]

        let (result, warnings) = try await convert(prompt)

        #expect(result.betas.isEmpty)
        #expect(result.prompt.messages == [
            AnthropicMessage(
                role: "assistant",
                content: [
                    .object([
                        "type": .string("mcp_tool_use"),
                        "id": .string("mcptoolu_01HXPYHs79HH36fBbKHysCrp"),
                        "name": .string("echo"),
                        "input": .object([:]),
                        "server_name": .string("echo"),
                    ]),
                    .object([
                        "type": .string("mcp_tool_result"),
                        "tool_use_id": .string("mcptoolu_01HXPYHs79HH36fBbKHysCrp"),
                        "is_error": .bool(false),
                        "content": .array([
                            .object([
                                "type": .string("text"),
                                "text": .string("Tool echo: hello world"),
                            ])
                        ]),
                    ]),
                    .object([
                        "type": .string("text"),
                        "text": .string("The echo tool responded back."),
                    ]),
                ]
            )
        ])
        #expect(warnings == [
            .other(message: "provider executed tool result for tool echo is not supported")
        ])
    }

    @Test("assistant server tool results mapped to provider metadata")
    func assistantServerToolResults() async throws {
        let codeCall = LanguageModelV4MessagePart.toolCall(
            .init(
                toolCallId: "tool-1",
                toolName: "code_execution",
                input: .object([:]),
                providerExecuted: true
            )
        )
        let webFetchCall = LanguageModelV4MessagePart.toolCall(
            .init(
                toolCallId: "tool-2",
                toolName: "web_fetch",
                input: .object([:]),
                providerExecuted: true
            )
        )
        let codeResult = LanguageModelV4MessagePart.toolResult(
            .init(
                toolCallId: "tool-1",
                toolName: "code_execution",
                output: .json(value: .object([
                    "type": .string("code_execution_result"),
                    "stdout": .string("done"),
                    "stderr": .string(""),
                    "return_code": .number(0),
                    "content": .array([])
                ]))
            )
        )
        let webFetchResult = LanguageModelV4MessagePart.toolResult(
            .init(
                toolCallId: "tool-2",
                toolName: "web_fetch",
                output: .json(value: .object([
                    "type": .string("web_fetch_result"),
                    "url": .string("https://example.com"),
                    "retrievedAt": .string("2024-01-01T00:00:00Z"),
                    "content": .object([
                        "type": .string("document"),
                        "title": .string("Example"),
                        "source": .object([
                            "type": .string("text"),
                            "mediaType": .string("text/plain"),
                            "data": .string("Example content")
                        ])
                    ])
                ]))
            )
        )
        let prompt: LanguageModelV4Prompt = [
            .assistant(content: [codeCall, webFetchCall, codeResult, webFetchResult], providerOptions: nil)
        ]

        let (result, warnings) = try await convert(prompt)

        #expect(warnings.isEmpty)
        #expect(result.betas.isEmpty)
        guard let content = result.prompt.messages.first?.content else {
            Issue.record("Expected assistant content")
            return
        }
        #expect(content.count == 4)
        if case let .object(first) = content[0] {
            #expect(first["type"] == .string("server_tool_use"))
        } else {
            Issue.record("Expected server tool use entry for code execution")
        }
        if case let .object(second) = content[1] {
            #expect(second["type"] == .string("server_tool_use"))
        } else {
            Issue.record("Expected server tool use entry for web fetch")
        }
        if case let .object(third) = content[2] {
            #expect(third["type"] == .string("code_execution_tool_result"))
        } else {
            Issue.record("Expected code execution tool result object")
        }
        if case let .object(fourth) = content[3] {
            #expect(fourth["type"] == .string("web_fetch_tool_result"))
        } else {
            Issue.record("Expected web fetch tool result object")
        }
    }

    @Test("assistant server tool maps encrypted code execution results")
    func assistantEncryptedCodeExecutionServerToolResult() async throws {
        let codeCall = LanguageModelV4MessagePart.toolCall(
            .init(
                toolCallId: "tool-1",
                toolName: "code_execution",
                input: .object([:]),
                providerExecuted: true
            )
        )
        let codeResult = LanguageModelV4MessagePart.toolResult(
            .init(
                toolCallId: "tool-1",
                toolName: "code_execution",
                output: .json(value: .object([
                    "type": .string("encrypted_code_execution_result"),
                    "encrypted_stdout": .string("ciphertext"),
                    "stderr": .string(""),
                    "return_code": .number(0),
                    "content": .array([])
                ]))
            )
        )
        let prompt: LanguageModelV4Prompt = [
            .assistant(content: [codeCall, codeResult], providerOptions: nil)
        ]

        let (result, warnings) = try await convert(prompt)

        #expect(warnings.isEmpty)
        guard let content = result.prompt.messages.first?.content else {
            Issue.record("Expected assistant content")
            return
        }
        #expect(content.count == 2)
        guard case let .object(second) = content[1] else {
            Issue.record("Expected code execution tool result object")
            return
        }

        #expect(second["type"] == .string("code_execution_tool_result"))
        #expect(second["tool_use_id"] == .string("tool-1"))
        guard case let .object(resultContent)? = second["content"] else {
            Issue.record("Expected code execution result content object")
            return
        }

        #expect(resultContent["type"] == .string("encrypted_code_execution_result"))
        #expect(resultContent["encrypted_stdout"] == .string("ciphertext"))
        #expect(resultContent["stderr"] == .string(""))
        #expect(resultContent["return_code"] == .number(0))
        #expect(resultContent["content"] == .array([]))
    }

    @Test("provider executed web search supports null title/pageAge")
    func providerExecutedWebSearchNulls() async throws {
        let webSearchCall = LanguageModelV4MessagePart.toolCall(
            .init(
                toolCallId: "tool-1",
                toolName: "web_search",
                input: .object([:]),
                providerExecuted: true
            )
        )
        let webSearchResult = LanguageModelV4MessagePart.toolResult(
            .init(
                toolCallId: "tool-1",
                toolName: "web_search",
                output: .json(value: .array([
                    .object([
                        "url": .string("https://example.com"),
                        "title": .null,
                        "pageAge": .null,
                        "encryptedContent": .string("encrypted"),
                        "type": .string("web_search_result"),
                    ])
                ]))
            )
        )

        let prompt: LanguageModelV4Prompt = [
            .assistant(content: [webSearchCall, webSearchResult], providerOptions: nil)
        ]

        let (result, warnings) = try await convert(prompt)
        #expect(warnings.isEmpty)

        guard let content = result.prompt.messages.first?.content else {
            Issue.record("Expected assistant content")
            return
        }

        #expect(content.count == 2)
        guard case let .object(webSearchToolResult) = content[1] else {
            Issue.record("Expected web_search_tool_result content object")
            return
        }

        #expect(webSearchToolResult["type"] == .string("web_search_tool_result"))
        #expect(webSearchToolResult["tool_use_id"] == .string("tool-1"))
        guard case let .array(items)? = webSearchToolResult["content"] else {
            Issue.record("Expected web_search_tool_result content array")
            return
        }
        #expect(items.count == 1)
        guard case let .object(item) = items[0] else {
            Issue.record("Expected web_search_result object")
            return
        }
        #expect(item["url"] == .string("https://example.com"))
        #expect(item["title"] == .null)
        #expect(item["page_age"] == .null)
        #expect(item["encrypted_content"] == .string("encrypted"))
        #expect(item["type"] == .string("web_search_result"))
    }

    @Test("provider executed web fetch rejects missing retrievedAt/title keys")
    func providerExecutedWebFetchRejectsMissingRequiredFields() async throws {
        let webFetchCall = LanguageModelV4MessagePart.toolCall(
            .init(
                toolCallId: "tool-1",
                toolName: "web_fetch",
                input: .object([:]),
                providerExecuted: true
            )
        )
        let webFetchResult = LanguageModelV4MessagePart.toolResult(
            .init(
                toolCallId: "tool-1",
                toolName: "web_fetch",
                output: .json(value: .object([
                    "type": .string("web_fetch_result"),
                    "url": .string("https://example.com"),
                    // Missing retrievedAt and content.title (both required, nullable)
                    "content": .object([
                        "type": .string("document"),
                        "source": .object([
                            "type": .string("text"),
                            "mediaType": .string("text/plain"),
                            "data": .string("Example content")
                        ])
                    ])
                ]))
            )
        )

        let prompt: LanguageModelV4Prompt = [
            .assistant(content: [webFetchCall, webFetchResult], providerOptions: nil)
        ]

        await #expect(throws: TypeValidationError.self) {
            _ = try await convert(prompt)
        }
    }

    @Test("rejects cache_control on thinking blocks")
    func rejectsCacheControlOnThinkingBlocks() async throws {

        let reasoningPart = LanguageModelV4MessagePart.reasoning(
            .init(
                text: "thinking content",
                providerOptions: anthropicOptions([
                    "signature": .string("test-sig"),
                    "cacheControl": .object(["type": .string("ephemeral")]),
                ])
            )
        )

        let (result, warnings) = try await convert([
            .assistant(content: [reasoningPart], providerOptions: nil)
        ])

        if case let .object(first)? = result.prompt.messages.first?.content.first {
            #expect(first["cache_control"] == nil)
        } else {
            Issue.record("Expected first assistant content object")
        }

        #expect(warnings == [
            .unsupported(
                feature: "cache_control on non-cacheable context",
                details: "cache_control cannot be set on thinking block. It will be ignored."
            )
        ])
    }

    @Test("rejects cache_control on redacted thinking blocks")
    func rejectsCacheControlOnRedactedThinkingBlocks() async throws {

        let reasoningPart = LanguageModelV4MessagePart.reasoning(
            .init(
                text: "redacted",
                providerOptions: anthropicOptions([
                    "redactedData": .string("abc123"),
                    "cacheControl": .object(["type": .string("ephemeral")]),
                ])
            )
        )

        let (result, warnings) = try await convert([
            .assistant(content: [reasoningPart], providerOptions: nil)
        ])

        if case let .object(first)? = result.prompt.messages.first?.content.first {
            #expect(first["cache_control"] == nil)
        } else {
            Issue.record("Expected first assistant content object")
        }

        #expect(warnings == [
            .unsupported(
                feature: "cache_control on non-cacheable context",
                details: "cache_control cannot be set on redacted thinking block. It will be ignored."
            )
        ])
    }
}

@Suite("convertToAnthropicMessagesPrompt cache control breakpoint limit")
struct ConvertToAnthropicMessagesPromptCacheControlBreakpointTests {
    @Test("limits cache breakpoints to 4")
    func limitsCacheBreakpointsTo4() async throws {
        let cacheOptions = anthropicOptions([
            "cacheControl": .object(["type": .string("ephemeral")])
        ])

        let (result, warnings) = try await convert([
            .system(content: "system 1", providerOptions: cacheOptions),
            .system(content: "system 2", providerOptions: cacheOptions),
            .user(content: [.text(.init(text: "user 1", providerOptions: cacheOptions))], providerOptions: nil),
            .assistant(content: [.text(.init(text: "assistant 1", providerOptions: cacheOptions))], providerOptions: nil),
            .user(content: [.text(.init(text: "user 2", providerOptions: cacheOptions))], providerOptions: nil),
        ])

        if let system = result.prompt.system, system.count == 2 {
            if case let .object(first) = system[0] {
                #expect(first["cache_control"] == .object(["type": .string("ephemeral")]))
            }
            if case let .object(second) = system[1] {
                #expect(second["cache_control"] == .object(["type": .string("ephemeral")]))
            }
        } else {
            Issue.record("Expected 2 system blocks")
        }

        #expect(result.prompt.messages.count == 3)

        if case let .object(user1)? = result.prompt.messages.first?.content.first {
            #expect(user1["cache_control"] == .object(["type": .string("ephemeral")]))
        } else {
            Issue.record("Expected first user content object")
        }

        if case let .object(assistant1)? = result.prompt.messages.dropFirst().first?.content.first {
            #expect(assistant1["cache_control"] == .object(["type": .string("ephemeral")]))
        } else {
            Issue.record("Expected first assistant content object")
        }

        if case let .object(user2)? = result.prompt.messages.dropFirst(2).first?.content.first {
            #expect(user2["cache_control"] == nil)
        } else {
            Issue.record("Expected second user content object")
        }

        #expect(warnings == [
            .unsupported(
                feature: "cacheControl breakpoint limit",
                details: "Maximum 4 cache breakpoints exceeded (found 5). This breakpoint will be ignored."
            )
        ])
    }
}

// MARK: - Miscellaneous Cases

@Suite("convertToAnthropicMessagesPrompt miscellaneous")
struct ConvertToAnthropicMessagesPromptMiscTests {
    @Test("warnings propagate from tool result output type")
    func warningForUnsupportedProviderExecutedOutput() async throws {
        let toolResult = LanguageModelV4MessagePart.toolResult(
            .init(
                toolCallId: "tool-3",
                toolName: "code_execution",
                output: .text(value: "plain text")
            )
        )
        let prompt: LanguageModelV4Prompt = [
            .assistant(content: [toolResult], providerOptions: nil)
        ]

        let (_, warnings) = try await convert(prompt)

        #expect(warnings.contains(.other(message: "provider executed tool result output type text for tool code_execution is not supported")))
    }

    @Test("betas union from multiple sources")
    func betasUnion() async throws {
        let pdf = LanguageModelV4FilePart(
            data: .base64("PDF=="),
            mediaType: "application/pdf"
        )
        let toolResult = LanguageModelV4ToolResultPart(
            toolCallId: "call",
            toolName: "calculator",
            output: .content(value: [.file(data: .base64("PDFDATA"), mediaType: "application/pdf", filename: nil, providerOptions: nil)])
        )
        let prompt: LanguageModelV4Prompt = [
            .user(content: [.file(pdf)], providerOptions: nil),
            .tool(content: [.toolResult(toolResult)], providerOptions: nil)
        ]

        let (result, _) = try await convert(prompt)

        #expect(result.betas == Set(["pdfs-2024-09-25"]))
    }
}

@Suite("Anthropic V4 prompt HTTP contracts")
struct AnthropicPromptHTTPTests {
    @Test("initial controls preserve instructions and route effort-only messages inline")
    func initialSystemControls() async throws {
        let (result, warnings) = try await convert([
            .system(content: "Instructions", providerOptions: anthropicOptions([
                "clearAt": .string("next_user_message"),
                "toolChanges": .array([.object(["type": .string("tool_addition"), "toolName": .string("search")])]),
            ])),
            .system(content: "", providerOptions: anthropicOptions(["effort": .string("high")])),
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil),
        ])
        #expect(result.prompt.system == [.object(["type": .string("text"), "text": .string("Instructions")])])
        #expect(result.prompt.messages.first == AnthropicMessage(role: "system", content: [], outputConfig: ["effort": .string("high")]))
        #expect(result.betas == ["mid-conversation-output-config-2026-07-01"])
        #expect(warnings.count == 2)
    }

    @Test("mid-conversation controls remain separate and resolve custom provider tool names")
    func midConversationSystemControls() async throws {
        let (result, warnings) = try await convert([
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil),
            .system(content: "", providerOptions: anthropicOptions([
                "clearAt": .string("next_user_message"),
                "effort": .string("max"),
                "toolChanges": .array([.object(["type": .string("tool_removal"), "toolName": .string("searchNews")])]),
            ])),
            .system(content: "New instructions", providerOptions: nil),
        ], tools: [.provider(.init(id: "anthropic.web_search_20250305", name: "searchNews", args: [:]))])
        #expect(warnings.isEmpty)
        #expect(Array(result.prompt.messages.suffix(2)) == [
            AnthropicMessage(role: "system", content: [.object([
                "type": .string("tool_removal"),
                "tool": .object(["type": .string("tool_reference"), "name": .string("web_search")]),
            ])], clearAt: "next_user_message", outputConfig: ["effort": .string("max")]),
            AnthropicMessage(role: "system", content: [.object(["type": .string("text"), "text": .string("New instructions")])]),
        ])
        #expect(result.betas == [
            "mid-conversation-system-2026-04-07", "mid-conversation-tool-changes-2026-07-01",
            "mid-conversation-system-clear-at-2026-08-21", "mid-conversation-output-config-2026-07-01",
        ])
    }

    @Test("V4 file references, text data, and wildcard media reach the HTTP payload")
    func nativeFileData() async throws {
        let (result, warnings) = try await convert([
            .user(content: [
                .file(.init(data: .reference(["anthropic": "file_image"]), mediaType: "image")),
                .file(.init(data: .reference(["anthropic": "file_upload"]), mediaType: "application/zip", providerOptions: anthropicOptions(["containerUpload": .bool(true)]))),
                .file(.init(data: .text("Document text"), mediaType: "application/custom", filename: "notes.txt", providerOptions: anthropicOptions([
                    "context": .string(""), "citations": .object(["enabled": .bool(true)]),
                ]))),
                .file(.init(data: .base64("iVBORw0KGgo="), mediaType: "image/*")),
                .file(.init(data: .data(Data([0xef, 0xbb, 0xbf, 0xff, 0x61])), mediaType: "text/plain")),
            ], providerOptions: nil),
        ])
        #expect(warnings.isEmpty)
        #expect(result.betas == ["files-api-2025-04-14"])
        #expect(result.prompt.messages.first?.content == [
            .object(["type": .string("image"), "source": .object(["type": .string("file"), "file_id": .string("file_image")])]),
            .object(["type": .string("container_upload"), "file_id": .string("file_upload")]),
            .object(["type": .string("document"), "source": .object(["type": .string("text"), "media_type": .string("text/plain"), "data": .string("Document text")]), "title": .string("notes.txt"), "citations": .object(["enabled": .bool(true)])]),
            .object(["type": .string("image"), "source": .object(["type": .string("base64"), "media_type": .string("image/png"), "data": .string("iVBORw0KGgo=")])]),
            .object(["type": .string("document"), "source": .object(["type": .string("text"), "media_type": .string("text/plain"), "data": .string("�a")])]),
        ])
    }

    @Test("references from another provider fail before request transmission")
    func rejectsForeignReference() async throws {
        await #expect(throws: NoSuchProviderReferenceError.self) {
            _ = try await convert([.user(content: [
                .file(.init(data: .reference(["other": "file_other"]), mediaType: "application/pdf")),
            ], providerOptions: nil)])
        }
    }

    @Test("tool result content supports references, URLs, and tool references while warning on unsupported data")
    func toolResultContent() async throws {
        let (result, warnings) = try await convert([
            .tool(content: [.toolResult(.init(toolCallId: "call", toolName: "read", output: .content(value: [
                .text(text: "Result", providerOptions: nil),
                .file(data: .reference(["anthropic": "file_pdf"]), mediaType: "application/pdf", filename: nil, providerOptions: nil),
                .file(data: .url(URL(string: "https://example.com/image.png")!), mediaType: "image", filename: nil, providerOptions: nil),
                .custom(providerOptions: anthropicOptions(["type": .string("tool-reference"), "toolName": .string("search")])),
                .file(data: .text("unsupported"), mediaType: "text/plain", filename: nil, providerOptions: nil),
            ])))], providerOptions: nil),
        ])
        #expect(result.prompt.messages.first?.content == [.object([
            "type": .string("tool_result"), "tool_use_id": .string("call"),
            "content": .array([
                .object(["type": .string("text"), "text": .string("Result")]),
                .object(["type": .string("document"), "source": .object(["type": .string("file"), "file_id": .string("file_pdf")])]),
                .object(["type": .string("image"), "source": .object(["type": .string("url"), "url": .string("https://example.com/image.png")])]),
                .object(["type": .string("tool_reference"), "tool_name": .string("search")]),
            ]),
        ])])
        #expect(result.betas == ["files-api-2025-04-14"])
        #expect(warnings == [.other(message: "unsupported tool content part type: file with data type: text")])
    }

    @Test("tool cache precedence uses part, output, first content metadata, then message without stealing approval position")
    func toolResultCachePrecedence() async throws {
        func cache(_ ttl: String) -> SharedV4ProviderOptions {
            anthropicOptions(["cacheControl": .object(["type": .string("ephemeral"), "ttl": .string(ttl)])])
        }
        let (result, warnings) = try await convert([
            .tool(content: [
                .toolResult(.init(toolCallId: "part", toolName: "read", output: .text(value: "one", providerOptions: cache("1h")), providerOptions: cache("5m"))),
                .toolResult(.init(toolCallId: "output", toolName: "read", output: .json(value: .null, providerOptions: cache("1h")))),
                .toolResult(.init(toolCallId: "content", toolName: "read", output: .content(value: [.text(text: "three", providerOptions: cache("5m"))]))),
                .toolResult(.init(toolCallId: "message", toolName: "read", output: .executionDenied(reason: nil))),
            ], providerOptions: cache("1h")),
            .tool(content: [
                .toolResult(.init(toolCallId: "approval", toolName: "read", output: .text(value: "four"))),
                .toolApprovalResponse(.init(approvalId: "approve", approved: true)),
            ], providerOptions: cache("5m")),
        ])
        let content = try #require(result.prompt.messages.first?.content)
        let controls = content.map { value -> JSONValue? in
            guard case .object(let object) = value else { return nil }
            return object["cache_control"]
        }
        let expectedControls: [JSONValue?] = ["5m", "1h", "5m", "1h"].map { .object(["type": .string("ephemeral"), "ttl": .string($0)]) } + [nil]
        #expect(controls == expectedControls)
        guard case .object(let denied) = content[3] else { throw PromptRequestError.invalidBody }
        #expect(denied["content"] == .string("Tool call execution denied."))
        #expect(warnings.isEmpty)
    }

    @Test("fallback boundaries keep tool uses in their own segment and signed compaction keeps opaque text")
    func signedCompactionAndFallback() async throws {
        let citations: JSONValue = .array([.object(["type": .string("page_location"), "document_index": .number(0), "start_page_number": .number(1), "end_page_number": .number(2), "cited_text": .string("source"), "document_title": .string("Doc")])])
        let (result, warnings) = try await convert([
            .assistant(content: [
                .toolCall(.init(toolCallId: "before", toolName: "save", input: .object([:]))),
                .custom(.init(kind: "anthropic.fallback", providerOptions: anthropicOptions([
                    "type": .string("fallback"), "from": .object(["model": .string("claude-opus-4-8")]), "to": .object(["model": .string("claude-sonnet-5")]),
                ]))),
                .text(.init(text: "Cited answer", providerOptions: anthropicOptions(["citations": citations]))),
                .text(.init(text: "", providerOptions: anthropicOptions(["type": .string("compaction")]))),
                .text(.init(text: "  condensed context \n", providerOptions: anthropicOptions(["type": .string("compaction"), "signature": .string("sig-compact")]))),
            ], providerOptions: nil),
        ])
        #expect(warnings.isEmpty)
        #expect(result.prompt.messages.first?.content == [
            .object(["type": .string("tool_use"), "id": .string("before"), "name": .string("save"), "input": .object([:])]),
            .object(["type": .string("fallback"), "from": .object(["model": .string("claude-opus-4-8")]), "to": .object(["model": .string("claude-sonnet-5")])]),
            .object(["type": .string("text"), "text": .string("Cited answer"), "citations": citations]),
            .object(["type": .string("compaction"), "content": .string("  condensed context \n"), "signature": .string("sig-compact")]),
        ])
        #expect(result.betas == ["compact-2026-09-04", "server-side-fallback-2026-06-01"])
    }

    @Test("generated signed compaction and fallback metadata survive the next HTTP turn")
    func generatedHistoryLifecycle() async throws {
        let historyBlocks: [JSONValue] = [
            .object(["type": .string("compaction"), "content": .string(" Condensed history \n"), "signature": .string("sig-generated")]),
            .object(["type": .string("fallback"), "from": .object(["model": .string("claude-opus-4-8")]), "to": .object(["model": .string("claude-sonnet-5")])]),
        ]
        let response = try JSONEncoder().encode(JSONValue.object([
            "type": .string("message"), "id": .string("msg_history"), "model": .string("claude-sonnet-5"),
            "content": .array(historyBlocks), "stop_reason": .string("end_turn"),
            "usage": .object(["input_tokens": .number(1), "output_tokens": .number(1)]),
        ]))
        let capture = PromptRequestCapture()
        let model = createAnthropic(settings: .init(apiKey: "test-key", fetch: { request in
            await capture.store(request)
            return FetchResponse(body: .data(response), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })).messages("claude-opus-4-8")
        let initial: LanguageModelV4Message = .user(content: [.text(.init(text: "Summarize"))], providerOptions: nil)
        let generated = try await model.doGenerate(options: .init(prompt: [initial]))
        let history: [LanguageModelV4MessagePart] = try generated.content.map { part in
            switch part {
            case .text(let text): .text(.init(text: text.text, providerOptions: text.providerMetadata))
            case .custom(let custom): .custom(.init(kind: custom.kind, providerOptions: custom.providerMetadata))
            default: throw PromptRequestError.invalidBody
            }
        }
        _ = try await model.doGenerate(options: .init(prompt: [
            initial,
            .assistant(content: history, providerOptions: nil),
            .user(content: [.text(.init(text: "Continue"))], providerOptions: nil),
        ]))
        let request = try #require(await capture.request)
        let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
        guard case .object(let object) = body, case .array(let messages) = object["messages"], messages.count > 1,
              case .object(let assistant) = messages[1] else { throw PromptRequestError.invalidBody }
        #expect(assistant["content"] == .array(historyBlocks))
        let betas = Set((request.value(forHTTPHeaderField: "anthropic-beta") ?? "").split(separator: ","))
        #expect(betas.contains("compact-2026-09-04"))
        #expect(betas.contains("server-side-fallback-2026-06-01"))
    }

    @Test("unsupported custom and empty compaction history does not create empty assistant API messages")
    func omittedAssistantContent() async throws {
        let (result, warnings) = try await convert([
            .assistant(content: [
                .custom(.init(kind: "other.content")),
                .custom(.init(kind: "anthropic.fallback", providerOptions: anthropicOptions(["type": .string("fallback")]))),
                .text(.init(text: "", providerOptions: anthropicOptions(["type": .string("compaction")]))),
                .file(.init(data: .text("ignored"), mediaType: "text/plain")),
            ], providerOptions: nil),
            .user(content: [.text(.init(text: "Continue"))], providerOptions: nil),
        ])
        #expect(result.prompt.messages == [.init(role: "user", content: [.object(["type": .string("text"), "text": .string("Continue")])])])
        #expect(warnings == [.other(message: "anthropic fallback metadata must include from.model and to.model")])
    }

    @Test("toolset calls use member names and configured toolset overrides metadata")
    func toolsetMemberCalls() async throws {
        let toolsetMetadata = anthropicOptions(["toolsetName": .string("previous-computer")])
        let (result, warnings) = try await convert([
            .assistant(content: [
                .toolCall(.init(toolCallId: "member", toolName: "desktop", input: .object(["action": .string("screenshot")]), providerOptions: toolsetMetadata)),
                .toolCall(.init(toolCallId: "invalid", toolName: "legacy", input: .array([.number(1)]), providerOptions: anthropicOptions(["toolsetName": .string("legacy-set")]))),
            ], providerOptions: nil),
            .tool(content: [.toolResult(.init(toolCallId: "member", toolName: "desktop", output: .text(value: "ok"), providerOptions: toolsetMetadata))], providerOptions: nil),
        ], tools: [.provider(.init(id: "anthropic.computer_toolset_20260801", name: "desktop", args: ["displayWidthPx": .number(100), "displayHeightPx": .number(100)]))])
        #expect(result.prompt.messages.first?.content == [
            .object(["type": .string("tool_use"), "id": .string("member"), "name": .string("screenshot"), "toolset_name": .string("computer"), "input": .object(["action": .string("screenshot")])]),
            .object(["type": .string("tool_use"), "id": .string("invalid"), "name": .string("legacy-set"), "toolset_name": .string("legacy-set"), "input": .object(["rawInvalidInput": .array([.number(1)])])]),
        ])
        #expect(result.prompt.messages.last?.content == [.object(["type": .string("tool_result"), "tool_use_id": .string("member"), "toolset_name": .string("computer"), "content": .string("ok")])])
        #expect(warnings == [.other(message: "toolset tool call for tool legacy is missing the action")])
    }

    @Test("orphan caller metadata is removed only once the next nonempty user turn starts", arguments: ["active", "history", "empty-user", "retained-source"])
    func callerHistoryNormalization(scenario: String) async throws {
        let caller = anthropicOptions(["caller": .object(["type": .string("code_execution_20260120"), "toolId": .string("execution")])])
        var parts: [LanguageModelV4MessagePart] = []
        if scenario == "retained-source" {
            parts.append(.toolCall(.init(toolCallId: "execution", toolName: "code_execution", input: .object(["code": .string("search()")]), providerExecuted: true)))
        }
        parts += [
            .toolCall(.init(toolCallId: "search", toolName: "web_search", input: .object(["query": .string("news")]), providerExecuted: true, providerOptions: caller)),
            .toolResult(.init(toolCallId: "search", toolName: "web_search", output: .errorJson(value: .object(["errorCode": .string("unavailable")])), providerOptions: caller)),
        ]
        var prompt: LanguageModelV4Prompt = [.assistant(content: parts, providerOptions: nil)]
        if scenario == "active" {
            prompt.append(.tool(content: [.toolResult(.init(toolCallId: "client", toolName: "read", output: .text(value: "ok")))], providerOptions: nil))
        } else {
            prompt.append(.user(content: scenario == "empty-user" ? [] : [.text(.init(text: "Continue"))], providerOptions: nil))
        }
        let (result, warnings) = try await convert(prompt)
        let content = try #require(result.prompt.messages.first?.content)
        let searchBlocks = content.filter { value in
            guard case .object(let object) = value else { return false }
            return object["id"] == .string("search") || object["tool_use_id"] == .string("search")
        }
        let callers = searchBlocks.map { value -> JSONValue? in
            guard case .object(let object) = value else { return nil }
            return object["caller"]
        }
        let expected: JSONValue? = scenario == "history" ? nil : .object(["type": .string("code_execution_20260120"), "tool_id": .string("execution")])
        #expect(callers == [expected, expected])
        #expect(warnings.count == (scenario == "history" ? 1 : 0))
    }

    @Test("code execution errors accept stringified output and fall back to bash unknown errors")
    func codeExecutionErrors() async throws {
        let (result, warnings) = try await convert([
            .assistant(content: [
                .toolResult(.init(toolCallId: "legacy", toolName: "code_execution", output: .errorText(value: #"{"type":"code_execution_tool_result_error","errorCode":"execution_failed"}"#))),
                .toolResult(.init(toolCallId: "bash", toolName: "code_execution", output: .errorJson(value: .object([:])))),
            ], providerOptions: nil),
        ])
        #expect(warnings.isEmpty)
        #expect(result.prompt.messages.first?.content == [
            .object(["type": .string("code_execution_tool_result"), "tool_use_id": .string("legacy"), "content": .object(["type": .string("code_execution_tool_result_error"), "error_code": .string("execution_failed")])]),
            .object(["type": .string("bash_code_execution_tool_result"), "tool_use_id": .string("bash"), "content": .object(["type": .string("bash_code_execution_tool_result_error"), "error_code": .string("unknown")])]),
        ])
    }

    @Test("text editor results retain required nullable fields in the HTTP history")
    func nullableTextEditorResult() async throws {
        let value: JSONValue = .object([
            "type": .string("text_editor_code_execution_view_result"), "content": .string("image data"), "file_type": .string("image"),
            "num_lines": .null, "start_line": .null, "total_lines": .null,
        ])
        let (result, warnings) = try await convert([
            .assistant(content: [.toolResult(.init(toolCallId: "editor", toolName: "code_execution", output: .json(value: value)))], providerOptions: nil),
        ])
        #expect(warnings.isEmpty)
        #expect(result.prompt.messages.first?.content == [.object([
            "type": .string("text_editor_code_execution_tool_result"), "tool_use_id": .string("editor"), "content": value,
        ])])
    }

    @Test("encrypted code execution history validates its required fields")
    func rejectsInvalidEncryptedResult() async throws {
        await #expect(throws: TypeValidationError.self) {
            _ = try await convert([
                .assistant(content: [.toolResult(.init(toolCallId: "encrypted", toolName: "code_execution", output: .json(value: .object([
                    "type": .string("encrypted_code_execution_result"), "encrypted_stdout": .number(1), "stderr": .string(""), "return_code": .number(0),
                ]))))], providerOptions: nil),
            ])
        }
    }

    @Test("tool search error values are recognized before validating reference arrays")
    func toolSearchErrorValue() async throws {
        let (result, warnings) = try await convert([
            .assistant(content: [.toolResult(.init(toolCallId: "search", toolName: "tool_search_tool_regex", output: .json(value: .object(["type": .string("tool_search_tool_result_error")]))))], providerOptions: nil),
        ])
        #expect(warnings.isEmpty)
        #expect(result.prompt.messages.first?.content == [.object(["type": .string("tool_search_tool_result"), "tool_use_id": .string("search"), "content": .object(["type": .string("tool_search_tool_result_error"), "error_code": .string("unavailable")])])])
    }
}

@Suite("convertToAnthropicMessagesPrompt additional file types")
struct ConvertToAnthropicMessagesPromptFileTests {
    @Test("add PDF file parts for URL PDFs")
    func addsPDFFilePartsForURLPDFs() async throws {
        let file = LanguageModelV4FilePart(
            data: .url(URL(string: "https://example.com/document.pdf")!),
            mediaType: "application/pdf"
        )
        let prompt: LanguageModelV4Prompt = [
            .user(content: [.file(file)], providerOptions: nil)
        ]

        let (result, warnings) = try await convert(prompt)

        #expect(warnings.isEmpty)
        #expect(result.betas == Set(["pdfs-2024-09-25"]))
        #expect(result.prompt == AnthropicMessagesPrompt(
            system: nil,
            messages: [
                AnthropicMessage(
                    role: "user",
                    content: [
                        .object([
                            "type": .string("document"),
                            "source": .object([
                                "type": .string("url"),
                                "url": .string("https://example.com/document.pdf")
                            ])
                        ])
                    ]
                )
            ]
        ))
    }

    @Test("add text file parts for text/plain documents")
    func addsTextFilePartsForTextPlainDocuments() async throws {
        // In TypeScript, Buffer.from('sample text content', 'utf-8').toString('base64')
        // We decode the base64 to get the actual text
        let textContent = "sample text content"
        let base64Data = textContent.data(using: .utf8)!.base64EncodedString()

        let file = LanguageModelV4FilePart(
            data: .base64(base64Data),
            mediaType: "text/plain",
            filename: "sample.txt"
        )
        let prompt: LanguageModelV4Prompt = [
            .user(content: [.file(file)], providerOptions: nil)
        ]

        let (result, warnings) = try await convert(prompt)

        #expect(warnings.isEmpty)
        #expect(result.betas.isEmpty)
        #expect(result.prompt == AnthropicMessagesPrompt(
            system: nil,
            messages: [
                AnthropicMessage(
                    role: "user",
                    content: [
                        .object([
                            "type": .string("document"),
                            "source": .object([
                                "type": .string("text"),
                                "media_type": .string("text/plain"),
                                "data": .string("sample text content")
                            ]),
                            "title": .string("sample.txt")
                        ])
                    ]
                )
            ]
        ))
    }
}
