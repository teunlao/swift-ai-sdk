import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import MistralProvider

private func makeChatModel(generateId: @escaping @Sendable () -> String = { UUID().uuidString }) -> (MistralChatLanguageModel, RequestRecorder, ResponseBox) {
    let recorder = RequestRecorder()
    let placeholderResponse = FetchResponse(
        body: .data(Data()),
        urlResponse: HTTPURLResponse(
            url: HTTPTestHelpers.chatURL,
            statusCode: 500,
            httpVersion: "HTTP/1.1",
            headerFields: [:]
        )!
    )
    let responseBox = ResponseBox(initial: placeholderResponse)

    let fetch: FetchFunction = { request in
        await recorder.record(request)
        return await responseBox.value()
    }

    let provider = createMistralProvider(
        settings: .init(
            apiKey: "test-api-key",
            fetch: fetch,
            generateId: generateId
        )
    )

    return (provider.chat(modelId: .mistralSmallLatest), recorder, responseBox)
}

private func defaultPrompt() -> LanguageModelV3Prompt {
    [
        .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
    ]
}


private func encodeJSON(_ object: Any) -> String {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [])
    return String(data: data, encoding: .utf8)!
}

private func makeSSEChunks(_ payloads: [Any]) -> [String] {
    var chunks: [String] = []
    for payload in payloads {
        chunks.append("data: " + encodeJSON(payload) + "\n\n")
    }
    chunks.append("data: [DONE]\n\n")
    return chunks
}

@Suite("MistralChatLanguageModel doGenerate")
struct MistralChatLanguageModelGenerateTests {
    @Test("extracts text content")
    func textContent() async throws {
        let (model, _, responseBox) = makeChatModel()
        await responseBox.setJSON(
            url: HTTPTestHelpers.chatURL,
            body: [
                "id": "test-id",
                "model": "mistral-small-latest",
                "choices": [[
                    "index": 0,
                    "message": [
                        "role": "assistant",
                        "content": "Hello, World!"
                    ],
                    "finish_reason": "stop"
                ]],
                "usage": [
                    "prompt_tokens": 4,
                    "completion_tokens": 30,
                    "total_tokens": 34
                ]
            ]
        )

        let result = try await model.doGenerate(options: .init(prompt: defaultPrompt()))
        #expect(result.content == [.text(LanguageModelV3Text(text: "Hello, World!"))])
        #expect(result.finishReason == .stop)
    }

    @Test("avoids duplication with trailing assistant message")
    func avoidDuplication() async throws {
        let (model, _, responseBox) = makeChatModel()
        await responseBox.setJSON(
            url: HTTPTestHelpers.chatURL,
            body: [
                "choices": [[
                    "index": 0,
                    "message": [
                        "role": "assistant",
                        "content": "prefix and more content"
                    ],
                    "finish_reason": "stop"
                ]]
            ]
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil),
            .assistant(content: [.text(.init(text: "prefix "))], providerOptions: nil)
        ]

        let result = try await model.doGenerate(options: .init(prompt: prompt))
        #expect(result.content == [.text(LanguageModelV3Text(text: "prefix and more content"))])
    }

    @Test("extracts tool call content")
    func toolCallContent() async throws {
        let (model, _, responseBox) = makeChatModel()
        await responseBox.setJSON(
            url: HTTPTestHelpers.chatURL,
            body: [
                "choices": [[
                    "index": 0,
                    "message": [
                        "role": "assistant",
                        "tool_calls": [[
                            "id": "gSIMJiOkT",
                            "function": [
                                "name": "weatherTool",
                                "arguments": "{\"location\": \"paris\"}"
                            ]
                        ]]
                    ],
                    "finish_reason": "tool_calls"
                ]]
            ]
        )

        let result = try await model.doGenerate(options: .init(prompt: defaultPrompt()))
        #expect(result.content == [
            .toolCall(LanguageModelV3ToolCall(toolCallId: "gSIMJiOkT", toolName: "weatherTool", input: "{\"location\": \"paris\"}"))
        ])
        #expect(result.finishReason == .toolCalls)
    }

    @Test("extracts reasoning content")
    func reasoningContent() async throws {
        let (model, _, responseBox) = makeChatModel()
        await responseBox.setJSON(
            url: HTTPTestHelpers.chatURL,
            body: [
                "choices": [[
                    "index": 0,
                    "message": [
                        "role": "assistant",
                        "content": [
                            [
                                "type": "thinking",
                                "thinking": [["type": "text", "text": "Let me think about this problem step by step."]]
                            ],
                            [
                                "type": "text",
                                "text": "Here is my answer."
                            ]
                        ]
                    ],
                    "finish_reason": "stop"
                ]]
            ]
        )

        let result = try await model.doGenerate(options: .init(prompt: defaultPrompt()))
        #expect(result.content == [
            .reasoning(LanguageModelV3Reasoning(text: "Let me think about this problem step by step.")),
            .text(LanguageModelV3Text(text: "Here is my answer."))
        ])
    }

    @Test("preserves ordering of reasoning and text")
    func reasoningOrdering() async throws {
        let (model, _, responseBox) = makeChatModel()
        await responseBox.setJSON(
            url: HTTPTestHelpers.chatURL,
            body: [
                "choices": [[
                    "index": 0,
                    "message": [
                        "role": "assistant",
                        "content": [
                            ["type": "thinking", "thinking": [["type": "text", "text": "First thought."]]],
                            ["type": "text", "text": "Partial answer."],
                            ["type": "thinking", "thinking": [["type": "text", "text": "Second thought."]]],
                            ["type": "text", "text": "Final answer."]
                        ]
                    ],
                    "finish_reason": "stop"
                ]]
            ]
        )

        let result = try await model.doGenerate(options: .init(prompt: defaultPrompt()))
        #expect(result.content == [
            .reasoning(LanguageModelV3Reasoning(text: "First thought.")),
            .text(LanguageModelV3Text(text: "Partial answer.")),
            .reasoning(LanguageModelV3Reasoning(text: "Second thought.")),
            .text(LanguageModelV3Text(text: "Final answer."))
        ])
    }

    @Test("ignores empty thinking content")
    func ignoresEmptyThinking() async throws {
        let (model, _, responseBox) = makeChatModel()
        await responseBox.setJSON(
            url: HTTPTestHelpers.chatURL,
            body: [
                "choices": [[
                    "index": 0,
                    "message": [
                        "role": "assistant",
                        "content": [
                            ["type": "thinking", "thinking": []],
                            ["type": "text", "text": "Just the answer."]
                        ]
                    ],
                    "finish_reason": "stop"
                ]]
            ]
        )

        let result = try await model.doGenerate(options: .init(prompt: defaultPrompt()))
        #expect(result.content == [.text(LanguageModelV3Text(text: "Just the answer."))])
    }

    @Test("captures usage metrics")
    func capturesUsage() async throws {
        let (model, _, responseBox) = makeChatModel()
        await responseBox.setJSON(
            url: HTTPTestHelpers.chatURL,
            body: [
                "choices": [[
                    "index": 0,
                    "message": ["role": "assistant", "content": ""],
                    "finish_reason": "stop"
                ]],
                "usage": [
                    "prompt_tokens": 20,
                    "completion_tokens": 5,
                    "total_tokens": 25
                ]
            ]
        )

        let result = try await model.doGenerate(options: .init(prompt: defaultPrompt()))
        #expect(result.usage.inputTokens == 20)
        #expect(result.usage.outputTokens == 5)
        #expect(result.usage.totalTokens == 25)
    }

    @Test("includes response metadata")
    func includesResponseMetadata() async throws {
        let (model, _, responseBox) = makeChatModel()
        await responseBox.setJSON(
            url: HTTPTestHelpers.chatURL,
            body: [
                "id": "test-id",
                "model": "test-model",
                "created": 123.0,
                "choices": [[
                    "index": 0,
                    "message": ["role": "assistant", "content": "hi"],
                    "finish_reason": "stop"
                ]]
            ]
        )

        let result = try await model.doGenerate(options: .init(prompt: defaultPrompt()))
        #expect(result.response?.id == "test-id")
        #expect(result.response?.modelId == "test-model")
        #expect(result.response?.timestamp == Date(timeIntervalSince1970: 123))
    }

    @Test("captures response headers")
    func capturesResponseHeaders() async throws {
        let (model, _, responseBox) = makeChatModel()
        await responseBox.setJSON(
            url: HTTPTestHelpers.chatURL,
            body: [
                "choices": [[
                    "index": 0,
                    "message": ["role": "assistant", "content": "hi"],
                    "finish_reason": "stop"
                ]]
            ],
            headers: ["Test-Header": "test-value"]
        )

        let result = try await model.doGenerate(options: .init(prompt: defaultPrompt()))
        let headers = result.response?.headers ?? [:]
        #expect(headers["test-header"] == "test-value")
        #expect(headers.keys.contains("content-type"))
    }

    @Test("request body mirrors prompt")
    func requestBodyMirrorsPrompt() async throws {
        let (model, _, responseBox) = makeChatModel()
        await responseBox.setJSON(
            url: HTTPTestHelpers.chatURL,
            body: [
                "choices": [[
                    "index": 0,
                    "message": ["role": "assistant", "content": ""],
                    "finish_reason": "stop"
                ]]
            ]
        )

        let result = try await model.doGenerate(options: .init(prompt: defaultPrompt()))
        guard let body = result.request?.body as? [String: JSONValue],
              case .array(let messages) = body["messages"],
              case .object(let userMessage) = messages.first,
              case .array(let contentArray) = userMessage["content"],
              case .object(let textEntry) = contentArray.first else {
            Issue.record("Unexpected request body")
            return
        }

        #expect(userMessage["role"] == .string("user"))
        #expect(textEntry["text"] == .string("Hello"))
        if case .string(let modelId) = body["model"] {
            #expect(modelId == "mistral-small-latest")
        } else {
            Issue.record("Missing model id")
        }
    }

    @Test("injects JSON instruction without schema")
    func injectsJSONInstruction() async throws {
        let (model, _, responseBox) = makeChatModel()
        await responseBox.setJSON(
            url: HTTPTestHelpers.chatURL,
            body: [
                "choices": [[
                    "index": 0,
                    "message": ["role": "assistant", "content": ""],
                    "finish_reason": "stop"
                ]]
            ]
        )

        let result = try await model.doGenerate(options: .init(prompt: defaultPrompt(), responseFormat: .json(schema: nil, name: nil, description: nil)))

        guard let body = result.request?.body as? [String: JSONValue],
              case .array(let messages) = body["messages"],
              case .object(let systemMessage) = messages.first else {
            Issue.record("Missing system message")
            return
        }

        #expect(systemMessage["role"] == .string("system"))
        if case .string(let content) = systemMessage["content"] {
            #expect(content.contains("You MUST answer with JSON."))
        } else {
            Issue.record("Missing instruction content")
        }
    }

    @Test("injects JSON instruction with schema")
    func injectsJSONInstructionWithSchema() async throws {
        let (model, _, responseBox) = makeChatModel()
        await responseBox.setJSON(
            url: HTTPTestHelpers.chatURL,
            body: [
                "choices": [[
                    "index": 0,
                    "message": ["role": "assistant", "content": ""],
                    "finish_reason": "stop"
                ]]
            ]
        )

        let schema: JSONValue = .object(["type": .string("object")])
        let result = try await model.doGenerate(options: .init(
            prompt: defaultPrompt(),
            responseFormat: .json(schema: schema, name: "Weather", description: "desc")
        ))

        guard let body = result.request?.body as? [String: JSONValue],
              case .object(let responseFormat) = body["response_format"],
              responseFormat["type"] == .string("json_schema"),
              case .object(let jsonSchema) = responseFormat["json_schema"],
              let encodedSchema = jsonSchema["schema"],
              encodedSchema == schema else {
            Issue.record("Missing JSON schema payload")
            return
        }
    }

    @Test("extracts text from content objects")
    func contentObjectText() async throws {
        let (model, _, responseBox) = makeChatModel()
        await responseBox.setJSON(
            url: HTTPTestHelpers.chatURL,
            body: [
                "choices": [[
                    "index": 0,
                    "message": [
                        "role": "assistant",
                        "content": [["type": "text", "text": "Hello"]]
                    ],
                    "finish_reason": "stop"
                ]]
            ]
        )

        let result = try await model.doGenerate(options: .init(prompt: defaultPrompt()))
        #expect(result.content == [.text(LanguageModelV3Text(text: "Hello"))])
    }

    @Test("returns raw text with think tags for reasoning models")
    func reasoningModelRawText() async throws {
        let (model, _, responseBox) = makeChatModel()
        await responseBox.setJSON(
            url: HTTPTestHelpers.chatURL,
            body: [
                "model": "magistral-small-2507",
                "choices": [[
                    "index": 0,
                    "message": [
                        "role": "assistant",
                        "content": "<think>Reasoning</think> Response"
                    ],
                    "finish_reason": "stop"
                ]]
            ]
        )

        let result = try await model.doGenerate(options: .init(prompt: defaultPrompt()))
        #expect(result.content == [.text(LanguageModelV3Text(text: "<think>Reasoning</think> Response"))])
    }

    @Test("passes parallel tool calls option")
    func parallelToolCalls() async throws {
        let (model, recorder, responseBox) = makeChatModel()
        await responseBox.setJSON(
            url: HTTPTestHelpers.chatURL,
            body: [
                "choices": [[
                    "index": 0,
                    "message": ["role": "assistant", "content": ""],
                    "finish_reason": "stop"
                ]]
            ]
        )

        _ = try await model.doGenerate(options: .init(
            prompt: defaultPrompt(),
            tools: [
                .function(.init(
                    name: "test-tool",
                    inputSchema: .object(["type": .string("object")]),
                    description: nil,
                    providerOptions: nil
                ))
            ],
            providerOptions: [
                "mistral": ["parallelToolCalls": .bool(false)]
            ]
        ))

        guard let request = await recorder.first() else {
            Issue.record("Missing request")
            return
        }

        let body = try decodeJSONBody(request)
        #expect(body["parallel_tool_calls"] as? Bool == false)
    }
    @Test("includes tools and tool choice in request")
    func toolsAndToolChoice() async throws {
        let (model, recorder, responseBox) = makeChatModel()
        await responseBox.setJSON(
            url: HTTPTestHelpers.chatURL,
            body: [
                "choices": [[
                    "index": 0,
                    "message": ["role": "assistant", "content": ""],
                    "finish_reason": "stop"
                ]]
            ]
        )

        let tool = LanguageModelV3Tool.function(LanguageModelV3FunctionTool(
            name: "test-tool",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object(["value": .object(["type": .string("string")])]),
                "required": .array([.string("value")]),
                "additionalProperties": .bool(false)
            ]),
            description: nil,
            providerOptions: nil
        ))

        _ = try await model.doGenerate(options: .init(
            prompt: defaultPrompt(),
            tools: [tool],
            toolChoice: .tool(toolName: "test-tool")
        ))

        guard let request = await recorder.first() else {
            Issue.record("Missing request")
            return
        }

        let body = try decodeJSONBody(request)
        #expect(body["tool_choice"] as? String == "any")
        if let tools = body["tools"] as? [[String: Any]],
           let first = tools.first,
           let function = first["function"] as? [String: Any] {
            #expect(function["name"] as? String == "test-tool")
        } else {
            Issue.record("Missing tools payload")
        }
    }

    @Test("merges headers for requests")
    func mergesHeaders() async throws {
        let recorder = RequestRecorder()
        let placeholderResponse = FetchResponse(
            body: .data(Data()),
            urlResponse: HTTPURLResponse(
                url: HTTPTestHelpers.chatURL,
                statusCode: 500,
                httpVersion: "HTTP/1.1",
                headerFields: [:]
            )!
        )
        let responseBox = ResponseBox(initial: placeholderResponse)

        let fetch: FetchFunction = { request in
            await recorder.record(request)
            return await responseBox.value()
        }

        let provider = createMistralProvider(
            settings: .init(
                apiKey: "test-api-key",
                headers: ["Custom-Provider-Header": "provider-header-value"],
                fetch: fetch
            )
        )

        await responseBox.setJSON(
            url: HTTPTestHelpers.chatURL,
            body: [
                "choices": [[
                    "index": 0,
                    "message": ["role": "assistant", "content": ""],
                    "finish_reason": "stop"
                ]]
            ]
        )

        _ = try await provider.chat(modelId: .mistralSmallLatest).doGenerate(options: .init(
            prompt: defaultPrompt(),
            headers: ["Custom-Request-Header": "request-header-value"]
        ))

        guard let request = await recorder.first() else {
            Issue.record("Missing request")
            return
        }

        let headers = (request.allHTTPHeaderFields ?? [:]).reduce(into: [:]) { result, entry in
            result[entry.key.lowercased()] = entry.value
        }

        #expect(headers["authorization"] == "Bearer test-api-key")
        #expect(headers["custom-provider-header"] == "provider-header-value")
        #expect(headers["custom-request-header"] == "request-header-value")
        #expect(headers["user-agent"]?.contains("ai-sdk/mistral") == true)
    }
}

@Suite("MistralChatLanguageModel doStream")
struct MistralChatLanguageModelStreamTests {
    private func makeStreamingModel(generateId: @escaping @Sendable () -> String = { UUID().uuidString }) -> (MistralChatLanguageModel, RequestRecorder, ResponseBox) {
        makeChatModel(generateId: generateId)
    }

    private func collectParts(_ stream: AsyncThrowingStream<LanguageModelV3StreamPart, Error>) async throws -> [LanguageModelV3StreamPart] {
        try await collectStream(stream)
    }

    @Test("streams text deltas")
    func streamsText() async throws {
        let (model, _, responseBox) = makeStreamingModel()
        let payloads: [Any] = [
            [
                "id": "chunk-1",
                "created": 1_750_537_996,
                "model": "mistral-small-latest",
                "choices": [[
                    "index": 0, "delta": ["role": "assistant", "content": ""], "finish_reason": nil]]
            ],
            [
                "id": "chunk-1",
                "created": 1_750_537_996,
                "model": "mistral-small-latest",
                "choices": [[
                    "index": 0, "delta": ["content": "Hello"], "finish_reason": nil]]
            ],
            [
                "id": "chunk-1",
                "created": 1_750_537_996,
                "model": "mistral-small-latest",
                "choices": [[
                    "index": 0,
                    "delta": ["content": " world"],
                    "finish_reason": "stop"
                ]],
                "usage": ["prompt_tokens": 4, "completion_tokens": 32, "total_tokens": 36]
            ]
        ]

        await responseBox.setStream(url: HTTPTestHelpers.chatURL, chunks: makeSSEChunks(payloads))

        let result = try await model.doStream(options: .init(prompt: defaultPrompt(), includeRawChunks: false))
        let parts = try await collectParts(result.stream)

        #expect(parts.contains { if case .textDelta(_, let delta, _) = $0 { return delta == "Hello" } else { return false } })
        #expect(parts.contains { if case .textDelta(_, let delta, _) = $0 { return delta == " world" } else { return false } })
        if let finish = parts.last, case let .finish(reason, usage, _) = finish {
            #expect(reason == .stop)
            #expect(usage.totalTokens == 36)
        } else {
            Issue.record("Missing finish part")
        }
    }

    @Test("avoids duplication when trailing assistant message present")
    func streamAvoidsDuplication() async throws {
        let (model, _, responseBox) = makeStreamingModel()
        let payloads: [Any] = [
            [
                "id": "chunk-2",
                "created": 1_750_537_996,
                "model": "mistral-small-latest",
                "choices": [[
                    "index": 0, "delta": ["role": "assistant", "content": ""], "finish_reason": nil]]
            ],
            [
                "id": "chunk-2",
                "created": 1_750_537_996,
                "model": "mistral-small-latest",
                "choices": [[
                    "index": 0, "delta": ["content": "prefix"], "finish_reason": nil]]
            ],
            [
                "id": "chunk-2",
                "created": 1_750_537_996,
                "model": "mistral-small-latest",
                "choices": [[
                    "index": 0, "delta": ["content": " and"], "finish_reason": nil]]
            ],
            [
                "id": "chunk-2",
                "created": 1_750_537_996,
                "model": "mistral-small-latest",
                "choices": [[
                    "index": 0, "delta": ["content": " more content"], "finish_reason": "stop"]]
            ]
        ]

        await responseBox.setStream(url: HTTPTestHelpers.chatURL, chunks: makeSSEChunks(payloads))

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil),
            .assistant(content: [.text(.init(text: "prefix "))], providerOptions: nil)
        ]

        let result = try await model.doStream(options: .init(prompt: prompt, includeRawChunks: false))
        let parts = try await collectParts(result.stream)
        let text = parts.compactMap { part -> String? in
            if case .textDelta(_, let delta, _) = part { return delta }
            return nil
        }.joined()
        #expect(text == "prefix and more content")
    }

    @Test("streams tool deltas")
    func streamsToolDeltas() async throws {
        let idGenerator = SequentialIDGenerator()
        let (model, _, responseBox) = makeStreamingModel(generateId: { idGenerator() })
        let chunks: [String] = makeSSEChunks([
            [
                "id": "tool-stream",
                "created": 1_750_538_400,
                "model": "mistral-large-latest",
                "choices": [[
                    "index": 0,
                    "delta": ["role": "assistant", "content": ""],
                    "finish_reason": nil
                ]]
            ],
            [
                "id": "tool-stream",
                "created": 1_750_538_400,
                "model": "mistral-large-latest",
                "choices": [[
                    "index": 0,
                    "delta": [
                        "content": nil,
                        "tool_calls": [[
                            "id": "call_9K8xFjN2mP3qR7sT",
                            "function": ["name": "test-tool", "arguments": #"{"value":"Sparkle Day"}"#]
                        ]]
                    ],
                    "finish_reason": "tool_calls"
                ]],
                "usage": ["prompt_tokens": 183, "completion_tokens": 133, "total_tokens": 316]
            ]
        ])

        await responseBox.setStream(url: HTTPTestHelpers.chatURL, chunks: chunks)

        let result = try await model.doStream(options: .init(
            prompt: defaultPrompt(),
            tools: [
                .function(LanguageModelV3FunctionTool(
                    name: "test-tool",
                    inputSchema: .object(["type": .string("object")])
                ))
            ],
            includeRawChunks: false
        ))

        let parts = try await collectParts(result.stream)
        #expect(parts.contains { if case .toolCall(let call) = $0 { return call.toolName == "test-tool" } else { return false } })
    }

    @Test("exposes response headers for streams")
    func streamResponseHeaders() async throws {
        let (model, _, responseBox) = makeStreamingModel()
        await responseBox.setStream(
            url: HTTPTestHelpers.chatURL,
            chunks: makeSSEChunks([
                ["id": "hdr", "choices": [[
                    "index": 0, "delta": ["role": "assistant", "content": "Hello"], "finish_reason": "stop"]]]
            ]),
            headers: ["Test-Header": "value"]
        )

        let result = try await model.doStream(options: .init(prompt: defaultPrompt()))
        let headers = result.response?.headers ?? [:]
        #expect(headers["test-header"] == "value")
        #expect(headers["content-type"] == "text/event-stream")
    }

    @Test("passes messages in streaming request")
    func streamRequestBody() async throws {
        let (model, recorder, responseBox) = makeStreamingModel()
        await responseBox.setStream(
            url: HTTPTestHelpers.chatURL,
            chunks: makeSSEChunks([
                ["id": "req", "choices": [[
                    "index": 0, "delta": ["role": "assistant", "content": ""], "finish_reason": "stop"]]]
            ])
        )

        _ = try await model.doStream(options: .init(prompt: defaultPrompt()))

        guard let request = await recorder.first() else {
            Issue.record("Missing request")
            return
        }

        let body = try decodeJSONBody(request)
        #expect(body["model"] as? String == "mistral-small-latest")
        if let messages = body["messages"] as? [[String: Any]], let first = messages.first {
            #expect(first["role"] as? String == "user")
        } else {
            Issue.record("Missing messages array")
        }
    }

    @Test("merges headers for streaming requests")
    func streamHeaders() async throws {
        let recorder = RequestRecorder()
        let placeholderResponse = FetchResponse(
            body: .data(Data()),
            urlResponse: HTTPURLResponse(
                url: HTTPTestHelpers.chatURL,
                statusCode: 500,
                httpVersion: "HTTP/1.1",
                headerFields: [:]
            )!
        )
        let responseBox = ResponseBox(initial: placeholderResponse)

        let fetch: FetchFunction = { request in
            await recorder.record(request)
            return await responseBox.value()
        }

        let provider = createMistralProvider(
            settings: .init(
                apiKey: "test-api-key",
                headers: ["Custom-Provider-Header": "provider-header-value"],
                fetch: fetch
            )
        )

        await responseBox.setStream(
            url: HTTPTestHelpers.chatURL,
            chunks: makeSSEChunks([
                ["id": "hdr", "choices": [[
                    "index": 0, "delta": ["role": "assistant", "content": ""], "finish_reason": "stop"]]]
            ])
        )

        _ = try await provider.chat(modelId: .mistralSmallLatest).doStream(options: .init(
            prompt: defaultPrompt(),
            headers: ["Custom-Request-Header": "request-header-value"]
        ))

        guard let request = await recorder.first() else {
            Issue.record("Missing request")
            return
        }

        let headers = (request.allHTTPHeaderFields ?? [:]).reduce(into: [:]) { result, entry in
            result[entry.key.lowercased()] = entry.value
        }

        #expect(headers["authorization"] == "Bearer test-api-key")
        #expect(headers["custom-provider-header"] == "provider-header-value")
        #expect(headers["custom-request-header"] == "request-header-value")
    }

    @Test("request body for stream includes stream flag")
    func streamRequestBodyIncludesFlag() async throws {
        let (model, _, responseBox) = makeStreamingModel()
        await responseBox.setStream(
            url: HTTPTestHelpers.chatURL,
            chunks: makeSSEChunks([
                ["id": "req", "choices": [[
                    "index": 0, "delta": ["role": "assistant", "content": ""], "finish_reason": "stop"]]]
            ])
        )

        let result = try await model.doStream(options: .init(prompt: defaultPrompt()))
        guard let body = result.request?.body as? [String: JSONValue] else {
            Issue.record("Missing request body")
            return
        }
        #expect(body["stream"] == .bool(true))
    }

    @Test("streams text when content is object array")
    func streamContentObjects() async throws {
        let (model, _, responseBox) = makeStreamingModel()
        await responseBox.setStream(
            url: HTTPTestHelpers.chatURL,
            chunks: makeSSEChunks([
                [
                    "id": "content",
                    "created": 1_750_538_500,
                    "model": "mistral-small-latest",
                    "choices": [[
                    "index": 0, "delta": ["role": "assistant", "content": [["type": "text", "text": "Hello"]]], "finish_reason": nil]]
                ],
                [
                    "id": "content",
                    "created": 1_750_538_500,
                    "model": "mistral-small-latest",
                    "choices": [[
                    "index": 0, "delta": ["content": [["type": "text", "text": ", world!"]]], "finish_reason": "stop"]],
                    "usage": ["prompt_tokens": 4, "completion_tokens": 32, "total_tokens": 36]
                ]
            ])
        )

        let result = try await model.doStream(options: .init(prompt: defaultPrompt()))
        let text = try await collectParts(result.stream).compactMap { part -> String? in
            if case .textDelta(_, let delta, _) = part { return delta }
            return nil
        }.joined()
        #expect(text == "Hello, world!")
    }

    @Test("streams thinking content as reasoning")
    func streamThinking() async throws {
        let idGenerator = SequentialIDGenerator()
        let (model, _, responseBox) = makeStreamingModel(generateId: { idGenerator() })
        await responseBox.setStream(
            url: HTTPTestHelpers.chatURL,
            chunks: makeSSEChunks([
                [
                    "id": "thinking",
                    "created": 1_750_538_000,
                    "model": "magistral-small-2507",
                    "choices": [[
                    "index": 0, "delta": ["role": "assistant", "content": [["type": "thinking", "thinking": [["type": "text", "text": "Let me think..."]]]]], "finish_reason": nil]]
                ],
                [
                    "id": "thinking",
                    "created": 1_750_538_000,
                    "model": "magistral-small-2507",
                    "choices": [[
                    "index": 0, "delta": ["content": [["type": "text", "text": "The answer is 4."]]], "finish_reason": "stop"]],
                    "usage": ["prompt_tokens": 5, "completion_tokens": 20, "total_tokens": 25]
                ]
            ])
        )

        let streamResult = try await model.doStream(options: .init(prompt: defaultPrompt()))
        let parts = try await collectParts(streamResult.stream)
        #expect(parts.contains { if case .reasoningDelta(_, let delta, _) = $0 { return delta == "Let me think..." } else { return false } })
        #expect(parts.contains { if case .textDelta(_, let delta, _) = $0 { return delta == "The answer is 4." } else { return false } })
    }

    @Test("streams interleaved thinking and text")
    func streamInterleaved() async throws {
        let idGenerator = SequentialIDGenerator()
        let (model, _, responseBox) = makeStreamingModel(generateId: { idGenerator() })
        await responseBox.setStream(
            url: HTTPTestHelpers.chatURL,
            chunks: makeSSEChunks([
                [
                    "id": "interleaved",
                    "choices": [[
                    "index": 0, "delta": ["content": [["type": "thinking", "thinking": [["type": "text", "text": "First thought."]]]]], "finish_reason": nil]]
                ],
                [
                    "id": "interleaved",
                    "choices": [[
                    "index": 0, "delta": ["content": [["type": "text", "text": "Partial answer."]]], "finish_reason": nil]]
                ],
                [
                    "id": "interleaved",
                    "choices": [[
                    "index": 0, "delta": ["content": [["type": "thinking", "thinking": [["type": "text", "text": "Second thought."]]]]], "finish_reason": nil]]
                ],
                [
                    "id": "interleaved",
                    "choices": [[
                    "index": 0, "delta": ["content": [["type": "text", "text": "Final answer."]]], "finish_reason": "stop"]]
                ]
            ])
        )

        let streamResult = try await model.doStream(options: .init(prompt: defaultPrompt()))
        let parts = try await collectParts(streamResult.stream)
        let reasoningStarts = parts.filter { if case .reasoningStart = $0 { return true } else { return false } }
        #expect(reasoningStarts.count == 2)
    }

    @Test("streams raw chunks when requested")
    func streamsRawChunks() async throws {
        let (model, _, responseBox) = makeStreamingModel()
        await responseBox.setStream(
            url: HTTPTestHelpers.chatURL,
            chunks: makeSSEChunks([
                ["id": "raw", "choices": [[
                    "index": 0, "delta": ["role": "assistant", "content": "Hello"], "finish_reason": nil]]],
                ["id": "raw", "choices": [[
                    "index": 0, "delta": ["content": " world"], "finish_reason": "stop"]], "usage": ["prompt_tokens": 10, "completion_tokens": 5, "total_tokens": 15]]
            ])
        )

        let parts = try await collectParts(model.doStream(options: .init(prompt: defaultPrompt(), includeRawChunks: true)).stream)
        #expect(parts.contains { if case .raw = $0 { return true } else { return false } })
    }
}
