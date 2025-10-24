import Foundation
import Testing
@testable import CerebrasProvider
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import OpenAICompatibleProvider

/**
 Cerebras Provider tests.

 Port of `@ai-sdk/cerebras/src/cerebras-provider.test.ts`.
 */

@Suite("CerebrasProvider")
struct CerebrasProviderTests {

    // MARK: - Helper Methods

    static func encodeJSON(_ dict: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: dict)
    }

    // MARK: - createCerebras Tests

    @Test("should create a CerebrasProvider instance with default options")
    func createCerebrasProviderWithDefaultOptions() throws {
        let provider = createCerebras(settings: CerebrasProviderSettings(
            apiKey: "test-api-key"
        ))

        let model = try provider("model-id")

        #expect(model is OpenAICompatibleChatLanguageModel)
        #expect(model.provider == "cerebras.chat")
    }

    @Test("should create a CerebrasProvider instance with custom options")
    func createCerebrasProviderWithCustomOptions() throws {
        let provider = createCerebras(settings: CerebrasProviderSettings(
            apiKey: "custom-key",
            baseURL: "https://custom.url",
            headers: ["Custom-Header": "value"]
        ))

        let model = try provider("model-id")

        #expect(model is OpenAICompatibleChatLanguageModel)
        #expect(model.provider == "cerebras.chat")
    }

    @Test("should pass header")
    func passHeader() async throws {
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
            url: URL(string: "https://api.cerebras.ai/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let provider = createCerebras(settings: CerebrasProviderSettings(
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
        #expect(userAgent?.contains("ai-sdk/cerebras") == true)
    }

    @Test("should return a chat model when called as a function")
    func returnChatModelWhenCalledAsFunction() throws {
        let provider = createCerebras(settings: CerebrasProviderSettings(
            apiKey: "test-api-key"
        ))
        let modelId = "foo-model-id"

        let model = try provider(modelId)

        #expect(model is OpenAICompatibleChatLanguageModel)
    }

    // MARK: - languageModel Tests

    @Test("should construct a language model with correct configuration")
    func constructLanguageModelWithCorrectConfiguration() throws {
        let provider = createCerebras(settings: CerebrasProviderSettings(
            apiKey: "test-api-key"
        ))
        let modelId = "foo-model-id"

        let model = try provider.languageModel(modelId: modelId)

        #expect(model is OpenAICompatibleChatLanguageModel)
    }

    // MARK: - textEmbeddingModel Tests

    @Test("should throw NoSuchModelError when attempting to create embedding model")
    func throwNoSuchModelErrorForEmbeddingModel() throws {
        let provider = createCerebras(settings: CerebrasProviderSettings(
            apiKey: "test-api-key"
        ))

        #expect(throws: NoSuchModelError.self) {
            _ = try provider.textEmbeddingModel(modelId: "any-model")
        }
    }

    // MARK: - chat Tests

    @Test("should construct a chat model with correct configuration")
    func constructChatModelWithCorrectConfiguration() throws {
        let provider = createCerebras(settings: CerebrasProviderSettings(
            apiKey: "test-api-key"
        ))
        let modelId = CerebrasChatModelId(rawValue: "foo-model-id")

        let model = provider.chat(modelId)

        #expect(model is OpenAICompatibleChatLanguageModel)
    }
}
