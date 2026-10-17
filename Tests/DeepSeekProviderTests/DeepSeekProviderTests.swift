import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import DeepSeekProvider

@Suite("DeepSeek provider")
struct DeepSeekProviderTests {
    actor Capture {
        var request: URLRequest?
        func store(_ value: URLRequest) { request = value }
        func value() -> URLRequest? { request }
    }
    static let response: JSONValue = [
        "id": "response-1", "created": 123, "model": "deepseek-v4-flash", "object": "chat.completion",
        "choices": [["index": 0, "message": ["role": "assistant", "content": "Answer", "reasoning_content": "Reason"], "finish_reason": "stop"]],
        "usage": ["prompt_tokens": 10, "completion_tokens": 3, "prompt_cache_hit_tokens": 4,
                  "completion_tokens_details": ["reasoning_tokens": 5], "custom": 8]
    ]
    static func fetch(_ response: JSONValue = response, capture: Capture? = nil) throws -> FetchFunction {
        let data = try JSONEncoder().encode(response)
        return { request in
            await capture?.store(request)
            return FetchResponse(body: .data(data), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        }
    }
    static func body(_ capture: Capture) async throws -> JSONValue {
        let request = try #require(await capture.value())
        return try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
    }
    static func object(_ value: JSONValue) -> [String: JSONValue] {
        guard case .object(let object) = value else { return [:] }
        return object
    }
    static let prompt: LanguageModelV4Prompt = [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)]

    @Test func nativeResponsePreservesUsageAndSafeMetadata() async throws {
        let model = createDeepSeek(settings: .init(apiKey: "key", fetch: try Self.fetch()))("deepseek-v4-flash")
        let result = try await model.doGenerate(options: .init(prompt: Self.prompt))
        #expect(result.content == [.reasoning(.init(text: "Reason")), .text(.init(text: "Answer"))])
        #expect(result.usage.inputTokens.total == 10)
        #expect(result.usage.inputTokens.cacheRead == 4)
        #expect(result.usage.outputTokens.text == 0)
        #expect(result.usage.raw == Self.object(Self.response)["usage"])
        #expect(result.providerMetadata?["deepseek"] == ["promptCacheHitTokens": 4, "responseObject": "chat.completion", "choiceIndex": 0, "messageRole": "assistant"])
        _ = try JSONEncoder().encode(result.providerMetadata)
    }

    @Test func requestUsesThinkingDefaultsAndMapsProviderSettings() async throws {
        let capture = Capture()
        let model = createDeepSeek(settings: .init(apiKey: "key", fetch: try Self.fetch(capture: capture)))("deepseek-v4-flash")
        let result = try await model.doGenerate(options: .init(prompt: Self.prompt, temperature: 0.5, topP: 0.8,
                                                              frequencyPenalty: 1, reasoning: .medium,
                                                              providerOptions: ["deepseek": ["topLogprobs": 2, "userId": "user_1"]]))
        let body = Self.object(try await Self.body(capture))
        #expect(body["thinking"] == ["type": "enabled"])
        #expect(body["reasoning_effort"] == "high")
        #expect(body["logprobs"] == true)
        #expect(body["top_logprobs"] == 2)
        #expect(body["user_id"] == "user_1")
        #expect(body["temperature"] == nil)
        #expect(body["top_p"] == nil)
        #expect(body["frequency_penalty"] == nil)
        #expect(result.warnings.contains { if case .deprecated(setting: "frequencyPenalty", message: _) = $0 { return true }; return false })
    }

    @Test func azureCapabilitiesControlRequest() async throws {
        let capture = Capture()
        let model = DeepSeekChatLanguageModel(modelId: "deployment", config: .init(provider: "azure.deepseek", url: { "https://azure.example\($0.path)" },
                                                                                 fetch: try Self.fetch(capture: capture), supportsPenaltySampling: true,
                                                                                 supportsThinking: false, supportsStructuredOutputs: true))
        _ = try await model.doGenerate(options: .init(prompt: Self.prompt, temperature: 0.4, frequencyPenalty: 0.2,
                                                     responseFormat: .json(schema: ["type": "object"], name: "value", description: nil),
                                                     providerOptions: ["azure": ["thinking": ["type": "enabled"]]]))
        let body = Self.object(try await Self.body(capture))
        #expect(body["temperature"] == 0.4)
        #expect(body["frequency_penalty"] == 0.2)
        #expect(body["thinking"] == nil)
        #expect(body["response_format"] == ["type": "json_schema", "json_schema": ["schema": ["type": "object"], "strict": true, "name": "value"]])
    }

    @Test func betaPrefixAndStrictToolsUseBetaEndpoint() async throws {
        let capture = Capture()
        let provider = createDeepSeek(settings: .init(apiKey: "key", baseURL: "https://api.deepseek.com/beta/", fetch: try Self.fetch(capture: capture)))
        let prompt: LanguageModelV4Prompt = [.assistant(content: [.text(.init(text: "Start"))], providerOptions: ["deepseek": ["prefix": true, "name": "writer"]])]
        _ = try await provider("deepseek-v4-pro").doGenerate(options: .init(prompt: prompt, tools: [.function(.init(name: "lookup", inputSchema: ["type": "object"], strict: true))]))
        let body = Self.object(try await Self.body(capture))
        #expect(body["messages"] == [["role": "assistant", "content": "Start", "name": "writer", "prefix": true, "reasoning_content": ""]])
        #expect(await capture.value()?.url?.absoluteString == "https://api.deepseek.com/beta/chat/completions")
        let normal = createDeepSeek(settings: .init(apiKey: "key", fetch: try Self.fetch()))("deepseek-v4-pro")
        await #expect(throws: UnsupportedFunctionalityError.self) {
            _ = try await normal.doGenerate(options: .init(prompt: prompt))
        }
    }

    @Test(arguments: ["invalid value", "user\n"])
    func invalidOptionsFailBeforeSending(userId: String) async throws {
        let capture = Capture()
        let model = createDeepSeek(settings: .init(apiKey: "key", fetch: try Self.fetch(capture: capture)))("deepseek-v4-flash")
        await #expect(throws: InvalidArgumentError.self) {
            _ = try await model.doGenerate(options: .init(prompt: Self.prompt, providerOptions: ["deepseek": ["userId": .string(userId)]]))
        }
        #expect(await capture.value() == nil)
    }

    @Test func customHeadersAndUserAgentReachHTTP() async throws {
        let capture = Capture()
        let provider = createDeepSeek(settings: .init(apiKey: "key", baseURL: "https://custom.example/", headers: ["authorization": "custom", "X-Custom": "value"], fetch: try Self.fetch(capture: capture)))
        _ = try await provider("deepseek-chat").doGenerate(options: .init(prompt: Self.prompt))
        let request = try #require(await capture.value())
        #expect(request.value(forHTTPHeaderField: "Authorization") == "custom")
        #expect(request.value(forHTTPHeaderField: "X-Custom") == "value")
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("ai-sdk-deepseek/") == true)
        #expect(request.url?.absoluteString == "https://custom.example/chat/completions")
    }

    @Suite(.serialized) struct Authentication {
        @Test func authorizationStillRequiresConfiguredKey() async throws {
            let previous = getenv("DEEPSEEK_API_KEY").flatMap { String(validatingCString: $0) }
            defer { if let previous { setenv("DEEPSEEK_API_KEY", previous, 1) } else { unsetenv("DEEPSEEK_API_KEY") } }
            unsetenv("DEEPSEEK_API_KEY")
            let model = createDeepSeek(settings: .init(headers: ["Authorization": "custom"], fetch: try DeepSeekProviderTests.fetch()))("deepseek-chat")
            await #expect(throws: LoadAPIKeyError.self) {
                _ = try await model.doGenerate(options: .init(prompt: DeepSeekProviderTests.prompt))
            }
        }
    }
}
