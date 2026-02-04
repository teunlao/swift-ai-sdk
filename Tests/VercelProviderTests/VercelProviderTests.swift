import Foundation
import Testing
@testable import VercelProvider
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import OpenAICompatibleProvider

/**
 Vercel Provider tests.

 Port of `packages/vercel/src/vercel-provider.test.ts`.
 */
@Suite("VercelProvider")
struct VercelProviderTests {
    // MARK: - Helpers

    static func encodeJSON(_ dict: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: dict)
    }

    // MARK: - createVercel

    @Test("should create a VercelProvider instance with default options")
    func createVercelWithDefaultOptions() throws {
        let provider = createVercel(settings: VercelProviderSettings(apiKey: "test-api-key"))

        let model = try provider("model-id")

        #expect(model is OpenAICompatibleChatLanguageModel)
        #expect(model.provider == "vercel.chat")
    }

    @Test("should create a VercelProvider instance with custom options")
    func createVercelWithCustomOptions() throws {
        let provider = createVercel(settings: VercelProviderSettings(
            apiKey: "custom-key",
            baseURL: "https://custom.url",
            headers: ["Custom-Header": "value"]
        ))

        let model = try provider("model-id")

        #expect(model is OpenAICompatibleChatLanguageModel)
        #expect(model.provider == "vercel.chat")
    }

    @Test("should return a chat model when called as a function")
    func returnChatModelWhenCalledAsFunction() throws {
        let provider = createVercel(settings: VercelProviderSettings(apiKey: "test-api-key"))

        let model = try provider("foo-model-id")

        #expect(model is OpenAICompatibleChatLanguageModel)
    }

    @Test("should include vercel version in user-agent header")
    func includeVercelVersionInUserAgentHeader() async throws {
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
                    "content": "Hello",
                ],
                "finish_reason": "stop",
            ]],
            "usage": [
                "prompt_tokens": 10,
                "completion_tokens": 5,
                "total_tokens": 15,
            ],
        ]

        let responseData = Self.encodeJSON(responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://api.v0.dev/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let provider = createVercel(settings: VercelProviderSettings(apiKey: "test-api-key", fetch: fetch))
        let model = try provider("model-id")

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil),
        ]

        _ = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: prompt))

        guard let request = await capture.value() else {
            Issue.record("Expected to capture request")
            return
        }

        let userAgent = request.value(forHTTPHeaderField: "User-Agent")
        #expect(userAgent?.contains("ai-sdk/vercel") == true)
    }

    // MARK: - Unsupported models

    @Test("should throw NoSuchModelError when attempting to create embedding model")
    func throwNoSuchModelErrorForEmbeddingModel() throws {
        let provider = createVercel(settings: VercelProviderSettings(apiKey: "test-api-key"))

        #expect(throws: NoSuchModelError.self) {
            _ = try provider.textEmbeddingModel(modelId: "any-model")
        }
    }

    @Test("should throw NoSuchModelError when attempting to create image model")
    func throwNoSuchModelErrorForImageModel() throws {
        let provider = createVercel(settings: VercelProviderSettings(apiKey: "test-api-key"))

        #expect(throws: NoSuchModelError.self) {
            _ = try provider.imageModel(modelId: "any-model")
        }
    }

    // MARK: - languageModel

    @Test("should construct a language model with correct configuration")
    func constructLanguageModelWithCorrectConfiguration() throws {
        let provider = createVercel(settings: VercelProviderSettings(apiKey: "test-api-key"))

        let model: any LanguageModelV3 = provider.languageModel(VercelChatModelId(rawValue: "vercel-chat-model"))

        #expect(model is OpenAICompatibleChatLanguageModel)
        #expect(model.provider == "vercel.chat")
    }

    @Test("should construct requests using custom baseURL without trailing slash")
    func constructRequestsUsingCustomBaseURL() async throws {
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
                    "content": "Hello",
                ],
                "finish_reason": "stop",
            ]],
            "usage": [
                "prompt_tokens": 10,
                "completion_tokens": 5,
                "total_tokens": 15,
            ],
        ]

        let responseData = Self.encodeJSON(responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://custom.url/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let provider = createVercel(settings: VercelProviderSettings(
            apiKey: "test-api-key",
            baseURL: "https://custom.url/",
            headers: ["Custom-Header": "value"],
            fetch: fetch
        ))

        let model = try provider("model-id")
        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil),
        ]

        _ = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: prompt))

        guard let request = await capture.value() else {
            Issue.record("Expected to capture request")
            return
        }

        #expect(request.url?.absoluteString == "https://custom.url/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Custom-Header") == "value")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-api-key")
    }
}
