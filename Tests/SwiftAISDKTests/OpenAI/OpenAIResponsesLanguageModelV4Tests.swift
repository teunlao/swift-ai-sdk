import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import OpenAIProvider

@Suite("OpenAIResponsesLanguageModelV4")
struct OpenAIResponsesLanguageModelV4Tests {
    actor RequestCapture {
        private var requests: [URLRequest] = []

        func store(_ request: URLRequest) {
            requests.append(request)
        }

        func last() -> URLRequest? {
            requests.last
        }
    }

    @Test("V4 responses facade returns native Responses model")
    func v4ResponsesFacadeReturnsNativeModel() throws {
        let provider = createOpenAI(settings: .init(apiKey: "test-api-key"))
        let model = provider.responses("gpt-5")

        #expect(type(of: model) == OpenAIResponsesLanguageModelV4.self)
        #expect(model.specificationVersion == "v4")
        #expect(model.provider == "openai.responses")

        let defaultModel = try provider.languageModel("gpt-5")
        #expect(defaultModel is OpenAIResponsesLanguageModelV4)
    }

    @Test("V4 responses sends top-level reasoning and provider reference files")
    func v4ResponsesSendsReasoningAndProviderReferenceFiles() async throws {
        let capture = RequestCapture()
        let responseData = try jsonData([
            "id": "resp-v4",
            "created_at": 1_711_115_037.0,
            "model": "gpt-5",
            "output": [
                [
                    "id": "reasoning-1",
                    "type": "reasoning",
                    "summary": [
                        ["type": "summary_text", "text": "Need the uploaded file."]
                    ],
                    "encrypted_content": "encrypted-reasoning"
                ],
                [
                    "id": "msg-1",
                    "type": "message",
                    "status": "completed",
                    "role": "assistant",
                    "content": [
                        [
                            "type": "output_text",
                            "text": "Done",
                            "annotations": []
                        ]
                    ]
                ]
            ],
            "service_tier": "default",
            "usage": [
                "input_tokens": 11,
                "input_tokens_details": ["cached_tokens": 1],
                "output_tokens": 7,
                "output_tokens_details": ["reasoning_tokens": 3]
            ],
            "warnings": [],
            "incomplete_details": ["reason": NSNull()],
            "finish_reason": NSNull(),
            "error": NSNull()
        ])

        let provider = createOpenAI(settings: .init(
            baseURL: "https://proxy.openai.example/v1",
            apiKey: "test-api-key",
            fetch: { request in
                await capture.store(request)
                return FetchResponse(
                    body: .data(responseData),
                    urlResponse: HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: ["Content-Type": "application/json"]
                    )!
                )
            }
        ))

        let model = provider.responses("gpt-5")
        let result = try await model.doGenerate(options: .init(
            prompt: [
                .system(content: "Use Responses.", providerOptions: nil),
                .user(content: [
                    .text(.init(text: "Summarize this upload.")),
                    .file(.init(
                        data: .reference(["openai": "file-openai-123"]),
                        mediaType: "application/pdf",
                        filename: "manual.pdf"
                    ))
                ], providerOptions: nil)
            ],
            temperature: 0.7,
            reasoning: .medium
        ))

        #expect(result.finishReason.unified == .stop)
        #expect(result.usage.inputTokens.total == 11)
        #expect(result.usage.inputTokens.cacheRead == 1)
        #expect(result.usage.outputTokens.reasoning == 3)

        let reasoning = result.content.compactMap { content -> LanguageModelV4Reasoning? in
            if case .reasoning(let reasoning) = content { return reasoning }
            return nil
        }
        #expect(reasoning.first?.text == "Need the uploaded file.")

        let request = try #require(await capture.last())
        #expect(request.url?.absoluteString == "https://proxy.openai.example/v1/responses")

        let body = try requestBodyJSON(request)
        #expect(body["model"] as? String == "gpt-5")
        #expect(body["temperature"] == nil)

        let reasoningBody = try #require(body["reasoning"] as? [String: Any])
        #expect(reasoningBody["effort"] as? String == "medium")
        #expect(reasoningBody["summary"] as? String == "detailed")

        let input = try #require(body["input"] as? [[String: Any]])
        #expect(input[0]["role"] as? String == "developer")
        let userContent = try #require(input[1]["content"] as? [[String: Any]])
        let filePart = try #require(userContent.first { $0["type"] as? String == "input_file" })
        #expect(filePart["file_id"] as? String == "file-openai-123")

        let warnings = result.warnings.compactMap { warning -> String? in
            if case .unsupported(let feature, _) = warning { return feature }
            return nil
        }
        #expect(warnings.contains("temperature"))
    }

    @Test("V4 responses respects provider reasoning overrides")
    func v4ResponsesRespectsProviderReasoningOverrides() async throws {
        let capture = RequestCapture()
        let provider = createOpenAI(settings: .init(
            baseURL: "https://proxy.openai.example/v1",
            apiKey: "test-api-key",
            fetch: { request in
                await capture.store(request)
                return FetchResponse(
                    body: .data(try jsonData([
                        "id": "resp-v4",
                        "created_at": 1_711_115_037.0,
                        "model": "gpt-5",
                        "output": [],
                        "usage": [
                            "input_tokens": 0,
                            "output_tokens": 0
                        ],
                        "warnings": [],
                        "incomplete_details": ["reason": NSNull()],
                        "finish_reason": NSNull(),
                        "error": NSNull()
                    ])),
                    urlResponse: HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: ["Content-Type": "application/json"]
                    )!
                )
            }
        ))

        let model = provider.responses("gpt-5")
        _ = try await model.doGenerate(options: .init(
            prompt: v4TextPrompt,
            reasoning: .medium,
            providerOptions: [
                "openai": [
                    "reasoningEffort": .string("low"),
                    "reasoningSummary": .string("auto")
                ]
            ]
        ))

        let body = try requestBodyJSON(try #require(await capture.last()))
        let reasoningBody = try #require(body["reasoning"] as? [String: Any])
        #expect(reasoningBody["effort"] as? String == "low")
        #expect(reasoningBody["summary"] as? String == "auto")
    }

    @Test("V4 responses maps tool_search request and response parts")
    func v4ResponsesMapsToolSearch() async throws {
        let capture = RequestCapture()
        let responseData = try jsonData([
            "id": "resp-tool-search",
            "created_at": 1_711_115_037.0,
            "model": "gpt-5",
            "output": [
                [
                    "id": "tsc-1",
                    "type": "tool_search_call",
                    "execution": "server",
                    "status": "completed",
                    "arguments": ["query": "weather"]
                ],
                [
                    "id": "tso-1",
                    "type": "tool_search_output",
                    "execution": "server",
                    "status": "completed",
                    "tools": [
                        [
                            "type": "function",
                            "name": "get_weather",
                            "description": "Get weather"
                        ]
                    ]
                ]
            ],
            "usage": [
                "input_tokens": 4,
                "output_tokens": 2
            ],
            "warnings": [],
            "incomplete_details": ["reason": NSNull()],
            "finish_reason": NSNull(),
            "error": NSNull()
        ])

        let provider = createOpenAI(settings: .init(
            baseURL: "https://proxy.openai.example/v1",
            apiKey: "test-api-key",
            fetch: { request in
                await capture.store(request)
                return FetchResponse(
                    body: .data(responseData),
                    urlResponse: HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: ["Content-Type": "application/json"]
                    )!
                )
            }
        ))

        let model = provider.responses("gpt-5")
        let result = try await model.doGenerate(options: .init(
            prompt: v4TextPrompt,
            tools: [
                .provider(LanguageModelV4ProviderTool(
                    id: "openai.tool_search",
                    name: "tool_search",
                    args: [
                        "execution": .string("server"),
                        "description": .string("Load deferred tools"),
                        "parameters": .object([
                            "type": .string("object"),
                            "properties": .object([
                                "query": .object(["type": .string("string")])
                            ])
                        ])
                    ]
                ))
            ]
        ))

        let toolCalls = result.content.compactMap { content -> LanguageModelV4ToolCall? in
            if case .toolCall(let toolCall) = content { return toolCall }
            return nil
        }
        #expect(toolCalls.first?.toolCallId == "tsc-1")
        #expect(toolCalls.first?.toolName == "tool_search")
        #expect(toolCalls.first?.providerExecuted == true)

        let toolResults = result.content.compactMap { content -> LanguageModelV4ToolResult? in
            if case .toolResult(let toolResult) = content { return toolResult }
            return nil
        }
        #expect(toolResults.first?.toolCallId == "tsc-1")
        #expect(toolResults.first?.toolName == "tool_search")
        #expect(toolResults.first?.result == .object([
            "tools": .array([
                .object([
                    "type": .string("function"),
                    "name": .string("get_weather"),
                    "description": .string("Get weather")
                ])
            ])
        ]))

        let body = try requestBodyJSON(try #require(await capture.last()))
        let tools = try #require(body["tools"] as? [[String: Any]])
        let toolSearch = try #require(tools.first { $0["type"] as? String == "tool_search" })
        #expect(toolSearch["execution"] as? String == "server")
        #expect(toolSearch["description"] as? String == "Load deferred tools")
        #expect(toolSearch["parameters"] is [String: Any])
    }

    @Test("V4 responses sends context management allowed tools and pass-through files")
    func v4ResponsesSendsContextManagementAllowedToolsAndPassThroughFiles() async throws {
        let capture = RequestCapture()
        let provider = createOpenAI(settings: .init(
            baseURL: "https://proxy.openai.example/v1",
            apiKey: "test-api-key",
            fetch: { request in
                await capture.store(request)
                return FetchResponse(
                    body: .data(try jsonData([
                        "id": "resp-options",
                        "created_at": 1_711_115_037.0,
                        "model": "gpt-5",
                        "output": [],
                        "usage": ["input_tokens": 0, "output_tokens": 0],
                        "warnings": [],
                        "incomplete_details": ["reason": NSNull()],
                        "finish_reason": NSNull(),
                        "error": NSNull()
                    ])),
                    urlResponse: HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: ["Content-Type": "application/json"]
                    )!
                )
            }
        ))

        let model = provider.responses("gpt-5")
        _ = try await model.doGenerate(options: .init(
            prompt: [
                .user(content: [
                    .text(.init(text: "Use this CSV.")),
                    .file(.init(
                        data: .base64("YSxiCg=="),
                        mediaType: "text/csv",
                        filename: "data.csv"
                    ))
                ], providerOptions: nil)
            ],
            tools: [
                .function(LanguageModelV4FunctionTool(
                    name: "weather",
                    inputSchema: .object(["type": .string("object")])
                ))
            ],
            toolChoice: LanguageModelV4ToolChoice.none,
            providerOptions: [
                "openai": [
                    "passThroughUnsupportedFiles": .bool(true),
                    "contextManagement": .array([
                        .object([
                            "type": .string("compaction"),
                            "compactThreshold": .number(0.8)
                        ])
                    ]),
                    "allowedTools": .object([
                        "toolNames": .array([.string("weather")]),
                        "mode": .string("required")
                    ])
                ]
            ]
        ))

        let body = try requestBodyJSON(try #require(await capture.last()))

        let contextManagement = try #require(body["context_management"] as? [[String: Any]])
        #expect(contextManagement.count == 1)
        #expect(contextManagement[0]["type"] as? String == "compaction")
        #expect(contextManagement[0]["compact_threshold"] as? Double == 0.8)

        let toolChoice = try #require(body["tool_choice"] as? [String: Any])
        #expect(toolChoice["type"] as? String == "allowed_tools")
        #expect(toolChoice["mode"] as? String == "required")
        let allowedTools = try #require(toolChoice["tools"] as? [[String: Any]])
        #expect(allowedTools.first?["type"] as? String == "function")
        #expect(allowedTools.first?["name"] as? String == "weather")

        let input = try #require(body["input"] as? [[String: Any]])
        let userContent = try #require(input.first?["content"] as? [[String: Any]])
        let filePart = try #require(userContent.first { $0["type"] as? String == "input_file" })
        #expect(filePart["filename"] as? String == "data.csv")
        #expect(filePart["file_data"] as? String == "data:text/csv;base64,YSxiCg==")
    }

    @Test("V4 responses maps compaction generate and stream custom content")
    func v4ResponsesMapsCompactionGenerateAndStreamCustomContent() async throws {
        let generateProvider = createOpenAI(settings: .init(
            baseURL: "https://proxy.openai.example/v1",
            apiKey: "test-api-key",
            fetch: { request in
                FetchResponse(
                    body: .data(try jsonData([
                        "id": "resp-compaction",
                        "created_at": 1_711_115_037.0,
                        "model": "gpt-5",
                        "output": [
                            [
                                "id": "cmp-1",
                                "type": "compaction",
                                "encrypted_content": "encrypted-compaction"
                            ]
                        ],
                        "usage": ["input_tokens": 1, "output_tokens": 1],
                        "warnings": [],
                        "incomplete_details": ["reason": NSNull()],
                        "finish_reason": NSNull(),
                        "error": NSNull()
                    ])),
                    urlResponse: HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: ["Content-Type": "application/json"]
                    )!
                )
            }
        ))

        let generated = try await generateProvider.responses("gpt-5").doGenerate(options: .init(prompt: v4TextPrompt))
        let custom = try #require(generated.content.compactMap { content -> LanguageModelV4CustomContent? in
            if case .custom(let custom) = content { return custom }
            return nil
        }.first)
        #expect(custom.kind == "openai.compaction")
        #expect(custom.providerMetadata?["openai"]?["type"] == .string("compaction"))
        #expect(custom.providerMetadata?["openai"]?["itemId"] == .string("cmp-1"))
        #expect(custom.providerMetadata?["openai"]?["encryptedContent"] == .string("encrypted-compaction"))

        let streamProvider = createOpenAI(settings: .init(
            baseURL: "https://proxy.openai.example/v1",
            apiKey: "test-api-key",
            fetch: { request in
                FetchResponse(
                    body: streamBody(from: [
                        #"{"type":"response.output_item.done","output_index":0,"item":{"id":"cmp-2","type":"compaction","encrypted_content":"stream-encrypted"}}"#,
                        #"{"type":"response.completed","response":{"id":"resp-stream-compaction","created_at":1711115037,"model":"gpt-5","output":[{"id":"cmp-2","type":"compaction","encrypted_content":"stream-encrypted"}],"usage":{"input_tokens":1,"output_tokens":1},"incomplete_details":{"reason":null},"finish_reason":null,"error":null}}"#
                    ]),
                    urlResponse: HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: ["Content-Type": "text/event-stream"]
                    )!
                )
            }
        ))

        let streamResult = try await streamProvider.responses("gpt-5").doStream(options: .init(prompt: v4TextPrompt))
        var streamedCustom: LanguageModelV4CustomContent?
        for try await part in streamResult.stream {
            if case .custom(let custom) = part {
                streamedCustom = custom
            }
        }

        #expect(streamedCustom?.kind == "openai.compaction")
        #expect(streamedCustom?.providerMetadata?["openai"]?["itemId"] == .string("cmp-2"))
        #expect(streamedCustom?.providerMetadata?["openai"]?["encryptedContent"] == .string("stream-encrypted"))
    }

    @Test("V4 responses throws API error for pre-output stream errors")
    func v4ResponsesThrowsPreOutputStreamErrors() async throws {
        let provider = createOpenAI(settings: .init(
            baseURL: "https://proxy.openai.example/v1",
            apiKey: "test-api-key",
            fetch: { request in
                FetchResponse(
                    body: streamBody(from: [
                        #"{"type":"error","message":"The server had an error processing your request.","code":"server_error"}"#
                    ]),
                    urlResponse: HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: ["Content-Type": "text/event-stream"]
                    )!
                )
            }
        ))

        let model = provider.responses("gpt-5")

        do {
            _ = try await model.doStream(options: .init(prompt: v4TextPrompt, includeRawChunks: false))
            Issue.record("Expected APICallError before a stream result is returned")
        } catch let error as APICallError {
            #expect(error.message == "The server had an error processing your request.")
            #expect(error.statusCode == 500)
            #expect(error.isRetryable == true)
        } catch {
            Issue.record("Expected APICallError, got: \(error)")
        }
    }

    @Test("V4 responses throws API error when response.failed arrives before output")
    func v4ResponsesThrowsPreOutputResponseFailedStreamErrors() async throws {
        let provider = createOpenAI(settings: .init(
            baseURL: "https://proxy.openai.example/v1",
            apiKey: "test-api-key",
            fetch: { request in
                FetchResponse(
                    body: streamBody(from: [
                        #"{"type":"response.created","sequence_number":0,"response":{"id":"resp-failed-before-output","created_at":1711115037,"model":"gpt-5","service_tier":null}}"#,
                        #"{"type":"response.failed","sequence_number":1,"response":{"error":{"code":"server_error","message":"response failed"},"incomplete_details":null,"usage":null,"service_tier":null}}"#
                    ]),
                    urlResponse: HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: ["Content-Type": "text/event-stream"]
                    )!
                )
            }
        ))

        let model = provider.responses("gpt-5")

        do {
            _ = try await model.doStream(options: .init(prompt: v4TextPrompt, includeRawChunks: false))
            Issue.record("Expected APICallError before a stream result is returned")
        } catch let error as APICallError {
            #expect(error.message == "response failed")
            #expect(error.statusCode == 500)
            #expect(error.isRetryable == true)
        } catch {
            Issue.record("Expected APICallError, got: \(error)")
        }
    }

    @Test("V4 responses emits late response.failed error and finish reason")
    func v4ResponsesEmitsLateResponseFailedStreamErrorAndFinishReason() async throws {
        let provider = createOpenAI(settings: .init(
            baseURL: "https://proxy.openai.example/v1",
            apiKey: "test-api-key",
            fetch: { request in
                FetchResponse(
                    body: streamBody(from: [
                        #"{"type":"response.created","sequence_number":0,"response":{"id":"resp-failed-late","created_at":1711115037,"model":"gpt-5","service_tier":null}}"#,
                        #"{"type":"response.output_item.added","sequence_number":1,"output_index":0,"item":{"id":"msg-failed-late","type":"message"}}"#,
                        #"{"type":"response.failed","sequence_number":2,"response":{"error":{"code":"server_error","message":"response failed"},"incomplete_details":{"reason":"max_output_tokens"},"usage":{"input_tokens":7,"input_tokens_details":{"cached_tokens":2},"output_tokens":5,"output_tokens_details":{"reasoning_tokens":1}},"service_tier":"auto"}}"#
                    ]),
                    urlResponse: HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: ["Content-Type": "text/event-stream"]
                    )!
                )
            }
        ))

        let streamResult = try await provider.responses("gpt-5").doStream(options: .init(
            prompt: v4TextPrompt,
            includeRawChunks: false
        ))

        var errorValue: JSONValue?
        var finishReason: LanguageModelV4FinishReason?
        var usage: LanguageModelV4Usage?
        var providerMetadata: SharedV4ProviderMetadata?

        for try await part in streamResult.stream {
            switch part {
            case .error(let error):
                errorValue = error
            case .finish(let reason, let finalUsage, let metadata):
                finishReason = reason
                usage = finalUsage
                providerMetadata = metadata
            default:
                break
            }
        }

        let streamError = try #require(errorValue)
        guard case .object(let errorObject) = streamError else {
            Issue.record("Expected response.failed error object")
            return
        }
        #expect(errorObject["type"] == .string("response.failed"))
        #expect(errorObject["sequence_number"] == .number(2))

        guard case .object(let responseObject)? = errorObject["response"],
              case .object(let responseError)? = responseObject["error"] else {
            Issue.record("Expected response.failed response error object")
            return
        }
        #expect(responseError["message"] == .string("response failed"))
        #expect(responseError["code"] == .string("server_error"))
        #expect(responseObject["service_tier"] == .string("auto"))

        #expect(finishReason == LanguageModelV4FinishReason(unified: .length, raw: "max_output_tokens"))
        #expect(usage?.inputTokens.total == 7)
        #expect(usage?.inputTokens.cacheRead == 2)
        #expect(usage?.outputTokens.total == 5)
        #expect(usage?.outputTokens.reasoning == 1)
        #expect(providerMetadata?["openai"]?["serviceTier"] == .string("auto"))
        #expect(providerMetadata?["openai"]?["responseId"] == .string("resp-failed-late"))
    }
}

private let v4TextPrompt: LanguageModelV4Prompt = [
    .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
]

private func jsonData(_ value: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: value)
}

private func requestBodyJSON(_ request: URLRequest) throws -> [String: Any] {
    let body = try #require(request.httpBody)
    return try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
}

private func streamBody(from events: [String]) -> ProviderHTTPResponseBody {
    .stream(AsyncThrowingStream { continuation in
        for event in events {
            continuation.yield(Data("data: \(event)\n\n".utf8))
        }
        continuation.yield(Data("data: [DONE]\n\n".utf8))
        continuation.finish()
    })
}
