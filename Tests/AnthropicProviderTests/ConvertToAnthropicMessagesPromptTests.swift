import Foundation
import Testing
@testable import AnthropicProvider
import AISDKProvider

private func convert(
    _ prompt: LanguageModelV3Prompt,
    sendReasoning: Bool = true
) async throws -> (AnthropicPromptConversionResult, [LanguageModelV3CallWarning]) {
    var warnings: [LanguageModelV3CallWarning] = []
    let result = try await convertToAnthropicMessagesPrompt(
        prompt: prompt,
        sendReasoning: sendReasoning,
        warnings: &warnings
    )
    return (result, warnings)
}

private func jsonString(_ value: JSONValue) -> String {
    let data = try! JSONEncoder().encode(value)
    return String(data: data, encoding: .utf8)!
}

private func anthropicOptions(_ values: [String: JSONValue]) -> SharedV3ProviderOptions {
    ["anthropic": values]
}

// MARK: - System Messages

@Suite("convertToAnthropicMessagesPrompt system messages")
struct ConvertToAnthropicMessagesPromptSystemTests {
    @Test("single system message")
    func singleSystemMessage() async throws {
        let prompt: LanguageModelV3Prompt = [
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
        let prompt: LanguageModelV3Prompt = [
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

    @Test("system message uses cache control from provider options")
    func systemMessageCacheControl() async throws {
        let prompt: LanguageModelV3Prompt = [
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
        let filePart = LanguageModelV3FilePart(
            data: .base64("AAECAw=="),
            mediaType: "image/png"
        )
        let prompt: LanguageModelV3Prompt = [
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
        let filePart = LanguageModelV3FilePart(
            data: .url(URL(string: "https://example.com/image.png")!),
            mediaType: "image/*"
        )
        let prompt: LanguageModelV3Prompt = [
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
        let filePart = LanguageModelV3FilePart(
            data: .base64("BASE64PDF=="),
            mediaType: "application/pdf",
            filename: "requirements.pdf",
            providerOptions: providerOptions
        )
        let prompt: LanguageModelV3Prompt = [
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
        let filePart = LanguageModelV3FilePart(
            data: .data("hello".data(using: .utf8)!),
            mediaType: "text/plain",
            filename: "notes.txt",
            providerOptions: providerOptions
        )
        let prompt: LanguageModelV3Prompt = [
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
        let toolPart = LanguageModelV3ToolResultPart(
            toolCallId: "call-1",
            toolName: "calculator",
            output: .json(value: .object(["answer": .number(42)]))
        )
        let prompt: LanguageModelV3Prompt = [
            .tool(content: [toolPart], providerOptions: nil)
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
        let output = LanguageModelV3ToolResultOutput.content(value: [
            .text(text: "summary"),
            .media(data: "PDFDATA", mediaType: "application/pdf")
        ])
        let toolPart = LanguageModelV3ToolResultPart(
            toolCallId: "call-2",
            toolName: "aggregator",
            output: output
        )
        let prompt: LanguageModelV3Prompt = [
            .tool(content: [toolPart], providerOptions: nil)
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

@Suite("convertToAnthropicMessagesPrompt assistant messages")
struct ConvertToAnthropicMessagesPromptAssistantTests {
    @Test("assistant text trims final whitespace")
    func assistantTextTrim() async throws {
        let message = LanguageModelV3Message.assistant(
            content: [
                .text(.init(text: "Hello world  \n"))
            ],
            providerOptions: nil
        )
        let prompt: LanguageModelV3Prompt = [message]

        let (result, warnings) = try await convert(prompt)

        #expect(warnings.isEmpty)
        #expect(result.prompt.messages == [
            AnthropicMessage(
                role: "assistant",
                content: [
                    .object([
                        "type": .string("text"),
                        "text": .string("Hello world")
                    ])
                ]
            )
        ])
    }

    @Test("assistant reasoning requires signature metadata")
    func assistantReasoningWithSignature() async throws {
        let reasoningPart = LanguageModelV3MessagePart.reasoning(
            .init(
                text: "Chain of thought",
                providerOptions: anthropicOptions([
                    "signature": .string("sig-123")
                ])
            )
        )
        let prompt: LanguageModelV3Prompt = [
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
        let reasoningPart = LanguageModelV3MessagePart.reasoning(
            .init(text: "Hidden thoughts", providerOptions: nil)
        )
        let prompt: LanguageModelV3Prompt = [
            .assistant(content: [reasoningPart], providerOptions: nil)
        ]

        let (_, warnings) = try await convert(prompt, sendReasoning: false)

        #expect(warnings.contains(.other(message: "sending reasoning content is disabled for this model")))
    }

    @Test("assistant provider executed tool call mapped to server tool use")
    func assistantProviderExecutedToolCall() async throws {
        let toolCall = LanguageModelV3MessagePart.toolCall(
            .init(
                toolCallId: "tool-1",
                toolName: "code_execution",
                input: .object(["code": .string("print('hi')")]),
                providerExecuted: true
            )
        )
        let prompt: LanguageModelV3Prompt = [
            .assistant(content: [toolCall], providerOptions: nil)
        ]

        let (result, warnings) = try await convert(prompt)

        #expect(warnings.isEmpty)
        #expect(result.betas == Set(["code-execution-2025-05-22"]))
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

    @Test("assistant tool call mapped to tool use with object input")
    func assistantToolCallUsesObjectInput() async throws {
        let toolCall = LanguageModelV3MessagePart.toolCall(
            .init(
                toolCallId: "tool-1",
                toolName: "read",
                input: .object(["path": .string("hello.txt")]),
                providerExecuted: false
            )
        )
        let prompt: LanguageModelV3Prompt = [
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

    @Test("assistant provider executed tool call unsupported warns")
    func assistantProviderExecutedUnsupportedToolCall() async throws {
        let toolCall = LanguageModelV3MessagePart.toolCall(
            .init(
                toolCallId: "tool-2",
                toolName: "unsupported",
                input: .object([:]),
                providerExecuted: true
            )
        )
        let prompt: LanguageModelV3Prompt = [
            .assistant(content: [toolCall], providerOptions: nil)
        ]

        let (_, warnings) = try await convert(prompt)

        #expect(warnings.contains(.other(message: "provider executed tool call for tool unsupported is not supported")))
    }

    @Test("assistant provider executed tool_search_tool_regex tool call and result parts")
    func assistantToolSearchToolRegexCallAndResult() async throws {
        let toolCall = LanguageModelV3MessagePart.toolCall(
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
        let toolResult = LanguageModelV3MessagePart.toolResult(
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
        let prompt: LanguageModelV3Prompt = [
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

    @Test("assistant mcp tool use call and result parts")
    func assistantMcpToolUseCallAndResult() async throws {
        let toolCall = LanguageModelV3MessagePart.toolCall(
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
        let toolResult = LanguageModelV3MessagePart.toolResult(
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
        let text = LanguageModelV3MessagePart.text(
            .init(text: "The echo tool responded back.")
        )
        let prompt: LanguageModelV3Prompt = [
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
        let codeCall = LanguageModelV3MessagePart.toolCall(
            .init(
                toolCallId: "tool-1",
                toolName: "code_execution",
                input: .object([:]),
                providerExecuted: true
            )
        )
        let webFetchCall = LanguageModelV3MessagePart.toolCall(
            .init(
                toolCallId: "tool-2",
                toolName: "web_fetch",
                input: .object([:]),
                providerExecuted: true
            )
        )
        let codeResult = LanguageModelV3MessagePart.toolResult(
            .init(
                toolCallId: "tool-1",
                toolName: "code_execution",
                output: .json(value: .object([
                    "type": .string("completion"),
                    "stdout": .string("done"),
                    "stderr": .string(""),
                    "return_code": .number(0)
                ]))
            )
        )
        let webFetchResult = LanguageModelV3MessagePart.toolResult(
            .init(
                toolCallId: "tool-2",
                toolName: "web_fetch",
                output: .json(value: .object([
                    "type": .string("web_fetch_result"),
                    "url": .string("https://example.com"),
                    "retrieved_at": .string("2024-01-01T00:00:00Z"),
                    "content": .object([
                        "type": .string("document"),
                        "title": .string("Example"),
                        "source": .object([
                            "type": .string("base64"),
                            "media_type": .string("text/plain"),
                            "data": .string("ZGF0YQ==")
                        ])
                    ])
                ]))
            )
        )
        let prompt: LanguageModelV3Prompt = [
            .assistant(content: [codeCall, webFetchCall, codeResult, webFetchResult], providerOptions: nil)
        ]

        let (result, warnings) = try await convert(prompt)

        #expect(warnings.isEmpty)
        #expect(result.betas == Set(["code-execution-2025-05-22", "web-fetch-2025-09-10"]))
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
}

// MARK: - Miscellaneous Cases

@Suite("convertToAnthropicMessagesPrompt miscellaneous")
struct ConvertToAnthropicMessagesPromptMiscTests {
    @Test("warnings propagate from tool result output type")
    func warningForUnsupportedProviderExecutedOutput() async throws {
        let toolResult = LanguageModelV3MessagePart.toolResult(
            .init(
                toolCallId: "tool-3",
                toolName: "code_execution",
                output: .text(value: "plain text")
            )
        )
        let prompt: LanguageModelV3Prompt = [
            .assistant(content: [toolResult], providerOptions: nil)
        ]

        let (_, warnings) = try await convert(prompt)

        #expect(warnings.contains(.other(message: "provider executed tool result output type for tool code_execution is not supported")))
    }

    @Test("betas union from multiple sources")
    func betasUnion() async throws {
        let pdf = LanguageModelV3FilePart(
            data: .base64("PDF=="),
            mediaType: "application/pdf"
        )
        let toolResult = LanguageModelV3ToolResultPart(
            toolCallId: "call",
            toolName: "calculator",
            output: .content(value: [.media(data: "PDFDATA", mediaType: "application/pdf")])
        )
        let prompt: LanguageModelV3Prompt = [
            .user(content: [.file(pdf)], providerOptions: nil),
            .tool(content: [toolResult], providerOptions: nil)
        ]

        let (result, _) = try await convert(prompt)

        #expect(result.betas == Set(["pdfs-2024-09-25"]))
    }
}

// MARK: - Batch 18: File Content Tests

@Suite("convertToAnthropicMessagesPrompt Batch 18: file content")
struct ConvertToAnthropicMessagesPromptBatch18Tests {
    @Test("add image parts for base64 images")
    func addsImagePartsForBase64Images() async throws {
        let file = LanguageModelV3FilePart(
            data: .base64("AAECAw=="),
            mediaType: "image/png"
        )
        let prompt: LanguageModelV3Prompt = [
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
    }

    @Test("add image parts for URL images")
    func addsImagePartsForURLImages() async throws {
        let file = LanguageModelV3FilePart(
            data: .url(URL(string: "https://example.com/image.png")!),
            mediaType: "image/*"
        )
        let prompt: LanguageModelV3Prompt = [
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
    }

    @Test("add PDF file parts for base64 PDFs")
    func addsPDFFilePartsForBase64PDFs() async throws {
        let file = LanguageModelV3FilePart(
            data: .base64("base64PDFdata"),
            mediaType: "application/pdf"
        )
        let prompt: LanguageModelV3Prompt = [
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
                                "type": .string("base64"),
                                "media_type": .string("application/pdf"),
                                "data": .string("base64PDFdata")
                            ])
                        ])
                    ]
                )
            ]
        ))
    }

    @Test("add PDF file parts for URL PDFs")
    func addsPDFFilePartsForURLPDFs() async throws {
        let file = LanguageModelV3FilePart(
            data: .url(URL(string: "https://example.com/document.pdf")!),
            mediaType: "application/pdf"
        )
        let prompt: LanguageModelV3Prompt = [
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

        let file = LanguageModelV3FilePart(
            data: .base64(base64Data),
            mediaType: "text/plain",
            filename: "sample.txt"
        )
        let prompt: LanguageModelV3Prompt = [
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
