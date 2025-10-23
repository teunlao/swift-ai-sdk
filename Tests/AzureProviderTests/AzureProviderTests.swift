import Foundation
import Testing
@testable import AzureProvider
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import OpenAIProvider

/**
 Azure Provider tests.

 Port of `@ai-sdk/azure/src/azure-openai-provider.test.ts`.
 */

let TEST_PROMPT: LanguageModelV3Prompt = [
    .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
]

@Suite("AzureProvider")
struct AzureProviderTests {

    // MARK: - Helper Methods

    static func encodeJSON(_ dict: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: dict)
    }

    static func decodeRequestBody(_ request: URLRequest) throws -> [String: Any] {
        guard let body = request.httpBody else {
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "No body"])
        }
        return try JSONSerialization.jsonObject(with: body) as! [String: Any]
    }

    static func makeConfig(
        provider: String,
        fetch: FetchFunction? = nil,
        fileIdPrefixes: [String]? = nil
    ) -> OpenAIConfig {
        let settings = AzureProviderSettings(
            resourceName: "test-resource",
            apiKey: "test-api-key",
            fetch: fetch
        )

        let azureProvider = createAzure(settings: settings)

        // Extract config from created model - we'll use a simple approach
        let urlBuilder: @Sendable (OpenAIConfig.URLOptions) -> String = { options in
            "https://test-resource.openai.azure.com/openai/v1\(options.path)?api-version=v1"
        }

        return OpenAIConfig(
            provider: provider,
            url: urlBuilder,
            headers: {
                [
                    "api-key": "test-api-key"
                ]
            },
            fetch: fetch,
            fileIdPrefixes: fileIdPrefixes
        )
    }

    // MARK: - Chat Tests

    @Test("should set the correct default api version")
    func setCorrectDefaultApiVersionForChat() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "id": "chatcmpl-test",
            "object": "chat.completion",
            "created": 1711115037,
            "model": "gpt-3.5-turbo",
            "choices": [[
                "index": 0,
                "message": [
                    "role": "assistant",
                    "content": "Test"
                ],
                "finish_reason": "stop"
            ]],
            "usage": [
                "prompt_tokens": 4,
                "total_tokens": 34,
                "completion_tokens": 30
            ]
        ]

        let responseData = Self.encodeJSON(responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://test-resource.openai.azure.com/openai/v1/chat/completions?api-version=v1")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let provider = createAzure(settings: AzureProviderSettings(
            resourceName: "test-resource",
            apiKey: "test-api-key",
            fetch: fetch
        ))

        _ = try await provider("test-deployment").doGenerate(options: LanguageModelV3CallOptions(prompt: TEST_PROMPT))

        guard let request = await capture.value(),
              let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let apiVersion = components.queryItems?.first(where: { $0.name == "api-version" })?.value else {
            Issue.record("Expected to capture request with api-version")
            return
        }

        #expect(apiVersion == "v1")
    }

    @Test("should set the correct modified api version")
    func setCorrectModifiedApiVersion() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "id": "chatcmpl-test",
            "object": "chat.completion",
            "created": 1711115037,
            "model": "gpt-3.5-turbo",
            "choices": [[
                "index": 0,
                "message": [
                    "role": "assistant",
                    "content": "Test"
                ],
                "finish_reason": "stop"
            ]],
            "usage": [
                "prompt_tokens": 4,
                "total_tokens": 34,
                "completion_tokens": 30
            ]
        ]

        let responseData = Self.encodeJSON(responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://test-resource.openai.azure.com/openai/v1/chat/completions?api-version=2025-04-01-preview")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let provider = createAzure(settings: AzureProviderSettings(
            resourceName: "test-resource",
            apiKey: "test-api-key",
            fetch: fetch,
            apiVersion: "2025-04-01-preview"
        ))

        _ = try await provider("test-deployment").doGenerate(options: LanguageModelV3CallOptions(prompt: TEST_PROMPT))

        guard let request = await capture.value(),
              let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let apiVersion = components.queryItems?.first(where: { $0.name == "api-version" })?.value else {
            Issue.record("Expected to capture request with api-version")
            return
        }

        #expect(apiVersion == "2025-04-01-preview")
    }

    @Test("should pass headers for chat")
    func passHeadersForChat() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "id": "chatcmpl-test",
            "object": "chat.completion",
            "created": 1711115037,
            "model": "gpt-3.5-turbo",
            "choices": [[
                "index": 0,
                "message": [
                    "role": "assistant",
                    "content": "Test"
                ],
                "finish_reason": "stop"
            ]],
            "usage": [
                "prompt_tokens": 4,
                "total_tokens": 34,
                "completion_tokens": 30
            ]
        ]

        let responseData = Self.encodeJSON(responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://test-resource.openai.azure.com/openai/v1/chat/completions?api-version=v1")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let provider = createAzure(settings: AzureProviderSettings(
            resourceName: "test-resource",
            apiKey: "test-api-key",
            headers: ["Custom-Provider-Header": "provider-header-value"],
            fetch: fetch
        ))

        _ = try await provider("test-deployment").doGenerate(options: LanguageModelV3CallOptions(
            prompt: TEST_PROMPT,
            headers: ["Custom-Request-Header": "request-header-value"]
        ))

        guard let request = await capture.value() else {
            Issue.record("Expected to capture request")
            return
        }

        #expect(request.value(forHTTPHeaderField: "api-key") == "test-api-key")
        #expect(request.value(forHTTPHeaderField: "Custom-Provider-Header") == "provider-header-value")
        #expect(request.value(forHTTPHeaderField: "Custom-Request-Header") == "request-header-value")
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("ai-sdk/azure") == true)
    }

    @Test("should use the baseURL correctly for chat")
    func useBaseURLCorrectlyForChat() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "id": "chatcmpl-test",
            "object": "chat.completion",
            "created": 1711115037,
            "model": "gpt-3.5-turbo",
            "choices": [[
                "index": 0,
                "message": [
                    "role": "assistant",
                    "content": "Test"
                ],
                "finish_reason": "stop"
            ]],
            "usage": [
                "prompt_tokens": 4,
                "total_tokens": 34,
                "completion_tokens": 30
            ]
        ]

        let responseData = Self.encodeJSON(responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://test-resource.openai.azure.com/openai/v1/chat/completions?api-version=v1")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let provider = createAzure(settings: AzureProviderSettings(
            baseURL: "https://test-resource.openai.azure.com/openai",
            apiKey: "test-api-key",
            fetch: fetch
        ))

        _ = try await provider("test-deployment").doGenerate(options: LanguageModelV3CallOptions(prompt: TEST_PROMPT))

        guard let request = await capture.value(),
              let url = request.url else {
            Issue.record("Expected to capture request with URL")
            return
        }

        #expect(url.absoluteString == "https://test-resource.openai.azure.com/openai/v1/chat/completions?api-version=v1")
    }

    // MARK: - Completion Tests

    @Test("should set the correct api version for completion")
    func setCorrectApiVersionForCompletion() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "id": "cmpl-96cAM1v77r4jXa4qb2NSmRREV5oWB",
            "object": "text_completion",
            "created": 1711363706,
            "model": "gpt-35-turbo-instruct",
            "choices": [[
                "text": "Hello World!",
                "index": 0,
                "finish_reason": "stop"
            ]],
            "usage": [
                "prompt_tokens": 4,
                "total_tokens": 34,
                "completion_tokens": 30
            ]
        ]

        let responseData = Self.encodeJSON(responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://test-resource.openai.azure.com/openai/v1/completions?api-version=v1")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let provider = createAzure(settings: AzureProviderSettings(
            resourceName: "test-resource",
            apiKey: "test-api-key",
            fetch: fetch
        ))

        _ = try await provider.completion(.init(rawValue: "gpt-35-turbo-instruct")).doGenerate(options: LanguageModelV3CallOptions(prompt: TEST_PROMPT))

        guard let request = await capture.value(),
              let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let apiVersion = components.queryItems?.first(where: { $0.name == "api-version" })?.value else {
            Issue.record("Expected to capture request with api-version")
            return
        }

        #expect(apiVersion == "v1")
    }

    @Test("should pass headers for completion")
    func passHeadersForCompletion() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "id": "cmpl-96cAM1v77r4jXa4qb2NSmRREV5oWB",
            "object": "text_completion",
            "created": 1711363706,
            "model": "gpt-35-turbo-instruct",
            "choices": [[
                "text": "Hello World!",
                "index": 0,
                "finish_reason": "stop"
            ]],
            "usage": [
                "prompt_tokens": 4,
                "total_tokens": 34,
                "completion_tokens": 30
            ]
        ]

        let responseData = Self.encodeJSON(responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://test-resource.openai.azure.com/openai/v1/completions?api-version=v1")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let provider = createAzure(settings: AzureProviderSettings(
            resourceName: "test-resource",
            apiKey: "test-api-key",
            headers: ["Custom-Provider-Header": "provider-header-value"],
            fetch: fetch
        ))

        _ = try await provider.completion(.init(rawValue: "gpt-35-turbo-instruct")).doGenerate(options: LanguageModelV3CallOptions(
            prompt: TEST_PROMPT,
            headers: ["Custom-Request-Header": "request-header-value"]
        ))

        guard let request = await capture.value() else {
            Issue.record("Expected to capture request")
            return
        }

        #expect(request.value(forHTTPHeaderField: "api-key") == "test-api-key")
        #expect(request.value(forHTTPHeaderField: "Custom-Provider-Header") == "provider-header-value")
        #expect(request.value(forHTTPHeaderField: "Custom-Request-Header") == "request-header-value")
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("ai-sdk/azure") == true)
    }

    // MARK: - Transcription Tests

    @Test("should use correct URL format for transcription")
    func useCorrectURLFormatForTranscription() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "text": "Hello, world!",
            "segments": [],
            "language": "en",
            "duration": 5.0
        ]

        let responseData = Self.encodeJSON(responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://test-resource.openai.azure.com/openai/v1/audio/transcriptions?api-version=v1")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let provider = createAzure(settings: AzureProviderSettings(
            resourceName: "test-resource",
            apiKey: "test-api-key",
            fetch: fetch
        ))

        _ = try await provider.transcription(.init(rawValue: "whisper-1")).doGenerate(options: TranscriptionModelV3CallOptions(
            audio: .binary(Data()),
            mediaType: "audio/wav"
        ))

        guard let request = await capture.value(),
              let url = request.url else {
            Issue.record("Expected to capture request with URL")
            return
        }

        #expect(url.absoluteString == "https://test-resource.openai.azure.com/openai/v1/audio/transcriptions?api-version=v1")
    }

    @Test("should use deployment-based URL format when useDeploymentBasedUrls is true")
    func useDeploymentBasedURLFormatForTranscription() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "text": "Hello, world!",
            "segments": [],
            "language": "en",
            "duration": 5.0
        ]

        let responseData = Self.encodeJSON(responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://test-resource.openai.azure.com/openai/deployments/whisper-1/audio/transcriptions?api-version=v1")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let provider = createAzure(settings: AzureProviderSettings(
            resourceName: "test-resource",
            apiKey: "test-api-key",
            fetch: fetch,
            useDeploymentBasedUrls: true
        ))

        _ = try await provider.transcription(.init(rawValue: "whisper-1")).doGenerate(options: TranscriptionModelV3CallOptions(
            audio: .binary(Data()),
            mediaType: "audio/wav"
        ))

        guard let request = await capture.value(),
              let url = request.url else {
            Issue.record("Expected to capture request with URL")
            return
        }

        #expect(url.absoluteString == "https://test-resource.openai.azure.com/openai/deployments/whisper-1/audio/transcriptions?api-version=v1")
    }

    // MARK: - Speech Tests

    @Test("should use correct URL format for speech")
    func useCorrectURLFormatForSpeech() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let audioData = Data([1, 2, 3])
        let response = HTTPURLResponse(
            url: URL(string: "https://test-resource.openai.azure.com/openai/v1/audio/speech?api-version=v1")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "audio/mpeg"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(audioData), urlResponse: response)
        }

        let provider = createAzure(settings: AzureProviderSettings(
            resourceName: "test-resource",
            apiKey: "test-api-key",
            fetch: fetch
        ))

        _ = try await provider.speech(.init(rawValue: "tts-1")).doGenerate(options: SpeechModelV3CallOptions(text: "Hello, world!"))

        guard let request = await capture.value(),
              let url = request.url else {
            Issue.record("Expected to capture request with URL")
            return
        }

        #expect(url.absoluteString == "https://test-resource.openai.azure.com/openai/v1/audio/speech?api-version=v1")
    }

    // MARK: - Embedding Tests

    @Test("should set the correct api version for embedding")
    func setCorrectApiVersionForEmbedding() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "object": "list",
            "data": [
                [
                    "object": "embedding",
                    "index": 0,
                    "embedding": [0.1, 0.2, 0.3, 0.4, 0.5]
                ],
                [
                    "object": "embedding",
                    "index": 1,
                    "embedding": [0.6, 0.7, 0.8, 0.9, 1.0]
                ]
            ],
            "model": "my-embedding",
            "usage": [
                "prompt_tokens": 8,
                "total_tokens": 8
            ]
        ]

        let responseData = Self.encodeJSON(responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://test-resource.openai.azure.com/openai/v1/embeddings?api-version=v1")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let provider = createAzure(settings: AzureProviderSettings(
            resourceName: "test-resource",
            apiKey: "test-api-key",
            fetch: fetch
        ))

        _ = try await provider.textEmbedding(.init(rawValue: "my-embedding")).doEmbed(options: EmbeddingModelV3DoEmbedOptions(values: ["sunny day at the beach", "rainy day in the city"]))

        guard let request = await capture.value(),
              let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let apiVersion = components.queryItems?.first(where: { $0.name == "api-version" })?.value else {
            Issue.record("Expected to capture request with api-version")
            return
        }

        #expect(apiVersion == "v1")
    }

    @Test("should pass headers for embedding")
    func passHeadersForEmbedding() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "object": "list",
            "data": [
                [
                    "object": "embedding",
                    "index": 0,
                    "embedding": [0.1, 0.2, 0.3, 0.4, 0.5]
                ],
                [
                    "object": "embedding",
                    "index": 1,
                    "embedding": [0.6, 0.7, 0.8, 0.9, 1.0]
                ]
            ],
            "model": "my-embedding",
            "usage": [
                "prompt_tokens": 8,
                "total_tokens": 8
            ]
        ]

        let responseData = Self.encodeJSON(responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://test-resource.openai.azure.com/openai/v1/embeddings?api-version=v1")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let provider = createAzure(settings: AzureProviderSettings(
            resourceName: "test-resource",
            apiKey: "test-api-key",
            headers: ["Custom-Provider-Header": "provider-header-value"],
            fetch: fetch
        ))

        _ = try await provider.textEmbedding(.init(rawValue: "my-embedding")).doEmbed(options: EmbeddingModelV3DoEmbedOptions(
            values: ["sunny day at the beach", "rainy day in the city"],
            headers: ["Custom-Request-Header": "request-header-value"]
        ))

        guard let request = await capture.value() else {
            Issue.record("Expected to capture request")
            return
        }

        #expect(request.value(forHTTPHeaderField: "api-key") == "test-api-key")
        #expect(request.value(forHTTPHeaderField: "Custom-Provider-Header") == "provider-header-value")
        #expect(request.value(forHTTPHeaderField: "Custom-Request-Header") == "request-header-value")
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("ai-sdk/azure") == true)
    }

    // MARK: - Image Tests

    @Test("should set the correct default api version for image")
    func setCorrectDefaultApiVersionForImage() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "created": 1733837122,
            "data": [
                [
                    "revised_prompt": "A charming visual illustration of a baby sea otter swimming joyously.",
                    "b64_json": "base64-image-1"
                ],
                [
                    "b64_json": "base64-image-2"
                ]
            ]
        ]

        let responseData = Self.encodeJSON(responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://test-resource.openai.azure.com/openai/v1/images/generations?api-version=v1")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let provider = createAzure(settings: AzureProviderSettings(
            resourceName: "test-resource",
            apiKey: "test-api-key",
            fetch: fetch
        ))

        _ = try await provider.imageModel(.init(rawValue: "dalle-deployment")).doGenerate(options: ImageModelV3CallOptions(
            prompt: "A cute baby sea otter",
            n: 1,
            size: "1024x1024"
        ))

        guard let request = await capture.value(),
              let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let apiVersion = components.queryItems?.first(where: { $0.name == "api-version" })?.value else {
            Issue.record("Expected to capture request with api-version")
            return
        }

        #expect(apiVersion == "v1")
    }

    @Test("should set the correct modified api version for image")
    func setCorrectModifiedApiVersionForImage() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "created": 1733837122,
            "data": [
                [
                    "revised_prompt": "A charming visual illustration of a baby sea otter swimming joyously.",
                    "b64_json": "base64-image-1"
                ],
                [
                    "b64_json": "base64-image-2"
                ]
            ]
        ]

        let responseData = Self.encodeJSON(responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://test-resource.openai.azure.com/openai/v1/images/generations?api-version=2025-04-01-preview")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let provider = createAzure(settings: AzureProviderSettings(
            resourceName: "test-resource",
            apiKey: "test-api-key",
            fetch: fetch,
            apiVersion: "2025-04-01-preview"
        ))

        _ = try await provider.imageModel(.init(rawValue: "dalle-deployment")).doGenerate(options: ImageModelV3CallOptions(
            prompt: "A cute baby sea otter",
            n: 1,
            size: "1024x1024"
        ))

        guard let request = await capture.value(),
              let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let apiVersion = components.queryItems?.first(where: { $0.name == "api-version" })?.value else {
            Issue.record("Expected to capture request with api-version")
            return
        }

        #expect(apiVersion == "2025-04-01-preview")
    }

    @Test("should pass headers for image")
    func passHeadersForImage() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "created": 1733837122,
            "data": [
                [
                    "revised_prompt": "A charming visual illustration of a baby sea otter swimming joyously.",
                    "b64_json": "base64-image-1"
                ],
                [
                    "b64_json": "base64-image-2"
                ]
            ]
        ]

        let responseData = Self.encodeJSON(responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://test-resource.openai.azure.com/openai/v1/images/generations?api-version=v1")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let provider = createAzure(settings: AzureProviderSettings(
            resourceName: "test-resource",
            apiKey: "test-api-key",
            headers: ["Custom-Provider-Header": "provider-header-value"],
            fetch: fetch
        ))

        _ = try await provider.imageModel(.init(rawValue: "dalle-deployment")).doGenerate(options: ImageModelV3CallOptions(
            prompt: "A cute baby sea otter",
            n: 1,
            size: "1024x1024",
            headers: ["Custom-Request-Header": "request-header-value"]
        ))

        guard let request = await capture.value() else {
            Issue.record("Expected to capture request")
            return
        }

        #expect(request.value(forHTTPHeaderField: "api-key") == "test-api-key")
        #expect(request.value(forHTTPHeaderField: "Custom-Provider-Header") == "provider-header-value")
        #expect(request.value(forHTTPHeaderField: "Custom-Request-Header") == "request-header-value")
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("ai-sdk/azure") == true)
    }

    @Test("should use the baseURL correctly for image")
    func useBaseURLCorrectlyForImage() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "created": 1733837122,
            "data": [
                [
                    "revised_prompt": "A charming visual illustration of a baby sea otter swimming joyously.",
                    "b64_json": "base64-image-1"
                ],
                [
                    "b64_json": "base64-image-2"
                ]
            ]
        ]

        let responseData = Self.encodeJSON(responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://test-resource.openai.azure.com/openai/v1/images/generations?api-version=v1")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let provider = createAzure(settings: AzureProviderSettings(
            baseURL: "https://test-resource.openai.azure.com/openai",
            apiKey: "test-api-key",
            fetch: fetch
        ))

        _ = try await provider.imageModel(.init(rawValue: "dalle-deployment")).doGenerate(options: ImageModelV3CallOptions(
            prompt: "A cute baby sea otter",
            n: 1,
            size: "1024x1024"
        ))

        guard let request = await capture.value(),
              let url = request.url else {
            Issue.record("Expected to capture request with URL")
            return
        }

        #expect(url.absoluteString == "https://test-resource.openai.azure.com/openai/v1/images/generations?api-version=v1")
    }

    @Test("should extract the generated images")
    func extractGeneratedImages() async throws {
        let responseJSON: [String: Any] = [
            "created": 1733837122,
            "data": [
                [
                    "revised_prompt": "A charming visual illustration of a baby sea otter swimming joyously.",
                    "b64_json": "base64-image-1"
                ],
                [
                    "b64_json": "base64-image-2"
                ]
            ]
        ]

        let responseData = Self.encodeJSON(responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://test-resource.openai.azure.com/openai/v1/images/generations?api-version=v1")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let provider = createAzure(settings: AzureProviderSettings(
            resourceName: "test-resource",
            apiKey: "test-api-key",
            fetch: fetch
        ))

        let result = try await provider.imageModel(.init(rawValue: "dalle-deployment")).doGenerate(options: ImageModelV3CallOptions(
            prompt: "A cute baby sea otter",
            n: 1,
            size: "1024x1024"
        ))

        if case .base64(let images) = result.images {
            #expect(images == ["base64-image-1", "base64-image-2"])
        } else {
            Issue.record("Expected base64 images")
        }
    }

    @Test("should send the correct request body for image")
    func sendCorrectRequestBodyForImage() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "created": 1733837122,
            "data": [
                [
                    "revised_prompt": "A charming visual illustration of a baby sea otter swimming joyously.",
                    "b64_json": "base64-image-1"
                ],
                [
                    "b64_json": "base64-image-2"
                ]
            ]
        ]

        let responseData = Self.encodeJSON(responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://test-resource.openai.azure.com/openai/v1/images/generations?api-version=v1")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let provider = createAzure(settings: AzureProviderSettings(
            resourceName: "test-resource",
            apiKey: "test-api-key",
            fetch: fetch
        ))

        _ = try await provider.imageModel(.init(rawValue: "dalle-deployment")).doGenerate(options: ImageModelV3CallOptions(
            prompt: "A cute baby sea otter",
            n: 2,
            size: "1024x1024",
            providerOptions: ["openai": ["style": "natural"]]
        ))

        guard let request = await capture.value(),
              let _ = request.httpBody else {
            Issue.record("Expected to capture request with body")
            return
        }

        let requestBody = try Self.decodeRequestBody(request)
        #expect(requestBody["model"] as? String == "dalle-deployment")
        #expect(requestBody["prompt"] as? String == "A cute baby sea otter")
        #expect(requestBody["n"] as? Int == 2)
        #expect(requestBody["size"] as? String == "1024x1024")
        #expect(requestBody["style"] as? String == "natural")
        #expect(requestBody["response_format"] as? String == "b64_json")
    }

    @Test("imageModel method should create the same model as image method")
    func imageModelMethodShouldCreateSameModelAsImageMethod() {
        let provider = createAzure(settings: AzureProviderSettings(
            resourceName: "test-resource",
            apiKey: "test-api-key"
        ))

        let imageModel = provider.imageModel(.init(rawValue: "dalle-deployment"))
        let imageModelAlias = provider.image(.init(rawValue: "dalle-deployment"))

        #expect(imageModel.provider == imageModelAlias.provider)
        #expect(imageModel.modelId == imageModelAlias.modelId)
    }

    // MARK: - Responses Tests

    @Test("should set the correct api version for responses")
    func setCorrectApiVersionForResponses() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "id": "resp_67c97c0203188190a025beb4a75242bc",
            "object": "response",
            "created_at": 1741257730,
            "status": "completed",
            "model": "test-deployment",
            "output": [[
                "id": "msg_67c97c02656c81908e080dfdf4a03cd1",
                "type": "message",
                "status": "completed",
                "role": "assistant",
                "content": [[
                    "type": "output_text",
                    "text": "",
                    "annotations": []
                ]]
            ]],
            "usage": [
                "input_tokens": 4,
                "output_tokens": 30,
                "total_tokens": 34
            ],
            "incomplete_details": NSNull()
        ]

        let responseData = Self.encodeJSON(responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://test-resource.openai.azure.com/openai/v1/responses?api-version=v1")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let provider = createAzure(settings: AzureProviderSettings(
            resourceName: "test-resource",
            apiKey: "test-api-key",
            fetch: fetch
        ))

        _ = try await provider.responses(.init(rawValue: "test-deployment")).doGenerate(options: LanguageModelV3CallOptions(prompt: TEST_PROMPT))

        guard let request = await capture.value(),
              let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let apiVersion = components.queryItems?.first(where: { $0.name == "api-version" })?.value else {
            Issue.record("Expected to capture request with api-version")
            return
        }

        #expect(apiVersion == "v1")
    }

    @Test("should pass headers for responses")
    func passHeadersForResponses() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "id": "resp_67c97c0203188190a025beb4a75242bc",
            "object": "response",
            "created_at": 1741257730,
            "status": "completed",
            "model": "test-deployment",
            "output": [[
                "id": "msg_67c97c02656c81908e080dfdf4a03cd1",
                "type": "message",
                "status": "completed",
                "role": "assistant",
                "content": [[
                    "type": "output_text",
                    "text": "",
                    "annotations": []
                ]]
            ]],
            "usage": [
                "input_tokens": 4,
                "output_tokens": 30,
                "total_tokens": 34
            ],
            "incomplete_details": NSNull()
        ]

        let responseData = Self.encodeJSON(responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://test-resource.openai.azure.com/openai/v1/responses?api-version=v1")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let provider = createAzure(settings: AzureProviderSettings(
            resourceName: "test-resource",
            apiKey: "test-api-key",
            headers: ["Custom-Provider-Header": "provider-header-value"],
            fetch: fetch
        ))

        _ = try await provider.responses(.init(rawValue: "test-deployment")).doGenerate(options: LanguageModelV3CallOptions(
            prompt: TEST_PROMPT,
            headers: ["Custom-Request-Header": "request-header-value"]
        ))

        guard let request = await capture.value() else {
            Issue.record("Expected to capture request")
            return
        }

        #expect(request.value(forHTTPHeaderField: "api-key") == "test-api-key")
        #expect(request.value(forHTTPHeaderField: "Custom-Provider-Header") == "provider-header-value")
        #expect(request.value(forHTTPHeaderField: "Custom-Request-Header") == "request-header-value")
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("ai-sdk/azure") == true)
    }

    @Test("should use the baseURL correctly for responses")
    func useBaseURLCorrectlyForResponses() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "id": "resp_67c97c0203188190a025beb4a75242bc",
            "object": "response",
            "created_at": 1741257730,
            "status": "completed",
            "model": "test-deployment",
            "output": [[
                "id": "msg_67c97c02656c81908e080dfdf4a03cd1",
                "type": "message",
                "status": "completed",
                "role": "assistant",
                "content": [[
                    "type": "output_text",
                    "text": "",
                    "annotations": []
                ]]
            ]],
            "usage": [
                "input_tokens": 4,
                "output_tokens": 30,
                "total_tokens": 34
            ],
            "incomplete_details": NSNull()
        ]

        let responseData = Self.encodeJSON(responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://test-resource.openai.azure.com/openai/v1/responses?api-version=v1")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let provider = createAzure(settings: AzureProviderSettings(
            baseURL: "https://test-resource.openai.azure.com/openai",
            apiKey: "test-api-key",
            fetch: fetch
        ))

        _ = try await provider.responses(.init(rawValue: "test-deployment")).doGenerate(options: LanguageModelV3CallOptions(prompt: TEST_PROMPT))

        guard let request = await capture.value(),
              let url = request.url else {
            Issue.record("Expected to capture request with URL")
            return
        }

        #expect(url.absoluteString == "https://test-resource.openai.azure.com/openai/v1/responses?api-version=v1")
    }

    @Test("should handle Azure file IDs with assistant- prefix")
    func handleAzureFileIDsWithAssistantPrefix() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "id": "resp_67c97c0203188190a025beb4a75242bc",
            "object": "response",
            "created_at": 1741257730,
            "status": "completed",
            "model": "test-deployment",
            "output": [[
                "id": "msg_67c97c02656c81908e080dfdf4a03cd1",
                "type": "message",
                "status": "completed",
                "role": "assistant",
                "content": [[
                    "type": "output_text",
                    "text": "I can see the image.",
                    "annotations": []
                ]]
            ]],
            "usage": [
                "input_tokens": 4,
                "output_tokens": 30,
                "total_tokens": 34
            ],
            "incomplete_details": NSNull()
        ]

        let responseData = Self.encodeJSON(responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://test-resource.openai.azure.com/openai/v1/responses?api-version=v1")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let provider = createAzure(settings: AzureProviderSettings(
            resourceName: "test-resource",
            apiKey: "test-api-key",
            fetch: fetch
        ))

        let testPromptWithAzureFile: LanguageModelV3Prompt = [
            .user(content: [
                .text(.init(text: "Analyze this image")),
                .file(.init(data: .base64("assistant-abc123"), mediaType: "image/jpeg"))
            ], providerOptions: nil)
        ]

        _ = try await provider.responses(.init(rawValue: "test-deployment")).doGenerate(options: LanguageModelV3CallOptions(prompt: testPromptWithAzureFile))

        guard let request = await capture.value() else {
            Issue.record("Expected to capture request")
            return
        }

        let requestBody = try Self.decodeRequestBody(request)
        guard let input = requestBody["input"] as? [[String: Any]],
              let content = input.first?["content"] as? [[String: Any]] else {
            Issue.record("Expected input in request body")
            return
        }

        #expect(content.count == 2)
        #expect(content[0]["type"] as? String == "input_text")
        #expect(content[0]["text"] as? String == "Analyze this image")
        #expect(content[1]["type"] as? String == "input_image")
        #expect(content[1]["file_id"] as? String == "assistant-abc123")
    }

    @Test("should handle PDF files with assistant- prefix")
    func handlePDFFilesWithAssistantPrefix() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "id": "resp_67c97c0203188190a025beb4a75242bc",
            "object": "response",
            "created_at": 1741257730,
            "status": "completed",
            "model": "test-deployment",
            "output": [[
                "id": "msg_67c97c02656c81908e080dfdf4a03cd1",
                "type": "message",
                "status": "completed",
                "role": "assistant",
                "content": [[
                    "type": "output_text",
                    "text": "I can analyze the PDF.",
                    "annotations": []
                ]]
            ]],
            "usage": [
                "input_tokens": 4,
                "output_tokens": 30,
                "total_tokens": 34
            ],
            "incomplete_details": NSNull()
        ]

        let responseData = Self.encodeJSON(responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://test-resource.openai.azure.com/openai/v1/responses?api-version=v1")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let provider = createAzure(settings: AzureProviderSettings(
            resourceName: "test-resource",
            apiKey: "test-api-key",
            fetch: fetch
        ))

        let testPromptWithAzurePDF: LanguageModelV3Prompt = [
            .user(content: [
                .text(.init(text: "Analyze this PDF")),
                .file(.init(data: .base64("assistant-pdf123"), mediaType: "application/pdf"))
            ], providerOptions: nil)
        ]

        _ = try await provider.responses(.init(rawValue: "test-deployment")).doGenerate(options: LanguageModelV3CallOptions(prompt: testPromptWithAzurePDF))

        guard let request = await capture.value() else {
            Issue.record("Expected to capture request")
            return
        }

        let requestBody = try Self.decodeRequestBody(request)
        guard let input = requestBody["input"] as? [[String: Any]],
              let content = input.first?["content"] as? [[String: Any]] else {
            Issue.record("Expected input in request body")
            return
        }

        #expect(content.count == 2)
        #expect(content[0]["type"] as? String == "input_text")
        #expect(content[0]["text"] as? String == "Analyze this PDF")
        #expect(content[1]["type"] as? String == "input_file")
        #expect(content[1]["file_id"] as? String == "assistant-pdf123")
    }

    @Test("should fall back to base64 for non-assistant file IDs")
    func fallBackToBase64ForNonAssistantFileIDs() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "id": "resp_67c97c0203188190a025beb4a75242bc",
            "object": "response",
            "created_at": 1741257730,
            "status": "completed",
            "model": "test-deployment",
            "output": [[
                "id": "msg_67c97c02656c81908e080dfdf4a03cd1",
                "type": "message",
                "status": "completed",
                "role": "assistant",
                "content": [[
                    "type": "output_text",
                    "text": "I can see the image.",
                    "annotations": []
                ]]
            ]],
            "usage": [
                "input_tokens": 4,
                "output_tokens": 30,
                "total_tokens": 34
            ],
            "incomplete_details": NSNull()
        ]

        let responseData = Self.encodeJSON(responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://test-resource.openai.azure.com/openai/v1/responses?api-version=v1")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let provider = createAzure(settings: AzureProviderSettings(
            resourceName: "test-resource",
            apiKey: "test-api-key",
            fetch: fetch
        ))

        let testPromptWithOpenAIFile: LanguageModelV3Prompt = [
            .user(content: [
                .text(.init(text: "Analyze this image")),
                .file(.init(data: .base64("file-abc123"), mediaType: "image/jpeg"))  // OpenAI prefix, should fall back to base64
            ], providerOptions: nil)
        ]

        _ = try await provider.responses(.init(rawValue: "test-deployment")).doGenerate(options: LanguageModelV3CallOptions(prompt: testPromptWithOpenAIFile))

        guard let request = await capture.value() else {
            Issue.record("Expected to capture request")
            return
        }

        let requestBody = try Self.decodeRequestBody(request)
        guard let input = requestBody["input"] as? [[String: Any]],
              let content = input.first?["content"] as? [[String: Any]] else {
            Issue.record("Expected input in request body")
            return
        }

        #expect(content.count == 2)
        #expect(content[0]["type"] as? String == "input_text")
        #expect(content[0]["text"] as? String == "Analyze this image")
        #expect(content[1]["type"] as? String == "input_image")
        #expect(content[1]["image_url"] as? String == "data:image/jpeg;base64,file-abc123")
    }

    @Test("should send include provider option for file search results")
    func sendIncludeProviderOptionForFileSearchResults() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "id": "resp_67c97c0203188190a025beb4a75242bc",
            "object": "response",
            "created_at": 1741257730,
            "status": "completed",
            "model": "test-deployment",
            "output": [[
                "id": "msg_67c97c02656c81908e080dfdf4a03cd1",
                "type": "message",
                "status": "completed",
                "role": "assistant",
                "content": [[
                    "type": "output_text",
                    "text": "",
                    "annotations": []
                ]]
            ]],
            "usage": [
                "input_tokens": 4,
                "output_tokens": 30,
                "total_tokens": 34
            ],
            "incomplete_details": NSNull()
        ]

        let responseData = Self.encodeJSON(responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://test-resource.openai.azure.com/openai/v1/responses?api-version=v1")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let provider = createAzure(settings: AzureProviderSettings(
            resourceName: "test-resource",
            apiKey: "test-api-key",
            fetch: fetch
        ))

        let fileSearchTool: LanguageModelV3Tool = .providerDefined(
            LanguageModelV3ProviderDefinedTool(
                id: "openai.file_search",
                name: "file_search",
                args: [
                    "vectorStoreIds": .array([.string("vs_123"), .string("vs_456")]),
                    "maxNumResults": .number(10),
                    "ranking": .object(["ranker": .string("auto")])
                ]
            )
        )

        _ = try await provider.responses(.init(rawValue: "test-deployment")).doGenerate(options: LanguageModelV3CallOptions(
            prompt: TEST_PROMPT,
            tools: [fileSearchTool]
        ))

        guard let request = await capture.value() else {
            Issue.record("Expected to capture request")
            return
        }

        let requestBody = try Self.decodeRequestBody(request)
        guard let tools = requestBody["tools"] as? [[String: Any]],
              let tool = tools.first else {
            Issue.record("Expected tools in request body")
            return
        }

        #expect(tool["type"] as? String == "file_search")
        #expect((tool["vector_store_ids"] as? [String]) == ["vs_123", "vs_456"])
        #expect(tool["max_num_results"] as? Int == 10)
        if let rankingOptions = tool["ranking_options"] as? [String: Any] {
            #expect(rankingOptions["ranker"] as? String == "auto")
        }
    }

    @Test("should forward include provider options to request body")
    func forwardIncludeProviderOptionsToRequestBody() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "id": "resp_67c97c0203188190a025beb4a75242bc",
            "object": "response",
            "created_at": 1741257730,
            "status": "completed",
            "model": "test-deployment",
            "output": [[
                "id": "msg_67c97c02656c81908e080dfdf4a03cd1",
                "type": "message",
                "status": "completed",
                "role": "assistant",
                "content": [[
                    "type": "output_text",
                    "text": "",
                    "annotations": []
                ]]
            ]],
            "usage": [
                "input_tokens": 4,
                "output_tokens": 30,
                "total_tokens": 34
            ],
            "incomplete_details": NSNull()
        ]

        let responseData = Self.encodeJSON(responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://test-resource.openai.azure.com/openai/v1/responses?api-version=v1")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let provider = createAzure(settings: AzureProviderSettings(
            resourceName: "test-resource",
            apiKey: "test-api-key",
            fetch: fetch
        ))

        _ = try await provider.responses(.init(rawValue: "test-deployment")).doGenerate(options: LanguageModelV3CallOptions(
            prompt: TEST_PROMPT,
            providerOptions: ["openai": ["include": ["file_search_call.results"]]]
        ))

        guard let request = await capture.value() else {
            Issue.record("Expected to capture request")
            return
        }

        let requestBody = try Self.decodeRequestBody(request)
        #expect(requestBody["model"] as? String == "test-deployment")
        guard let input = requestBody["input"] as? [[String: Any]] else {
            Issue.record("Expected input in request body")
            return
        }
        #expect(input.count == 1)
        #expect((requestBody["include"] as? [String]) == ["file_search_call.results"])
    }
}
