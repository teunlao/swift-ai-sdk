import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import DeepInfraProvider

@Suite("DeepInfraProvider")
struct DeepInfraProviderTests {
    private static func encodeJSON(_ dict: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: dict)
    }

    @Test("supports upstream createDeepInfra alias")
    func supportsCreateDeepInfraAlias() throws {
        let provider = createDeepInfra(settings: DeepInfraProviderSettings(apiKey: "test-key"))
        let model = try provider.languageModel(modelId: DeepInfraChatModelId.deepinfraAiroboros70b.rawValue)
        #expect(model.provider == "deepinfra.chat")
    }

    @Test("uses default upstream base URL for chat requests")
    func usesDefaultBaseURLForChatRequests() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "id": "chatcmpl-1",
            "object": "chat.completion",
            "created": 1_700_000_000,
            "model": "deepinfra/airoboros-70b",
            "choices": [[
                "index": 0,
                "message": [
                    "role": "assistant",
                    "content": "ok",
                ],
                "finish_reason": "stop",
            ]],
            "usage": [
                "prompt_tokens": 1,
                "completion_tokens": 1,
                "total_tokens": 2,
            ],
        ]

        let responseData = Self.encodeJSON(responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://api.deepinfra.com/v1/openai/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let provider = createDeepInfra(settings: DeepInfraProviderSettings(apiKey: "test-key", fetch: fetch))
        let model = try provider.languageModel(modelId: DeepInfraChatModelId.deepinfraAiroboros70b.rawValue)
        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "hello"))], providerOptions: nil),
        ]

        _ = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: prompt))

        guard let request = await capture.value() else {
            Issue.record("Expected request capture")
            return
        }

        #expect(request.url?.absoluteString == "https://api.deepinfra.com/v1/openai/chat/completions")
    }

    @Test("uses default upstream base URL for completion requests")
    func usesDefaultBaseURLForCompletionRequests() async throws {
        actor RequestCapture {
            private(set) var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()
        let responseJSON: [String: Any] = [
            "id": "cmpl-1",
            "object": "text_completion",
            "created": 1_700_000_000,
            "model": "deepinfra-completion-model",
            "choices": [[
                "text": "ok",
                "index": 0,
                "finish_reason": "stop",
            ]],
            "usage": [
                "prompt_tokens": 1,
                "completion_tokens": 1,
                "total_tokens": 2,
            ],
        ]

        let responseData = Self.encodeJSON(responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://api.deepinfra.com/v1/openai/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let provider = createDeepInfra(settings: .init(apiKey: "test-key", fetch: fetch))
        let model = try provider.completionModel(modelId: "deepinfra-completion-model")
        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "hello"))], providerOptions: nil),
        ]

        _ = try await model.doGenerate(options: .init(prompt: prompt))

        guard let request = await capture.value() else {
            Issue.record("Expected request capture")
            return
        }

        #expect(request.url?.absoluteString == "https://api.deepinfra.com/v1/openai/completions")
    }

    @Test("uses default upstream base URL for embedding requests")
    func usesDefaultBaseURLForEmbeddingRequests() async throws {
        actor RequestCapture {
            private(set) var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()
        let responseJSON: [String: Any] = [
            "object": "list",
            "data": [[
                "object": "embedding",
                "index": 0,
                "embedding": [0.1, 0.2, 0.3],
            ]],
            "model": "deepinfra-embedding-model",
            "usage": [
                "prompt_tokens": 1,
                "total_tokens": 1,
            ],
        ]

        let responseData = Self.encodeJSON(responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://api.deepinfra.com/v1/openai/embeddings")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let provider = createDeepInfra(settings: .init(apiKey: "test-key", fetch: fetch))
        let model = try provider.textEmbeddingModel(modelId: "deepinfra-embedding-model")

        _ = try await model.doEmbed(options: .init(values: ["hello"]))

        guard let request = await capture.value() else {
            Issue.record("Expected request capture")
            return
        }

        #expect(request.url?.absoluteString == "https://api.deepinfra.com/v1/openai/embeddings")
    }

    @Test("uses default upstream base URL for image inference requests")
    func usesDefaultBaseURLForImageInferenceRequests() async throws {
        actor RequestCapture {
            private(set) var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()
        let responseJSON: [String: Any] = [
            "images": ["data:image/png;base64,test-image-data"],
        ]

        let responseData = Self.encodeJSON(responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://api.deepinfra.com/v1/inference/stability-ai/sdxl")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let provider = createDeepInfra(settings: .init(apiKey: "test-key", fetch: fetch))
        let model = try provider.imageModel(modelId: "stability-ai/sdxl")

        _ = try await model.doGenerate(options: .init(prompt: "hello", n: 1))

        guard let request = await capture.value() else {
            Issue.record("Expected request capture")
            return
        }

        #expect(request.url?.absoluteString == "https://api.deepinfra.com/v1/inference/stability-ai/sdxl")
    }

    @Test("respects custom baseURL for image inference requests")
    func respectsCustomBaseURLForImageInferenceRequests() async throws {
        actor RequestCapture {
            private(set) var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()
        let responseJSON: [String: Any] = [
            "images": ["data:image/png;base64,test-image-data"],
        ]

        let responseData = Self.encodeJSON(responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://custom.api.deepinfra.com/inference/stability-ai/sdxl")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let provider = createDeepInfra(settings: .init(apiKey: "test-key", baseURL: "https://custom.api.deepinfra.com", fetch: fetch))
        let model = try provider.imageModel(modelId: "stability-ai/sdxl")

        _ = try await model.doGenerate(options: .init(prompt: "hello", n: 1))

        guard let request = await capture.value() else {
            Issue.record("Expected request capture")
            return
        }

        #expect(request.url?.absoluteString == "https://custom.api.deepinfra.com/inference/stability-ai/sdxl")
    }

    @Suite("auth behavior", .serialized)
    struct AuthBehaviorTests {
        @Test("missing API key throws LoadAPIKeyError at request time")
        func missingAPIKeyThrowsAtRequestTime() async throws {
            actor RequestCapture {
                var request: URLRequest?
                func store(_ request: URLRequest) { self.request = request }
                func value() -> URLRequest? { request }
            }

            let original = getenv("DEEPINFRA_API_KEY").flatMap { String(validatingCString: $0) }
            defer {
                if let original {
                    setenv("DEEPINFRA_API_KEY", original, 1)
                } else {
                    unsetenv("DEEPINFRA_API_KEY")
                }
            }

            unsetenv("DEEPINFRA_API_KEY")

            let capture = RequestCapture()
            let responseJSON: [String: Any] = [
                "id": "chatcmpl-1",
                "object": "chat.completion",
                "created": 1_700_000_000,
                "model": "deepinfra/airoboros-70b",
                "choices": [[
                    "index": 0,
                    "message": [
                        "role": "assistant",
                        "content": "ok",
                    ],
                    "finish_reason": "stop",
                ]],
                "usage": [
                    "prompt_tokens": 1,
                    "completion_tokens": 1,
                    "total_tokens": 2,
                ],
            ]

            let responseData = DeepInfraProviderTests.encodeJSON(responseJSON)
            let response = HTTPURLResponse(
                url: URL(string: "https://api.deepinfra.com/v1/openai/chat/completions")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!

            let fetch: FetchFunction = { request in
                await capture.store(request)
                return FetchResponse(body: .data(responseData), urlResponse: response)
            }

            let provider = createDeepInfra(settings: DeepInfraProviderSettings(fetch: fetch))
            let model = try provider.languageModel(modelId: DeepInfraChatModelId.deepinfraAiroboros70b.rawValue)
            let prompt: LanguageModelV3Prompt = [
                .user(content: [.text(.init(text: "hello"))], providerOptions: nil),
            ]

            do {
                _ = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: prompt))
                Issue.record("Expected missing API key error")
            } catch let error as LoadAPIKeyError {
                #expect(error.message.contains("DEEPINFRA_API_KEY environment variable"))
            } catch {
                Issue.record("Expected LoadAPIKeyError, got: \(error)")
            }

            #expect(await capture.value() == nil)
        }
    }
}
