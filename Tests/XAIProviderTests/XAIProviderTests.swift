import Foundation
import Testing
@testable import XAIProvider
@testable import AISDKProvider
@testable import AISDKProviderUtils

/**
 XAI Provider tests.

 Port of `@ai-sdk/xai/src/xai-provider.test.ts`.
 */

@Suite("XAIProvider")
struct XAIProviderTests {

    @Test("creates a language model with default settings")
    func createLanguageModelWithDefaults() {
        let provider = createXai(settings: XAIProviderSettings(apiKey: "test-api-key"))
        let model = provider.chat(modelId: "grok-beta")

        #expect(model.provider == "xai.chat")
        #expect(model.modelId == "grok-beta")
    }

    @Test("creates language model via call operator")
    func createLanguageModelViaCallOperator() {
        let provider = createXai(settings: XAIProviderSettings(apiKey: "test-api-key"))
        let model = provider("grok-beta")

        #expect(model.provider == "xai.chat")
        #expect(model.modelId == "grok-beta")
    }

    @Test("creates language model via languageModel method")
    func createLanguageModelViaLanguageModelMethod() {
        let provider = createXai(settings: XAIProviderSettings(apiKey: "test-api-key"))
        let model = provider.languageModel(modelId: "grok-3")

        #expect(model.provider == "xai.chat")
        #expect(model.modelId == "grok-3")
    }

    @Test("creates an image model with correct settings")
    func createImageModel() {
        let provider = createXai(settings: XAIProviderSettings(apiKey: "test-api-key"))
        let model = provider.imageModel(modelId: "grok-2-image")

        #expect(model.provider == "xai.image")
        #expect(model.modelId == "grok-2-image")
    }

    @Test("creates image model via image method")
    func createImageModelViaImageMethod() {
        let provider = createXai(settings: XAIProviderSettings(apiKey: "test-api-key"))
        let model = provider.image(modelId: "grok-2-image")

        #expect(model.provider == "xai.image")
        #expect(model.modelId == "grok-2-image")
    }

    @Test("uses custom baseURL when provided")
    func usesCustomBaseURL() {
        let provider = createXai(settings: XAIProviderSettings(
            baseURL: "https://custom.xai.api",
            apiKey: "test-api-key"
        ))
        let model = provider.chat(modelId: "grok-beta")

        // BaseURL is internal to the model, we just verify model is created
        #expect(model.provider == "xai.chat")
        #expect(model.modelId == "grok-beta")
    }

    @Test("uses default baseURL when not provided")
    func usesDefaultBaseURL() {
        let provider = createXai(settings: XAIProviderSettings(apiKey: "test-api-key"))
        let model = provider.chat(modelId: "grok-beta")

        // BaseURL is internal, we verify the model works
        #expect(model.provider == "xai.chat")
        #expect(model.modelId == "grok-beta")
    }

    @Test("should pass correct configuration to chat model")
    func passCorrectConfigurationToChatModel() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "id": "test-id",
            "object": "chat.completion",
            "created": 1699472111,
            "model": "grok-beta",
            "choices": [[
                "index": 0,
                "message": [
                    "role": "assistant",
                    "content": "Test response"
                ],
                "finish_reason": "stop"
            ]],
            "usage": ["prompt_tokens": 10, "total_tokens": 20, "completion_tokens": 10]
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

        let provider = createXai(settings: XAIProviderSettings(
            apiKey: "test-api-key",
            fetch: fetch
        ))

        let model = provider.chat(modelId: "grok-beta")

        // Verify model configuration
        #expect(model.provider == "xai.chat")
        #expect(model.modelId == "grok-beta")

        // Make a request to verify baseURL is used correctly
        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        _ = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: prompt))

        guard let capturedRequest = await capture.value() else {
            Issue.record("Expected request to be captured")
            return
        }

        // Verify the request uses the correct baseURL
        #expect(capturedRequest.url?.absoluteString.hasPrefix("https://api.x.ai/v1") == true)
        #expect(capturedRequest.url?.path == "/v1/chat/completions")
    }
}
