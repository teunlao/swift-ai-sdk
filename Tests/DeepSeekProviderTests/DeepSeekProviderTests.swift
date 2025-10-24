import Foundation
import Testing
@testable import DeepSeekProvider
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import OpenAICompatibleProvider

/**
 DeepSeek Provider tests.

 Port of `@ai-sdk/deepseek/src/deepseek-provider.test.ts`.
 */

@Suite("DeepSeekProvider")
struct DeepSeekProviderTests {

    // MARK: - Helper Methods

    static func encodeJSON(_ dict: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: dict)
    }

    // MARK: - createDeepSeek Tests

    @Test("should create a DeepSeekProvider instance with default options")
    func createDeepSeekProviderWithDefaultOptions() throws {
        let provider = createDeepSeek(settings: DeepSeekProviderSettings(
            apiKey: "test-api-key"
        ))

        let model = try provider("model-id")

        #expect(model is OpenAICompatibleChatLanguageModel)
        #expect(model.provider == "deepseek.chat")
    }

    @Test("should create a DeepSeekProvider instance with custom options")
    func createDeepSeekProviderWithCustomOptions() throws {
        let provider = createDeepSeek(settings: DeepSeekProviderSettings(
            apiKey: "custom-key",
            baseURL: "https://custom.url",
            headers: ["Custom-Header": "value"]
        ))

        let model = try provider("model-id")

        #expect(model is OpenAICompatibleChatLanguageModel)
        #expect(model.provider == "deepseek.chat")
    }

    @Test("should return a chat model when called as a function")
    func returnChatModelWhenCalledAsFunction() throws {
        let provider = createDeepSeek(settings: DeepSeekProviderSettings(
            apiKey: "test-api-key"
        ))
        let modelId = "foo-model-id"

        let model = try provider(modelId)

        #expect(model is OpenAICompatibleChatLanguageModel)
    }

    @Test("should include deepseek version in user-agent header")
    func includeDeepSeekVersionInUserAgentHeader() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "id": "test-id",
            "object": "chat.completion",
            "created": 1234567890,
            "model": "model-id",
            "choices": [[
                "index": 0,
                "message": [
                    "role": "assistant",
                    "content": "Hello"
                ],
                "finish_reason": "stop"
            ]],
            "usage": [
                "prompt_tokens": 10,
                "completion_tokens": 5,
                "total_tokens": 15
            ]
        ]

        let responseData = Self.encodeJSON(responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://api.deepseek.com/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let provider = createDeepSeek(settings: DeepSeekProviderSettings(
            apiKey: "test-api-key",
            fetch: fetch
        ))

        let model = try provider("model-id")
        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        _ = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: prompt))

        guard let request = await capture.value() else {
            Issue.record("Expected to capture request")
            return
        }

        let userAgent = request.value(forHTTPHeaderField: "User-Agent")
        #expect(userAgent?.contains("ai-sdk/deepseek") == true)
    }

    @Test("should throw NoSuchModelError when attempting to create embedding model")
    func throwNoSuchModelErrorForEmbeddingModel() throws {
        let provider = createDeepSeek(settings: DeepSeekProviderSettings(
            apiKey: "test-api-key"
        ))

        #expect(throws: NoSuchModelError.self) {
            _ = try provider.textEmbeddingModel(modelId: "any-model")
        }
    }

    // MARK: - chat Tests

    @Test("should construct a chat model with correct configuration")
    func constructChatModelWithCorrectConfiguration() throws {
        let provider = createDeepSeek(settings: DeepSeekProviderSettings(
            apiKey: "test-api-key"
        ))
        let modelId = DeepSeekChatModelId(rawValue: "deepseek-chat-model")

        let model = provider.chat(modelId)

        #expect(model is OpenAICompatibleChatLanguageModel)
    }
}
