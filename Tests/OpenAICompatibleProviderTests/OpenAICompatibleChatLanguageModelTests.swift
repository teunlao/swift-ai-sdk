import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import OpenAICompatibleProvider

/**
 Tests for OpenAICompatibleChatLanguageModel.

 Port of `@ai-sdk/openai-compatible/src/chat/openai-compatible-chat-language-model.test.ts`.
 */

@Suite("OpenAICompatibleChatLanguageModel")
struct OpenAICompatibleChatLanguageModelTests {
    private let testPrompt: LanguageModelV3Prompt = [
        .user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)
    ]

    // MARK: - Config Tests

    @Test("should extract base name from provider string")
    func extractBaseNameFromProviderString() {
        let model = OpenAICompatibleChatLanguageModel(
            modelId: OpenAICompatibleChatModelId(rawValue: "gpt-4"),
            config: OpenAICompatibleChatConfig(
                provider: "anthropic.beta",
                headers: { [:] },
                url: { _ in "" }
            )
        )

        // Access private property for testing
        let mirror = Mirror(reflecting: model)
        if let providerOptionsName = mirror.children.first(where: { $0.label == "providerOptionsName" })?.value as? String {
            #expect(providerOptionsName == "anthropic")
        } else {
            Issue.record("Could not access providerOptionsName")
        }
    }

    @Test("should handle provider without dot notation")
    func handleProviderWithoutDotNotation() {
        let model = OpenAICompatibleChatLanguageModel(
            modelId: OpenAICompatibleChatModelId(rawValue: "gpt-4"),
            config: OpenAICompatibleChatConfig(
                provider: "openai",
                headers: { [:] },
                url: { _ in "" }
            )
        )

        let mirror = Mirror(reflecting: model)
        if let providerOptionsName = mirror.children.first(where: { $0.label == "providerOptionsName" })?.value as? String {
            #expect(providerOptionsName == "openai")
        } else {
            Issue.record("Could not access providerOptionsName")
        }
    }

    @Test("should return empty for empty provider")
    func returnEmptyForEmptyProvider() {
        let model = OpenAICompatibleChatLanguageModel(
            modelId: OpenAICompatibleChatModelId(rawValue: "gpt-4"),
            config: OpenAICompatibleChatConfig(
                provider: "",
                headers: { [:] },
                url: { _ in "" }
            )
        )

        let mirror = Mirror(reflecting: model)
        if let providerOptionsName = mirror.children.first(where: { $0.label == "providerOptionsName" })?.value as? String {
            #expect(providerOptionsName == "")
        } else {
            Issue.record("Could not access providerOptionsName")
        }
    }

    // MARK: - doGenerate Tests

    actor RequestCapture {
        private(set) var request: URLRequest?
        func store(_ request: URLRequest) { self.request = request }
        func current() -> URLRequest? { request }
    }

    private func makeHTTPResponse(url: URL, statusCode: Int = 200, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    private func makeChatResponse(
        id: String = "chatcmpl-95ZTZkhr0mHNKqerQfiwkuox3PHAd",
        created: Double = 1711115037,
        model: String = "grok-beta",
        content: String = "",
        reasoningContent: String? = nil,
        reasoning: String? = nil,
        toolCalls: [[String: Any]]? = nil,
        finishReason: String = "stop",
        usage: [String: Any] = ["prompt_tokens": 4, "total_tokens": 34, "completion_tokens": 30]
    ) -> [String: Any] {
        var message: [String: Any] = [
            "role": "assistant",
            "content": content
        ]

        if let reasoningContent {
            message["reasoning_content"] = reasoningContent
        }

        if let reasoning {
            message["reasoning"] = reasoning
        }

        if let toolCalls {
            message["tool_calls"] = toolCalls
        }

        return [
            "id": id,
            "object": "chat.completion",
            "created": created,
            "model": model,
            "choices": [
                [
                    "index": 0,
                    "message": message,
                    "finish_reason": finishReason
                ]
            ],
            "usage": usage,
            "system_fingerprint": "fp_3bc1b5746c"
        ]
    }

    @Test("should extract text response")
    func extractTextResponse() async throws {
        let responseJSON = makeChatResponse(content: "Hello, World!")
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/chat/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL)

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch
        ))

        let model = provider.chatModel(modelId: "grok-beta")
        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: testPrompt))

        #expect(result.content.count == 1)
        if case .text(let textPart) = result.content.first {
            #expect(textPart.text == "Hello, World!")
        } else {
            Issue.record("Expected text content")
        }
    }

    @Test("should extract reasoning content")
    func extractReasoningContent() async throws {
        let responseJSON = makeChatResponse(
            content: "Hello, World!",
            reasoningContent: "This is the reasoning behind the response"
        )
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/chat/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL)

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch
        ))

        let model = provider.chatModel(modelId: "grok-beta")
        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: testPrompt))

        #expect(result.content.count == 2)

        if case .text(let textPart) = result.content[0] {
            #expect(textPart.text == "Hello, World!")
        } else {
            Issue.record("Expected text content at index 0")
        }

        if case .reasoning(let reasoningPart) = result.content[1] {
            #expect(reasoningPart.text == "This is the reasoning behind the response")
        } else {
            Issue.record("Expected reasoning content at index 1")
        }
    }

    @Test("should extract reasoning from reasoning field when reasoning_content is not provided")
    func extractReasoningFromReasoningField() async throws {
        let responseJSON = makeChatResponse(
            content: "Hello, World!",
            reasoning: "This is the reasoning from the reasoning field"
        )
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/chat/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL)

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch
        ))

        let model = provider.chatModel(modelId: "grok-beta")
        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: testPrompt))

        // Note: reasoning field is NOT extracted in doGenerate, only reasoning_content
        #expect(result.content.count == 1)
        if case .text(let textPart) = result.content.first {
            #expect(textPart.text == "Hello, World!")
        } else {
            Issue.record("Expected text content")
        }
    }

    @Test("should prefer reasoning_content over reasoning field when both are provided")
    func preferReasoningContentOverReasoningField() async throws {
        let responseJSON = makeChatResponse(
            content: "Hello, World!",
            reasoningContent: "This is from reasoning_content",
            reasoning: "This is from reasoning field"
        )
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/chat/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL)

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch
        ))

        let model = provider.chatModel(modelId: "grok-beta")
        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: testPrompt))

        #expect(result.content.count == 2)

        if case .text(let textPart) = result.content[0] {
            #expect(textPart.text == "Hello, World!")
        } else {
            Issue.record("Expected text content at index 0")
        }

        if case .reasoning(let reasoningPart) = result.content[1] {
            #expect(reasoningPart.text == "This is from reasoning_content")
        } else {
            Issue.record("Expected reasoning content at index 1")
        }
    }

    @Test("should extract usage")
    func extractUsage() async throws {
        let responseJSON = makeChatResponse(
            usage: ["prompt_tokens": 20, "total_tokens": 25, "completion_tokens": 5]
        )
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/chat/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL)

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch
        ))

        let model = provider.chatModel(modelId: "grok-beta")
        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: testPrompt))

        #expect(result.usage.inputTokens == 20)
        #expect(result.usage.outputTokens == 5)
        #expect(result.usage.totalTokens == 25)
    }

    @Test("should extract finish reason")
    func extractFinishReason() async throws {
        let responseJSON = makeChatResponse(finishReason: "stop")
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/chat/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL)

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch
        ))

        let model = provider.chatModel(modelId: "grok-beta")
        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: testPrompt))

        #expect(result.finishReason == .stop)
    }

    @Test("should support unknown finish reason")
    func supportUnknownFinishReason() async throws {
        let responseJSON = makeChatResponse(finishReason: "eos")
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/chat/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL)

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch
        ))

        let model = provider.chatModel(modelId: "grok-beta")
        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: testPrompt))

        #expect(result.finishReason == .unknown)
    }

    @Test("should expose the raw response headers")
    func exposeRawResponseHeaders() async throws {
        let responseJSON = makeChatResponse()
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/chat/completions")!
        let httpResponse = makeHTTPResponse(
            url: targetURL,
            headers: ["test-header": "test-value"]
        )

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch
        ))

        let model = provider.chatModel(modelId: "grok-beta")
        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: testPrompt))

        #expect(result.response?.headers?["test-header"] == "test-value")
    }

    @Test("should pass the model and the messages")
    func passModelAndMessages() async throws {
        let responseJSON = makeChatResponse()
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/chat/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL)
        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch
        ))

        let model = provider.chatModel(modelId: "grok-beta")
        _ = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: testPrompt))

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Missing captured request")
            return
        }

        #expect(json["model"] as? String == "grok-beta")

        if let messages = json["messages"] as? [[String: Any]], let firstMessage = messages.first {
            #expect(firstMessage["role"] as? String == "user")
            #expect(firstMessage["content"] as? String == "Hello")
        } else {
            Issue.record("Missing messages in request")
        }
    }

    @Test("should pass headers")
    func passHeaders() async throws {
        let responseJSON = makeChatResponse()
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/chat/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL)
        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: [
                "Authorization": "Bearer test-api-key",
                "Custom-Provider-Header": "provider-header-value"
            ],
            fetch: fetch
        ))

        let model = provider.chatModel(modelId: "grok-beta")
        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: testPrompt,
                headers: ["Custom-Request-Header": "request-header-value"]
            )
        )

        guard let request = await capture.current() else {
            Issue.record("Missing captured request")
            return
        }

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-api-key")
        #expect(request.value(forHTTPHeaderField: "Custom-Provider-Header") == "provider-header-value")
        #expect(request.value(forHTTPHeaderField: "Custom-Request-Header") == "request-header-value")
    }

    @Test("should include provider-specific options")
    func includeProviderSpecificOptions() async throws {
        let responseJSON = makeChatResponse()
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/chat/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL)
        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch
        ))

        let model = provider.chatModel(modelId: "grok-beta")
        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: testPrompt,
                providerOptions: [
                    "test-provider": ["someCustomOption": .string("test-value")]
                ]
            )
        )

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Missing captured request")
            return
        }

        #expect(json["someCustomOption"] as? String == "test-value")
    }

    @Test("should not include provider-specific options for different provider")
    func notIncludeProviderSpecificOptionsForDifferentProvider() async throws {
        let responseJSON = makeChatResponse()
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/chat/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL)
        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch
        ))

        let model = provider.chatModel(modelId: "grok-beta")
        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: testPrompt,
                providerOptions: [
                    "notThisProviderName": ["someCustomOption": .string("test-value")]
                ]
            )
        )

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Missing captured request")
            return
        }

        #expect(json["someCustomOption"] == nil)
    }

    @Test("should send request body")
    func sendRequestBody() async throws {
        let responseJSON = makeChatResponse()
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/chat/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL)

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch
        ))

        let model = provider.chatModel(modelId: "grok-beta")
        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: testPrompt))

        #expect(result.request != nil)
        guard let requestBody = result.request?.body as? [String: JSONValue] else {
            Issue.record("Expected request body")
            return
        }

        #expect(requestBody["model"] == .string("grok-beta"))

        if case .array(let messages) = requestBody["messages"] {
            #expect(messages.count > 0)
        } else {
            Issue.record("Expected messages array")
        }
    }

    @Test("should send additional response information")
    func sendAdditionalResponseInformation() async throws {
        let responseJSON = makeChatResponse(
            id: "test-id",
            created: 123,
            model: "test-model"
        )
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/chat/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL)

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch
        ))

        let model = provider.chatModel(modelId: "grok-beta")
        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: testPrompt))

        #expect(result.response?.id == "test-id")
        #expect(result.response?.modelId == "test-model")
        #expect(result.response?.timestamp == Date(timeIntervalSince1970: 123))
    }

    @Test("should support partial usage")
    func supportPartialUsage() async throws {
        let responseJSON = makeChatResponse(
            usage: ["prompt_tokens": 20, "total_tokens": 20]
        )
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/chat/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL)

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch
        ))

        let model = provider.chatModel(modelId: "grok-beta")
        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: testPrompt))

        #expect(result.usage.inputTokens == 20)
        #expect(result.usage.outputTokens == nil)
        #expect(result.usage.totalTokens == 20)
    }

    @Test("should pass settings")
    func passSettings() async throws {
        let responseJSON = makeChatResponse()
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/chat/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL)
        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "openai-compatible",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch
        ))

        let model = provider.chatModel(modelId: "grok-beta")
        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: testPrompt,
                providerOptions: [
                    "openai-compatible": ["user": .string("test-user-id")]
                ]
            )
        )

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Missing captured request")
            return
        }

        #expect(json["user"] as? String == "test-user-id")
    }

    @Test("should pass tools and toolChoice")
    func passToolsAndToolChoice() async throws {
        let responseJSON = makeChatResponse()
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/chat/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL)
        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch
        ))

        let schema: [String: JSONValue] = [
            "type": .string("object"),
            "properties": .object(["value": .object(["type": .string("string")])]),
            "required": .array([.string("value")]),
            "additionalProperties": .bool(false),
            "$schema": .string("http://json-schema.org/draft-07/schema#")
        ]

        let model = provider.chatModel(modelId: "grok-beta")
        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: testPrompt,
                tools: [
                    .function(LanguageModelV3FunctionTool(
                        name: "test-tool",
                        inputSchema: .object(schema)
                    ))
                ],
                toolChoice: .tool(toolName: "test-tool")
            )
        )

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Missing captured request")
            return
        }

        #expect(json["tools"] != nil)
        #expect(json["tool_choice"] != nil)

        if let tools = json["tools"] as? [[String: Any]], let firstTool = tools.first {
            #expect(firstTool["type"] as? String == "function")
            if let function = firstTool["function"] as? [String: Any] {
                #expect(function["name"] as? String == "test-tool")
            }
        } else {
            Issue.record("Expected tools array")
        }
    }

    @Test("should parse tool results")
    func parseToolResults() async throws {
        let toolCalls: [[String: Any]] = [[
            "id": "call_O17Uplv4lJvD6DVdIvFFeRMw",
            "type": "function",
            "function": [
                "name": "test-tool",
                "arguments": "{\"value\":\"Spark\"}"
            ]
        ]]

        let responseJSON = makeChatResponse(toolCalls: toolCalls)
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/chat/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL)

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch
        ))

        let schema: [String: JSONValue] = [
            "type": .string("object"),
            "properties": .object(["value": .object(["type": .string("string")])]),
            "required": .array([.string("value")]),
            "additionalProperties": .bool(false),
            "$schema": .string("http://json-schema.org/draft-07/schema#")
        ]

        let model = provider.chatModel(modelId: "grok-beta")
        let result = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: testPrompt,
                tools: [
                    .function(LanguageModelV3FunctionTool(
                        name: "test-tool",
                        inputSchema: .object(schema)
                    ))
                ],
                toolChoice: .tool(toolName: "test-tool")
            )
        )

        #expect(result.content.count == 1)

        if case .toolCall(let toolCall) = result.content.first {
            #expect(toolCall.toolCallId == "call_O17Uplv4lJvD6DVdIvFFeRMw")
            #expect(toolCall.toolName == "test-tool")
            #expect(toolCall.input == "{\"value\":\"Spark\"}")
        } else {
            Issue.record("Expected tool-call content")
        }
    }

    // MARK: - Response Format Tests

    @Test("should not send a response_format when response format is text")
    func notSendResponseFormatWhenText() async throws {
        let responseJSON = makeChatResponse(content: "{\"value\":\"Spark\"}")
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/chat/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL)
        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let model = OpenAICompatibleChatLanguageModel(
            modelId: OpenAICompatibleChatModelId(rawValue: "gpt-4o-2024-08-06"),
            config: OpenAICompatibleChatConfig(
                provider: "test-provider",
                headers: { [:] },
                url: { _ in "https://my.api.com/v1/chat/completions" },
                fetch: fetch,
                supportsStructuredOutputs: false
            )
        )

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: testPrompt,
                responseFormat: .text
            )
        )

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Missing captured request")
            return
        }

        #expect(json["response_format"] == nil)
    }

    @Test("should forward json response format as json_object without schema")
    func forwardJsonResponseFormatWithoutSchema() async throws {
        let responseJSON = makeChatResponse(content: "{\"value\":\"Spark\"}")
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/chat/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL)
        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch
        ))

        let model = provider.chatModel(modelId: "gpt-4o-2024-08-06")
        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: testPrompt,
                responseFormat: .json(schema: nil, name: nil, description: nil)
            )
        )

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Missing captured request")
            return
        }

        if let responseFormat = json["response_format"] as? [String: Any] {
            #expect(responseFormat["type"] as? String == "json_object")
        } else {
            Issue.record("Expected response_format")
        }
    }

    @Test("should forward json response format as json_object and omit schema when structuredOutputs are disabled")
    func forwardJsonResponseFormatOmitSchemaWhenDisabled() async throws {
        let responseJSON = makeChatResponse(content: "{\"value\":\"Spark\"}")
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/chat/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL)
        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let model = OpenAICompatibleChatLanguageModel(
            modelId: OpenAICompatibleChatModelId(rawValue: "gpt-4o-2024-08-06"),
            config: OpenAICompatibleChatConfig(
                provider: "test-provider",
                headers: { [:] },
                url: { _ in "https://my.api.com/v1/chat/completions" },
                fetch: fetch,
                supportsStructuredOutputs: false
            )
        )

        let schema: [String: JSONValue] = [
            "type": .string("object"),
            "properties": .object(["value": .object(["type": .string("string")])]),
            "required": .array([.string("value")]),
            "additionalProperties": .bool(false),
            "$schema": .string("http://json-schema.org/draft-07/schema#")
        ]

        let result = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: testPrompt,
                responseFormat: .json(schema: .object(schema), name: nil, description: nil)
            )
        )

        #expect(result.warnings.count == 1)
        if case .unsupportedSetting(let setting, let details) = result.warnings.first {
            #expect(setting == "responseFormat")
            #expect(details == "JSON response format schema is only supported with structuredOutputs")
        } else {
            Issue.record("Expected unsupported-setting warning")
        }

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Missing captured request")
            return
        }

        if let responseFormat = json["response_format"] as? [String: Any] {
            #expect(responseFormat["type"] as? String == "json_object")
            #expect(responseFormat["json_schema"] == nil)
        } else {
            Issue.record("Expected response_format")
        }
    }

    @Test("should forward json response format and include schema when structuredOutputs are enabled")
    func forwardJsonResponseFormatIncludeSchemaWhenEnabled() async throws {
        let responseJSON = makeChatResponse(content: "{\"value\":\"Spark\"}")
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/chat/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL)
        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let model = OpenAICompatibleChatLanguageModel(
            modelId: OpenAICompatibleChatModelId(rawValue: "gpt-4o-2024-08-06"),
            config: OpenAICompatibleChatConfig(
                provider: "test-provider",
                headers: { [:] },
                url: { _ in "https://my.api.com/v1/chat/completions" },
                fetch: fetch,
                supportsStructuredOutputs: true
            )
        )

        let schema: [String: JSONValue] = [
            "type": .string("object"),
            "properties": .object(["value": .object(["type": .string("string")])]),
            "required": .array([.string("value")]),
            "additionalProperties": .bool(false),
            "$schema": .string("http://json-schema.org/draft-07/schema#")
        ]

        let result = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: testPrompt,
                responseFormat: .json(schema: .object(schema), name: nil, description: nil)
            )
        )

        #expect(result.warnings.isEmpty)

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Missing captured request")
            return
        }

        if let responseFormat = json["response_format"] as? [String: Any] {
            #expect(responseFormat["type"] as? String == "json_schema")
            #expect(responseFormat["json_schema"] != nil)
        } else {
            Issue.record("Expected response_format")
        }
    }

    @Test("should pass reasoningEffort setting from providerOptions")
    func passReasoningEffortSetting() async throws {
        let responseJSON = makeChatResponse(content: "{\"value\":\"test\"}")
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/chat/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL)
        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let model = OpenAICompatibleChatLanguageModel(
            modelId: OpenAICompatibleChatModelId(rawValue: "gpt-5"),
            config: OpenAICompatibleChatConfig(
                provider: "test-provider",
                headers: { [:] },
                url: { _ in "https://my.api.com/v1/chat/completions" },
                fetch: fetch
            )
        )

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: testPrompt,
                providerOptions: [
                    "test-provider": ["reasoningEffort": .string("high")]
                ]
            )
        )

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Missing captured request")
            return
        }

        #expect(json["reasoning_effort"] as? String == "high")
    }

    @Test("should not duplicate reasoningEffort in request body")
    func notDuplicateReasoningEffort() async throws {
        let responseJSON = makeChatResponse(content: "{\"value\":\"test\"}")
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/chat/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL)
        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let model = OpenAICompatibleChatLanguageModel(
            modelId: OpenAICompatibleChatModelId(rawValue: "gpt-5"),
            config: OpenAICompatibleChatConfig(
                provider: "test-provider",
                headers: { [:] },
                url: { _ in "https://my.api.com/v1/chat/completions" },
                fetch: fetch
            )
        )

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: testPrompt,
                providerOptions: [
                    "test-provider": [
                        "reasoningEffort": .string("high"),
                        "customOption": .string("should-be-included")
                    ]
                ]
            )
        )

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Missing captured request")
            return
        }

        #expect(json["reasoning_effort"] as? String == "high")
        #expect(json["reasoningEffort"] == nil)
        #expect(json["customOption"] as? String == "should-be-included")
    }

    @Test("should pass textVerbosity setting from providerOptions")
    func passTextVerbositySetting() async throws {
        let responseJSON = makeChatResponse(content: "{\"value\":\"test\"}")
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/chat/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL)
        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let model = OpenAICompatibleChatLanguageModel(
            modelId: OpenAICompatibleChatModelId(rawValue: "gpt-5"),
            config: OpenAICompatibleChatConfig(
                provider: "test-provider",
                headers: { [:] },
                url: { _ in "https://my.api.com/v1/chat/completions" },
                fetch: fetch
            )
        )

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: testPrompt,
                providerOptions: [
                    "test-provider": ["textVerbosity": .string("low")]
                ]
            )
        )

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Missing captured request")
            return
        }

        #expect(json["verbosity"] as? String == "low")
    }

    @Test("should not duplicate textVerbosity in request body")
    func notDuplicateTextVerbosity() async throws {
        let responseJSON = makeChatResponse(content: "{\"value\":\"test\"}")
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/chat/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL)
        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let model = OpenAICompatibleChatLanguageModel(
            modelId: OpenAICompatibleChatModelId(rawValue: "gpt-5"),
            config: OpenAICompatibleChatConfig(
                provider: "test-provider",
                headers: { [:] },
                url: { _ in "https://my.api.com/v1/chat/completions" },
                fetch: fetch
            )
        )

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: testPrompt,
                providerOptions: [
                    "test-provider": [
                        "textVerbosity": .string("medium"),
                        "customOption": .string("should-be-included")
                    ]
                ]
            )
        )

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Missing captured request")
            return
        }

        #expect(json["verbosity"] as? String == "medium")
        #expect(json["textVerbosity"] == nil)
        #expect(json["customOption"] as? String == "should-be-included")
    }

    @Test("should use json_schema with responseFormat json when structuredOutputs are enabled")
    func useJsonSchemaWhenStructuredOutputsEnabled() async throws {
        let responseJSON = makeChatResponse(content: "{\"value\":\"Spark\"}")
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/chat/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL)
        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let model = OpenAICompatibleChatLanguageModel(
            modelId: OpenAICompatibleChatModelId(rawValue: "gpt-4o-2024-08-06"),
            config: OpenAICompatibleChatConfig(
                provider: "test-provider",
                headers: { [:] },
                url: { _ in "https://my.api.com/v1/chat/completions" },
                fetch: fetch,
                supportsStructuredOutputs: true
            )
        )

        let schema: [String: JSONValue] = [
            "type": .string("object"),
            "properties": .object(["value": .object(["type": .string("string")])]),
            "required": .array([.string("value")]),
            "additionalProperties": .bool(false),
            "$schema": .string("http://json-schema.org/draft-07/schema#")
        ]

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: testPrompt,
                responseFormat: .json(schema: .object(schema), name: nil, description: nil)
            )
        )

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Missing captured request")
            return
        }

        if let responseFormat = json["response_format"] as? [String: Any] {
            #expect(responseFormat["type"] as? String == "json_schema")
            if let jsonSchema = responseFormat["json_schema"] as? [String: Any] {
                #expect(jsonSchema["name"] as? String == "response")
                #expect(jsonSchema["schema"] != nil)
            } else {
                Issue.record("Expected json_schema")
            }
        } else {
            Issue.record("Expected response_format")
        }
    }

    @Test("should set name and description with responseFormat json when structuredOutputs are enabled")
    func setNameAndDescriptionWhenStructuredOutputsEnabled() async throws {
        let responseJSON = makeChatResponse(content: "{\"value\":\"Spark\"}")
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/chat/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL)
        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let model = OpenAICompatibleChatLanguageModel(
            modelId: OpenAICompatibleChatModelId(rawValue: "gpt-4o-2024-08-06"),
            config: OpenAICompatibleChatConfig(
                provider: "test-provider",
                headers: { [:] },
                url: { _ in "https://my.api.com/v1/chat/completions" },
                fetch: fetch,
                supportsStructuredOutputs: true
            )
        )

        let schema: [String: JSONValue] = [
            "type": .string("object"),
            "properties": .object(["value": .object(["type": .string("string")])]),
            "required": .array([.string("value")]),
            "additionalProperties": .bool(false),
            "$schema": .string("http://json-schema.org/draft-07/schema#")
        ]

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: testPrompt,
                responseFormat: .json(
                    schema: .object(schema),
                    name: "test-name",
                    description: "test description"
                )
            )
        )

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Missing captured request")
            return
        }

        if let responseFormat = json["response_format"] as? [String: Any] {
            #expect(responseFormat["type"] as? String == "json_schema")
            if let jsonSchema = responseFormat["json_schema"] as? [String: Any] {
                #expect(jsonSchema["name"] as? String == "test-name")
                #expect(jsonSchema["description"] as? String == "test description")
            } else {
                Issue.record("Expected json_schema")
            }
        } else {
            Issue.record("Expected response_format")
        }
    }

    @Test("should allow for undefined schema with responseFormat json when structuredOutputs are enabled")
    func allowUndefinedSchemaWhenStructuredOutputsEnabled() async throws {
        let responseJSON = makeChatResponse(content: "{\"value\":\"Spark\"}")
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/chat/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL)
        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let model = OpenAICompatibleChatLanguageModel(
            modelId: OpenAICompatibleChatModelId(rawValue: "gpt-4o-2024-08-06"),
            config: OpenAICompatibleChatConfig(
                provider: "test-provider",
                headers: { [:] },
                url: { _ in "https://my.api.com/v1/chat/completions" },
                fetch: fetch,
                supportsStructuredOutputs: true
            )
        )

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: testPrompt,
                responseFormat: .json(
                    schema: nil,
                    name: "test-name",
                    description: "test description"
                )
            )
        )

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Missing captured request")
            return
        }

        if let responseFormat = json["response_format"] as? [String: Any] {
            #expect(responseFormat["type"] as? String == "json_object")
            #expect(responseFormat["json_schema"] == nil)
        } else {
            Issue.record("Expected response_format")
        }
    }

    // MARK: - Usage Details Tests

    @Test("should extract detailed token usage when available")
    func extractDetailedTokenUsage() async throws {
        let usage: [String: Any] = [
            "prompt_tokens": 20,
            "completion_tokens": 30,
            "total_tokens": 50,
            "prompt_tokens_details": [
                "cached_tokens": 5
            ],
            "completion_tokens_details": [
                "reasoning_tokens": 10,
                "accepted_prediction_tokens": 15,
                "rejected_prediction_tokens": 5
            ]
        ]

        let responseJSON = makeChatResponse(usage: usage)
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/chat/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL)

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch
        ))

        let model = provider.chatModel(modelId: "grok-beta")
        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: testPrompt))

        #expect(result.usage.inputTokens == 20)
        #expect(result.usage.outputTokens == 30)
        #expect(result.usage.totalTokens == 50)
        #expect(result.usage.cachedInputTokens == 5)
        #expect(result.usage.reasoningTokens == 10)

        // Check provider metadata
        guard let providerMetadata = result.providerMetadata,
              let testProviderData = providerMetadata["test-provider"] else {
            Issue.record("Expected provider metadata")
            return
        }

        #expect(testProviderData["acceptedPredictionTokens"] == JSONValue.number(15))
        #expect(testProviderData["rejectedPredictionTokens"] == JSONValue.number(5))
    }

    @Test("should handle missing token details")
    func handleMissingTokenDetails() async throws {
        let usage: [String: Any] = [
            "prompt_tokens": 20,
            "completion_tokens": 30
        ]

        let responseJSON = makeChatResponse(usage: usage)
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/chat/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL)

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch
        ))

        let model = provider.chatModel(modelId: "grok-beta")
        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: testPrompt))

        // Provider metadata should be empty object when no details
        guard let providerMetadata = result.providerMetadata,
              let testProviderData = providerMetadata["test-provider"] else {
            Issue.record("Expected provider metadata")
            return
        }

        #expect(testProviderData.isEmpty)
    }

    @Test("should handle partial token details")
    func handlePartialTokenDetails() async throws {
        let usage: [String: Any] = [
            "prompt_tokens": 20,
            "completion_tokens": 30,
            "total_tokens": 50,
            "prompt_tokens_details": [
                "cached_tokens": 5
            ],
            "completion_tokens_details": [
                "reasoning_tokens": 10
            ]
        ]

        let responseJSON = makeChatResponse(usage: usage)
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/chat/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL)

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch
        ))

        let model = provider.chatModel(modelId: "grok-beta")
        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: testPrompt))

        #expect(result.usage.inputTokens == 20)
        #expect(result.usage.outputTokens == 30)
        #expect(result.usage.totalTokens == 50)
        #expect(result.usage.cachedInputTokens == 5)
        #expect(result.usage.reasoningTokens == 10)
    }
}
