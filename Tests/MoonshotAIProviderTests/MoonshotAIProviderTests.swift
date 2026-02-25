import Foundation
import Testing
@testable import MoonshotAIProvider
import AISDKProvider
import AISDKProviderUtils

private let moonshotTestPrompt: LanguageModelV3Prompt = [
    .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
]

private actor RequestCapture {
    private var request: URLRequest?
    func store(_ request: URLRequest) { self.request = request }
    func current() -> URLRequest? { request }
}

private func makeHTTPResponse(url: URL, contentType: String = "application/json") -> HTTPURLResponse {
    HTTPURLResponse(
        url: url,
        statusCode: 200,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": contentType]
    )!
}

private func makeMoonshotChatResponseData(usage: [String: Any]) throws -> Data {
    let response: [String: Any] = [
        "id": "chatcmpl-test",
        "created": 1_700_000_000,
        "model": "kimi-k2",
        "choices": [[
            "message": ["content": "Hi"],
            "finish_reason": "stop"
        ]],
        "usage": usage
    ]
    return try JSONSerialization.data(withJSONObject: response)
}

@Suite("MoonshotAIProvider", .serialized)
struct MoonshotAIProviderTests {
    @Test("default baseURL + Authorization injected from MOONSHOT_API_KEY")
    func defaultBaseURLAndAuthFromEnv() async throws {
        let original = getenv("MOONSHOT_API_KEY").flatMap { String(validatingCString: $0) }
        defer {
            if let original {
                setenv("MOONSHOT_API_KEY", original, 1)
            } else {
                unsetenv("MOONSHOT_API_KEY")
            }
        }

        setenv("MOONSHOT_API_KEY", "env-moonshot-key", 1)

        let capture = RequestCapture()
        let responseData = try makeMoonshotChatResponseData(usage: [
            "prompt_tokens": 1,
            "completion_tokens": 1,
            "total_tokens": 2,
        ])

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let url = request.url ?? URL(string: "https://api.moonshot.ai/v1/chat/completions")!
            return FetchResponse(body: .data(responseData), urlResponse: makeHTTPResponse(url: url))
        }

        let provider = createMoonshotAIProvider(settings: .init(fetch: fetch))
        let model = try provider.chatModel(modelId: MoonshotAIChatModelId.kimiK2.rawValue)
        _ = try await model.doGenerate(options: .init(prompt: moonshotTestPrompt))

        let request = await capture.current()
        #expect(request?.url?.absoluteString == "https://api.moonshot.ai/v1/chat/completions")

        let headers = (request?.allHTTPHeaderFields ?? [:]).reduce(into: [String: String]()) { result, entry in
            result[entry.key.lowercased()] = entry.value
        }

        #expect(headers["authorization"] == "Bearer env-moonshot-key")
        #expect((headers["user-agent"] ?? "").contains("ai-sdk/moonshotai/") == true)
    }

    @Test("does not override existing Authorization header")
    func doesNotOverrideAuthorization() async throws {
        let original = getenv("MOONSHOT_API_KEY").flatMap { String(validatingCString: $0) }
        defer {
            if let original {
                setenv("MOONSHOT_API_KEY", original, 1)
            } else {
                unsetenv("MOONSHOT_API_KEY")
            }
        }

        setenv("MOONSHOT_API_KEY", "env-moonshot-key", 1)

        let capture = RequestCapture()
        let responseData = try makeMoonshotChatResponseData(usage: [
            "prompt_tokens": 1,
            "completion_tokens": 1,
            "total_tokens": 2,
        ])

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let url = request.url ?? URL(string: "https://api.moonshot.ai/v1/chat/completions")!
            return FetchResponse(body: .data(responseData), urlResponse: makeHTTPResponse(url: url))
        }

        let provider = createMoonshotAIProvider(settings: .init(
            headers: ["Authorization": "Bearer custom-auth"],
            fetch: fetch
        ))

        let model = try provider.chatModel(modelId: MoonshotAIChatModelId.kimiK2.rawValue)
        _ = try await model.doGenerate(options: .init(prompt: moonshotTestPrompt))

        let request = await capture.current()
        let headers = (request?.allHTTPHeaderFields ?? [:]).reduce(into: [String: String]()) { result, entry in
            result[entry.key.lowercased()] = entry.value
        }

        #expect(headers["authorization"] == "Bearer custom-auth")
    }

    @Test("transformRequestBody converts thinking + reasoningHistory keys")
    func transformsThinkingAndReasoningHistory() async throws {
        let capture = RequestCapture()
        let responseData = try makeMoonshotChatResponseData(usage: [
            "prompt_tokens": 1,
            "completion_tokens": 1,
            "total_tokens": 2,
        ])

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let url = request.url ?? URL(string: "https://api.moonshot.ai/v1/chat/completions")!
            return FetchResponse(body: .data(responseData), urlResponse: makeHTTPResponse(url: url))
        }

        let provider = createMoonshotAIProvider(settings: .init(apiKey: "test-key", fetch: fetch))
        let model = try provider.chatModel(modelId: MoonshotAIChatModelId.kimiK2Thinking.rawValue)

        _ = try await model.doGenerate(options: .init(
            prompt: moonshotTestPrompt,
            providerOptions: [
                "moonshotai": [
                    "thinking": .object([
                        "type": .string("enabled"),
                        "budgetTokens": .number(2048),
                    ]),
                    "reasoningHistory": .string("interleaved"),
                ]
            ]
        ))

        let request = await capture.current()
        let bodyData = try #require(request?.httpBody)
        let body = try JSONDecoder().decode([String: JSONValue].self, from: bodyData)

        #expect(body["reasoningHistory"] == nil)
        #expect(body["reasoning_history"] == .string("interleaved"))

        guard case .object(let thinking)? = body["thinking"] else {
            Issue.record("Expected thinking object")
            return
        }
        #expect(thinking["type"] == .string("enabled"))
        #expect(thinking["budgetTokens"] == nil)
        #expect(thinking["budget_tokens"] == .number(2048))
    }

    @Test("MoonshotAI usage conversion uses cached_tokens when present")
    func usageConversionUsesCachedTokensTopLevel() async throws {
        let capture = RequestCapture()
        let responseData = try makeMoonshotChatResponseData(usage: [
            "prompt_tokens": 20,
            "completion_tokens": 30,
            "total_tokens": 50,
            "cached_tokens": 7,
            "prompt_tokens_details": ["cached_tokens": 5],
            "completion_tokens_details": ["reasoning_tokens": 10],
        ])

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let url = request.url ?? URL(string: "https://api.moonshot.ai/v1/chat/completions")!
            return FetchResponse(body: .data(responseData), urlResponse: makeHTTPResponse(url: url))
        }

        let provider = createMoonshotAIProvider(settings: .init(apiKey: "test-key", fetch: fetch))
        let model = try provider.chatModel(modelId: MoonshotAIChatModelId.kimiK2.rawValue)
        let result = try await model.doGenerate(options: .init(prompt: moonshotTestPrompt))

        #expect(result.usage.inputTokens.total == 20)
        #expect(result.usage.inputTokens.cacheRead == 7) // cached_tokens wins
        #expect(result.usage.inputTokens.noCache == 13)
        #expect(result.usage.outputTokens.reasoning == 10)
    }
}

