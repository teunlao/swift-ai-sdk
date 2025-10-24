import Foundation
import Testing
@testable import BasetenProvider
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import OpenAICompatibleProvider

/**
 Baseten Provider tests.

 Port of `@ai-sdk/baseten/src/baseten-provider.unit.test.ts`.
 */

@Suite("BasetenProvider")
struct BasetenProviderTests {

    // MARK: - Helper Methods

    static func encodeJSON(_ dict: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: dict)
    }

    // MARK: - createBaseten Tests

    @Test("should create a BasetenProvider instance with default options")
    func createBasetenProviderWithDefaultOptions() throws {
        let provider = createBaseten(settings: BasetenProviderSettings(
            apiKey: "test-api-key"
        ))
        let model = try provider.chatModel(modelId: "deepseek-ai/DeepSeek-V3-0324")

        #expect(model is OpenAICompatibleChatLanguageModel)
        #expect(model.provider == "baseten.chat")
    }

    @Test("should create a BasetenProvider instance with custom options")
    func createBasetenProviderWithCustomOptions() throws {
        let provider = createBaseten(settings: BasetenProviderSettings(
            apiKey: "custom-key",
            baseURL: "https://custom.url",
            headers: ["Custom-Header": "value"]
        ))
        let model = try provider.chatModel(modelId: "deepseek-ai/DeepSeek-V3-0324")

        #expect(model is OpenAICompatibleChatLanguageModel)
        #expect(model.provider == "baseten.chat")
    }

    @Test("should support optional modelId parameter")
    func supportOptionalModelIdParameter() throws {
        let provider = createBaseten(settings: BasetenProviderSettings(
            apiKey: "test-api-key"
        ))

        // Should work without modelId
        let model1 = try provider.chat()
        #expect(model1 is OpenAICompatibleChatLanguageModel)

        // Should work with modelId
        let model2 = try provider("deepseek-ai/DeepSeek-V3-0324")
        #expect(model2 is OpenAICompatibleChatLanguageModel)
    }

    // MARK: - chatModel Tests

    @Test("should construct a chat model with correct configuration for default Model APIs")
    func constructChatModelWithCorrectConfigurationForDefaultModelAPIs() throws {
        let provider = createBaseten(settings: BasetenProviderSettings(
            apiKey: "test-api-key"
        ))
        let modelId = "deepseek-ai/DeepSeek-V3-0324"

        let model = try provider.chatModel(modelId: modelId)

        #expect(model is OpenAICompatibleChatLanguageModel)
        #expect(model.provider == "baseten.chat")
    }

    @Test("should construct a chat model with optional modelId")
    func constructChatModelWithOptionalModelId() throws {
        let provider = createBaseten(settings: BasetenProviderSettings(
            apiKey: "test-api-key"
        ))

        // Should work without modelId
        let model1 = try provider.chat()
        #expect(model1 is OpenAICompatibleChatLanguageModel)

        // Should work with modelId
        let model2 = try provider.chatModel(modelId: "deepseek-ai/DeepSeek-V3-0324")
        #expect(model2 is OpenAICompatibleChatLanguageModel)
    }

    @Test("should handle /sync/v1 endpoints correctly")
    func handleSyncV1EndpointsCorrectly() throws {
        let provider = createBaseten(settings: BasetenProviderSettings(
            apiKey: "test-api-key",
            modelURL: "https://model-123.api.baseten.co/environments/production/sync/v1"
        ))

        let model = try provider.chat()

        #expect(model is OpenAICompatibleChatLanguageModel)
        #expect(model.provider == "baseten.chat")
    }

    @Test("should throw error for /predict endpoints with chat models")
    func throwErrorForPredictEndpointsWithChatModels() throws {
        let provider = createBaseten(settings: BasetenProviderSettings(
            apiKey: "test-api-key",
            modelURL: "https://model-123.api.baseten.co/environments/production/predict"
        ))

        #expect(throws: (any Error).self) {
            _ = try provider.chat()
        }
    }

    // MARK: - languageModel Tests

    @Test("should be an alias for chatModel")
    func shouldBeAnAliasForChatModel() throws {
        let provider = createBaseten(settings: BasetenProviderSettings(
            apiKey: "test-api-key"
        ))
        let modelId = "deepseek-ai/DeepSeek-V3-0324"

        let chatModel = try provider.chatModel(modelId: modelId)
        let languageModel = try provider.languageModel(modelId: modelId)

        #expect(chatModel is OpenAICompatibleChatLanguageModel)
        #expect(languageModel is OpenAICompatibleChatLanguageModel)
    }

    @Test("should support optional modelId parameter")
    func languageModelShouldSupportOptionalModelIdParameter() throws {
        let provider = createBaseten(settings: BasetenProviderSettings(
            apiKey: "test-api-key"
        ))

        let model1 = try provider.languageModel()
        #expect(model1 is OpenAICompatibleChatLanguageModel)

        let model2 = try provider.languageModel(modelId: "deepseek-ai/DeepSeek-V3-0324")
        #expect(model2 is OpenAICompatibleChatLanguageModel)
    }

    // MARK: - textEmbeddingModel Tests

    @Test("should throw error when no modelURL is provided")
    func throwErrorWhenNoModelURLIsProvided() throws {
        let provider = createBaseten(settings: BasetenProviderSettings(
            apiKey: "test-api-key"
        ))

        #expect(throws: (any Error).self) {
            _ = try provider.textEmbeddingModel()
        }
    }

    @Test("should construct embedding model for /sync endpoints")
    func constructEmbeddingModelForSyncEndpoints() throws {
        let provider = createBaseten(settings: BasetenProviderSettings(
            apiKey: "test-api-key",
            modelURL: "https://model-123.api.baseten.co/environments/production/sync"
        ))

        let model = try provider.textEmbeddingModel()

        #expect(model is BasetenEmbeddingModel)
        #expect(model.provider == "baseten.embedding")
    }

    @Test("should throw error for /predict endpoints (not supported with Performance Client)")
    func throwErrorForPredictEndpointsNotSupportedWithPerformanceClient() throws {
        let provider = createBaseten(settings: BasetenProviderSettings(
            apiKey: "test-api-key",
            modelURL: "https://model-123.api.baseten.co/environments/production/predict"
        ))

        #expect(throws: (any Error).self) {
            _ = try provider.textEmbeddingModel()
        }
    }

    @Test("should support /sync/v1 endpoints (strips /v1 before passing to Performance Client)")
    func supportSyncV1EndpointsStripsV1BeforePassingToPerformanceClient() throws {
        let provider = createBaseten(settings: BasetenProviderSettings(
            apiKey: "test-api-key",
            modelURL: "https://model-123.api.baseten.co/environments/production/sync/v1"
        ))

        let model = try provider.textEmbeddingModel()

        #expect(model is BasetenEmbeddingModel)
        #expect(model.provider == "baseten.embedding")
    }

    @Test("should support custom modelId for embeddings")
    func supportCustomModelIdForEmbeddings() throws {
        let provider = createBaseten(settings: BasetenProviderSettings(
            apiKey: "test-api-key",
            modelURL: "https://model-123.api.baseten.co/environments/production/sync"
        ))

        let model = try provider.textEmbeddingModel()

        #expect(model is BasetenEmbeddingModel)
        #expect(model.provider == "baseten.embedding")
    }

    // MARK: - imageModel Tests

    @Test("should throw NoSuchModelError for unsupported image models")
    func throwNoSuchModelErrorForUnsupportedImageModels() throws {
        let provider = createBaseten(settings: BasetenProviderSettings(
            apiKey: "test-api-key"
        ))

        #expect(throws: NoSuchModelError.self) {
            _ = try provider.imageModel(modelId: "test-model")
        }
    }

    // MARK: - URL construction Tests

    @Test("should use default baseURL when no modelURL is provided")
    func useDefaultBaseURLWhenNoModelURLIsProvided() async throws {
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
            "model": "test-model",
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
            url: URL(string: "https://inference.baseten.co/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let provider = createBaseten(settings: BasetenProviderSettings(
            apiKey: "test-api-key",
            fetch: fetch
        ))

        let model = try provider.chatModel(modelId: "test-model")
        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        _ = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: prompt))

        guard let request = await capture.value(),
              let url = request.url else {
            Issue.record("Expected to capture request with URL")
            return
        }

        #expect(url.absoluteString.contains("https://inference.baseten.co/v1/chat/completions"))
    }

    @Test("should use custom baseURL when provided")
    func useCustomBaseURLWhenProvided() async throws {
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
            "model": "test-model",
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
            url: URL(string: "https://custom.baseten.co/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let provider = createBaseten(settings: BasetenProviderSettings(
            apiKey: "test-api-key",
            baseURL: "https://custom.baseten.co/v1",
            fetch: fetch
        ))

        let model = try provider.chatModel(modelId: "test-model")
        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        _ = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: prompt))

        guard let request = await capture.value(),
              let url = request.url else {
            Issue.record("Expected to capture request with URL")
            return
        }

        #expect(url.absoluteString.contains("https://custom.baseten.co/v1/chat/completions"))
    }

    @Test("should use modelURL for custom endpoints")
    func useModelURLForCustomEndpoints() async throws {
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
            "model": "placeholder",
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
            url: URL(string: "https://model-123.api.baseten.co/environments/production/sync/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let provider = createBaseten(settings: BasetenProviderSettings(
            apiKey: "test-api-key",
            modelURL: "https://model-123.api.baseten.co/environments/production/sync/v1",
            fetch: fetch
        ))

        let model = try provider.chat()
        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        _ = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: prompt))

        guard let request = await capture.value(),
              let url = request.url else {
            Issue.record("Expected to capture request with URL")
            return
        }

        #expect(url.absoluteString.contains("https://model-123.api.baseten.co/environments/production/sync/v1/chat/completions"))
    }

    // MARK: - Headers Tests

    @Test("should include Authorization header with API key")
    func includeAuthorizationHeaderWithAPIKey() async throws {
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
            "model": "test-model",
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
            url: URL(string: "https://inference.baseten.co/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let provider = createBaseten(settings: BasetenProviderSettings(
            apiKey: "test-api-key",
            fetch: fetch
        ))

        let model = try provider.chatModel(modelId: "test-model")
        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        _ = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: prompt))

        guard let request = await capture.value() else {
            Issue.record("Expected to capture request")
            return
        }

        let authorization = request.value(forHTTPHeaderField: "Authorization")
        #expect(authorization?.contains("Bearer") == true)
    }

    @Test("should include custom headers when provided")
    func includeCustomHeadersWhenProvided() async throws {
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
            "model": "test-model",
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
            url: URL(string: "https://inference.baseten.co/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let provider = createBaseten(settings: BasetenProviderSettings(
            apiKey: "test-api-key",
            headers: ["Custom-Header": "custom-value"],
            fetch: fetch
        ))

        let model = try provider.chatModel(modelId: "test-model")
        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        _ = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: prompt))

        guard let request = await capture.value() else {
            Issue.record("Expected to capture request")
            return
        }

        let customHeader = request.value(forHTTPHeaderField: "Custom-Header")
        #expect(customHeader == "custom-value")
    }

    @Test("should include user-agent with version")
    func includeUserAgentWithVersion() async throws {
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
            "model": "test-model",
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
            url: URL(string: "https://inference.baseten.co/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let provider = createBaseten(settings: BasetenProviderSettings(
            apiKey: "test-api-key",
            fetch: fetch
        ))

        let model = try provider.chatModel(modelId: "test-model")
        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
        ]

        _ = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: prompt))

        guard let request = await capture.value() else {
            Issue.record("Expected to capture request")
            return
        }

        let userAgent = request.value(forHTTPHeaderField: "User-Agent")
        #expect(userAgent?.contains("ai-sdk/baseten") == true)
    }

    // MARK: - Error handling Tests

    @Test("should handle missing modelURL for embeddings gracefully")
    func handleMissingModelURLForEmbeddingsGracefully() throws {
        let provider = createBaseten(settings: BasetenProviderSettings(
            apiKey: "test-api-key"
        ))

        #expect(throws: (any Error).self) {
            _ = try provider.textEmbeddingModel()
        }
    }

    @Test("should handle unsupported image models")
    func handleUnsupportedImageModels() throws {
        let provider = createBaseten(settings: BasetenProviderSettings(
            apiKey: "test-api-key"
        ))

        #expect(throws: NoSuchModelError.self) {
            _ = try provider.imageModel(modelId: "unsupported-model")
        }
    }

    // MARK: - Provider interface Tests

    @Test("should implement all required provider methods")
    func implementAllRequiredProviderMethods() throws {
        let provider = createBaseten(settings: BasetenProviderSettings(
            apiKey: "test-api-key"
        ))

        // Provider should be callable
        _ = try provider.chat()
        _ = try provider("test-model")

        // All methods should exist and be callable
        _ = try provider.chatModel(modelId: "test-model")
        _ = try provider.languageModel()

        #expect(throws: (any Error).self) {
            _ = try provider.textEmbeddingModel()
        }

        #expect(throws: NoSuchModelError.self) {
            _ = try provider.imageModel(modelId: "test")
        }
    }

    @Test("should allow calling provider as function")
    func allowCallingProviderAsFunction() throws {
        let provider = createBaseten(settings: BasetenProviderSettings(
            apiKey: "test-api-key"
        ))

        let model1 = try provider.chat()
        #expect(model1 is OpenAICompatibleChatLanguageModel)

        let model2 = try provider("test-model")
        #expect(model2 is OpenAICompatibleChatLanguageModel)
    }
}
