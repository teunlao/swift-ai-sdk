import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import OpenAIProvider

private let samplePrompt: LanguageModelV3Prompt = [
    .system(content: "You are helpful", providerOptions: nil),
    .user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)
]

@Suite("OpenAIChatLanguageModel")
struct OpenAIChatLanguageModelTests {
    @Test("doGenerate sends expected payload and maps response")
    func testDoGenerate() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "id": "chatcmpl-test",
            "created": 1_711_115_037,
            "model": "gpt-4o-mini",
            "choices": [
                [
                    "index": 0,
                    "message": [
                        "content": "Hello there!",
                        "tool_calls": [
                            [
                                "id": "call-1",
                                "type": "function",
                                "function": [
                                    "name": "get_weather",
                                    "arguments": "{\"location\":\"Berlin\"}"
                                ]
                            ]
                        ],
                        "annotations": [
                            [
                                "type": "url_citation",
                                "start_index": 0,
                                "end_index": 5,
                                "url": "https://example.com",
                                "title": "Example"
                            ]
                        ]
                    ],
                    "finish_reason": "stop",
                    "logprobs": [
                        "content": [
                            [
                                "token": "Hello",
                                "logprob": -0.01,
                                "top_logprobs": [["token": "Hello", "logprob": -0.01]]
                            ]
                        ]
                    ]
                ]
            ],
            "usage": [
                "prompt_tokens": 4,
                "completion_tokens": 6,
                "total_tokens": 10,
                "prompt_tokens_details": ["cached_tokens": 2],
                "completion_tokens_details": [
                    "reasoning_tokens": 1,
                    "accepted_prediction_tokens": 2,
                    "rejected_prediction_tokens": 0
                ]
            ]
        ]

        let mockData = try JSONSerialization.data(withJSONObject: responseJSON)

        let mockFetch: FetchFunction = { request in
            await capture.store(request)
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: [
                    "Content-Type": "application/json",
                    "x-request-id": "req-123"
                ]
            )!
            return FetchResponse(body: .data(mockData), urlResponse: httpResponse)
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch,
            _internal: .init(currentDate: { Date(timeIntervalSince1970: 0) })
        )

        let model = OpenAIChatLanguageModel(modelId: "gpt-4o-mini", config: config)

        let result = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                headers: ["Custom-Header": "request-header-value"]
            )
        )

        // Validate result content
        #expect(result.content.count >= 2)
        guard result.content.count >= 2 else { return }
        if case .text(let text) = result.content[0] {
            #expect(text.text == "Hello there!")
        } else {
            Issue.record("Expected text content")
        }

        let toolCallElements = result.content.compactMap { content -> LanguageModelV3ToolCall? in
            if case .toolCall(let call) = content { return call }
            return nil
        }
        #expect(toolCallElements.count == 1)
        #expect(toolCallElements.first?.toolCallId == "call-1")
        #expect(toolCallElements.first?.toolName == "get_weather")
        #expect(toolCallElements.first?.input == "{\"location\":\"Berlin\"}")

        let sourceElements = result.content.compactMap { content -> LanguageModelV3Source? in
            if case .source(let source) = content { return source }
            return nil
        }
        #expect(sourceElements.count == 1)

        #expect(result.finishReason == .stop)
        #expect(result.usage.inputTokens == 4)
        #expect(result.usage.outputTokens == 6)
        #expect(result.usage.totalTokens == 10)
        #expect(result.usage.reasoningTokens == 1)
        #expect(result.usage.cachedInputTokens == 2)

        if let metadata = result.providerMetadata?["openai"] {
            #expect(metadata["acceptedPredictionTokens"] == .number(2))
            #expect(metadata["logprobs"] != nil)
        } else {
            Issue.record("Missing provider metadata")
        }

        // Validate request
        guard let request = await capture.value(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Missing request data")
            return
        }

        let headers = request.allHTTPHeaderFields ?? [:]
        let normalizedHeaders = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
        #expect(normalizedHeaders["authorization"] == "Bearer test-key")
        #expect(normalizedHeaders["custom-header"] == "request-header-value")
        #expect(normalizedHeaders["content-type"] == "application/json")

        #expect(json["model"] as? String == "gpt-4o-mini")
        if let messages = json["messages"] as? [[String: Any]] {
            #expect(messages.count == 2)
            #expect(messages.first?["role"] as? String == "system")
        } else {
            Issue.record("messages missing from body")
        }
    }

    // MARK: - Batch 1: Settings & Configuration

    @Test("Pass provider settings (logitBias, user, parallelToolCalls)")
    func testPassSettings() async throws {
        final class RequestCapture: @unchecked Sendable {
            var body: [String: Any]?
        }

        let capture = RequestCapture()
        let mockData = try JSONSerialization.data(withJSONObject: [
            "id": "test", "created": 1, "model": "gpt-3.5-turbo",
            "choices": [["index": 0, "message": ["content": "ok"], "finish_reason": "stop"]],
            "usage": ["prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2]
        ])

        let mockFetch: FetchFunction = { request in
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                capture.body = json
            }
            let httpResponse = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return FetchResponse(body: .data(mockData), urlResponse: httpResponse)
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch
        )

        let model = OpenAIChatLanguageModel(modelId: "gpt-3.5-turbo", config: config)

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                providerOptions: [
                    "openai": [
                        "logitBias": JSONValue.object(["50256": JSONValue.number(-100)]),
                        "parallelToolCalls": JSONValue.bool(false),
                        "user": JSONValue.string("test-user-id")
                    ]
                ]
            )
        )

        guard let body = capture.body else {
            Issue.record("Request body not captured")
            return
        }

        #expect(body["model"] as? String == "gpt-3.5-turbo")
        #expect(body["user"] as? String == "test-user-id")
        #expect(body["parallel_tool_calls"] as? Bool == false)

        if let logitBias = body["logit_bias"] as? [String: Any] {
            #expect(logitBias["50256"] as? Int == -100)
        } else {
            Issue.record("logit_bias missing")
        }
    }

    @Test("Pass reasoningEffort from provider metadata")
    func testReasoningEffortFromMetadata() async throws {
        final class RequestCapture: @unchecked Sendable {
            var body: [String: Any]?
        }

        let capture = RequestCapture()
        let mockData = try JSONSerialization.data(withJSONObject: [
            "id": "test", "created": 1, "model": "o1-mini",
            "choices": [["index": 0, "message": ["content": "ok"], "finish_reason": "stop"]],
            "usage": ["prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2]
        ])

        let mockFetch: FetchFunction = { request in
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                capture.body = json
            }
            return FetchResponse(
                body: .data(mockData),
                urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"])!
            )
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch
        )

        let model = OpenAIChatLanguageModel(modelId: "o1-mini", config: config)

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: [.user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)],
                providerOptions: ["openai": ["reasoningEffort": JSONValue.string("low")]]
            )
        )

        guard let body = capture.body else {
            Issue.record("Request body not captured")
            return
        }

        #expect(body["model"] as? String == "o1-mini")
        #expect(body["reasoning_effort"] as? String == "low")
    }

    @Test("Pass reasoningEffort from settings")
    func testReasoningEffortFromSettings() async throws {
        final class RequestCapture: @unchecked Sendable {
            var body: [String: Any]?
        }

        let capture = RequestCapture()
        let mockData = try JSONSerialization.data(withJSONObject: [
            "id": "test", "created": 1, "model": "o1-mini",
            "choices": [["index": 0, "message": ["content": "ok"], "finish_reason": "stop"]],
            "usage": ["prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2]
        ])

        let mockFetch: FetchFunction = { request in
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                capture.body = json
            }
            return FetchResponse(
                body: .data(mockData),
                urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"])!
            )
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch
        )

        let model = OpenAIChatLanguageModel(modelId: "o1-mini", config: config)

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: [.user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)],
                providerOptions: ["openai": ["reasoningEffort": JSONValue.string("high")]]
            )
        )

        guard let body = capture.body else {
            Issue.record("Request body not captured")
            return
        }

        #expect(body["model"] as? String == "o1-mini")
        #expect(body["reasoning_effort"] as? String == "high")
    }

    @Test("Pass textVerbosity setting")
    func testTextVerbosity() async throws {
        final class RequestCapture: @unchecked Sendable {
            var body: [String: Any]?
        }

        let capture = RequestCapture()
        let mockData = try JSONSerialization.data(withJSONObject: [
            "id": "test", "created": 1, "model": "gpt-4o-2024-11-20",
            "choices": [["index": 0, "message": ["content": "ok"], "finish_reason": "stop"]],
            "usage": ["prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2]
        ])

        let mockFetch: FetchFunction = { request in
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                capture.body = json
            }
            return FetchResponse(
                body: .data(mockData),
                urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"])!
            )
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch
        )

        let model = OpenAIChatLanguageModel(modelId: "gpt-4o-2024-11-20", config: config)

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: [.user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)],
                providerOptions: ["openai": ["textVerbosity": JSONValue.string("low")]]
            )
        )

        guard let body = capture.body else {
            Issue.record("Request body not captured")
            return
        }

        #expect(body["model"] as? String == "gpt-4o-2024-11-20")
        #expect(body["verbosity"] as? String == "low")
    }

    @Test("Pass custom headers to request")
    func testCustomHeaders() async throws {
        final class RequestCapture: @unchecked Sendable {
            var headers: [String: String]?
        }

        let capture = RequestCapture()
        let mockData = try JSONSerialization.data(withJSONObject: [
            "id": "test", "created": 1, "model": "gpt-4o-mini",
            "choices": [["index": 0, "message": ["content": "ok"], "finish_reason": "stop"]],
            "usage": ["prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2]
        ])

        let mockFetch: FetchFunction = { request in
            capture.headers = request.allHTTPHeaderFields ?? [:]
            return FetchResponse(
                body: .data(mockData),
                urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"])!
            )
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch
        )

        let model = OpenAIChatLanguageModel(modelId: "gpt-4o-mini", config: config)

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: samplePrompt,
                headers: ["X-Custom-Header": "custom-value", "X-Test-Id": "123"]
            )
        )

        guard let headers = capture.headers else {
            Issue.record("Headers not captured")
            return
        }

        let normalized = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
        #expect(normalized["authorization"] == "Bearer test-key")
        #expect(normalized["x-custom-header"] == "custom-value")
        #expect(normalized["x-test-id"] == "123")
    }

    // MARK: - Batch 2: Response Format

    @Test("Should not send response_format when text")
    func testResponseFormatText() async throws {
        final class RequestCapture: @unchecked Sendable {
            var body: [String: Any]?
        }

        let capture = RequestCapture()
        let mockData = try JSONSerialization.data(withJSONObject: [
            "id": "test", "created": 1, "model": "gpt-4o-2024-08-06",
            "choices": [["index": 0, "message": ["content": "{\"value\":\"Spark\"}"], "finish_reason": "stop"]],
            "usage": ["prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2]
        ])

        let mockFetch: FetchFunction = { request in
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                capture.body = json
            }
            return FetchResponse(
                body: .data(mockData),
                urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"])!
            )
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch
        )

        let model = OpenAIChatLanguageModel(modelId: "gpt-4o-2024-08-06", config: config)

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: [.user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)],
                responseFormat: LanguageModelV3ResponseFormat.text
            )
        )

        guard let body = capture.body else {
            Issue.record("Request body not captured")
            return
        }

        #expect(body["model"] as? String == "gpt-4o-2024-08-06")
        #expect(body["response_format"] == nil)
    }

    @Test("Forward json response format as json_object without schema")
    func testResponseFormatJsonObject() async throws {
        final class RequestCapture: @unchecked Sendable {
            var body: [String: Any]?
        }

        let capture = RequestCapture()
        let mockData = try JSONSerialization.data(withJSONObject: [
            "id": "test", "created": 1, "model": "gpt-4o-2024-08-06",
            "choices": [["index": 0, "message": ["content": "{\"value\":\"Spark\"}"], "finish_reason": "stop"]],
            "usage": ["prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2]
        ])

        let mockFetch: FetchFunction = { request in
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                capture.body = json
            }
            return FetchResponse(
                body: .data(mockData),
                urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"])!
            )
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch
        )

        let model = OpenAIChatLanguageModel(modelId: "gpt-4o-2024-08-06", config: config)

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: [.user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)],
                responseFormat: LanguageModelV3ResponseFormat.json(schema: nil, name: nil, description: nil)
            )
        )

        guard let body = capture.body else {
            Issue.record("Request body not captured")
            return
        }

        #expect(body["model"] as? String == "gpt-4o-2024-08-06")
        if let responseFormat = body["response_format"] as? [String: Any] {
            #expect(responseFormat["type"] as? String == "json_object")
        } else {
            Issue.record("response_format missing")
        }
    }

    @Test("Forward json format and omit schema when structuredOutputs disabled")
    func testResponseFormatJsonStructuredOutputsDisabled() async throws {
        final class RequestCapture: @unchecked Sendable {
            var body: [String: Any]?
        }

        let capture = RequestCapture()
        let mockData = try JSONSerialization.data(withJSONObject: [
            "id": "test", "created": 1, "model": "gpt-4o-2024-08-06",
            "choices": [["index": 0, "message": ["content": "{\"value\":\"Spark\"}"], "finish_reason": "stop"]],
            "usage": ["prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2]
        ])

        let mockFetch: FetchFunction = { request in
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                capture.body = json
            }
            return FetchResponse(
                body: .data(mockData),
                urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"])!
            )
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch
        )

        let model = OpenAIChatLanguageModel(modelId: "gpt-4o-2024-08-06", config: config)

        let schema = JSONValue.object([
            "type": .string("object"),
            "properties": .object(["value": .object(["type": .string("string")])]),
            "required": .array([.string("value")]),
            "additionalProperties": .bool(false),
            "$schema": .string("http://json-schema.org/draft-07/schema#")
        ])

        let result = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: [.user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)],
                responseFormat: LanguageModelV3ResponseFormat.json(schema: schema, name: nil, description: nil),
                providerOptions: ["openai": ["structuredOutputs": .bool(false)]]
            )
        )

        guard let body = capture.body else {
            Issue.record("Request body not captured")
            return
        }

        #expect(body["model"] as? String == "gpt-4o-2024-08-06")
        if let responseFormat = body["response_format"] as? [String: Any] {
            #expect(responseFormat["type"] as? String == "json_object")
            #expect(responseFormat["json_schema"] == nil)
        } else {
            Issue.record("response_format missing")
        }

        // Check for warning
        #expect(result.warnings.count == 1)
        if case .unsupportedSetting(let setting, _) = result.warnings.first {
            #expect(setting == "responseFormat")
        } else {
            Issue.record("Expected unsupported-setting warning")
        }
    }

    @Test("Include schema when structuredOutputs enabled")
    func testResponseFormatJsonStructuredOutputsEnabled() async throws {
        final class RequestCapture: @unchecked Sendable {
            var body: [String: Any]?
        }

        let capture = RequestCapture()
        let mockData = try JSONSerialization.data(withJSONObject: [
            "id": "test", "created": 1, "model": "gpt-4o-2024-08-06",
            "choices": [["index": 0, "message": ["content": "{\"value\":\"Spark\"}"], "finish_reason": "stop"]],
            "usage": ["prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2]
        ])

        let mockFetch: FetchFunction = { request in
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                capture.body = json
            }
            return FetchResponse(
                body: .data(mockData),
                urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"])!
            )
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch
        )

        let model = OpenAIChatLanguageModel(modelId: "gpt-4o-2024-08-06", config: config)

        let schema = JSONValue.object([
            "type": .string("object"),
            "properties": .object(["value": .object(["type": .string("string")])]),
            "required": .array([.string("value")]),
            "additionalProperties": .bool(false),
            "$schema": .string("http://json-schema.org/draft-07/schema#")
        ])

        let result = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: [.user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)],
                responseFormat: LanguageModelV3ResponseFormat.json(schema: schema, name: nil, description: nil)
            )
        )

        guard let body = capture.body else {
            Issue.record("Request body not captured")
            return
        }

        #expect(body["model"] as? String == "gpt-4o-2024-08-06")
        if let responseFormat = body["response_format"] as? [String: Any] {
            #expect(responseFormat["type"] as? String == "json_schema")
            if let jsonSchema = responseFormat["json_schema"] as? [String: Any] {
                #expect(jsonSchema["name"] as? String == "response")
                #expect(jsonSchema["strict"] as? Bool == false)
                #expect(jsonSchema["schema"] != nil)
            } else {
                Issue.record("json_schema missing")
            }
        } else {
            Issue.record("response_format missing")
        }

        // No warnings expected
        #expect(result.warnings.isEmpty)
    }

    @Test("Use json_schema and strict with responseFormat json")
    func testResponseFormatJsonSchemaStrict() async throws {
        final class RequestCapture: @unchecked Sendable {
            var body: [String: Any]?
        }

        let capture = RequestCapture()
        let mockData = try JSONSerialization.data(withJSONObject: [
            "id": "test", "created": 1, "model": "gpt-4o-2024-08-06",
            "choices": [["index": 0, "message": ["content": "{\"value\":\"Spark\"}"], "finish_reason": "stop"]],
            "usage": ["prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2]
        ])

        let mockFetch: FetchFunction = { request in
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                capture.body = json
            }
            return FetchResponse(
                body: .data(mockData),
                urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"])!
            )
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch
        )

        let model = OpenAIChatLanguageModel(modelId: "gpt-4o-2024-08-06", config: config)

        let schema = JSONValue.object([
            "type": .string("object"),
            "properties": .object(["value": .object(["type": .string("string")])]),
            "required": .array([.string("value")]),
            "additionalProperties": .bool(false),
            "$schema": .string("http://json-schema.org/draft-07/schema#")
        ])

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: [.user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)],
                responseFormat: LanguageModelV3ResponseFormat.json(schema: schema, name: nil, description: nil)
            )
        )

        guard let body = capture.body else {
            Issue.record("Request body not captured")
            return
        }

        #expect(body["model"] as? String == "gpt-4o-2024-08-06")
        if let responseFormat = body["response_format"] as? [String: Any] {
            #expect(responseFormat["type"] as? String == "json_schema")
            if let jsonSchema = responseFormat["json_schema"] as? [String: Any] {
                #expect(jsonSchema["name"] as? String == "response")
                #expect(jsonSchema["strict"] as? Bool == false)
            } else {
                Issue.record("json_schema missing")
            }
        } else {
            Issue.record("response_format missing")
        }
    }

    @Test("Set name and description with responseFormat json")
    func testResponseFormatJsonWithNameDescription() async throws {
        final class RequestCapture: @unchecked Sendable {
            var body: [String: Any]?
        }

        let capture = RequestCapture()
        let mockData = try JSONSerialization.data(withJSONObject: [
            "id": "test", "created": 1, "model": "gpt-4o-2024-08-06",
            "choices": [["index": 0, "message": ["content": "{\"value\":\"Spark\"}"], "finish_reason": "stop"]],
            "usage": ["prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2]
        ])

        let mockFetch: FetchFunction = { request in
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                capture.body = json
            }
            return FetchResponse(
                body: .data(mockData),
                urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"])!
            )
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch
        )

        let model = OpenAIChatLanguageModel(modelId: "gpt-4o-2024-08-06", config: config)

        let schema = JSONValue.object([
            "type": .string("object"),
            "properties": .object(["value": .object(["type": .string("string")])]),
            "required": .array([.string("value")]),
            "additionalProperties": .bool(false),
            "$schema": .string("http://json-schema.org/draft-07/schema#")
        ])

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: [.user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)],
                responseFormat: LanguageModelV3ResponseFormat.json(
                    schema: schema,
                    name: "test-name",
                    description: "test description"
                )
            )
        )

        guard let body = capture.body else {
            Issue.record("Request body not captured")
            return
        }

        #expect(body["model"] as? String == "gpt-4o-2024-08-06")
        if let responseFormat = body["response_format"] as? [String: Any] {
            #expect(responseFormat["type"] as? String == "json_schema")
            if let jsonSchema = responseFormat["json_schema"] as? [String: Any] {
                #expect(jsonSchema["name"] as? String == "test-name")
                #expect(jsonSchema["description"] as? String == "test description")
                #expect(jsonSchema["strict"] as? Bool == false)
            } else {
                Issue.record("json_schema missing")
            }
        } else {
            Issue.record("response_format missing")
        }
    }

    @Test("Allow undefined schema with responseFormat json")
    func testResponseFormatJsonUndefinedSchema() async throws {
        final class RequestCapture: @unchecked Sendable {
            var body: [String: Any]?
        }

        let capture = RequestCapture()
        let mockData = try JSONSerialization.data(withJSONObject: [
            "id": "test", "created": 1, "model": "gpt-4o-2024-08-06",
            "choices": [["index": 0, "message": ["content": "{\"value\":\"Spark\"}"], "finish_reason": "stop"]],
            "usage": ["prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2]
        ])

        let mockFetch: FetchFunction = { request in
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                capture.body = json
            }
            return FetchResponse(
                body: .data(mockData),
                urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"])!
            )
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch
        )

        let model = OpenAIChatLanguageModel(modelId: "gpt-4o-2024-08-06", config: config)

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: [.user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)],
                responseFormat: LanguageModelV3ResponseFormat.json(
                    schema: nil,
                    name: "test-name",
                    description: "test description"
                )
            )
        )

        guard let body = capture.body else {
            Issue.record("Request body not captured")
            return
        }

        #expect(body["model"] as? String == "gpt-4o-2024-08-06")
        if let responseFormat = body["response_format"] as? [String: Any] {
            #expect(responseFormat["type"] as? String == "json_object")
        } else {
            Issue.record("response_format missing")
        }
    }

    // MARK: - Batch 3: O1/O3 Model-Specific

    @Test("Clear temperature, topP, frequencyPenalty, presencePenalty and return warnings for o1")
    func testClearTemperatureForO1Preview() async throws {
        final class RequestCapture: @unchecked Sendable {
            var body: [String: Any]?
        }

        let capture = RequestCapture()
        let mockData = try JSONSerialization.data(withJSONObject: [
            "id": "test", "created": 1, "model": "o1-preview",
            "choices": [["index": 0, "message": ["content": "ok"], "finish_reason": "stop"]],
            "usage": ["prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2]
        ])

        let mockFetch: FetchFunction = { request in
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                capture.body = json
            }
            return FetchResponse(
                body: .data(mockData),
                urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"])!
            )
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch
        )

        let model = OpenAIChatLanguageModel(modelId: "o1-preview", config: config)

        let result = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: [.user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)],
                temperature: 0.5,
                topP: 0.7,
                presencePenalty: 0.3,
                frequencyPenalty: 0.2
            )
        )

        guard let body = capture.body else {
            Issue.record("Request body not captured")
            return
        }

        #expect(body["model"] as? String == "o1-preview")
        #expect(body["temperature"] == nil)
        #expect(body["top_p"] == nil)
        #expect(body["frequency_penalty"] == nil)
        #expect(body["presence_penalty"] == nil)

        // Check warnings
        #expect(result.warnings.count == 4)
        let warningSettings = result.warnings.compactMap { warning -> String? in
            if case .unsupportedSetting(let setting, _) = warning {
                return setting
            }
            return nil
        }
        #expect(warningSettings.contains("temperature"))
        #expect(warningSettings.contains("topP"))
        #expect(warningSettings.contains("frequencyPenalty"))
        #expect(warningSettings.contains("presencePenalty"))
    }

    @Test("Convert maxOutputTokens to max_completion_tokens for o1")
    func testConvertMaxOutputTokensForO1Preview() async throws {
        final class RequestCapture: @unchecked Sendable {
            var body: [String: Any]?
        }

        let capture = RequestCapture()
        let mockData = try JSONSerialization.data(withJSONObject: [
            "id": "test", "created": 1, "model": "o1-preview",
            "choices": [["index": 0, "message": ["content": "ok"], "finish_reason": "stop"]],
            "usage": ["prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2]
        ])

        let mockFetch: FetchFunction = { request in
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                capture.body = json
            }
            return FetchResponse(
                body: .data(mockData),
                urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"])!
            )
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch
        )

        let model = OpenAIChatLanguageModel(modelId: "o1-preview", config: config)

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: [.user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)],
                maxOutputTokens: 1000
            )
        )

        guard let body = capture.body else {
            Issue.record("Request body not captured")
            return
        }

        #expect(body["model"] as? String == "o1-preview")
        #expect(body["max_completion_tokens"] as? Int == 1000)
    }

    @Test("Remove system messages for o1-preview and add warning")
    func testRemoveSystemMessagesForO1Preview() async throws {
        final class RequestCapture: @unchecked Sendable {
            var body: [String: Any]?
        }

        let capture = RequestCapture()
        let mockData = try JSONSerialization.data(withJSONObject: [
            "id": "test", "created": 1, "model": "o1-preview",
            "choices": [["index": 0, "message": ["content": "ok"], "finish_reason": "stop"]],
            "usage": ["prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2]
        ])

        let mockFetch: FetchFunction = { request in
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                capture.body = json
            }
            return FetchResponse(
                body: .data(mockData),
                urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"])!
            )
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch
        )

        let model = OpenAIChatLanguageModel(modelId: "o1-preview", config: config)

        let result = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: [
                    .system(content: "You are a helpful assistant", providerOptions: nil),
                    .user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)
                ]
            )
        )

        guard let body = capture.body else {
            Issue.record("Request body not captured")
            return
        }

        #expect(body["model"] as? String == "o1-preview")
        if let messages = body["messages"] as? [[String: Any]] {
            #expect(messages.count == 1)
            #expect(messages.first?["role"] as? String == "user")
        } else {
            Issue.record("messages missing")
        }

        // Check warning
        #expect(result.warnings.count == 1)
        if case .other(let message) = result.warnings.first {
            #expect(message == "system messages are removed for this model")
        } else {
            Issue.record("Expected 'other' warning about system messages")
        }
    }

    @Test("Use developer messages for o1")
    func testUseDeveloperMessagesForO1() async throws {
        final class RequestCapture: @unchecked Sendable {
            var body: [String: Any]?
        }

        let capture = RequestCapture()
        let mockData = try JSONSerialization.data(withJSONObject: [
            "id": "test", "created": 1, "model": "o1",
            "choices": [["index": 0, "message": ["content": "ok"], "finish_reason": "stop"]],
            "usage": ["prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2]
        ])

        let mockFetch: FetchFunction = { request in
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                capture.body = json
            }
            return FetchResponse(
                body: .data(mockData),
                urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"])!
            )
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch
        )

        let model = OpenAIChatLanguageModel(modelId: "o1", config: config)

        let result = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: [
                    .system(content: "You are a helpful assistant", providerOptions: nil),
                    .user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)
                ]
            )
        )

        guard let body = capture.body else {
            Issue.record("Request body not captured")
            return
        }

        #expect(body["model"] as? String == "o1")
        if let messages = body["messages"] as? [[String: Any]] {
            #expect(messages.count == 2)
            #expect(messages[0]["role"] as? String == "developer")
            #expect(messages[0]["content"] as? String == "You are a helpful assistant")
            #expect(messages[1]["role"] as? String == "user")
        } else {
            Issue.record("messages missing")
        }

        // No warnings expected
        #expect(result.warnings.isEmpty)
    }

    @Test("Return reasoning tokens in provider metadata")
    func testReturnReasoningTokens() async throws {
        let mockData = try JSONSerialization.data(withJSONObject: [
            "id": "test", "created": 1, "model": "o1-preview",
            "choices": [["index": 0, "message": ["content": "ok"], "finish_reason": "stop"]],
            "usage": [
                "prompt_tokens": 15,
                "completion_tokens": 20,
                "total_tokens": 35,
                "completion_tokens_details": [
                    "reasoning_tokens": 10
                ]
            ]
        ])

        let mockFetch: FetchFunction = { request in
            return FetchResponse(
                body: .data(mockData),
                urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"])!
            )
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch
        )

        let model = OpenAIChatLanguageModel(modelId: "o1-preview", config: config)

        let result = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: [.user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)]
            )
        )

        #expect(result.usage.inputTokens == 15)
        #expect(result.usage.outputTokens == 20)
        #expect(result.usage.totalTokens == 35)
        #expect(result.usage.reasoningTokens == 10)
    }

    // MARK: - Batch 4: Extension Settings

    @Test("Send max_completion_tokens extension setting")
    func testMaxCompletionTokensExtension() async throws {
        final class RequestCapture: @unchecked Sendable {
            var body: [String: Any]?
        }

        let capture = RequestCapture()
        let mockData = try JSONSerialization.data(withJSONObject: [
            "id": "test", "created": 1, "model": "o1-preview",
            "choices": [["index": 0, "message": ["content": "ok"], "finish_reason": "stop"]],
            "usage": ["prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2]
        ])

        let mockFetch: FetchFunction = { request in
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                capture.body = json
            }
            return FetchResponse(
                body: .data(mockData),
                urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"])!
            )
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch
        )

        let model = OpenAIChatLanguageModel(modelId: "o1-preview", config: config)

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: [.user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)],
                providerOptions: ["openai": ["maxCompletionTokens": JSONValue.number(255)]]
            )
        )

        guard let body = capture.body else {
            Issue.record("Request body not captured")
            return
        }

        #expect(body["model"] as? String == "o1-preview")
        #expect(body["max_completion_tokens"] as? Int == 255)
    }

    @Test("Send prediction extension setting")
    func testPredictionExtension() async throws {
        final class RequestCapture: @unchecked Sendable {
            var body: [String: Any]?
        }

        let capture = RequestCapture()
        let mockData = try JSONSerialization.data(withJSONObject: [
            "id": "test", "created": 1, "model": "gpt-3.5-turbo",
            "choices": [["index": 0, "message": ["content": "ok"], "finish_reason": "stop"]],
            "usage": ["prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2]
        ])

        let mockFetch: FetchFunction = { request in
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                capture.body = json
            }
            return FetchResponse(
                body: .data(mockData),
                urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"])!
            )
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch
        )

        let model = OpenAIChatLanguageModel(modelId: "gpt-3.5-turbo", config: config)

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: [.user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)],
                providerOptions: ["openai": [
                    "prediction": JSONValue.object([
                        "type": .string("content"),
                        "content": .string("Hello, World!")
                    ])
                ]]
            )
        )

        guard let body = capture.body else {
            Issue.record("Request body not captured")
            return
        }

        #expect(body["model"] as? String == "gpt-3.5-turbo")
        if let prediction = body["prediction"] as? [String: Any] {
            #expect(prediction["type"] as? String == "content")
            #expect(prediction["content"] as? String == "Hello, World!")
        } else {
            Issue.record("prediction missing")
        }
    }

    @Test("Send store extension setting")
    func testStoreExtension() async throws {
        final class RequestCapture: @unchecked Sendable {
            var body: [String: Any]?
        }

        let capture = RequestCapture()
        let mockData = try JSONSerialization.data(withJSONObject: [
            "id": "test", "created": 1, "model": "gpt-3.5-turbo",
            "choices": [["index": 0, "message": ["content": "ok"], "finish_reason": "stop"]],
            "usage": ["prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2]
        ])

        let mockFetch: FetchFunction = { request in
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                capture.body = json
            }
            return FetchResponse(
                body: .data(mockData),
                urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"])!
            )
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch
        )

        let model = OpenAIChatLanguageModel(modelId: "gpt-3.5-turbo", config: config)

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: [.user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)],
                providerOptions: ["openai": ["store": JSONValue.bool(true)]]
            )
        )

        guard let body = capture.body else {
            Issue.record("Request body not captured")
            return
        }

        #expect(body["model"] as? String == "gpt-3.5-turbo")
        #expect(body["store"] as? Bool == true)
    }

    @Test("Send metadata extension values")
    func testMetadataExtension() async throws {
        final class RequestCapture: @unchecked Sendable {
            var body: [String: Any]?
        }

        let capture = RequestCapture()
        let mockData = try JSONSerialization.data(withJSONObject: [
            "id": "test", "created": 1, "model": "gpt-3.5-turbo",
            "choices": [["index": 0, "message": ["content": "ok"], "finish_reason": "stop"]],
            "usage": ["prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2]
        ])

        let mockFetch: FetchFunction = { request in
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                capture.body = json
            }
            return FetchResponse(
                body: .data(mockData),
                urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"])!
            )
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch
        )

        let model = OpenAIChatLanguageModel(modelId: "gpt-3.5-turbo", config: config)

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: [.user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)],
                providerOptions: ["openai": [
                    "metadata": JSONValue.object(["custom": .string("value")])
                ]]
            )
        )

        guard let body = capture.body else {
            Issue.record("Request body not captured")
            return
        }

        #expect(body["model"] as? String == "gpt-3.5-turbo")
        if let metadata = body["metadata"] as? [String: Any] {
            #expect(metadata["custom"] as? String == "value")
        } else {
            Issue.record("metadata missing")
        }
    }

    @Test("Send promptCacheKey extension value")
    func testPromptCacheKeyExtension() async throws {
        final class RequestCapture: @unchecked Sendable {
            var body: [String: Any]?
        }

        let capture = RequestCapture()
        let mockData = try JSONSerialization.data(withJSONObject: [
            "id": "test", "created": 1, "model": "gpt-3.5-turbo",
            "choices": [["index": 0, "message": ["content": "ok"], "finish_reason": "stop"]],
            "usage": ["prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2]
        ])

        let mockFetch: FetchFunction = { request in
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                capture.body = json
            }
            return FetchResponse(
                body: .data(mockData),
                urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"])!
            )
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch
        )

        let model = OpenAIChatLanguageModel(modelId: "gpt-3.5-turbo", config: config)

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: [.user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)],
                providerOptions: ["openai": ["promptCacheKey": JSONValue.string("test-cache-key-123")]]
            )
        )

        guard let body = capture.body else {
            Issue.record("Request body not captured")
            return
        }

        #expect(body["model"] as? String == "gpt-3.5-turbo")
        #expect(body["prompt_cache_key"] as? String == "test-cache-key-123")
    }

    @Test("Send safetyIdentifier extension value")
    func testSafetyIdentifierExtension() async throws {
        final class RequestCapture: @unchecked Sendable {
            var body: [String: Any]?
        }

        let capture = RequestCapture()
        let mockData = try JSONSerialization.data(withJSONObject: [
            "id": "test", "created": 1, "model": "gpt-3.5-turbo",
            "choices": [["index": 0, "message": ["content": "ok"], "finish_reason": "stop"]],
            "usage": ["prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2]
        ])

        let mockFetch: FetchFunction = { request in
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                capture.body = json
            }
            return FetchResponse(
                body: .data(mockData),
                urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"])!
            )
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch
        )

        let model = OpenAIChatLanguageModel(modelId: "gpt-3.5-turbo", config: config)

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: [.user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)],
                providerOptions: ["openai": ["safetyIdentifier": JSONValue.string("test-safety-identifier-123")]]
            )
        )

        guard let body = capture.body else {
            Issue.record("Request body not captured")
            return
        }

        #expect(body["model"] as? String == "gpt-3.5-turbo")
        #expect(body["safety_identifier"] as? String == "test-safety-identifier-123")
    }

    // MARK: - Batch 5: Search Models (3 tests)

    @Test("Remove temperature for gpt-4o-search-preview with warning")
    func testRemoveTemperatureForGpt4oSearchPreview() async throws {
        final class RequestCapture: @unchecked Sendable {
            var body: [String: Any]?
        }

        let capture = RequestCapture()
        let mockData = try JSONSerialization.data(withJSONObject: [
            "id": "test", "created": 1, "model": "gpt-4o-search-preview",
            "choices": [["index": 0, "message": ["content": "ok"], "finish_reason": "stop"]],
            "usage": ["prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2]
        ])

        let mockFetch: FetchFunction = { request in
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                capture.body = json
            }
            return FetchResponse(
                body: .data(mockData),
                urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"])!
            )
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch
        )

        let model = OpenAIChatLanguageModel(modelId: "gpt-4o-search-preview", config: config)

        let result = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: [.user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)],
                temperature: 0.7
            )
        )

        guard let body = capture.body else {
            Issue.record("Request body not captured")
            return
        }

        #expect(body["model"] as? String == "gpt-4o-search-preview")
        #expect(body["temperature"] == nil)
        #expect(result.warnings.count == 1)
        if case .unsupportedSetting(let setting, let details) = result.warnings.first {
            #expect(setting == "temperature")
            #expect(details == "temperature is not supported for the search preview models and has been removed.")
        } else {
            Issue.record("Expected unsupported-setting warning for temperature")
        }
    }

    @Test("Remove temperature for gpt-4o-mini-search-preview with warning")
    func testRemoveTemperatureForGpt4oMiniSearchPreview() async throws {
        final class RequestCapture: @unchecked Sendable {
            var body: [String: Any]?
        }

        let capture = RequestCapture()
        let mockData = try JSONSerialization.data(withJSONObject: [
            "id": "test", "created": 1, "model": "gpt-4o-mini-search-preview",
            "choices": [["index": 0, "message": ["content": "ok"], "finish_reason": "stop"]],
            "usage": ["prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2]
        ])

        let mockFetch: FetchFunction = { request in
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                capture.body = json
            }
            return FetchResponse(
                body: .data(mockData),
                urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"])!
            )
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch
        )

        let model = OpenAIChatLanguageModel(modelId: "gpt-4o-mini-search-preview", config: config)

        let result = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: [.user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)],
                temperature: 0.7
            )
        )

        guard let body = capture.body else {
            Issue.record("Request body not captured")
            return
        }

        #expect(body["model"] as? String == "gpt-4o-mini-search-preview")
        #expect(body["temperature"] == nil)
        #expect(result.warnings.count == 1)
        if case .unsupportedSetting(let setting, let details) = result.warnings.first {
            #expect(setting == "temperature")
            #expect(details == "temperature is not supported for the search preview models and has been removed.")
        } else {
            Issue.record("Expected unsupported-setting warning for temperature")
        }
    }

    @Test("Remove temperature for gpt-4o-mini-search-preview-2025-03-11 with warning")
    func testRemoveTemperatureForGpt4oMiniSearchPreview20250311() async throws {
        final class RequestCapture: @unchecked Sendable {
            var body: [String: Any]?
        }

        let capture = RequestCapture()
        let mockData = try JSONSerialization.data(withJSONObject: [
            "id": "test", "created": 1, "model": "gpt-4o-mini-search-preview-2025-03-11",
            "choices": [["index": 0, "message": ["content": "ok"], "finish_reason": "stop"]],
            "usage": ["prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2]
        ])

        let mockFetch: FetchFunction = { request in
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                capture.body = json
            }
            return FetchResponse(
                body: .data(mockData),
                urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"])!
            )
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch
        )

        let model = OpenAIChatLanguageModel(modelId: "gpt-4o-mini-search-preview-2025-03-11", config: config)

        let result = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: [.user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)],
                temperature: 0.7
            )
        )

        guard let body = capture.body else {
            Issue.record("Request body not captured")
            return
        }

        #expect(body["model"] as? String == "gpt-4o-mini-search-preview-2025-03-11")
        #expect(body["temperature"] == nil)
        #expect(result.warnings.count == 1)
        if case .unsupportedSetting(let setting, let details) = result.warnings.first {
            #expect(setting == "temperature")
            #expect(details == "temperature is not supported for the search preview models and has been removed.")
        } else {
            Issue.record("Expected unsupported-setting warning for temperature")
        }
    }

    // MARK: - Batch 6: Service Tier Processing (6 tests)

    @Test("Send serviceTier flex processing setting")
    func testServiceTierFlexProcessing() async throws {
        final class RequestCapture: @unchecked Sendable {
            var body: [String: Any]?
        }

        let capture = RequestCapture()
        let mockData = try JSONSerialization.data(withJSONObject: [
            "id": "test", "created": 1, "model": "o3-mini",
            "choices": [["index": 0, "message": ["content": ""], "finish_reason": "stop"]],
            "usage": ["prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2]
        ])

        let mockFetch: FetchFunction = { request in
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                capture.body = json
            }
            return FetchResponse(
                body: .data(mockData),
                urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"])!
            )
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch
        )

        let model = OpenAIChatLanguageModel(modelId: "o3-mini", config: config)

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: [.user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)],
                providerOptions: ["openai": ["serviceTier": JSONValue.string("flex")]]
            )
        )

        guard let body = capture.body else {
            Issue.record("Request body not captured")
            return
        }

        #expect(body["model"] as? String == "o3-mini")
        #expect(body["service_tier"] as? String == "flex")
    }

    @Test("Show warning when using flex processing with unsupported model")
    func testFlexProcessingWarningUnsupportedModel() async throws {
        final class RequestCapture: @unchecked Sendable {
            var body: [String: Any]?
        }

        let capture = RequestCapture()
        let mockData = try JSONSerialization.data(withJSONObject: [
            "id": "test", "created": 1, "model": "gpt-4o-mini",
            "choices": [["index": 0, "message": ["content": "ok"], "finish_reason": "stop"]],
            "usage": ["prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2]
        ])

        let mockFetch: FetchFunction = { request in
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                capture.body = json
            }
            return FetchResponse(
                body: .data(mockData),
                urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"])!
            )
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch
        )

        let model = OpenAIChatLanguageModel(modelId: "gpt-4o-mini", config: config)

        let result = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: [.user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)],
                providerOptions: ["openai": ["serviceTier": JSONValue.string("flex")]]
            )
        )

        guard let body = capture.body else {
            Issue.record("Request body not captured")
            return
        }

        #expect(body["service_tier"] == nil)
        #expect(result.warnings.count == 1)
        if case .unsupportedSetting(let setting, let details) = result.warnings.first {
            #expect(setting == "serviceTier")
            #expect(details == "flex processing is only available for o3, o4-mini, and gpt-5 models")
        } else {
            Issue.record("Expected unsupported-setting warning for serviceTier")
        }
    }

    @Test("Allow flex processing with o4-mini model without warnings")
    func testFlexProcessingO4Mini() async throws {
        final class RequestCapture: @unchecked Sendable {
            var body: [String: Any]?
        }

        let capture = RequestCapture()
        let mockData = try JSONSerialization.data(withJSONObject: [
            "id": "test", "created": 1, "model": "o4-mini",
            "choices": [["index": 0, "message": ["content": "ok"], "finish_reason": "stop"]],
            "usage": ["prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2]
        ])

        let mockFetch: FetchFunction = { request in
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                capture.body = json
            }
            return FetchResponse(
                body: .data(mockData),
                urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"])!
            )
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch
        )

        let model = OpenAIChatLanguageModel(modelId: "o4-mini", config: config)

        let result = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: [.user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)],
                providerOptions: ["openai": ["serviceTier": JSONValue.string("flex")]]
            )
        )

        guard let body = capture.body else {
            Issue.record("Request body not captured")
            return
        }

        #expect(body["service_tier"] as? String == "flex")
        #expect(result.warnings.isEmpty)
    }

    @Test("Send serviceTier priority processing setting")
    func testServiceTierPriorityProcessing() async throws {
        final class RequestCapture: @unchecked Sendable {
            var body: [String: Any]?
        }

        let capture = RequestCapture()
        let mockData = try JSONSerialization.data(withJSONObject: [
            "id": "test", "created": 1, "model": "gpt-4o-mini",
            "choices": [["index": 0, "message": ["content": "ok"], "finish_reason": "stop"]],
            "usage": ["prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2]
        ])

        let mockFetch: FetchFunction = { request in
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                capture.body = json
            }
            return FetchResponse(
                body: .data(mockData),
                urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"])!
            )
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch
        )

        let model = OpenAIChatLanguageModel(modelId: "gpt-4o-mini", config: config)

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: [.user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)],
                providerOptions: ["openai": ["serviceTier": JSONValue.string("priority")]]
            )
        )

        guard let body = capture.body else {
            Issue.record("Request body not captured")
            return
        }

        #expect(body["model"] as? String == "gpt-4o-mini")
        #expect(body["service_tier"] as? String == "priority")
    }

    @Test("Show warning when using priority processing with unsupported model")
    func testPriorityProcessingWarningUnsupportedModel() async throws {
        final class RequestCapture: @unchecked Sendable {
            var body: [String: Any]?
        }

        let capture = RequestCapture()
        let mockData = try JSONSerialization.data(withJSONObject: [
            "id": "test", "created": 1, "model": "gpt-3.5-turbo",
            "choices": [["index": 0, "message": ["content": "ok"], "finish_reason": "stop"]],
            "usage": ["prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2]
        ])

        let mockFetch: FetchFunction = { request in
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                capture.body = json
            }
            return FetchResponse(
                body: .data(mockData),
                urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"])!
            )
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch
        )

        let model = OpenAIChatLanguageModel(modelId: "gpt-3.5-turbo", config: config)

        let result = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: [.user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)],
                providerOptions: ["openai": ["serviceTier": JSONValue.string("priority")]]
            )
        )

        guard let body = capture.body else {
            Issue.record("Request body not captured")
            return
        }

        #expect(body["service_tier"] == nil)
        #expect(result.warnings.count == 1)
        if case .unsupportedSetting(let setting, let details) = result.warnings.first {
            #expect(setting == "serviceTier")
            #expect(details == "priority processing is only available for supported models (gpt-4, gpt-5, gpt-5-mini, o3, o4-mini) and requires Enterprise access. gpt-5-nano is not supported")
        } else {
            Issue.record("Expected unsupported-setting warning for serviceTier")
        }
    }

    @Test("Allow priority processing with gpt-4o model without warnings")
    func testPriorityProcessingGpt4o() async throws {
        final class RequestCapture: @unchecked Sendable {
            var body: [String: Any]?
        }

        let capture = RequestCapture()
        let mockData = try JSONSerialization.data(withJSONObject: [
            "id": "test", "created": 1, "model": "gpt-4o",
            "choices": [["index": 0, "message": ["content": "ok"], "finish_reason": "stop"]],
            "usage": ["prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2]
        ])

        let mockFetch: FetchFunction = { request in
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                capture.body = json
            }
            return FetchResponse(
                body: .data(mockData),
                urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"])!
            )
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch
        )

        let model = OpenAIChatLanguageModel(modelId: "gpt-4o", config: config)

        let result = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: [.user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)],
                providerOptions: ["openai": ["serviceTier": JSONValue.string("priority")]]
            )
        )

        guard let body = capture.body else {
            Issue.record("Request body not captured")
            return
        }

        #expect(body["service_tier"] as? String == "priority")
        #expect(result.warnings.isEmpty)
    }

    // MARK: - Batch 7: Tools & Additional (4 tests)

    @Test("Support partial usage")
    func testPartialUsage() async throws {
        let mockData = try JSONSerialization.data(withJSONObject: [
            "id": "test", "created": 1, "model": "gpt-3.5-turbo",
            "choices": [["index": 0, "message": ["content": "ok"], "finish_reason": "stop"]],
            "usage": ["prompt_tokens": 20, "total_tokens": 20]
        ])

        let mockFetch: FetchFunction = { _ in
            FetchResponse(
                body: .data(mockData),
                urlResponse: HTTPURLResponse(url: URL(string: "https://api.openai.com")!, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"])!
            )
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch
        )

        let model = OpenAIChatLanguageModel(modelId: "gpt-3.5-turbo", config: config)

        let result = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: [.user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)]
            )
        )

        #expect(result.usage.inputTokens == 20)
        #expect(result.usage.outputTokens == nil)
        #expect(result.usage.totalTokens == 20)
    }

    @Test("Support unknown finish reason")
    func testUnknownFinishReason() async throws {
        let mockData = try JSONSerialization.data(withJSONObject: [
            "id": "test", "created": 1, "model": "gpt-3.5-turbo",
            "choices": [["index": 0, "message": ["content": "ok"], "finish_reason": "eos"]],
            "usage": ["prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2]
        ])

        let mockFetch: FetchFunction = { _ in
            FetchResponse(
                body: .data(mockData),
                urlResponse: HTTPURLResponse(url: URL(string: "https://api.openai.com")!, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"])!
            )
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch
        )

        let model = OpenAIChatLanguageModel(modelId: "gpt-3.5-turbo", config: config)

        let result = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: [.user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)]
            )
        )

        #expect(result.finishReason == .unknown)
    }

    @Test("Pass tools and toolChoice")
    func testPassToolsAndToolChoice() async throws {
        final class RequestCapture: @unchecked Sendable {
            var body: [String: Any]?
        }

        let capture = RequestCapture()
        let mockData = try JSONSerialization.data(withJSONObject: [
            "id": "test", "created": 1, "model": "gpt-3.5-turbo",
            "choices": [["index": 0, "message": ["content": ""], "finish_reason": "stop"]],
            "usage": ["prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2]
        ])

        let mockFetch: FetchFunction = { request in
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                capture.body = json
            }
            return FetchResponse(
                body: .data(mockData),
                urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"])!
            )
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch
        )

        let model = OpenAIChatLanguageModel(modelId: "gpt-3.5-turbo", config: config)

        let toolSchema = JSONValue.object([
            "type": .string("object"),
            "properties": .object(["value": .object(["type": .string("string")])]),
            "required": .array([.string("value")]),
            "additionalProperties": .bool(false),
            "$schema": .string("http://json-schema.org/draft-07/schema#")
        ])

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: [.user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)],
                tools: [.function(LanguageModelV3FunctionTool(name: "test-tool", inputSchema: toolSchema))],
                toolChoice: .tool(toolName: "test-tool")
            )
        )

        guard let body = capture.body else {
            Issue.record("Request body not captured")
            return
        }

        #expect(body["model"] as? String == "gpt-3.5-turbo")

        // Check tools array
        guard let tools = body["tools"] as? [[String: Any]],
              let firstTool = tools.first,
              let function = firstTool["function"] as? [String: Any] else {
            Issue.record("Tools not properly formatted")
            return
        }

        #expect(firstTool["type"] as? String == "function")
        #expect(function["name"] as? String == "test-tool")
        #expect(function["strict"] as? Bool == false)

        // Check tool_choice
        guard let toolChoice = body["tool_choice"] as? [String: Any],
              let choiceFunction = toolChoice["function"] as? [String: Any] else {
            Issue.record("Tool choice not properly formatted")
            return
        }

        #expect(toolChoice["type"] as? String == "function")
        #expect(choiceFunction["name"] as? String == "test-tool")
    }

    @Test("Set strict for tool usage when structuredOutputs enabled")
    func testStrictToolWithStructuredOutputs() async throws {
        final class RequestCapture: @unchecked Sendable {
            var body: [String: Any]?
        }

        let capture = RequestCapture()
        let mockData = try JSONSerialization.data(withJSONObject: [
            "id": "test", "created": 1, "model": "gpt-4o-2024-08-06",
            "choices": [[
                "index": 0,
                "message": [
                    "content": "",
                    "tool_calls": [[
                        "id": "call_O17Uplv4lJvD6DVdIvFFeRMw",
                        "type": "function",
                        "function": ["name": "test-tool", "arguments": "{\"value\":\"Spark\"}"]
                    ]]
                ],
                "finish_reason": "tool_calls"
            ]],
            "usage": ["prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2]
        ])

        let mockFetch: FetchFunction = { request in
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                capture.body = json
            }
            return FetchResponse(
                body: .data(mockData),
                urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"])!
            )
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch
        )

        let model = OpenAIChatLanguageModel(modelId: "gpt-4o-2024-08-06", config: config)

        let toolSchema = JSONValue.object([
            "type": .string("object"),
            "properties": .object(["value": .object(["type": .string("string")])]),
            "required": .array([.string("value")]),
            "additionalProperties": .bool(false),
            "$schema": .string("http://json-schema.org/draft-07/schema#")
        ])

        let result = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: [.user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)],
                tools: [.function(LanguageModelV3FunctionTool(name: "test-tool", inputSchema: toolSchema))],
                toolChoice: .tool(toolName: "test-tool")
            )
        )

        guard let body = capture.body else {
            Issue.record("Request body not captured")
            return
        }

        #expect(body["model"] as? String == "gpt-4o-2024-08-06")

        // Check strict is false for gpt-4o-2024-08-06 (structured outputs model)
        guard let tools = body["tools"] as? [[String: Any]],
              let firstTool = tools.first,
              let function = firstTool["function"] as? [String: Any] else {
            Issue.record("Tools not properly formatted")
            return
        }

        #expect(function["strict"] as? Bool == false)

        // Check response content has tool call
        #expect(result.content.count > 0)
    }

    // MARK: - Batch 8: Response Metadata & Token Details (3 tests)

    @Test("Send additional response information")
    func testAdditionalResponseInformation() async throws {
        let mockData = try JSONSerialization.data(withJSONObject: [
            "id": "test-id",
            "created": 123,
            "model": "test-model",
            "object": "chat.completion",
            "system_fingerprint": "fp_3bc1b5746c",
            "choices": [["index": 0, "message": ["content": "", "role": "assistant"], "finish_reason": "stop"]],
            "usage": ["prompt_tokens": 4, "completion_tokens": 30, "total_tokens": 34]
        ])

        let mockFetch: FetchFunction = { _ in
            FetchResponse(
                body: .data(mockData),
                urlResponse: HTTPURLResponse(url: URL(string: "https://api.openai.com")!, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json", "Content-Length": "275"])!
            )
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch
        )

        let model = OpenAIChatLanguageModel(modelId: "gpt-3.5-turbo", config: config)

        let result = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: [.user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)]
            )
        )

        // Check response metadata
        #expect(result.response?.id == "test-id")
        #expect(result.response?.modelId == "test-model")
        #expect(result.response?.timestamp != nil)

        // Check response body exists
        guard let responseBody = result.response?.body,
              let bodyDict = responseBody as? [String: Any] else {
            Issue.record("Response body not present")
            return
        }

        // Verify body contains expected data
        #expect(bodyDict["id"] as? String == "test-id")
        #expect(bodyDict["model"] as? String == "test-model")
        #expect(bodyDict["created"] as? Int == 123)
    }

    @Test("Return cached_tokens in prompt_details_tokens")
    func testCachedTokensInUsage() async throws {
        let mockData = try JSONSerialization.data(withJSONObject: [
            "id": "test", "created": 1, "model": "gpt-4o-mini",
            "choices": [["index": 0, "message": ["content": "ok"], "finish_reason": "stop"]],
            "usage": [
                "prompt_tokens": 15,
                "completion_tokens": 20,
                "total_tokens": 35,
                "prompt_tokens_details": ["cached_tokens": 1152]
            ]
        ])

        let mockFetch: FetchFunction = { _ in
            FetchResponse(
                body: .data(mockData),
                urlResponse: HTTPURLResponse(url: URL(string: "https://api.openai.com")!, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"])!
            )
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch
        )

        let model = OpenAIChatLanguageModel(modelId: "gpt-4o-mini", config: config)

        let result = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: [.user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)]
            )
        )

        #expect(result.usage.inputTokens == 15)
        #expect(result.usage.outputTokens == 20)
        #expect(result.usage.totalTokens == 35)
        #expect(result.usage.cachedInputTokens == 1152)
    }

    @Test("Return accepted and rejected prediction tokens in completion details")
    func testPredictionTokensInMetadata() async throws {
        let mockData = try JSONSerialization.data(withJSONObject: [
            "id": "test", "created": 1, "model": "gpt-4o-mini",
            "choices": [["index": 0, "message": ["content": "ok"], "finish_reason": "stop"]],
            "usage": [
                "prompt_tokens": 15,
                "completion_tokens": 20,
                "total_tokens": 35,
                "completion_tokens_details": [
                    "accepted_prediction_tokens": 123,
                    "rejected_prediction_tokens": 456
                ]
            ]
        ])

        let mockFetch: FetchFunction = { _ in
            FetchResponse(
                body: .data(mockData),
                urlResponse: HTTPURLResponse(url: URL(string: "https://api.openai.com")!, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"])!
            )
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch
        )

        let model = OpenAIChatLanguageModel(modelId: "gpt-4o-mini", config: config)

        let result = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: [.user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)]
            )
        )

        // Check provider metadata
        guard let metadata = result.providerMetadata,
              let openaiMetadata = metadata["openai"] else {
            Issue.record("Provider metadata not present")
            return
        }

        if case .number(let accepted) = openaiMetadata["acceptedPredictionTokens"] {
            #expect(Int(accepted) == 123)
        } else {
            Issue.record("acceptedPredictionTokens not found")
        }

        if case .number(let rejected) = openaiMetadata["rejectedPredictionTokens"] {
            #expect(Int(rejected) == 456)
        } else {
            Issue.record("rejectedPredictionTokens not found")
        }
    }

    // MARK: - Batch 9: Missing Non-Streaming Tests (2 tests)

    @Test("Pass the model and the messages")
    func testPassModelAndMessages() async throws {
        final class RequestCapture: @unchecked Sendable {
            var body: [String: Any]?
        }

        let capture = RequestCapture()
        let mockData = try JSONSerialization.data(withJSONObject: [
            "id": "test-id",
            "created": 123,
            "model": "gpt-3.5-turbo",
            "choices": [["index": 0, "message": ["content": "", "role": "assistant"], "finish_reason": "stop"]],
            "usage": ["prompt_tokens": 4, "completion_tokens": 5, "total_tokens": 9]
        ])

        let mockFetch: FetchFunction = { request in
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                capture.body = json
            }
            return FetchResponse(
                body: .data(mockData),
                urlResponse: HTTPURLResponse(
                    url: URL(string: "https://api.openai.com")!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
            )
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch
        )

        let model = OpenAIChatLanguageModel(modelId: "gpt-3.5-turbo", config: config)

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: [.user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)]
            )
        )

        // Verify request body
        guard let bodyDict = capture.body else {
            Issue.record("Request body not captured")
            return
        }

        #expect(bodyDict["model"] as? String == "gpt-3.5-turbo")

        guard let messages = bodyDict["messages"] as? [[String: Any]] else {
            Issue.record("Messages not found in request")
            return
        }

        #expect(messages.count == 1)
        #expect(messages[0]["role"] as? String == "user")
        #expect(messages[0]["content"] as? String == "Hello")
    }

    @Test("Allow priority processing with o3 model without warnings")
    func testPriorityProcessingO3Mini() async throws {
        final class RequestCapture: @unchecked Sendable {
            var body: [String: Any]?
        }

        let capture = RequestCapture()
        let mockData = try JSONSerialization.data(withJSONObject: [
            "id": "test-id",
            "created": 123,
            "model": "o3-mini",
            "choices": [["index": 0, "message": ["content": "", "role": "assistant"], "finish_reason": "stop"]],
            "usage": ["prompt_tokens": 4, "completion_tokens": 5, "total_tokens": 9]
        ])

        let mockFetch: FetchFunction = { request in
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                capture.body = json
            }
            return FetchResponse(
                body: .data(mockData),
                urlResponse: HTTPURLResponse(
                    url: URL(string: "https://api.openai.com")!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
            )
        }

        let config = OpenAIConfig(
            provider: "openai.chat",
            url: { _ in "https://api.openai.com/v1/chat/completions" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch
        )

        let model = OpenAIChatLanguageModel(modelId: "o3-mini", config: config)

        let result = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: [.user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)],
                providerOptions: ["openai": ["serviceTier": JSONValue.string("priority")]]
            )
        )

        // Verify request body contains service_tier
        guard let bodyDict = capture.body else {
            Issue.record("Request body not captured")
            return
        }

        #expect(bodyDict["service_tier"] as? String == "priority")

        // Verify no warnings
        #expect(result.warnings.isEmpty)
    }
}
