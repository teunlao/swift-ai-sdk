import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import AlibabaProvider

@Suite("AlibabaChatLanguageModel")
struct AlibabaChatLanguageModelTests {
    private let baseURL = "https://dashscope-intl.aliyuncs.com/compatible-mode/v1"

    private let prompt: LanguageModelV3Prompt = [
        .user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)
    ]

    private func httpResponse(url: URL, statusCode: Int = 200, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    private func jsonData(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [])
    }

    private actor Capture {
        private(set) var requests: [URLRequest] = []

        func store(_ request: URLRequest) {
            requests.append(request)
        }

        func first() -> URLRequest? { requests.first }
    }

    private func makeModel(
        fetch: @escaping FetchFunction,
        includeUsage: Bool = true,
        generateId: @escaping IDGenerator = { "test-reasoning-id" }
    ) -> AlibabaChatLanguageModel {
        AlibabaChatLanguageModel(
            modelId: .qwenPlus,
            config: AlibabaChatConfig(
                provider: "alibaba.chat",
                baseURL: baseURL,
                headers: { ["authorization": "Bearer test"] },
                fetch: fetch,
                includeUsage: includeUsage,
                generateId: generateId
            )
        )
    }

    private func decodeRequestBody(_ request: URLRequest) throws -> JSONValue {
        guard let body = request.httpBody else { return .null }
        return try JSONDecoder().decode(JSONValue.self, from: body)
    }

    private func sse(_ obj: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: obj, options: [])
        let text = String(data: data, encoding: .utf8) ?? "{}"
        return "data: \(text)\n\n"
    }

    private func sseDone() -> String {
        "data: [DONE]\n\n"
    }

    @Test("doGenerate extracts text and sends correct request body")
    func doGenerateText() async throws {
        let capture = Capture()

        let responseJSON: [String: Any] = [
            "id": "chatcmpl-1",
            "created": 1_770_764_844,
            "model": "qwen-plus",
            "choices": [
                [
                    "index": 0,
                    "message": ["role": "assistant", "content": "Hello back"],
                    "finish_reason": "stop",
                ]
            ],
            "usage": [
                "prompt_tokens": 18,
                "completion_tokens": 1064,
                "total_tokens": 1082,
                "prompt_tokens_details": ["cached_tokens": 0],
            ],
        ]

        let data = try jsonData(responseJSON)

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(data), urlResponse: self.httpResponse(url: request.url!))
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: .init(prompt: prompt))

        #expect(result.content.count == 1)
        if case let .text(text) = result.content[0] {
            #expect(text.text == "Hello back")
        } else {
            Issue.record("Expected text content")
        }

        guard let request = await capture.first() else {
            Issue.record("Missing captured request")
            return
        }

        let body = try decodeRequestBody(request)
        #expect(body == .object([
            "model": .string("qwen-plus"),
            "messages": .array([
                .object([
                    "role": .string("user"),
                    "content": .string("Hello"),
                ])
            ]),
        ]))
    }

    @Test("doGenerate extracts tool call content")
    func doGenerateToolCall() async throws {
        let responseJSON: [String: Any] = [
            "id": "chatcmpl-tool",
            "created": 1,
            "model": "qwen-plus",
            "choices": [
                [
                    "index": 0,
                    "message": [
                        "role": "assistant",
                        "content": NSNull(),
                        "tool_calls": [
                            [
                                "id": "call-1",
                                "type": "function",
                                "function": [
                                    "name": "get_weather",
                                    "arguments": "{\"location\":\"SF\"}",
                                ],
                            ],
                        ],
                    ],
                    "finish_reason": "tool_calls",
                ]
            ],
        ]

        let data = try jsonData(responseJSON)
        let fetch: FetchFunction = { request in
            FetchResponse(body: .data(data), urlResponse: self.httpResponse(url: request.url!))
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: .init(prompt: prompt))

        let toolCalls = result.content.compactMap { part -> LanguageModelV3ToolCall? in
            if case let .toolCall(value) = part { return value }
            return nil
        }

        #expect(toolCalls.count == 1)
        #expect(toolCalls[0].toolCallId == "call-1")
        #expect(toolCalls[0].toolName == "get_weather")
        #expect(toolCalls[0].input == "{\"location\":\"SF\"}")
    }

    @Test("doGenerate extracts reasoning content and usage with reasoning tokens")
    func doGenerateReasoningUsage() async throws {
        let responseJSON: [String: Any] = [
            "id": "chatcmpl-reasoning",
            "created": 1,
            "model": "qwen-plus",
            "choices": [
                [
                    "index": 0,
                    "message": [
                        "role": "assistant",
                        "content": "Final answer",
                        "reasoning_content": "Reasoning trace",
                    ],
                    "finish_reason": "stop",
                ]
            ],
            "usage": [
                "prompt_tokens": 24,
                "completion_tokens": 1668,
                "total_tokens": 1692,
                "prompt_tokens_details": [
                    "cached_tokens": 0,
                ],
                "completion_tokens_details": [
                    "reasoning_tokens": 1353,
                ],
            ],
        ]

        let data = try jsonData(responseJSON)
        let fetch: FetchFunction = { request in
            FetchResponse(body: .data(data), urlResponse: self.httpResponse(url: request.url!))
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: .init(prompt: prompt))

        #expect(result.content.count == 2)
        #expect(result.usage.inputTokens.total == 24)
        #expect(result.usage.inputTokens.cacheRead == 0)
        #expect(result.usage.inputTokens.cacheWrite == 0)
        #expect(result.usage.inputTokens.noCache == 24)
        #expect(result.usage.outputTokens.total == 1668)
        #expect(result.usage.outputTokens.reasoning == 1353)
        #expect(result.usage.outputTokens.text == 315)
    }

    @Test("doGenerate calculates cacheWrite/noCache with cache tokens")
    func doGenerateCacheTokens() async throws {
        let responseJSON: [String: Any] = [
            "id": "chatcmpl-cache-test",
            "created": 1,
            "model": "qwen-plus",
            "choices": [
                [
                    "index": 0,
                    "message": ["role": "assistant", "content": "Hello"],
                    "finish_reason": "stop",
                ]
            ],
            "usage": [
                "prompt_tokens": 100,
                "completion_tokens": 50,
                "total_tokens": 150,
                "prompt_tokens_details": [
                    "cached_tokens": 80,
                    "cache_creation_input_tokens": 20,
                ],
                "completion_tokens_details": [
                    "reasoning_tokens": 10,
                ],
            ],
        ]

        let data = try jsonData(responseJSON)
        let fetch: FetchFunction = { request in
            FetchResponse(body: .data(data), urlResponse: self.httpResponse(url: request.url!))
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: .init(prompt: prompt))

        #expect(result.usage.inputTokens.total == 100)
        #expect(result.usage.inputTokens.cacheRead == 80)
        #expect(result.usage.inputTokens.cacheWrite == 20)
        #expect(result.usage.inputTokens.noCache == 0)
        #expect(result.usage.outputTokens.total == 50)
        #expect(result.usage.outputTokens.reasoning == 10)
        #expect(result.usage.outputTokens.text == 40)
    }

    @Test("doGenerate sends enable_thinking and thinking_budget")
    func doGenerateThinkingOptions() async throws {
        let capture = Capture()
        let responseJSON = [
            "id": "chatcmpl-1",
            "created": 1,
            "model": "qwen-plus",
            "choices": [
                [
                    "index": 0,
                    "message": ["role": "assistant", "content": "ok"],
                    "finish_reason": "stop",
                ]
            ],
        ] as [String: Any]

        let data = try jsonData(responseJSON)
        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(data), urlResponse: self.httpResponse(url: request.url!))
        }

        let model = makeModel(fetch: fetch)
        _ = try await model.doGenerate(options: .init(
            prompt: prompt,
            providerOptions: [
                "alibaba": [
                    "enableThinking": .bool(true),
                    "thinkingBudget": .number(2048),
                ]
            ]
        ))

        guard let request = await capture.first() else {
            Issue.record("Missing captured request")
            return
        }

        let body = try decodeRequestBody(request)
        guard case let .object(obj) = body else {
            Issue.record("Expected request object")
            return
        }

        #expect(obj["enable_thinking"] == .bool(true))
        #expect(obj["thinking_budget"] == .number(2048))
    }

    @Test("doStream streams text deltas and finish usage")
    func doStreamText() async throws {
        let capture = Capture()

        let chunk1: [String: Any] = [
            "id": "chatcmpl-stream-text",
            "created": 1,
            "model": "qwen-plus",
            "choices": [
                [
                    "index": 0,
                    "delta": ["role": "assistant", "content": NSNull()],
                    "finish_reason": NSNull(),
                ]
            ],
        ]
        let chunk2: [String: Any] = [
            "id": "chatcmpl-stream-text",
            "created": 1,
            "model": "qwen-plus",
            "choices": [
                [
                    "index": 0,
                    "delta": ["content": "Hello"],
                    "finish_reason": NSNull(),
                ]
            ],
        ]
        let chunk3: [String: Any] = [
            "id": "chatcmpl-stream-text",
            "created": 1,
            "model": "qwen-plus",
            "choices": [
                [
                    "index": 0,
                    "delta": ["content": " world"],
                    "finish_reason": NSNull(),
                ]
            ],
        ]
        let finish: [String: Any] = [
            "id": "chatcmpl-stream-text",
            "created": 1,
            "model": "qwen-plus",
            "choices": [
                [
                    "index": 0,
                    "delta": [:],
                    "finish_reason": "stop",
                ]
            ],
        ]
        let usage: [String: Any] = [
            "id": "chatcmpl-stream-text",
            "created": 1,
            "model": "qwen-plus",
            "choices": [],
            "usage": [
                "prompt_tokens": 3,
                "completion_tokens": 4,
                "total_tokens": 7,
                "prompt_tokens_details": ["cached_tokens": 0],
            ],
        ]

        let sseText = try sse(chunk1) + sse(chunk2) + sse(chunk3) + sse(finish) + sse(usage) + sseDone()
        let data = Data(sseText.utf8)

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(data), urlResponse: self.httpResponse(url: request.url!))
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doStream(options: .init(prompt: prompt))

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        #expect(parts.contains { if case .textStart = $0 { return true }; return false })
        let deltas = parts.compactMap { part -> String? in
            if case let .textDelta(_, delta, _) = part { return delta }
            return nil
        }
        #expect(deltas == ["Hello", " world"])

        let finishPart = parts.last { if case .finish = $0 { return true }; return false }
        guard case let .finish(finishReason, usage, _) = finishPart else {
            Issue.record("Missing finish part")
            return
        }
        #expect(finishReason.unified == .stop)
        #expect(usage.inputTokens.total == 3)
        #expect(usage.outputTokens.total == 4)
    }

    @Test("doStream streams tool calls")
    func doStreamToolCall() async throws {
        let chunk1: [String: Any] = [
            "id": "chatcmpl-stream-tool",
            "created": 1,
            "model": "qwen-plus",
            "choices": [
                [
                    "index": 0,
                    "delta": ["role": "assistant"],
                    "finish_reason": NSNull(),
                ]
            ],
        ]

        let toolStart: [String: Any] = [
            "id": "chatcmpl-stream-tool",
            "created": 1,
            "model": "qwen-plus",
            "choices": [
                [
                    "index": 0,
                    "delta": [
                        "tool_calls": [
                            [
                                "index": NSNull(),
                                "id": "call-1",
                                "type": "function",
                                "function": [
                                    "name": "get_weather",
                                    "arguments": "{",
                                ],
                            ],
                        ],
                    ],
                    "finish_reason": NSNull(),
                ]
            ],
        ]

        let toolContinue: [String: Any] = [
            "id": "chatcmpl-stream-tool",
            "created": 1,
            "model": "qwen-plus",
            "choices": [
                [
                    "index": 0,
                    "delta": [
                        "tool_calls": [
                            [
                                "index": 0,
                                "function": [
                                    "arguments": "\"location\":\"SF\"}",
                                ],
                            ],
                        ],
                    ],
                    "finish_reason": NSNull(),
                ]
            ],
        ]

        let finish: [String: Any] = [
            "id": "chatcmpl-stream-tool",
            "created": 1,
            "model": "qwen-plus",
            "choices": [
                [
                    "index": 0,
                    "delta": [:],
                    "finish_reason": "tool_calls",
                ]
            ],
        ]

        let usage: [String: Any] = [
            "id": "chatcmpl-stream-tool",
            "created": 1,
            "model": "qwen-plus",
            "choices": [],
            "usage": [
                "prompt_tokens": 1,
                "completion_tokens": 1,
                "total_tokens": 2,
                "prompt_tokens_details": ["cached_tokens": 0],
            ],
        ]

        let sseText = try sse(chunk1) + sse(toolStart) + sse(toolContinue) + sse(finish) + sse(usage) + sseDone()
        let data = Data(sseText.utf8)

        let fetch: FetchFunction = { request in
            FetchResponse(body: .data(data), urlResponse: self.httpResponse(url: request.url!))
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doStream(options: .init(prompt: prompt))

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        #expect(parts.contains { if case .toolInputStart = $0 { return true }; return false })
        #expect(parts.contains { if case .toolInputEnd = $0 { return true }; return false })

        let toolCalls = parts.compactMap { part -> LanguageModelV3ToolCall? in
            if case let .toolCall(value) = part { return value }
            return nil
        }

        #expect(toolCalls.count == 1)
        #expect(toolCalls[0].toolCallId == "call-1")
        #expect(toolCalls[0].toolName == "get_weather")
        #expect(toolCalls[0].input == "{\"location\":\"SF\"}")

        let finishPart = parts.last { if case .finish = $0 { return true }; return false }
        guard case let .finish(finishReason, _, _) = finishPart else {
            Issue.record("Missing finish part")
            return
        }
        #expect(finishReason.unified == .toolCalls)
    }

    @Test("doStream streams reasoning with generated reasoning id")
    func doStreamReasoning() async throws {
        let chunk1: [String: Any] = [
            "id": "chatcmpl-stream-reasoning",
            "created": 1,
            "model": "qwen-plus",
            "choices": [
                [
                    "index": 0,
                    "delta": ["role": "assistant", "reasoning_content": "Reason"],
                    "finish_reason": NSNull(),
                ]
            ],
        ]

        let chunk2: [String: Any] = [
            "id": "chatcmpl-stream-reasoning",
            "created": 1,
            "model": "qwen-plus",
            "choices": [
                [
                    "index": 0,
                    "delta": ["reasoning_content": "ing"],
                    "finish_reason": NSNull(),
                ]
            ],
        ]

        let finish: [String: Any] = [
            "id": "chatcmpl-stream-reasoning",
            "created": 1,
            "model": "qwen-plus",
            "choices": [
                [
                    "index": 0,
                    "delta": [:],
                    "finish_reason": "stop",
                ]
            ],
        ]

        let usage: [String: Any] = [
            "id": "chatcmpl-stream-reasoning",
            "created": 1,
            "model": "qwen-plus",
            "choices": [],
            "usage": [
                "prompt_tokens": 1,
                "completion_tokens": 2,
                "total_tokens": 3,
                "prompt_tokens_details": ["cached_tokens": 0],
                "completion_tokens_details": ["reasoning_tokens": 2],
            ],
        ]

        let sseText = try sse(chunk1) + sse(chunk2) + sse(finish) + sse(usage) + sseDone()
        let data = Data(sseText.utf8)

        let fetch: FetchFunction = { request in
            FetchResponse(body: .data(data), urlResponse: self.httpResponse(url: request.url!))
        }

        let model = makeModel(fetch: fetch, generateId: { "test-reasoning-id" })
        let result = try await model.doStream(options: .init(prompt: prompt))

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        let reasoningStarts = parts.compactMap { part -> String? in
            if case let .reasoningStart(id, _) = part { return id }
            return nil
        }
        #expect(reasoningStarts == ["test-reasoning-id"])

        let reasoningDeltas = parts.compactMap { part -> String? in
            if case let .reasoningDelta(_, delta, _) = part { return delta }
            return nil
        }
        #expect(reasoningDeltas == ["Reason", "ing"])
    }
}
