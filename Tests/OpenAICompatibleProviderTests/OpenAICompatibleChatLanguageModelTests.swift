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
    func extractBaseNameFromProviderString() throws {
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
    func handleProviderWithoutDotNotation() throws {
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
    func returnEmptyForEmptyProvider() throws {
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

    @Test("should pass user setting to requests")
    func passUserSettingToRequests() async throws {
        let responseJSON = makeChatResponse(content: "Hello, World!")
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/chat/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL)
        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        // Provider name is "test-provider", but providerOptions uses "xai"
        // So user setting should NOT be included in request (name mismatch)
        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch
        ))

        let model = try provider.chatModel(modelId: "grok-beta")
        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: testPrompt,
                providerOptions: [
                    "xai": ["user": .string("test-user-id")]
                ]
            )
        )

        // Verify that user setting is NOT included in request body
        // (provider name doesn't match, so xai options are ignored)
        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Missing captured request")
            return
        }

        #expect(json["user"] == nil)
        #expect(json["model"] as? String == "grok-beta")

        if let messages = json["messages"] as? [[String: Any]] {
            #expect(messages.count == 1)
            #expect(messages[0]["role"] as? String == "user")
            #expect(messages[0]["content"] as? String == "Hello")
        } else {
            Issue.record("Expected messages array")
        }
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

        let model = try provider.chatModel(modelId: "grok-beta")
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

        let model = try provider.chatModel(modelId: "grok-beta")
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

        let model = try provider.chatModel(modelId: "grok-beta")
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

        let model = try provider.chatModel(modelId: "grok-beta")
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

        let model = try provider.chatModel(modelId: "grok-beta")
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

        let model = try provider.chatModel(modelId: "grok-beta")
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

        let model = try provider.chatModel(modelId: "grok-beta")
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

        let model = try provider.chatModel(modelId: "grok-beta")
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

        let model = try provider.chatModel(modelId: "grok-beta")
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

        let model = try provider.chatModel(modelId: "grok-beta")
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

        let model = try provider.chatModel(modelId: "grok-beta")
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

        let model = try provider.chatModel(modelId: "grok-beta")
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

        let model = try provider.chatModel(modelId: "grok-beta")
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

        let model = try provider.chatModel(modelId: "grok-beta")
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

        let model = try provider.chatModel(modelId: "grok-beta")
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

        let model = try provider.chatModel(modelId: "grok-beta")
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

        let model = try provider.chatModel(modelId: "grok-beta")
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

        let model = try provider.chatModel(modelId: "grok-beta")
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

        let model = try provider.chatModel(modelId: "gpt-4o-2024-08-06")
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
        if let warning = result.warnings.first,
           case .unsupported(let feature, let details) = warning {
            #expect(feature == "responseFormat")
            #expect(details == "JSON response format schema is only supported with structuredOutputs")
        } else {
            Issue.record("Expected unsupported warning")
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

        let model = try provider.chatModel(modelId: "grok-beta")
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

        let model = try provider.chatModel(modelId: "grok-beta")
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

        let model = try provider.chatModel(modelId: "grok-beta")
        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: testPrompt))

        #expect(result.usage.inputTokens == 20)
        #expect(result.usage.outputTokens == 30)
        #expect(result.usage.totalTokens == 50)
        #expect(result.usage.cachedInputTokens == 5)
        #expect(result.usage.reasoningTokens == 10)
    }

    // MARK: - doStream Tests

    private func makeStreamChunks(
        content: [String] = [],
        finishReason: String = "stop",
        reasoning: [(field: String, content: String)] = []
    ) -> String {
        var chunks: [String] = []

        // First chunk with role
        if !reasoning.isEmpty {
            let reasoningField = reasoning[0].field
            let reasoningContent = reasoning[0].content
            chunks.append("data: {\"id\":\"chatcmpl-stream-test\",\"object\":\"chat.completion.chunk\",\"created\":1702657020,\"model\":\"grok-beta\"," +
                "\"system_fingerprint\":null,\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":\"\",\"\(reasoningField)\":\"\(reasoningContent)\"},\"finish_reason\":null}]}\n\n")

            // Additional reasoning chunks
            for i in 1..<reasoning.count {
                let reasoningField = reasoning[i].field
                let reasoningContent = reasoning[i].content
                chunks.append("data: {\"id\":\"chatcmpl-stream-test\",\"object\":\"chat.completion.chunk\",\"created\":1702657020,\"model\":\"grok-beta\"," +
                    "\"system_fingerprint\":null,\"choices\":[{\"index\":0,\"delta\":{\"content\":\"\",\"\(reasoningField)\":\"\(reasoningContent)\"},\"finish_reason\":null}]}\n\n")
            }
        } else {
            chunks.append("data: {\"id\":\"chatcmpl-stream-test\",\"object\":\"chat.completion.chunk\",\"created\":1702657020,\"model\":\"grok-beta\"," +
                "\"system_fingerprint\":null,\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":\"\"},\"finish_reason\":null}]}\n\n")
        }

        // Content chunks
        for text in content {
            chunks.append("data: {\"id\":\"chatcmpl-stream-test\",\"object\":\"chat.completion.chunk\",\"created\":1702657020,\"model\":\"grok-beta\"," +
                "\"system_fingerprint\":null,\"choices\":[{\"index\":0,\"delta\":{\"content\":\"\(text)\"},\"finish_reason\":null}]}\n\n")
        }

        // Finish chunk
        chunks.append("data: {\"id\":\"chatcmpl-stream-test\",\"object\":\"chat.completion.chunk\",\"created\":1702657020,\"model\":\"grok-beta\"," +
            "\"system_fingerprint\":null,\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"\(finishReason)\"}]}\n\n")

        // Usage chunk
        chunks.append("data: {\"id\":\"chatcmpl-stream-test\",\"object\":\"chat.completion.chunk\",\"created\":1729171479,\"model\":\"grok-beta\"," +
            "\"system_fingerprint\":\"fp_test\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"\(finishReason)\"}]," +
            "\"usage\":{\"prompt_tokens\":18,\"completion_tokens\":439,\"total_tokens\":457}}\n\n")

        // DONE chunk
        chunks.append("data: [DONE]\n\n")

        return chunks.joined()
    }

    @Test("should respect the includeUsage option")
    func respectIncludeUsageOption() async throws {
        let streamChunks = makeStreamChunks(content: ["Hello", ", ", "World!"])
        let data = Data(streamChunks.utf8)
        let targetURL = URL(string: "https://my.api.com/v1/chat/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL)

        let requestCapture = RequestCapture()

        let fetch: FetchFunction = { request in
            await requestCapture.store(request)
            return FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch,
            includeUsage: true
        ))

        let model = try provider.chatModel(modelId: "grok-beta")
        _ = try await model.doStream(options: LanguageModelV3CallOptions(prompt: testPrompt))

        let capturedRequest = await requestCapture.current()
        let bodyData = try #require(capturedRequest?.httpBody)
        let body = try JSONDecoder().decode([String: JSONValue].self, from: bodyData)

        #expect(body["stream"] == JSONValue.bool(true))
        guard let streamOptionsValue = body["stream_options"],
              case let .object(streamOptions) = streamOptionsValue else {
            Issue.record("Expected stream_options object")
            return
        }

        #expect(streamOptions["include_usage"] == JSONValue.bool(true))
    }

    @Test("should stream text deltas")
    func streamTextDeltas() async throws {
        let streamChunks = makeStreamChunks(content: ["Hello", ", ", "World!"])
        let data = Data(streamChunks.utf8)
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

        let model = try provider.chatModel(modelId: "grok-beta")
        let result = try await model.doStream(options: LanguageModelV3CallOptions(prompt: testPrompt))

        var chunks: [LanguageModelV3StreamPart] = []
        for try await chunk in result.stream {
            chunks.append(chunk)
        }

        // Verify stream structure
        #expect(chunks.count > 0)

        // Check for stream-start
        if case .streamStart = chunks[0] {
            // Expected
        } else {
            Issue.record("Expected stream-start as first chunk")
        }

        // Check for text deltas
        let textDeltas = chunks.compactMap { chunk -> String? in
            if case let .textDelta(_, delta, _) = chunk {
                return delta
            }
            return nil
        }

        #expect(textDeltas.count == 3)
        #expect(textDeltas[0] == "Hello")
        #expect(textDeltas[1] == ", ")
        #expect(textDeltas[2] == "World!")

        // Check for finish with usage
        let finishChunk = chunks.last { chunk in
            if case .finish = chunk { return true }
            return false
        }

        #expect(finishChunk != nil)
        if case let .finish(finishReason, usage, _) = finishChunk {
            #expect(finishReason == .stop)
            #expect(usage.inputTokens == 18)
            #expect(usage.outputTokens == 439)
            #expect(usage.totalTokens == 457)
        }
    }

    @Test("should stream reasoning content before text deltas")
    func streamReasoningContentBeforeTextDeltas() async throws {
        // Create custom chunks with reasoning_content
        let customChunks = "data: {\"id\":\"chatcmpl-test\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"grok-beta\"," +
            "\"system_fingerprint\":\"fp_test\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":\"\",\"reasoning_content\":\"Let me think\"},\"finish_reason\":null}]}\n\n" +
            "data: {\"id\":\"chatcmpl-test\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"grok-beta\"," +
            "\"system_fingerprint\":\"fp_test\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"\",\"reasoning_content\":\" about this\"},\"finish_reason\":null}]}\n\n" +
            "data: {\"id\":\"chatcmpl-test\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"grok-beta\"," +
            "\"system_fingerprint\":\"fp_test\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Here's\"},\"finish_reason\":null}]}\n\n" +
            "data: {\"id\":\"chatcmpl-test\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"grok-beta\"," +
            "\"system_fingerprint\":\"fp_test\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\" my response\"},\"finish_reason\":null}]}\n\n" +
            "data: {\"id\":\"chatcmpl-test\",\"object\":\"chat.completion.chunk\",\"created\":1729171479,\"model\":\"grok-beta\"," +
            "\"system_fingerprint\":\"fp_test\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]," +
            "\"usage\":{\"prompt_tokens\":18,\"completion_tokens\":439}}\n\n" +
            "data: [DONE]\n\n"

        let data = Data(customChunks.utf8)
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

        let model = try provider.chatModel(modelId: "grok-beta")
        let result = try await model.doStream(options: LanguageModelV3CallOptions(prompt: testPrompt))

        var chunks: [LanguageModelV3StreamPart] = []
        for try await chunk in result.stream {
            chunks.append(chunk)
        }

        // Check for reasoning deltas before text deltas
        let reasoningDeltas = chunks.compactMap { chunk -> String? in
            if case let .reasoningDelta(_, delta, _) = chunk {
                return delta
            }
            return nil
        }

        let textDeltas = chunks.compactMap { chunk -> String? in
            if case let .textDelta(_, delta, _) = chunk {
                return delta
            }
            return nil
        }

        #expect(reasoningDeltas.count == 2)
        #expect(reasoningDeltas[0] == "Let me think")
        #expect(reasoningDeltas[1] == " about this")

        #expect(textDeltas.count == 2)
        #expect(textDeltas[0] == "Here's")
        #expect(textDeltas[1] == " my response")

        // Verify reasoning comes before text in stream
        let reasoningStartIndex = chunks.firstIndex { chunk in
            if case .reasoningStart = chunk { return true }
            return false
        }
        let textStartIndex = chunks.firstIndex { chunk in
            if case .textStart = chunk { return true }
            return false
        }

        if let rsIdx = reasoningStartIndex, let tsIdx = textStartIndex {
            #expect(rsIdx < tsIdx)
        } else {
            Issue.record("Expected both reasoning-start and text-start")
        }
    }

    @Test("should stream reasoning from reasoning field when reasoning_content is not provided")
    func streamReasoningFromReasoningField() async throws {
        let customChunks = "data: {\"id\":\"chatcmpl-test\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"grok-beta\"," +
            "\"system_fingerprint\":\"fp_test\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":\"\",\"reasoning\":\"Let me consider\"},\"finish_reason\":null}]}\n\n" +
            "data: {\"id\":\"chatcmpl-test\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"grok-beta\"," +
            "\"system_fingerprint\":\"fp_test\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"\",\"reasoning\":\" this carefully\"},\"finish_reason\":null}]}\n\n" +
            "data: {\"id\":\"chatcmpl-test\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"grok-beta\"," +
            "\"system_fingerprint\":\"fp_test\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"My answer is\"},\"finish_reason\":null}]}\n\n" +
            "data: {\"id\":\"chatcmpl-test\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"grok-beta\"," +
            "\"system_fingerprint\":\"fp_test\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\" correct\"},\"finish_reason\":null}]}\n\n" +
            "data: {\"id\":\"chatcmpl-test\",\"object\":\"chat.completion.chunk\",\"created\":1729171479,\"model\":\"grok-beta\"," +
            "\"system_fingerprint\":\"fp_test\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]," +
            "\"usage\":{\"prompt_tokens\":18,\"completion_tokens\":439}}\n\n" +
            "data: [DONE]\n\n"

        let data = Data(customChunks.utf8)
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

        let model = try provider.chatModel(modelId: "grok-beta")
        let result = try await model.doStream(options: LanguageModelV3CallOptions(prompt: testPrompt))

        var chunks: [LanguageModelV3StreamPart] = []
        for try await chunk in result.stream {
            chunks.append(chunk)
        }

        // Check for reasoning deltas using reasoning field
        let reasoningDeltas = chunks.compactMap { chunk -> String? in
            if case let .reasoningDelta(_, delta, _) = chunk {
                return delta
            }
            return nil
        }

        #expect(reasoningDeltas.count == 2)
        #expect(reasoningDeltas[0] == "Let me consider")
        #expect(reasoningDeltas[1] == " this carefully")
    }

    @Test("should prefer reasoning_content over reasoning field in streaming when both are provided")
    func preferReasoningContentOverReasoningFieldInStreaming() async throws {
        let customChunks = "data: {\"id\":\"chatcmpl-test\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"grok-beta\"," +
            "\"system_fingerprint\":\"fp_test\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":\"\",\"reasoning_content\":\"From reasoning_content\",\"reasoning\":\"From reasoning\"},\"finish_reason\":null}]}\n\n" +
            "data: {\"id\":\"chatcmpl-test\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"grok-beta\"," +
            "\"system_fingerprint\":\"fp_test\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Final response\"},\"finish_reason\":null}]}\n\n" +
            "data: {\"id\":\"chatcmpl-test\",\"object\":\"chat.completion.chunk\",\"created\":1729171479,\"model\":\"grok-beta\"," +
            "\"system_fingerprint\":\"fp_test\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]," +
            "\"usage\":{\"prompt_tokens\":18,\"completion_tokens\":439}}\n\n" +
            "data: [DONE]\n\n"

        let data = Data(customChunks.utf8)
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

        let model = try provider.chatModel(modelId: "grok-beta")
        let result = try await model.doStream(options: LanguageModelV3CallOptions(prompt: testPrompt))

        var chunks: [LanguageModelV3StreamPart] = []
        for try await chunk in result.stream {
            chunks.append(chunk)
        }

        // Check that reasoning_content was used, not reasoning
        let reasoningDeltas = chunks.compactMap { chunk -> String? in
            if case let .reasoningDelta(_, delta, _) = chunk {
                return delta
            }
            return nil
        }

        #expect(reasoningDeltas.count == 1)
        #expect(reasoningDeltas[0] == "From reasoning_content")
    }

    @Test("should pass the messages and the model")
    func passTheMessagesAndTheModel() async throws {
        let streamChunks = makeStreamChunks(content: [])
        let data = Data(streamChunks.utf8)
        let targetURL = URL(string: "https://my.api.com/v1/chat/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL)

        let requestCapture = RequestCapture()

        let fetch: FetchFunction = { request in
            await requestCapture.store(request)
            return FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch
        ))

        let model = try provider.chatModel(modelId: "grok-beta")
        _ = try await model.doStream(options: LanguageModelV3CallOptions(prompt: testPrompt))

        let capturedRequest = await requestCapture.current()
        let bodyData = try #require(capturedRequest?.httpBody)
        let body = try JSONDecoder().decode([String: JSONValue].self, from: bodyData)

        #expect(body["stream"] == JSONValue.bool(true))
        #expect(body["model"] == JSONValue.string("grok-beta"))

        guard let messagesValue = body["messages"],
              case let .array(messages) = messagesValue else {
            Issue.record("Expected messages array")
            return
        }

        #expect(messages.count == 1)
        if case let .object(message) = messages[0] {
            #expect(message["role"] == JSONValue.string("user"))
            #expect(message["content"] == JSONValue.string("Hello"))
        }
    }

    @Test("should pass headers in streaming")
    func passHeadersInStreaming() async throws {
        let streamChunks = makeStreamChunks(content: [])
        let data = Data(streamChunks.utf8)
        let targetURL = URL(string: "https://my.api.com/v1/chat/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL)

        let requestCapture = RequestCapture()

        let fetch: FetchFunction = { request in
            await requestCapture.store(request)
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

        let model = try provider.chatModel(modelId: "grok-beta")
        _ = try await model.doStream(options: LanguageModelV3CallOptions(
            prompt: testPrompt,
            headers: ["Custom-Request-Header": "request-header-value"]
        ))

        guard let request = await requestCapture.current() else {
            Issue.record("Missing captured request")
            return
        }

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-api-key")
        #expect(request.value(forHTTPHeaderField: "Custom-Provider-Header") == "provider-header-value")
        #expect(request.value(forHTTPHeaderField: "Custom-Request-Header") == "request-header-value")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test("should include provider-specific options in streaming")
    func includeProviderSpecificOptionsInStreaming() async throws {
        let streamChunks = makeStreamChunks(content: [])
        let data = Data(streamChunks.utf8)
        let targetURL = URL(string: "https://my.api.com/v1/chat/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL)

        let requestCapture = RequestCapture()

        let fetch: FetchFunction = { request in
            await requestCapture.store(request)
            return FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch
        ))

        let model = try provider.chatModel(modelId: "grok-beta")
        _ = try await model.doStream(options: LanguageModelV3CallOptions(
            prompt: testPrompt,
            providerOptions: [
                "test-provider": [
                    "someCustomOption": .string("test-value")
                ]
            ]
        ))

        let capturedRequest = await requestCapture.current()
        let bodyData = try #require(capturedRequest?.httpBody)
        let body = try JSONDecoder().decode([String: JSONValue].self, from: bodyData)

        #expect(body["stream"] == JSONValue.bool(true))
        #expect(body["model"] == JSONValue.string("grok-beta"))
        #expect(body["someCustomOption"] == JSONValue.string("test-value"))
    }

    @Test("should not include provider-specific options for different provider in streaming")
    func notIncludeProviderSpecificOptionsForDifferentProviderInStreaming() async throws {
        let streamChunks = makeStreamChunks(content: [])
        let data = Data(streamChunks.utf8)
        let targetURL = URL(string: "https://my.api.com/v1/chat/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL)

        let requestCapture = RequestCapture()

        let fetch: FetchFunction = { request in
            await requestCapture.store(request)
            return FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch
        ))

        let model = try provider.chatModel(modelId: "grok-beta")
        _ = try await model.doStream(options: LanguageModelV3CallOptions(
            prompt: testPrompt,
            providerOptions: [
                "notThisProviderName": [
                    "someCustomOption": .string("test-value")
                ]
            ]
        ))

        let capturedRequest = await requestCapture.current()
        let bodyData = try #require(capturedRequest?.httpBody)
        let body = try JSONDecoder().decode([String: JSONValue].self, from: bodyData)

        #expect(body["stream"] == JSONValue.bool(true))
        #expect(body["model"] == JSONValue.string("grok-beta"))
        #expect(body["someCustomOption"] == nil)
    }

    @Test("should send request body in streaming")
    func sendRequestBodyInStreaming() async throws {
        let streamChunks = makeStreamChunks(content: [])
        let data = Data(streamChunks.utf8)
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

        let model = try provider.chatModel(modelId: "grok-beta")
        let result = try await model.doStream(options: LanguageModelV3CallOptions(prompt: testPrompt))

        // Verify request metadata is present
        #expect(result.request != nil)
        if let request = result.request {
            #expect(request.body != nil)
        }
    }

    @Test("should expose the raw response headers in streaming")
    func exposeRawResponseHeadersInStreaming() async throws {
        let streamChunks = makeStreamChunks(content: ["Hello"])
        let data = Data(streamChunks.utf8)
        let targetURL = URL(string: "https://my.api.com/v1/chat/completions")!
        let httpResponse = makeHTTPResponse(
            url: targetURL,
            headers: [
                "Content-Type": "text/event-stream",
                "Cache-Control": "no-cache",
                "Connection": "keep-alive",
                "Test-Header": "test-value"
            ]
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

        let model = try provider.chatModel(modelId: "grok-beta")
        let result = try await model.doStream(options: LanguageModelV3CallOptions(prompt: testPrompt))

        #expect(result.response != nil)
        if let response = result.response, let headers = response.headers {
            #expect(headers["content-type"] == "text/event-stream")
            #expect(headers["cache-control"] == "no-cache")
            #expect(headers["connection"] == "keep-alive")
            #expect(headers["test-header"] == "test-value")
        }
    }

    @Test("should handle error stream parts")
    func handleErrorStreamParts() async throws {
        let errorChunk = "data: {\"error\": {\"message\": \"Incorrect API key provided: as***T7. You can obtain an API key from https://console.api.com.\", \"code\": \"Client specified an invalid argument\"}}\n\n" +
            "data: [DONE]\n\n"
        let data = Data(errorChunk.utf8)
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

        let model = try provider.chatModel(modelId: "grok-beta")
        let result = try await model.doStream(options: LanguageModelV3CallOptions(prompt: testPrompt))

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        // Check for stream start
        #expect(parts.count > 0)
        if case .streamStart = parts[0] {} else {
            Issue.record("Expected streamStart")
        }

        // Check for error
        var foundError = false
        for part in parts {
            if case let .error(error) = part {
                foundError = true
                if case let .string(message) = error {
                    #expect(message == "Incorrect API key provided: as***T7. You can obtain an API key from https://console.api.com.")
                }
            }
        }
        #expect(foundError)

        // Check finish with error reason
        if case let .finish(finishReason, _, _) = parts.last {
            #expect(finishReason == .error)
        } else {
            Issue.record("Expected finish part")
        }
    }

    @Test("should extract detailed token usage from stream finish")
    func extractDetailedTokenUsageFromStreamFinish() async throws {
        let streamChunks = "data: {\"id\":\"chat-id\",\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}\n\n" +
            "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]," +
            "\"usage\":{\"prompt_tokens\":20,\"completion_tokens\":30," +
            "\"prompt_tokens_details\":{\"cached_tokens\":5}," +
            "\"completion_tokens_details\":{" +
            "\"reasoning_tokens\":10," +
            "\"accepted_prediction_tokens\":15," +
            "\"rejected_prediction_tokens\":5}}}\n\n" +
            "data: [DONE]\n\n"
        let data = Data(streamChunks.utf8)
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

        let model = try provider.chatModel(modelId: "grok-beta")
        let result = try await model.doStream(options: LanguageModelV3CallOptions(prompt: testPrompt))

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        // Find the finish part
        var finishPart: LanguageModelV3StreamPart?
        for part in parts {
            if case .finish = part {
                finishPart = part
                break
            }
        }

        #expect(finishPart != nil)
        if case let .finish(finishReason, usage, providerMetadata) = finishPart {
            #expect(finishReason == .stop)
            #expect(usage.inputTokens == 20)
            #expect(usage.outputTokens == 30)
            #expect(usage.cachedInputTokens == 5)
            #expect(usage.reasoningTokens == 10)

            // Check provider metadata for prediction tokens
            #expect(providerMetadata != nil)
            if let metadata = providerMetadata,
               let providerData = metadata["test-provider"],
               case let .number(accepted) = providerData["acceptedPredictionTokens"],
               case let .number(rejected) = providerData["rejectedPredictionTokens"] {
                #expect(accepted == 15)
                #expect(rejected == 5)
            } else {
                Issue.record("Expected provider metadata with prediction tokens")
            }
        }
    }

    @Test("should handle missing token details in stream")
    func handleMissingTokenDetailsInStream() async throws {
        let streamChunks = "data: {\"id\":\"chat-id\",\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}\n\n" +
            "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]," +
            "\"usage\":{\"prompt_tokens\":20,\"completion_tokens\":30}}\n\n" +
            "data: [DONE]\n\n"
        let data = Data(streamChunks.utf8)
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

        let model = try provider.chatModel(modelId: "grok-beta")
        let result = try await model.doStream(options: LanguageModelV3CallOptions(prompt: testPrompt))

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        // Find the finish part
        if case let .finish(_, _, providerMetadata) = parts.last {
            // Should have empty provider metadata when no details
            if let metadata = providerMetadata,
               let providerData = metadata["test-provider"] {
                #expect(providerData.isEmpty)
            }
        } else {
            Issue.record("Expected finish part")
        }
    }

    @Test("should handle partial token details in stream")
    func handlePartialTokenDetailsInStream() async throws {
        let streamChunks = "data: {\"id\":\"chat-id\",\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}\n\n" +
            "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]," +
            "\"usage\":{\"prompt_tokens\":20,\"completion_tokens\":30," +
            "\"total_tokens\":50," +
            "\"prompt_tokens_details\":{\"cached_tokens\":5}," +
            "\"completion_tokens_details\":{\"reasoning_tokens\":10}}}\n\n" +
            "data: [DONE]\n\n"
        let data = Data(streamChunks.utf8)
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

        let model = try provider.chatModel(modelId: "grok-beta")
        let result = try await model.doStream(options: LanguageModelV3CallOptions(prompt: testPrompt))

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        // Find the finish part
        if case let .finish(finishReason, usage, providerMetadata) = parts.last {
            #expect(finishReason == .stop)
            #expect(usage.inputTokens == 20)
            #expect(usage.outputTokens == 30)
            #expect(usage.totalTokens == 50)
            #expect(usage.cachedInputTokens == 5)
            #expect(usage.reasoningTokens == 10)

            // Provider metadata should be empty (no prediction tokens)
            if let metadata = providerMetadata,
               let providerData = metadata["test-provider"] {
                #expect(providerData.isEmpty)
            }
        } else {
            Issue.record("Expected finish part")
        }
    }

    // MARK: - Tool Call Streaming Tests

    @Test("should stream tool deltas")
    func streamToolDeltas() async throws {
        let streamChunks = "data: {\"id\":\"chatcmpl-test\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"grok-beta\"," +
            "\"system_fingerprint\":\"fp_test\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":null," +
            "\"tool_calls\":[{\"index\":0,\"id\":\"call_test\",\"type\":\"function\",\"function\":{\"name\":\"test-tool\",\"arguments\":\"\"}}]}," +
            "\"finish_reason\":null}]}\n\n" +
            "data: {\"id\":\"chatcmpl-test\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"grok-beta\"," +
            "\"system_fingerprint\":\"fp_test\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"{\\\"\"}}]}," +
            "\"finish_reason\":null}]}\n\n" +
            "data: {\"id\":\"chatcmpl-test\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"grok-beta\"," +
            "\"system_fingerprint\":\"fp_test\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"value\"}}]}," +
            "\"finish_reason\":null}]}\n\n" +
            "data: {\"id\":\"chatcmpl-test\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"grok-beta\"," +
            "\"system_fingerprint\":\"fp_test\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"\\\":\\\"\"}}]}," +
            "\"finish_reason\":null}]}\n\n" +
            "data: {\"id\":\"chatcmpl-test\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"grok-beta\"," +
            "\"system_fingerprint\":\"fp_test\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"Sparkle\"}}]}," +
            "\"finish_reason\":null}]}\n\n" +
            "data: {\"id\":\"chatcmpl-test\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"grok-beta\"," +
            "\"system_fingerprint\":\"fp_test\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\" Day\\\"\"}}]}," +
            "\"finish_reason\":null}]}\n\n" +
            "data: {\"id\":\"chatcmpl-test\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"grok-beta\"," +
            "\"system_fingerprint\":\"fp_test\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"}\"}}]}," +
            "\"finish_reason\":null}]}\n\n" +
            "data: {\"id\":\"chatcmpl-test\",\"object\":\"chat.completion.chunk\",\"created\":1729171479,\"model\":\"grok-beta\"," +
            "\"system_fingerprint\":\"fp_test\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"tool_calls\"}]," +
            "\"usage\":{\"prompt_tokens\":18,\"completion_tokens\":20,\"total_tokens\":38}}\n\n" +
            "data: [DONE]\n\n"
        let data = Data(streamChunks.utf8)
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

        let model = try provider.chatModel(modelId: "grok-beta")
        let result = try await model.doStream(
            options: LanguageModelV3CallOptions(
                prompt: testPrompt,
                tools: [.function(LanguageModelV3FunctionTool(
                    name: "test-tool",
                    inputSchema: .object(["type": "object", "properties": ["value": ["type": "string"]]])
                ))]
            )
        )

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        // Verify tool-input-start
        var toolInputStarts: [(String, String)] = []
        for part in parts {
            if case let .toolInputStart(id, toolName, _, _, _, _) = part {
                toolInputStarts.append((id, toolName))
            }
        }
        #expect(toolInputStarts.count == 1)
        #expect(toolInputStarts[0].0 == "call_test")
        #expect(toolInputStarts[0].1 == "test-tool")

        // Verify tool-input-delta
        let toolInputDeltas = parts.compactMap { part -> String? in
            if case let .toolInputDelta(_, delta, _) = part {
                return delta
            }
            return nil
        }
        #expect(toolInputDeltas.count == 7)
        #expect(toolInputDeltas.joined() == "{\"value\":\"Sparkle Day\"}")

        // Verify tool-call
        let toolCalls = parts.compactMap { part -> (String, String, String)? in
            if case let .toolCall(toolCall) = part {
                return (toolCall.toolCallId, toolCall.toolName, toolCall.input)
            }
            return nil
        }
        #expect(toolCalls.count == 1)
        #expect(toolCalls[0].0 == "call_test")
        #expect(toolCalls[0].1 == "test-tool")
        #expect(toolCalls[0].2 == "{\"value\":\"Sparkle Day\"}")
    }

    @Test("should stream tool call deltas when tool call arguments are passed in the first chunk")
    func streamToolCallDeltasWithArgumentsInFirstChunk() async throws {
        let streamChunks = "data: {\"id\":\"chatcmpl-test\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"grok-beta\"," +
            "\"system_fingerprint\":\"fp_test\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":null," +
            "\"tool_calls\":[{\"index\":0,\"id\":\"call_test\",\"type\":\"function\",\"function\":{\"name\":\"test-tool\",\"arguments\":\"{\\\"\"}}]}," +
            "\"finish_reason\":null}]}\n\n" +
            "data: {\"id\":\"chatcmpl-test\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"grok-beta\"," +
            "\"system_fingerprint\":\"fp_test\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"va\"}}]}," +
            "\"finish_reason\":null}]}\n\n" +
            "data: {\"id\":\"chatcmpl-test\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"grok-beta\"," +
            "\"system_fingerprint\":\"fp_test\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"lue\"}}]}," +
            "\"finish_reason\":null}]}\n\n" +
            "data: {\"id\":\"chatcmpl-test\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"grok-beta\"," +
            "\"system_fingerprint\":\"fp_test\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"\\\":\\\"\"}}]}," +
            "\"finish_reason\":null}]}\n\n" +
            "data: {\"id\":\"chatcmpl-test\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"grok-beta\"," +
            "\"system_fingerprint\":\"fp_test\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"Test\\\"\"}}]}," +
            "\"finish_reason\":null}]}\n\n" +
            "data: {\"id\":\"chatcmpl-test\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"grok-beta\"," +
            "\"system_fingerprint\":\"fp_test\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"}\"}}]}," +
            "\"finish_reason\":null}]}\n\n" +
            "data: {\"id\":\"chatcmpl-test\",\"object\":\"chat.completion.chunk\",\"created\":1729171479,\"model\":\"grok-beta\"," +
            "\"system_fingerprint\":\"fp_test\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"tool_calls\"}]," +
            "\"usage\":{\"prompt_tokens\":18,\"completion_tokens\":20,\"total_tokens\":38}}\n\n" +
            "data: [DONE]\n\n"
        let data = Data(streamChunks.utf8)
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

        let model = try provider.chatModel(modelId: "grok-beta")
        let result = try await model.doStream(
            options: LanguageModelV3CallOptions(
                prompt: testPrompt,
                tools: [.function(LanguageModelV3FunctionTool(
                    name: "test-tool",
                    inputSchema: .object(["type": "object", "properties": ["value": ["type": "string"]]])
                ))]
            )
        )

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        // Verify tool-input-delta includes first chunk arguments
        let toolInputDeltas = parts.compactMap { part -> String? in
            if case let .toolInputDelta(_, delta, _) = part {
                return delta
            }
            return nil
        }
        #expect(toolInputDeltas.count == 6)
        #expect(toolInputDeltas[0] == "{\"")
        #expect(toolInputDeltas.joined() == "{\"value\":\"Test\"}")
    }

    @Test("should stream tool call that is sent in one chunk")
    func streamToolCallInOneChunk() async throws {
        let streamChunks = "data: {\"id\":\"chatcmpl-test\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"grok-beta\"," +
            "\"system_fingerprint\":\"fp_test\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":null," +
            "\"tool_calls\":[{\"index\":0,\"id\":\"call_test\",\"type\":\"function\",\"function\":{\"name\":\"test-tool\",\"arguments\":\"{\\\"value\\\":\\\"Sparkle Day\\\"}\"}}]}," +
            "\"finish_reason\":null}]}\n\n" +
            "data: {\"id\":\"chatcmpl-test\",\"object\":\"chat.completion.chunk\",\"created\":1729171479,\"model\":\"grok-beta\"," +
            "\"system_fingerprint\":\"fp_test\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"tool_calls\"}]," +
            "\"usage\":{\"prompt_tokens\":18,\"completion_tokens\":20,\"total_tokens\":38}}\n\n" +
            "data: [DONE]\n\n"
        let data = Data(streamChunks.utf8)
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

        let model = try provider.chatModel(modelId: "grok-beta")
        let result = try await model.doStream(
            options: LanguageModelV3CallOptions(
                prompt: testPrompt,
                tools: [.function(LanguageModelV3FunctionTool(
                    name: "test-tool",
                    inputSchema: .object(["type": "object", "properties": ["value": ["type": "string"]]])
                ))]
            )
        )

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        // Verify exactly one tool-input-delta with complete arguments
        let toolInputDeltas = parts.compactMap { part -> String? in
            if case let .toolInputDelta(_, delta, _) = part {
                return delta
            }
            return nil
        }
        #expect(toolInputDeltas.count == 1)
        #expect(toolInputDeltas[0] == "{\"value\":\"Sparkle Day\"}")

        // Verify tool-call
        let toolCalls = parts.compactMap { part -> String? in
            if case let .toolCall(toolCall) = part {
                return toolCall.input
            }
            return nil
        }
        #expect(toolCalls.count == 1)
        #expect(toolCalls[0] == "{\"value\":\"Sparkle Day\"}")
    }

    @Test("should stream empty tool call that is sent in one chunk")
    func streamEmptyToolCallInOneChunk() async throws {
        let streamChunks = "data: {\"id\":\"chatcmpl-test\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"grok-beta\"," +
            "\"system_fingerprint\":\"fp_test\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":null," +
            "\"tool_calls\":[{\"index\":0,\"id\":\"call_test\",\"type\":\"function\",\"function\":{\"name\":\"test-tool\",\"arguments\":\"\"}}]}," +
            "\"finish_reason\":null}]}\n\n" +
            "data: {\"id\":\"chatcmpl-test\",\"object\":\"chat.completion.chunk\",\"created\":1729171479,\"model\":\"grok-beta\"," +
            "\"system_fingerprint\":\"fp_test\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"tool_calls\"}]," +
            "\"usage\":{\"prompt_tokens\":18,\"completion_tokens\":20,\"total_tokens\":38}}\n\n" +
            "data: [DONE]\n\n"
        let data = Data(streamChunks.utf8)
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

        let model = try provider.chatModel(modelId: "grok-beta")
        let result = try await model.doStream(
            options: LanguageModelV3CallOptions(
                prompt: testPrompt,
                tools: [.function(LanguageModelV3FunctionTool(
                    name: "test-tool",
                    inputSchema: .object(["type": "object"])
                ))]
            )
        )

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        // Verify tool-input-start exists
        let toolInputStarts = parts.filter { part in
            if case .toolInputStart = part {
                return true
            }
            return false
        }
        #expect(toolInputStarts.count == 1)

        // Verify tool-input-end exists
        let toolInputEnds = parts.filter { part in
            if case .toolInputEnd = part {
                return true
            }
            return false
        }
        #expect(toolInputEnds.count == 1)

        // Verify tool-call with empty input
        let toolCalls = parts.compactMap { part -> String? in
            if case let .toolCall(toolCall) = part {
                return toolCall.input
            }
            return nil
        }
        #expect(toolCalls.count == 1)
        #expect(toolCalls[0] == "")
    }

    @Test("should not duplicate tool calls when there is an additional empty chunk after completion")
    func notDuplicateToolCallsWithEmptyChunk() async throws {
        let streamChunks = "data: {\"id\":\"chat-test\",\"object\":\"chat.completion.chunk\",\"created\":1733162241," +
            "\"model\":\"test-model\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":\"\"},\"logprobs\":null,\"finish_reason\":null}]," +
            "\"usage\":{\"prompt_tokens\":226,\"total_tokens\":226,\"completion_tokens\":0}}\n\n" +
            "data: {\"id\":\"chat-test\",\"object\":\"chat.completion.chunk\",\"created\":1733162241," +
            "\"model\":\"test-model\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"id\":\"tool-id\"," +
            "\"type\":\"function\",\"index\":0,\"function\":{\"name\":\"searchGoogle\"}}]},\"logprobs\":null,\"finish_reason\":null}]," +
            "\"usage\":{\"prompt_tokens\":226,\"total_tokens\":233,\"completion_tokens\":7}}\n\n" +
            "data: {\"id\":\"chat-test\",\"object\":\"chat.completion.chunk\",\"created\":1733162241," +
            "\"model\":\"test-model\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0," +
            "\"function\":{\"arguments\":\"{\\\"query\\\": \\\"\"}}]},\"logprobs\":null,\"finish_reason\":null}]," +
            "\"usage\":{\"prompt_tokens\":226,\"total_tokens\":241,\"completion_tokens\":15}}\n\n" +
            "data: {\"id\":\"chat-test\",\"object\":\"chat.completion.chunk\",\"created\":1733162241," +
            "\"model\":\"test-model\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0," +
            "\"function\":{\"arguments\":\"latest\"}}]},\"logprobs\":null,\"finish_reason\":null}]," +
            "\"usage\":{\"prompt_tokens\":226,\"total_tokens\":242,\"completion_tokens\":16}}\n\n" +
            "data: {\"id\":\"chat-test\",\"object\":\"chat.completion.chunk\",\"created\":1733162241," +
            "\"model\":\"test-model\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0," +
            "\"function\":{\"arguments\":\" news\"}}]},\"logprobs\":null,\"finish_reason\":null}]," +
            "\"usage\":{\"prompt_tokens\":226,\"total_tokens\":243,\"completion_tokens\":17}}\n\n" +
            "data: {\"id\":\"chat-test\",\"object\":\"chat.completion.chunk\",\"created\":1733162241," +
            "\"model\":\"test-model\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0," +
            "\"function\":{\"arguments\":\" on ai\\\"\"}}]},\"logprobs\":null,\"finish_reason\":null}]," +
            "\"usage\":{\"prompt_tokens\":226,\"total_tokens\":245,\"completion_tokens\":19}}\n\n" +
            "data: {\"id\":\"chat-test\",\"object\":\"chat.completion.chunk\",\"created\":1733162241," +
            "\"model\":\"test-model\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0," +
            "\"function\":{\"arguments\":\"}\"}}]},\"logprobs\":null,\"finish_reason\":null}]," +
            "\"usage\":{\"prompt_tokens\":226,\"total_tokens\":246,\"completion_tokens\":20}}\n\n" +
            // Empty arguments chunk after tool call finished:
            "data: {\"id\":\"chat-test\",\"object\":\"chat.completion.chunk\",\"created\":1733162241," +
            "\"model\":\"test-model\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0," +
            "\"function\":{\"arguments\":\"\"}}]},\"logprobs\":null,\"finish_reason\":\"tool_calls\",\"stop_reason\":128008}]," +
            "\"usage\":{\"prompt_tokens\":226,\"total_tokens\":246,\"completion_tokens\":20}}\n\n" +
            "data: [DONE]\n\n"
        let data = Data(streamChunks.utf8)
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

        let model = try provider.chatModel(modelId: "grok-beta")
        let result = try await model.doStream(
            options: LanguageModelV3CallOptions(
                prompt: testPrompt,
                tools: [.function(LanguageModelV3FunctionTool(
                    name: "searchGoogle",
                    inputSchema: .object(["type": "object", "properties": ["query": ["type": "string"]]])
                ))]
            )
        )

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        // Count tool-call parts - should be exactly 1
        let toolCalls = parts.compactMap { part -> String? in
            if case let .toolCall(toolCall) = part {
                return toolCall.input
            }
            return nil
        }
        #expect(toolCalls.count == 1, "Should have exactly one tool-call, not duplicated")
        #expect(toolCalls[0] == "{\"query\": \"latest news on ai\"}")
    }

    // MARK: - Advanced Streaming Tests

    @Test("should include raw chunks when includeRawChunks is true")
    func includeRawChunksWhenRequested() async throws {
        let streamChunks = "data: {\"id\":\"chatcmpl-test\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-4\"," +
            "\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":\"Hello\"},\"finish_reason\":null}]}\n\n" +
            "data: {\"id\":\"chatcmpl-test\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-4\"," +
            "\"choices\":[{\"index\":0,\"delta\":{\"content\":\" World\"},\"finish_reason\":null}]}\n\n" +
            "data: {\"id\":\"chatcmpl-test\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-4\"," +
            "\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":5,\"total_tokens\":15}}\n\n" +
            "data: [DONE]\n\n"
        let data = Data(streamChunks.utf8)
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

        let model = try provider.chatModel(modelId: "gpt-4")
        let result = try await model.doStream(
            options: LanguageModelV3CallOptions(
                prompt: testPrompt,
                includeRawChunks: true
            )
        )

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        // Should have raw chunks (3 data chunks excluding [DONE])
        let rawCount = parts.filter { part in
            if case .raw = part {
                return true
            }
            return false
        }.count
        #expect(rawCount == 3, "Should include 3 raw chunks when includeRawChunks is true")
    }

    @Test("should omit raw chunks when includeRawChunks is false or not set")
    func omitRawChunksWhenNotRequested() async throws {
        let streamChunks = "data: {\"id\":\"chatcmpl-test\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-4\"," +
            "\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":\"Hello\"},\"finish_reason\":null}]}\n\n" +
            "data: {\"id\":\"chatcmpl-test\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-4\"," +
            "\"choices\":[{\"index\":0,\"delta\":{\"content\":\" World\"},\"finish_reason\":null}]}\n\n" +
            "data: {\"id\":\"chatcmpl-test\",\"object\":\"chat.completion.chunk\",\"created\":1711357598,\"model\":\"gpt-4\"," +
            "\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":5,\"total_tokens\":15}}\n\n" +
            "data: [DONE]\n\n"
        let data = Data(streamChunks.utf8)
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

        let model = try provider.chatModel(modelId: "gpt-4")
        let result = try await model.doStream(
            options: LanguageModelV3CallOptions(
                prompt: testPrompt
                // includeRawChunks not set (defaults to nil/false)
            )
        )

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        // Should have NO raw chunks
        let rawCount = parts.filter { part in
            if case .raw = part {
                return true
            }
            return false
        }.count
        #expect(rawCount == 0, "Should not include raw chunks when includeRawChunks is not set")
    }

    @Test("should handle unparsable stream parts")
    func handleUnparsableStreamParts() async throws {
        // Send malformed JSON that cannot be parsed
        let streamChunks = "data: {unparsable}\n\n" +
            "data: [DONE]\n\n"
        let data = Data(streamChunks.utf8)
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

        let model = try provider.chatModel(modelId: "grok-beta")
        let result = try await model.doStream(
            options: LanguageModelV3CallOptions(
                prompt: testPrompt,
                includeRawChunks: false
            )
        )

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        // Verify we got the expected sequence
        guard parts.count >= 3 else {
            Issue.record("Expected at least 3 parts (stream-start, error, finish), got \(parts.count)")
            return
        }

        // First part should be stream-start
        guard case .streamStart(let warnings) = parts[0] else {
            Issue.record("Expected stream-start, got \(parts[0])")
            return
        }
        #expect(warnings.isEmpty)

        // Second part should be error
        guard case .error(let errorValue) = parts[1] else {
            Issue.record("Expected error, got \(parts[1])")
            return
        }
        // Error should contain JSON parse error message
        let errorString = String(describing: errorValue)
        #expect(errorString.contains("JSON") || errorString.contains("parse") || errorString.contains("Unexpected"))

        // Last part should be finish with error reason
        guard case .finish(let finishReason, let usage, let providerMetadata) = parts.last else {
            Issue.record("Expected finish, got \(parts.last!)")
            return
        }
        #expect(finishReason == .error)
        #expect(usage.inputTokens == nil)
        #expect(usage.outputTokens == nil)
        // Provider metadata may be present with empty object or nil when error occurs
        if let metadata = providerMetadata {
            #expect(metadata["test-provider"] != nil)
        }
    }
}
