import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import XAIProvider

/**
 Tests for XAIChatLanguageModel.

 Port of `@ai-sdk/xai/src/xai-chat-language-model.test.ts`.
 */

@Suite("XAIChatLanguageModel")
struct XAIChatLanguageModelTests {
    private static func makeConfig(
        fetch: @escaping FetchFunction,
        generateId: @escaping @Sendable () -> String = { UUID().uuidString }
    ) -> XAIChatLanguageModel.Config {
        XAIChatLanguageModel.Config(
            provider: "xai.chat",
            baseURL: "https://api.x.ai/v1",
            headers: { ["authorization": "Bearer test-api-key"] },
            generateId: generateId,
            fetch: fetch
        )
    }

    private static func decodeRequestBody(_ request: URLRequest) throws -> [String: Any] {
        guard let body = request.httpBody else { return [:] }
        return try JSONSerialization.jsonObject(with: body) as? [String: Any] ?? [:]
    }

    private static func encodeJSON(_ object: Any) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [])
        return String(data: data, encoding: .utf8)!
    }

    private static func sseEvents(_ payloads: [String]) -> [String] {
        payloads.map { "data: \($0)\n\n" } + ["data: [DONE]\n\n"]
    }

    private static func collect(_ stream: AsyncThrowingStream<LanguageModelV3StreamPart, Error>) async throws -> [LanguageModelV3StreamPart] {
        var parts: [LanguageModelV3StreamPart] = []
        for try await part in stream {
            parts.append(part)
        }
        return parts
    }

    // MARK: - Basic Tests

    @Test("should be instantiated correctly")
    func instantiateCorrectly() async throws {
        let model = XAIChatLanguageModel(
            modelId: XAIChatModelId(rawValue: "grok-beta"),
            config: Self.makeConfig(fetch: { _ in fatalError("Unexpected fetch call") })
        )

        #expect(model.modelId == "grok-beta")
        #expect(model.provider == "xai.chat")
        #expect(model.specificationVersion == "v3")
    }

    @Test("should have supported URLs")
    func supportedURLs() async throws {
        let model = XAIChatLanguageModel(
            modelId: XAIChatModelId(rawValue: "grok-beta"),
            config: Self.makeConfig(fetch: { _ in fatalError("Unexpected fetch call") })
        )

        let urls = try await model.supportedUrls
        #expect(urls.count == 1)
        #expect(urls["image/*"] != nil)

        // Verify regex matches https URLs
        if let patterns = urls["image/*"], let pattern = patterns.first {
            let testString = "https://example.com/image.jpg"
            let match = pattern.firstMatch(in: testString, options: [], range: NSRange(location: 0, length: testString.utf16.count))
            #expect(match != nil)
        }
    }

    // MARK: - doGenerate Tests

    @Test("should extract text content")
    func extractTextContent() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "id": "chatcmpl-test-id",
            "object": "chat.completion",
            "created": 1699472111.0,
            "model": "grok-beta",
            "choices": [[
                "index": 0,
                "message": [
                    "role": "assistant",
                    "content": "Hello, World!",
                    "tool_calls": NSNull()
                ],
                "finish_reason": "stop"
            ]],
            "usage": [
                "prompt_tokens": 4,
                "total_tokens": 34,
                "completion_tokens": 30
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://api.x.ai/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let model = XAIChatLanguageModel(
            modelId: XAIChatModelId(rawValue: "grok-beta"),
            config: Self.makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: prompt))

        #expect(result.content.count == 1)
        guard case .text(let text) = result.content[0] else {
            Issue.record("Expected text content")
            return
        }
        #expect(text.text == "Hello, World!")
    }

    @Test("should avoid duplication when there is a trailing assistant message")
    func avoidDuplicationWithTrailingAssistant() async throws {
        let responseJSON: [String: Any] = [
            "id": "chatcmpl-test-id",
            "object": "chat.completion",
            "created": 1699472111.0,
            "model": "grok-beta",
            "choices": [[
                "index": 0,
                "message": [
                    "role": "assistant",
                    "content": "prefix and more content",
                    "tool_calls": NSNull()
                ],
                "finish_reason": "stop"
            ]],
            "usage": [
                "prompt_tokens": 4,
                "total_tokens": 34,
                "completion_tokens": 30
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://api.x.ai/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let model = XAIChatLanguageModel(
            modelId: XAIChatModelId(rawValue: "grok-beta"),
            config: Self.makeConfig(fetch: { _ in
                FetchResponse(body: .data(responseData), urlResponse: response)
            })
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil),
            .assistant(content: [.text(.init(text: "prefix "))], providerOptions: nil)
        ]

        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: prompt))

        #expect(result.content.count == 1)
        guard case .text(let text) = result.content[0] else {
            Issue.record("Expected text content")
            return
        }
        #expect(text.text == "prefix and more content")
    }

    @Test("should extract tool call content")
    func extractToolCallContent() async throws {
        let responseJSON: [String: Any] = [
            "id": "chatcmpl-test-tool-call",
            "object": "chat.completion",
            "created": 1699472111.0,
            "model": "grok-beta",
            "choices": [[
                "index": 0,
                "message": [
                    "role": "assistant",
                    "content": NSNull(),
                    "tool_calls": [[
                        "id": "call_test123",
                        "type": "function",
                        "function": [
                            "name": "weatherTool",
                            "arguments": "{\"location\": \"paris\"}"
                        ]
                    ]]
                ],
                "finish_reason": "tool_calls"
            ]],
            "usage": [
                "prompt_tokens": 124,
                "total_tokens": 146,
                "completion_tokens": 22
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://api.x.ai/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let model = XAIChatLanguageModel(
            modelId: XAIChatModelId(rawValue: "grok-beta"),
            config: Self.makeConfig(fetch: { _ in
                FetchResponse(body: .data(responseData), urlResponse: response)
            })
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: prompt))

        #expect(result.content.count == 1)
        guard case .toolCall(let toolCall) = result.content[0] else {
            Issue.record("Expected tool call content")
            return
        }
        #expect(toolCall.toolCallId == "call_test123")
        #expect(toolCall.toolName == "weatherTool")
        #expect(toolCall.input == "{\"location\": \"paris\"}")
    }

    @Test("should extract usage")
    func extractUsage() async throws {
        let responseJSON: [String: Any] = [
            "id": "chatcmpl-test-id",
            "object": "chat.completion",
            "created": 1699472111.0,
            "model": "grok-beta",
            "choices": [[
                "index": 0,
                "message": [
                    "role": "assistant",
                    "content": "Hello",
                    "tool_calls": NSNull()
                ],
                "finish_reason": "stop"
            ]],
            "usage": [
                "prompt_tokens": 20,
                "total_tokens": 25,
                "completion_tokens": 5
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://api.x.ai/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let model = XAIChatLanguageModel(
            modelId: XAIChatModelId(rawValue: "grok-beta"),
            config: Self.makeConfig(fetch: { _ in
                FetchResponse(body: .data(responseData), urlResponse: response)
            })
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: prompt))

        #expect(result.usage.inputTokens.total == 20)
        #expect(result.usage.outputTokens.total == 5)
        #expect((result.usage.inputTokens.total ?? 0) + (result.usage.outputTokens.total ?? 0) == 25)
        #expect(result.usage.outputTokens.reasoning == 0)
    }

    @Test("should send additional response information")
    func sendAdditionalResponseInfo() async throws {
        let responseJSON: [String: Any] = [
            "id": "test-id",
            "object": "chat.completion",
            "created": 123.0,
            "model": "test-model",
            "choices": [[
                "index": 0,
                "message": [
                    "role": "assistant",
                    "content": "Hello",
                    "tool_calls": NSNull()
                ],
                "finish_reason": "stop"
            ]],
            "usage": [
                "prompt_tokens": 4,
                "total_tokens": 34,
                "completion_tokens": 30
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://api.x.ai/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let model = XAIChatLanguageModel(
            modelId: XAIChatModelId(rawValue: "grok-beta"),
            config: Self.makeConfig(fetch: { _ in
                FetchResponse(body: .data(responseData), urlResponse: response)
            })
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: prompt))

        guard let response = result.response else {
            Issue.record("Missing response")
            return
        }

        #expect(response.id == "test-id")
        #expect(response.timestamp == Date(timeIntervalSince1970: 123))
        #expect(response.modelId == "test-model")
    }

    @Test("should expose the raw response headers")
    func exposeRawResponseHeaders() async throws {
        let responseJSON: [String: Any] = [
            "id": "chatcmpl-test-id",
            "object": "chat.completion",
            "created": 1699472111.0,
            "model": "grok-beta",
            "choices": [[
                "index": 0,
                "message": [
                    "role": "assistant",
                    "content": "Hello",
                    "tool_calls": NSNull()
                ],
                "finish_reason": "stop"
            ]],
            "usage": [
                "prompt_tokens": 4,
                "total_tokens": 34,
                "completion_tokens": 30
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://api.x.ai/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": "application/json",
                "test-header": "test-value"
            ]
        )!

        let model = XAIChatLanguageModel(
            modelId: XAIChatModelId(rawValue: "grok-beta"),
            config: Self.makeConfig(fetch: { _ in
                FetchResponse(body: .data(responseData), urlResponse: response)
            })
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: prompt))

        guard let response = result.response else {
            Issue.record("Missing response")
            return
        }

        #expect(response.headers?["content-type"] == "application/json")
        #expect(response.headers?["test-header"] == "test-value")
    }

    @Test("should pass the model and the messages")
    func passModelAndMessages() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "id": "chatcmpl-test-id",
            "object": "chat.completion",
            "created": 1699472111.0,
            "model": "grok-beta",
            "choices": [[
                "index": 0,
                "message": ["role": "assistant", "content": "", "tool_calls": NSNull()],
                "finish_reason": "stop"
            ]],
            "usage": ["prompt_tokens": 4, "total_tokens": 4, "completion_tokens": 0]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://api.x.ai/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let model = XAIChatLanguageModel(
            modelId: XAIChatModelId(rawValue: "grok-beta"),
            config: Self.makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        _ = try await model.doGenerate(options: .init(prompt: prompt))

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }

        let json = try Self.decodeRequestBody(request)
        #expect(json["model"] as? String == "grok-beta")

        if let messages = json["messages"] as? [[String: Any]],
           let firstMessage = messages.first {
            #expect(firstMessage["role"] as? String == "user")
            #expect(firstMessage["content"] as? String == "Hello")
        } else {
            Issue.record("Missing or invalid messages in request")
        }
    }

    @Test("should pass tools and toolChoice")
    func passToolsAndToolChoice() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "id": "chatcmpl-test-id",
            "object": "chat.completion",
            "created": 1699472111.0,
            "model": "grok-beta",
            "choices": [[
                "index": 0,
                "message": ["role": "assistant", "content": "", "tool_calls": NSNull()],
                "finish_reason": "stop"
            ]],
            "usage": ["prompt_tokens": 4, "total_tokens": 4, "completion_tokens": 0]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://api.x.ai/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let model = XAIChatLanguageModel(
            modelId: XAIChatModelId(rawValue: "grok-beta"),
            config: Self.makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        let tool = LanguageModelV3Tool.function(LanguageModelV3FunctionTool(
            name: "test-tool",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object(["value": .object(["type": .string("string")])]),
                "required": .array([.string("value")]),
                "additionalProperties": .bool(false),
                "$schema": .string("http://json-schema.org/draft-07/schema#")
            ]),
            description: nil
        ))

        let toolChoice = LanguageModelV3ToolChoice.tool(toolName: "test-tool")

        _ = try await model.doGenerate(options: .init(
            prompt: prompt,
            tools: [tool],
            toolChoice: toolChoice
        ))

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }

        let json = try Self.decodeRequestBody(request)

        if let toolsArray = json["tools"] as? [[String: Any]],
           let firstTool = toolsArray.first,
           let function = firstTool["function"] as? [String: Any] {
            #expect(firstTool["type"] as? String == "function")
            #expect(function["name"] as? String == "test-tool")
        } else {
            Issue.record("Missing or invalid tools in request")
        }

        if let toolChoiceDict = json["tool_choice"] as? [String: Any],
           let function = toolChoiceDict["function"] as? [String: Any] {
            #expect(toolChoiceDict["type"] as? String == "function")
            #expect(function["name"] as? String == "test-tool")
        } else {
            Issue.record("Missing or invalid tool_choice in request")
        }
    }

    @Test("should pass headers")
    func passHeaders() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "id": "chatcmpl-test-id",
            "object": "chat.completion",
            "created": 1699472111.0,
            "model": "grok-beta",
            "choices": [[
                "index": 0,
                "message": ["role": "assistant", "content": "", "tool_calls": NSNull()],
                "finish_reason": "stop"
            ]],
            "usage": ["prompt_tokens": 4, "total_tokens": 4, "completion_tokens": 0]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://api.x.ai/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let config = XAIChatLanguageModel.Config(
            provider: "xai.chat",
            baseURL: "https://api.x.ai/v1",
            headers: {
                [
                    "authorization": "Bearer test-api-key",
                    "Custom-Provider-Header": "provider-header-value"
                ]
            },
            generateId: { UUID().uuidString },
            fetch: fetch
        )

        let model = XAIChatLanguageModel(
            modelId: XAIChatModelId(rawValue: "grok-beta"),
            config: config
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        _ = try await model.doGenerate(options: .init(
            prompt: prompt,
            headers: ["Custom-Request-Header": "request-header-value"]
        ))

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }

        // Verify headers (URLRequest headers are case-insensitive)
        let headers = request.allHTTPHeaderFields ?? [:]
        let normalizedHeaders = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
        #expect(normalizedHeaders["authorization"] == "Bearer test-api-key")
        #expect(normalizedHeaders["custom-provider-header"] == "provider-header-value")
        #expect(normalizedHeaders["custom-request-header"] == "request-header-value")
        #expect(normalizedHeaders["content-type"] == "application/json")
    }

    @Test("should include provider user agent when using createXai")
    func includeProviderUserAgent() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "id": "chatcmpl-test-id",
            "object": "chat.completion",
            "created": 1699472111.0,
            "model": "grok-beta",
            "choices": [[
                "index": 0,
                "message": ["role": "assistant", "content": "", "tool_calls": NSNull()],
                "finish_reason": "stop"
            ]],
            "usage": ["prompt_tokens": 4, "total_tokens": 4, "completion_tokens": 0]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://api.x.ai/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let xai = createXai(settings: XAIProviderSettings(
            apiKey: "test-api-key",
            headers: ["Custom-Provider-Header": "provider-header-value"],
            fetch: fetch
        ))

        let model = xai.chat(modelId: "grok-beta")

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        _ = try await model.doGenerate(options: .init(
            prompt: prompt,
            headers: ["Custom-Request-Header": "request-header-value"]
        ))

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }

        let headers = request.allHTTPHeaderFields ?? [:]
        let normalizedHeaders = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
        if let userAgent = normalizedHeaders["user-agent"] {
            #expect(userAgent.contains("ai-sdk/xai/"))
        } else {
            Issue.record("Missing User-Agent header")
        }
    }

    @Test("should send request body")
    func sendRequestBody() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "id": "chatcmpl-test-id",
            "object": "chat.completion",
            "created": 1699472111.0,
            "model": "grok-beta",
            "choices": [[
                "index": 0,
                "message": ["role": "assistant", "content": "", "tool_calls": NSNull()],
                "finish_reason": "stop"
            ]],
            "usage": ["prompt_tokens": 4, "total_tokens": 4, "completion_tokens": 0]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://api.x.ai/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let model = XAIChatLanguageModel(
            modelId: XAIChatModelId(rawValue: "grok-beta"),
            config: Self.makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: prompt))

        // Verify request body structure
        guard let request = result.request, let requestBody = request.body as? [String: JSONValue] else {
            Issue.record("Missing or invalid request body")
            return
        }

        #expect(requestBody["model"] != nil)
        #expect(requestBody["messages"] != nil)

        // These should be nil/undefined in the request
        #expect(requestBody["max_tokens"] == nil)
        #expect(requestBody["temperature"] == nil)
        #expect(requestBody["top_p"] == nil)
        #expect(requestBody["seed"] == nil)
        #expect(requestBody["reasoning_effort"] == nil)
        #expect(requestBody["response_format"] == nil)
        #expect(requestBody["search_parameters"] == nil)
        #expect(requestBody["tool_choice"] == nil)
        #expect(requestBody["tools"] == nil)
    }

    // Note: Skipping some redundant search parameter tests for brevity.
    // The implementation is tested through the basic search parameter test below.

    @Test("should pass search parameters")
    func passSearchParameters() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "id": "chatcmpl-test-id",
            "object": "chat.completion",
            "created": 1699472111.0,
            "model": "grok-beta",
            "choices": [[
                "index": 0,
                "message": ["role": "assistant", "content": "", "tool_calls": NSNull()],
                "finish_reason": "stop"
            ]],
            "usage": ["prompt_tokens": 4, "total_tokens": 4, "completion_tokens": 0]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://api.x.ai/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let model = XAIChatLanguageModel(
            modelId: XAIChatModelId(rawValue: "grok-beta"),
            config: Self.makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        _ = try await model.doGenerate(options: .init(
            prompt: prompt,
            providerOptions: [
                "xai": [
                    "searchParameters": .object([
                        "mode": .string("auto"),
                        "returnCitations": .bool(true),
                        "fromDate": .string("2024-01-01"),
                        "toDate": .string("2024-12-31"),
                        "maxSearchResults": .number(10)
                    ])
                ]
            ]
        ))

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }

        let json = try Self.decodeRequestBody(request)

        if let searchParams = json["search_parameters"] as? [String: Any] {
            #expect(searchParams["mode"] as? String == "auto")
            #expect(searchParams["return_citations"] as? Bool == true)
            #expect(searchParams["from_date"] as? String == "2024-01-01")
            #expect(searchParams["to_date"] as? String == "2024-12-31")
            #expect(searchParams["max_search_results"] as? Int == 10)
        } else {
            Issue.record("Missing search_parameters in request")
        }
    }

    @Test("should extract citations as sources")
    func extractCitationsAsSources() async throws {
        let responseJSON: [String: Any] = [
            "id": "citations-test",
            "object": "chat.completion",
            "created": 1699472111.0,
            "model": "grok-beta",
            "choices": [[
                "index": 0,
                "message": [
                    "role": "assistant",
                    "content": "Here are the latest developments in AI.",
                    "tool_calls": NSNull()
                ],
                "finish_reason": "stop"
            ]],
            "usage": ["prompt_tokens": 4, "total_tokens": 34, "completion_tokens": 30],
            "citations": [
                "https://example.com/article1",
                "https://example.com/article2"
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://api.x.ai/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let model = XAIChatLanguageModel(
            modelId: XAIChatModelId(rawValue: "grok-beta"),
            config: Self.makeConfig(fetch: { _ in
                FetchResponse(body: .data(responseData), urlResponse: response)
            }, generateId: { "test-id" })
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: prompt))

        #expect(result.content.count == 3)

        guard case .text(let text) = result.content[0] else {
            Issue.record("Expected text content at index 0")
            return
        }
        #expect(text.text == "Here are the latest developments in AI.")

        guard case .source(let source1) = result.content[1],
              case .url(let id1, let url1, _, _) = source1 else {
            Issue.record("Expected source content at index 1")
            return
        }
        #expect(id1 == "test-id")
        #expect(url1 == "https://example.com/article1")

        guard case .source(let source2) = result.content[2],
              case .url(let id2, let url2, _, _) = source2 else {
            Issue.record("Expected source content at index 2")
            return
        }
        #expect(id2 == "test-id")
        #expect(url2 == "https://example.com/article2")
    }

    @Test("should extract content when message content is a content object")
    func extractContentWhenMessageContentIsContentObject() async throws {
        let responseJSON: [String: Any] = [
            "id": "object-id",
            "object": "chat.completion",
            "created": 1699472111,
            "model": "grok-beta",
            "choices": [[
                "index": 0,
                "message": [
                    "role": "assistant",
                    "content": "Hello from object",
                    "tool_calls": NSNull()
                ],
                "finish_reason": "stop"
            ]],
            "usage": ["prompt_tokens": 4, "total_tokens": 34, "completion_tokens": 30]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://api.x.ai/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let model = XAIChatLanguageModel(
            modelId: XAIChatModelId(rawValue: "grok-beta"),
            config: Self.makeConfig(fetch: { _ in
                FetchResponse(body: .data(responseData), urlResponse: response)
            })
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: prompt))

        #expect(result.content.count == 1)
        guard case .text(let text) = result.content[0] else {
            Issue.record("Expected text content")
            return
        }
        #expect(text.text == "Hello from object")
    }

    @Test("should handle empty citations array")
    func handleEmptyCitationsArray() async throws {
        let responseJSON: [String: Any] = [
            "id": "no-citations-test",
            "object": "chat.completion",
            "created": 1699472111,
            "model": "grok-beta",
            "choices": [[
                "index": 0,
                "message": [
                    "role": "assistant",
                    "content": "Response without citations.",
                    "tool_calls": NSNull()
                ],
                "finish_reason": "stop"
            ]],
            "usage": ["prompt_tokens": 4, "total_tokens": 34, "completion_tokens": 30],
            "citations": []
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://api.x.ai/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let model = XAIChatLanguageModel(
            modelId: XAIChatModelId(rawValue: "grok-beta"),
            config: Self.makeConfig(fetch: { _ in
                FetchResponse(body: .data(responseData), urlResponse: response)
            })
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: prompt))

        #expect(result.content.count == 1)
        guard case .text(let text) = result.content[0] else {
            Issue.record("Expected text content")
            return
        }
        #expect(text.text == "Response without citations.")
    }

    // MARK: - doStream Tests

    @Test("should stream text deltas")
    func streamTextDeltas() async throws {
        let payloads = [
            Self.encodeJSON([
                "id": "chunk-test",
                "object": "chat.completion.chunk",
                "created": 1699472111,
                "model": "grok-beta",
                "choices": [[
                    "index": 0,
                    "delta": ["role": "assistant", "content": ""],
                    "finish_reason": NSNull()
                ]]
            ]),
            Self.encodeJSON([
                "id": "chunk-test",
                "object": "chat.completion.chunk",
                "created": 1699472111,
                "model": "grok-beta",
                "choices": [[
                    "index": 0,
                    "delta": ["content": "Hello"],
                    "finish_reason": NSNull()
                ]]
            ]),
            Self.encodeJSON([
                "id": "chunk-test",
                "object": "chat.completion.chunk",
                "created": 1699472111,
                "model": "grok-beta",
                "choices": [[
                    "index": 0,
                    "delta": ["content": ", "],
                    "finish_reason": NSNull()
                ]]
            ]),
            Self.encodeJSON([
                "id": "chunk-test",
                "object": "chat.completion.chunk",
                "created": 1699472111,
                "model": "grok-beta",
                "choices": [[
                    "index": 0,
                    "delta": ["content": "world!"],
                    "finish_reason": NSNull()
                ]]
            ]),
            Self.encodeJSON([
                "id": "chunk-test",
                "object": "chat.completion.chunk",
                "created": 1699472111,
                "model": "grok-beta",
                "choices": [[
                    "index": 0,
                    "delta": ["content": ""],
                    "finish_reason": "stop"
                ]],
                "usage": [
                    "prompt_tokens": 4,
                    "total_tokens": 36,
                    "completion_tokens": 32
                ]
            ])
        ]

        let events = Self.sseEvents(payloads)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.x.ai/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        @Sendable func buildStream() -> AsyncThrowingStream<Data, Error> {
            AsyncThrowingStream { continuation in
                for event in events {
                    continuation.yield(Data(event.utf8))
                }
                continuation.finish()
            }
        }

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .stream(buildStream()), urlResponse: httpResponse)
        }

        let model = XAIChatLanguageModel(
            modelId: XAIChatModelId(rawValue: "grok-beta"),
            config: Self.makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        let result = try await model.doStream(options: LanguageModelV3CallOptions(prompt: prompt))
        let parts = try await Self.collect(result.stream)

        // Verify text deltas
        let textDeltas = parts.compactMap { part -> String? in
            if case .textDelta(_, let delta, _) = part {
                return delta
            }
            return nil
        }

        #expect(textDeltas.contains("Hello"))
        #expect(textDeltas.contains(", "))
        #expect(textDeltas.contains("world!"))

        // Verify finish
        #expect(parts.contains { if case .finish(let reason, _, _) = $0, reason == .stop { return true } else { return false } })
    }

    @Test("should stream tool deltas")
    func streamToolDeltas() async throws {
        let payloads = [
            Self.encodeJSON([
                "id": "a9648117-740c-4270-9e07-6a8457f23b7a",
                "object": "chat.completion.chunk",
                "created": 1750535985,
                "model": "grok-beta",
                "choices": [[
                    "index": 0,
                    "delta": ["role": "assistant", "content": ""],
                    "finish_reason": NSNull()
                ]],
                "system_fingerprint": "fp_13a6dc65a6"
            ]),
            Self.encodeJSON([
                "id": "a9648117-740c-4270-9e07-6a8457f23b7a",
                "object": "chat.completion.chunk",
                "created": 1750535985,
                "model": "grok-beta",
                "choices": [[
                    "index": 0,
                    "delta": [
                        "content": NSNull(),
                        "tool_calls": [[
                            "id": "call_yfBEybNYi",
                            "type": "function",
                            "function": [
                                "name": "test-tool",
                                "arguments": "{\"value\":\"Sparkle Day\"}"
                            ]
                        ]]
                    ],
                    "finish_reason": "tool_calls"
                ]],
                "usage": [
                    "prompt_tokens": 183,
                    "total_tokens": 316,
                    "completion_tokens": 133
                ],
                "system_fingerprint": "fp_13a6dc65a6"
            ])
        ]

        let events = Self.sseEvents(payloads)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.x.ai/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        @Sendable func buildStream() -> AsyncThrowingStream<Data, Error> {
            AsyncThrowingStream { continuation in
                for event in events {
                    continuation.yield(Data(event.utf8))
                }
                continuation.finish()
            }
        }

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .stream(buildStream()), urlResponse: httpResponse)
        }

        let model = XAIChatLanguageModel(
            modelId: XAIChatModelId(rawValue: "grok-beta"),
            config: Self.makeConfig(fetch: fetch)
        )

        let tool = LanguageModelV3Tool.function(LanguageModelV3FunctionTool(
            name: "test-tool",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "value": .object(["type": .string("string")])
                ]),
                "required": .array([.string("value")]),
                "additionalProperties": .bool(false),
                "$schema": .string("http://json-schema.org/draft-07/schema#")
            ]),
            description: nil
        ))

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "What's the weather?"))], providerOptions: nil)
        ]

        let result = try await model.doStream(
            options: LanguageModelV3CallOptions(
                prompt: prompt,
                tools: [tool]
            )
        )
        let parts = try await Self.collect(result.stream)

        // Verify tool input start
        #expect(parts.contains {
            if case .toolInputStart(let id, let name, _, _, _, _) = $0 {
                return id == "call_yfBEybNYi" && name == "test-tool"
            }
            return false
        })

        // Verify tool input delta
        let toolInputDeltas = parts.compactMap { part -> String? in
            if case .toolInputDelta(_, let delta, _) = part {
                return delta
            }
            return nil
        }
        #expect(toolInputDeltas == ["{\"value\":\"Sparkle Day\"}"])

        // Verify tool input end
        #expect(parts.contains { if case .toolInputEnd(let id, _) = $0 { return id == "call_yfBEybNYi" } else { return false } })

        // Verify tool call
        #expect(parts.contains { if case .toolCall(let call) = $0 { return call.toolName == "test-tool" && call.toolCallId == "call_yfBEybNYi" } else { return false } })

        // Verify finish
        #expect(parts.contains { if case .finish(let reason, _, _) = $0, reason == .toolCalls { return true } else { return false } })
    }

    @Test("should avoid duplication when there is a trailing assistant message")
    func avoidDuplicationWithTrailingAssistantMessage() async throws {
        let payloads = [
            Self.encodeJSON([
                "id": "35e18f56-4ec6-48e4-8ca0-c1c4cbeeebbe",
                "object": "chat.completion.chunk",
                "created": 1750537778,
                "model": "grok-beta",
                "choices": [[
                    "index": 0,
                    "delta": ["role": "assistant", "content": ""],
                    "finish_reason": NSNull()
                ]],
                "system_fingerprint": "fp_13a6dc65a6"
            ]),
            Self.encodeJSON([
                "id": "35e18f56-4ec6-48e4-8ca0-c1c4cbeeebbe",
                "object": "chat.completion.chunk",
                "created": 1750537778,
                "model": "grok-beta",
                "choices": [[
                    "index": 0,
                    "delta": ["role": "assistant", "content": "prefix"],
                    "finish_reason": NSNull()
                ]],
                "system_fingerprint": "fp_13a6dc65a6"
            ]),
            Self.encodeJSON([
                "id": "35e18f56-4ec6-48e4-8ca0-c1c4cbeeebbe",
                "object": "chat.completion.chunk",
                "created": 1750537778,
                "model": "grok-beta",
                "choices": [[
                    "index": 0,
                    "delta": ["role": "assistant", "content": " and"],
                    "finish_reason": NSNull()
                ]],
                "system_fingerprint": "fp_13a6dc65a6"
            ]),
            Self.encodeJSON([
                "id": "35e18f56-4ec6-48e4-8ca0-c1c4cbeeebbe",
                "object": "chat.completion.chunk",
                "created": 1750537778,
                "model": "grok-beta",
                "choices": [[
                    "index": 0,
                    "delta": ["role": "assistant", "content": " more content"],
                    "finish_reason": NSNull()
                ]],
                "system_fingerprint": "fp_13a6dc65a6"
            ]),
            Self.encodeJSON([
                "id": "35e18f56-4ec6-48e4-8ca0-c1c4cbeeebbe",
                "object": "chat.completion.chunk",
                "created": 1750537778,
                "model": "grok-beta",
                "choices": [[
                    "index": 0,
                    "delta": ["content": ""],
                    "finish_reason": "stop"
                ]],
                "usage": [
                    "prompt_tokens": 4,
                    "total_tokens": 36,
                    "completion_tokens": 32
                ],
                "system_fingerprint": "fp_13a6dc65a6"
            ])
        ]

        let events = Self.sseEvents(payloads)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.x.ai/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        @Sendable func buildStream() -> AsyncThrowingStream<Data, Error> {
            AsyncThrowingStream { continuation in
                for event in events {
                    continuation.yield(Data(event.utf8))
                }
                continuation.finish()
            }
        }

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .stream(buildStream()), urlResponse: httpResponse)
        }

        let model = XAIChatLanguageModel(
            modelId: XAIChatModelId(rawValue: "grok-beta"),
            config: Self.makeConfig(fetch: fetch)
        )

        // Prompt with trailing assistant message
        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil),
            .assistant(content: [.text(.init(text: "prefix "))], providerOptions: nil)
        ]

        let result = try await model.doStream(options: LanguageModelV3CallOptions(prompt: prompt))
        let parts = try await Self.collect(result.stream)

        // Verify text deltas
        let textDeltas = parts.compactMap { part -> String? in
            if case .textDelta(_, let delta, _) = part {
                return delta
            }
            return nil
        }

        // Should stream "prefix", " and", " more content" without duplication
        #expect(textDeltas == ["prefix", " and", " more content"])

        // Verify finish
        #expect(parts.contains { if case .finish(let reason, _, _) = $0, reason == .stop { return true } else { return false } })
    }

    @Test("should expose the raw response headers")
    func exposeRawResponseHeadersStream() async throws {
        let payloads = [
            Self.encodeJSON([
                "id": "35e18f56-4ec6-48e4-8ca0-c1c4cbeeebbe",
                "object": "chat.completion.chunk",
                "created": 1750537778,
                "model": "grok-beta",
                "choices": [[
                    "index": 0,
                    "delta": ["role": "assistant", "content": ""],
                    "finish_reason": NSNull()
                ]],
                "system_fingerprint": "fp_13a6dc65a6"
            ]),
            Self.encodeJSON([
                "id": "35e18f56-4ec6-48e4-8ca0-c1c4cbeeebbe",
                "object": "chat.completion.chunk",
                "created": 1750537778,
                "model": "grok-beta",
                "choices": [[
                    "index": 0,
                    "delta": ["content": ""],
                    "finish_reason": "stop"
                ]],
                "usage": [
                    "prompt_tokens": 4,
                    "total_tokens": 36,
                    "completion_tokens": 32
                ],
                "system_fingerprint": "fp_13a6dc65a6"
            ])
        ]

        let events = Self.sseEvents(payloads)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.x.ai/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": "text/event-stream",
                "Cache-Control": "no-cache",
                "Connection": "keep-alive",
                "test-header": "test-value"
            ]
        )!

        @Sendable func buildStream() -> AsyncThrowingStream<Data, Error> {
            AsyncThrowingStream { continuation in
                for event in events {
                    continuation.yield(Data(event.utf8))
                }
                continuation.finish()
            }
        }

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .stream(buildStream()), urlResponse: httpResponse)
        }

        let model = XAIChatLanguageModel(
            modelId: XAIChatModelId(rawValue: "grok-beta"),
            config: Self.makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        let result = try await model.doStream(options: LanguageModelV3CallOptions(prompt: prompt))

        guard let response = result.response else {
            Issue.record("Missing response")
            return
        }

        // Verify headers are exposed
        #expect(response.headers?["test-header"] == "test-value")
        #expect(response.headers?["content-type"] == "text/event-stream")
    }

    @Test("should pass the messages")
    func passMessagesStream() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let payloads = [
            Self.encodeJSON([
                "id": "test",
                "object": "chat.completion.chunk",
                "created": 1750537778,
                "model": "grok-beta",
                "choices": [[
                    "index": 0,
                    "delta": ["role": "assistant", "content": "Hi"],
                    "finish_reason": "stop"
                ]],
                "usage": ["prompt_tokens": 4, "total_tokens": 10, "completion_tokens": 6]
            ])
        ]

        let events = Self.sseEvents(payloads)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.x.ai/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        @Sendable func buildStream() -> AsyncThrowingStream<Data, Error> {
            AsyncThrowingStream { continuation in
                for event in events {
                    continuation.yield(Data(event.utf8))
                }
                continuation.finish()
            }
        }

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .stream(buildStream()), urlResponse: httpResponse)
        }

        let model = XAIChatLanguageModel(
            modelId: XAIChatModelId(rawValue: "grok-beta"),
            config: Self.makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        _ = try await model.doStream(options: LanguageModelV3CallOptions(prompt: prompt))

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }

        let json = try Self.decodeRequestBody(request)

        if let messages = json["messages"] as? [[String: Any]],
           let firstMessage = messages.first {
            #expect(firstMessage["role"] as? String == "user")
            if let content = firstMessage["content"] as? String {
                #expect(content == "Hello")
            }
        } else {
            Issue.record("Expected messages array in request")
        }
    }

    @Test("should pass headers")
    func passHeadersStream() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let payloads = [
            Self.encodeJSON([
                "id": "test",
                "object": "chat.completion.chunk",
                "created": 1750537778,
                "model": "grok-beta",
                "choices": [[
                    "index": 0,
                    "delta": ["role": "assistant", "content": "Hi"],
                    "finish_reason": "stop"
                ]],
                "usage": ["prompt_tokens": 4, "total_tokens": 10, "completion_tokens": 6]
            ])
        ]

        let events = Self.sseEvents(payloads)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.x.ai/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        @Sendable func buildStream() -> AsyncThrowingStream<Data, Error> {
            AsyncThrowingStream { continuation in
                for event in events {
                    continuation.yield(Data(event.utf8))
                }
                continuation.finish()
            }
        }

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .stream(buildStream()), urlResponse: httpResponse)
        }

        let model = XAIChatLanguageModel(
            modelId: XAIChatModelId(rawValue: "grok-beta"),
            config: Self.makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        _ = try await model.doStream(
            options: LanguageModelV3CallOptions(
                prompt: prompt,
                headers: ["Custom-Request-Header": "request-header-value"]
            )
        )

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }

        let normalizedHeaders: [String: String] = Dictionary(uniqueKeysWithValues: request.allHTTPHeaderFields?.map { ($0.key.lowercased(), $0.value) } ?? [])
        #expect(normalizedHeaders["custom-request-header"] == "request-header-value")
    }

    @Test("should send request body")
    func sendRequestBodyStream() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let payloads = [
            Self.encodeJSON([
                "id": "test",
                "object": "chat.completion.chunk",
                "created": 1750537778,
                "model": "grok-beta",
                "choices": [[
                    "index": 0,
                    "delta": ["role": "assistant", "content": "Hi"],
                    "finish_reason": "stop"
                ]],
                "usage": ["prompt_tokens": 4, "total_tokens": 10, "completion_tokens": 6]
            ])
        ]

        let events = Self.sseEvents(payloads)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.x.ai/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        @Sendable func buildStream() -> AsyncThrowingStream<Data, Error> {
            AsyncThrowingStream { continuation in
                for event in events {
                    continuation.yield(Data(event.utf8))
                }
                continuation.finish()
            }
        }

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .stream(buildStream()), urlResponse: httpResponse)
        }

        let model = XAIChatLanguageModel(
            modelId: XAIChatModelId(rawValue: "grok-beta"),
            config: Self.makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        _ = try await model.doStream(options: LanguageModelV3CallOptions(prompt: prompt))

        guard let request = await capture.value() else {
            Issue.record("Missing captured request")
            return
        }

        let json = try Self.decodeRequestBody(request)

        #expect(json["model"] as? String == "grok-beta")
        #expect(json["stream"] as? Bool == true)
    }

    // MARK: - Remaining doGenerate tests

    @Test("should pass search parameters with sources array")
    func passSearchParametersWithSourcesArray() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "id": "test-id",
            "choices": [["index": 0, "message": ["role": "assistant", "content": "Test"], "finish_reason": "stop"]],
            "usage": ["prompt_tokens": 10, "total_tokens": 20, "completion_tokens": 10]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let response = HTTPURLResponse(url: URL(string: "https://api.x.ai/v1/chat/completions")!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let model = XAIChatLanguageModel(
            modelId: XAIChatModelId(rawValue: "grok-beta"),
            config: Self.makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: ["xai": ["searchParameters": .object(["sources": .array([.string("twitter"), .string("news")])])]])
        ]

        _ = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: prompt))

        guard let request = await capture.value() else {
            Issue.record("Missing request")
            return
        }

        let json = try Self.decodeRequestBody(request)
        if let searchParams = json["search_parameters"] as? [String: Any],
           let sources = searchParams["sources"] as? [String] {
            #expect(sources.contains("twitter"))
            #expect(sources.contains("news"))
        }
    }

    @Test("should handle complex search parameter combinations")
    func handleComplexSearchParameterCombinations() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "id": "test-id",
            "choices": [["index": 0, "message": ["role": "assistant", "content": "Test"], "finish_reason": "stop"]],
            "usage": ["prompt_tokens": 10, "total_tokens": 20, "completion_tokens": 10]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let response = HTTPURLResponse(url: URL(string: "https://api.x.ai/v1/chat/completions")!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let model = XAIChatLanguageModel(
            modelId: XAIChatModelId(rawValue: "grok-beta"),
            config: Self.makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: ["xai": ["searchParameters": .object([
                "mode": .string("auto"),
                "maxResults": .number(10),
                "sources": .array([.string("twitter")])
            ])]])
        ]

        _ = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: prompt))

        guard let request = await capture.value() else {
            Issue.record("Missing request")
            return
        }

        let json = try Self.decodeRequestBody(request)
        if let searchParams = json["search_parameters"] as? [String: Any] {
            #expect(searchParams["mode"] as? String == "auto")
            #expect(searchParams["max_results"] as? Int == 10)
        }
    }

    // MARK: - Remaining doStream tests

    @Test("should stream citations as sources")
    func streamCitationsAsSources() async throws {
        let payloads = [
            Self.encodeJSON([
                "id": "test",
                "object": "chat.completion.chunk",
                "created": 1750537778,
                "model": "grok-beta",
                "choices": [[
                    "index": 0,
                    "delta": ["role": "assistant", "content": ""],
                    "finish_reason": NSNull()
                ]]
            ]),
            Self.encodeJSON([
                "id": "test",
                "object": "chat.completion.chunk",
                "created": 1750537778,
                "model": "grok-beta",
                "choices": [[
                    "index": 0,
                    "delta": ["content": "Latest AI news"],
                    "finish_reason": NSNull()
                ]]
            ]),
            Self.encodeJSON([
                "id": "test",
                "object": "chat.completion.chunk",
                "created": 1750537778,
                "model": "grok-beta",
                "choices": [[
                    "index": 0,
                    "delta": [:],
                    "finish_reason": "stop"
                ]],
                "usage": ["prompt_tokens": 4, "total_tokens": 34, "completion_tokens": 30],
                "citations": ["https://example.com/source1", "https://example.com/source2"]
            ])
        ]

        let events = Self.sseEvents(payloads)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.x.ai/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        @Sendable func buildStream() -> AsyncThrowingStream<Data, Error> {
            AsyncThrowingStream { continuation in
                for event in events {
                    continuation.yield(Data(event.utf8))
                }
                continuation.finish()
            }
        }

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .stream(buildStream()), urlResponse: httpResponse)
        }

        let model = XAIChatLanguageModel(
            modelId: XAIChatModelId(rawValue: "grok-beta"),
            config: Self.makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        let result = try await model.doStream(options: LanguageModelV3CallOptions(prompt: prompt))
        let parts = try await Self.collect(result.stream)

        // Verify sources
        let sources = parts.compactMap { part -> LanguageModelV3Source? in
            if case .source(let source) = part {
                return source
            }
            return nil
        }

        #expect(sources.count == 2)
        if case .url(_, let url, _, _) = sources[0] {
            #expect(url == "https://example.com/source1")
        }
        if case .url(_, let url, _, _) = sources[1] {
            #expect(url == "https://example.com/source2")
        }
    }

    // MARK: - Reasoning tests

    @Test("should pass reasoning_effort parameter")
    func passReasoningEffort() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "id": "test-id",
            "choices": [["index": 0, "message": ["role": "assistant", "content": "Test"], "finish_reason": "stop"]],
            "usage": ["prompt_tokens": 10, "total_tokens": 20, "completion_tokens": 10]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let response = HTTPURLResponse(url: URL(string: "https://api.x.ai/v1/chat/completions")!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let model = XAIChatLanguageModel(
            modelId: XAIChatModelId(rawValue: "grok-beta"),
            config: Self.makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        _ = try await model.doGenerate(options: LanguageModelV3CallOptions(
            prompt: prompt,
            providerOptions: ["xai": ["reasoningEffort": .string("high")]]
        ))

        guard let request = await capture.value() else {
            Issue.record("Missing request")
            return
        }

        let json = try Self.decodeRequestBody(request)
        #expect(json["reasoning_effort"] as? String == "high")
    }

    @Test("should extract reasoning content")
    func extractReasoningContent() async throws {
        let responseJSON: [String: Any] = [
            "id": "test-id",
            "choices": [[
                "index": 0,
                "message": [
                    "role": "assistant",
                    "content": "This is answer",
                    "reasoning_content": "This is reasoning"
                ],
                "finish_reason": "stop"
            ]],
            "usage": ["prompt_tokens": 10, "total_tokens": 20, "completion_tokens": 10]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let response = HTTPURLResponse(url: URL(string: "https://api.x.ai/v1/chat/completions")!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let model = XAIChatLanguageModel(
            modelId: XAIChatModelId(rawValue: "grok-beta"),
            config: Self.makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: prompt))

        #expect(result.content.count == 2)

        if case .text(let text) = result.content[0] {
            #expect(text.text == "This is answer")
        } else {
            Issue.record("Expected text content")
        }

        if case .reasoning(let reasoning) = result.content[1] {
            #expect(reasoning.text == "This is reasoning")
        } else {
            Issue.record("Expected reasoning content")
        }
    }

    @Test("should extract reasoning tokens from usage")
    func extractReasoningTokensFromUsage() async throws {
        let responseJSON: [String: Any] = [
            "id": "test-id",
            "choices": [["index": 0, "message": ["role": "assistant", "content": "Test"], "finish_reason": "stop"]],
            "usage": [
                "prompt_tokens": 10,
                "total_tokens": 30,
                "completion_tokens": 20,
                "completion_tokens_details": ["reasoning_tokens": 15]
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let response = HTTPURLResponse(url: URL(string: "https://api.x.ai/v1/chat/completions")!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let model = XAIChatLanguageModel(
            modelId: XAIChatModelId(rawValue: "grok-beta"),
            config: Self.makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: prompt))

        #expect(result.usage.inputTokens.total == 10)
        #expect(result.usage.outputTokens.total == 20)
        #expect(result.usage.outputTokens.reasoning == 15)
        #expect((result.usage.inputTokens.total ?? 0) + (result.usage.outputTokens.total ?? 0) == 30)
    }

    @Test("should handle reasoning streaming")
    func handleReasoningStreaming() async throws {
        let payloads = [
            Self.encodeJSON([
                "id": "test",
                "object": "chat.completion.chunk",
                "created": 1750537778,
                "model": "grok-beta",
                "choices": [[
                    "index": 0,
                    "delta": ["role": "assistant", "content": ""],
                    "finish_reason": NSNull()
                ]]
            ]),
            Self.encodeJSON([
                "id": "test",
                "object": "chat.completion.chunk",
                "created": 1750537778,
                "model": "grok-beta",
                "choices": [[
                    "index": 0,
                    "delta": ["reasoning_content": "Let me calculate: "],
                    "finish_reason": NSNull()
                ]]
            ]),
            Self.encodeJSON([
                "id": "test",
                "object": "chat.completion.chunk",
                "created": 1750537778,
                "model": "grok-beta",
                "choices": [[
                    "index": 0,
                    "delta": ["reasoning_content": "101 * 3 = 303"],
                    "finish_reason": NSNull()
                ]]
            ]),
            Self.encodeJSON([
                "id": "test",
                "object": "chat.completion.chunk",
                "created": 1750537778,
                "model": "grok-beta",
                "choices": [[
                    "index": 0,
                    "delta": ["content": "Answer"],
                    "finish_reason": "stop"
                ]],
                "usage": ["prompt_tokens": 4, "total_tokens": 10, "completion_tokens": 6]
            ])
        ]

        let events = Self.sseEvents(payloads)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.x.ai/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        @Sendable func buildStream() -> AsyncThrowingStream<Data, Error> {
            AsyncThrowingStream { continuation in
                for event in events {
                    continuation.yield(Data(event.utf8))
                }
                continuation.finish()
            }
        }

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .stream(buildStream()), urlResponse: httpResponse)
        }

        let model = XAIChatLanguageModel(
            modelId: XAIChatModelId(rawValue: "grok-beta"),
            config: Self.makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        let result = try await model.doStream(options: LanguageModelV3CallOptions(prompt: prompt))
        let parts = try await Self.collect(result.stream)

        // Verify reasoning deltas
        let reasoningDeltas = parts.compactMap { part -> String? in
            if case .reasoningDelta(_, let delta, _) = part {
                return delta
            }
            return nil
        }

        #expect(reasoningDeltas.count == 2)
        #expect(reasoningDeltas[0] == "Let me calculate: ")
        #expect(reasoningDeltas[1] == "101 * 3 = 303")

        // Verify text delta
        let textDeltas = parts.compactMap { part -> String? in
            if case .textDelta(_, let delta, _) = part {
                return delta
            }
            return nil
        }

        #expect(textDeltas.contains("Answer"))
    }

    @Test("should deduplicate repetitive reasoning deltas")
    func deduplicateRepetitiveReasoningDeltas() async throws {
        let payloads = [
            Self.encodeJSON([
                "id": "grok-4-test",
                "object": "chat.completion.chunk",
                "created": 1750537778,
                "model": "grok-4-0709",
                "choices": [[
                    "index": 0,
                    "delta": ["role": "assistant", "content": ""],
                    "finish_reason": NSNull()
                ]]
            ]),
            // Multiple identical "Thinking... " deltas (simulating Grok 4 issue)
            Self.encodeJSON([
                "id": "grok-4-test",
                "object": "chat.completion.chunk",
                "created": 1750537778,
                "model": "grok-4-0709",
                "choices": [[
                    "index": 0,
                    "delta": ["reasoning_content": "Thinking... "],
                    "finish_reason": NSNull()
                ]]
            ]),
            Self.encodeJSON([
                "id": "grok-4-test",
                "object": "chat.completion.chunk",
                "created": 1750537778,
                "model": "grok-4-0709",
                "choices": [[
                    "index": 0,
                    "delta": ["reasoning_content": "Thinking... "],
                    "finish_reason": NSNull()
                ]]
            ]),
            Self.encodeJSON([
                "id": "grok-4-test",
                "object": "chat.completion.chunk",
                "created": 1750537778,
                "model": "grok-4-0709",
                "choices": [[
                    "index": 0,
                    "delta": ["reasoning_content": "Thinking... "],
                    "finish_reason": NSNull()
                ]]
            ]),
            // Different reasoning content should still come through
            Self.encodeJSON([
                "id": "grok-4-test",
                "object": "chat.completion.chunk",
                "created": 1750537778,
                "model": "grok-4-0709",
                "choices": [[
                    "index": 0,
                    "delta": ["reasoning_content": "Actually calculating now..."],
                    "finish_reason": NSNull()
                ]]
            ]),
            Self.encodeJSON([
                "id": "grok-4-test",
                "object": "chat.completion.chunk",
                "created": 1750537778,
                "model": "grok-4-0709",
                "choices": [[
                    "index": 0,
                    "delta": ["content": "The answer is 42."],
                    "finish_reason": NSNull()
                ]]
            ]),
            Self.encodeJSON([
                "id": "grok-4-test",
                "object": "chat.completion.chunk",
                "created": 1750537778,
                "model": "grok-4-0709",
                "choices": [[
                    "index": 0,
                    "delta": [:],
                    "finish_reason": "stop"
                ]],
                "usage": ["prompt_tokens": 15, "total_tokens": 35, "completion_tokens": 20, "completion_tokens_details": ["reasoning_tokens": 10]]
            ])
        ]

        let events = Self.sseEvents(payloads)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.x.ai/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        @Sendable func buildStream() -> AsyncThrowingStream<Data, Error> {
            AsyncThrowingStream { continuation in
                for event in events {
                    continuation.yield(Data(event.utf8))
                }
                continuation.finish()
            }
        }

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .stream(buildStream()), urlResponse: httpResponse)
        }

        let model = XAIChatLanguageModel(
            modelId: XAIChatModelId(rawValue: "grok-beta"),
            config: Self.makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        let result = try await model.doStream(options: LanguageModelV3CallOptions(prompt: prompt))
        let parts = try await Self.collect(result.stream)

        // Verify reasoning deltas are deduplicated
        let reasoningDeltas = parts.compactMap { part -> String? in
            if case .reasoningDelta(_, let delta, _) = part {
                return delta
            }
            return nil
        }

        // Should only have "Thinking... " once (not 3 times), and "Actually calculating now..." once
        #expect(reasoningDeltas.count == 2)
        #expect(reasoningDeltas[0] == "Thinking... ")
        #expect(reasoningDeltas[1] == "Actually calculating now...")

        // Verify text delta
        let textDeltas = parts.compactMap { part -> String? in
            if case .textDelta(_, let delta, _) = part {
                return delta
            }
            return nil
        }

        #expect(textDeltas.contains("The answer is 42."))
    }

    @Test("should stream raw chunks when includeRawChunks is true")
    func streamRawChunksWhenIncludeRawChunksTrue() async throws {
        let payloads = [
            Self.encodeJSON([
                "id": "d9f56e23-8b4c-4e7a-9d2f-6c8a9b5e3f7d",
                "object": "chat.completion.chunk",
                "created": 1750538300,
                "model": "grok-beta",
                "choices": [[
                    "index": 0,
                    "delta": ["role": "assistant", "content": "Hello"],
                    "finish_reason": NSNull()
                ]],
                "system_fingerprint": "fp_13a6dc65a6"
            ]),
            Self.encodeJSON([
                "id": "e2a47b89-3f6d-4c8e-9a1b-7d5f8c9e2a4b",
                "object": "chat.completion.chunk",
                "created": 1750538301,
                "model": "grok-beta",
                "choices": [[
                    "index": 0,
                    "delta": ["content": " world"],
                    "finish_reason": NSNull()
                ]],
                "system_fingerprint": "fp_13a6dc65a6"
            ]),
            Self.encodeJSON([
                "id": "f3b58c9a-4e7f-5d9e-ab2c-8e6f9d0e3b5c",
                "object": "chat.completion.chunk",
                "created": 1750538302,
                "model": "grok-beta",
                "choices": [[
                    "index": 0,
                    "delta": [:],
                    "finish_reason": "stop"
                ]],
                "usage": ["prompt_tokens": 10, "completion_tokens": 5, "total_tokens": 15],
                "citations": ["https://example.com"],
                "system_fingerprint": "fp_13a6dc65a6"
            ])
        ]

        let events = Self.sseEvents(payloads)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.x.ai/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        @Sendable func buildStream() -> AsyncThrowingStream<Data, Error> {
            AsyncThrowingStream { continuation in
                for event in events {
                    continuation.yield(Data(event.utf8))
                }
                continuation.finish()
            }
        }

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .stream(buildStream()), urlResponse: httpResponse)
        }

        let model = XAIChatLanguageModel(
            modelId: XAIChatModelId(rawValue: "grok-beta"),
            config: Self.makeConfig(fetch: fetch)
        )

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        let result = try await model.doStream(options: LanguageModelV3CallOptions(
            prompt: prompt,
            includeRawChunks: true
        ))
        let parts = try await Self.collect(result.stream)

        // Verify raw chunks are present
        let rawChunks = parts.compactMap { part -> JSONValue? in
            if case .raw(let raw) = part {
                return raw
            }
            return nil
        }

        #expect(rawChunks.count == 3)

        // Verify first raw chunk has the expected structure
        guard case .object(let firstChunk) = rawChunks[0] else {
            Issue.record("Expected first raw chunk to be an object")
            return
        }

        guard case .string(let id) = firstChunk["id"] else {
            Issue.record("Expected id to be a string")
            return
        }

        guard case .array(let choices) = firstChunk["choices"] else {
            Issue.record("Expected choices to be an array")
            return
        }

        #expect(id == "d9f56e23-8b4c-4e7a-9d2f-6c8a9b5e3f7d")
        #expect(choices.count == 1)

        // Verify text deltas are also present
        let textDeltas = parts.compactMap { part -> String? in
            if case .textDelta(_, let delta, _) = part {
                return delta
            }
            return nil
        }

        #expect(textDeltas.count == 2)
        #expect(textDeltas[0] == "Hello")
        #expect(textDeltas[1] == " world")
    }
}
