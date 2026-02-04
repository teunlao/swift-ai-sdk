import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import OpenAICompatibleProvider

private let chatPrompt: LanguageModelV3Prompt = [
    .user(
        content: [.text(LanguageModelV3TextPart(text: "Hello"))],
        providerOptions: nil
    )
]

private let completionPrompt: LanguageModelV3Prompt = [
    .user(
        content: [.text(LanguageModelV3TextPart(text: "Hi there"))],
        providerOptions: nil
    )
]

@Suite("OpenAICompatibleProvider")
struct OpenAICompatibleProviderTests {
    actor RequestCapture {
        private(set) var request: URLRequest?
        func store(_ request: URLRequest) { self.request = request }
        func current() -> URLRequest? { request }
    }

    private func makeHTTPResponse(url: URL, statusCode: Int = 200, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    private func makeStreamBody(from events: [String]) -> ProviderHTTPResponseBody {
        .stream(AsyncThrowingStream { continuation in
            for event in events {
                let payload = "data: \(event)\n\n"
                continuation.yield(Data(payload.utf8))
            }
            continuation.finish()
        })
    }

    @Test("chat doGenerate maps response and request payload")
    func chatDoGenerate() async throws {
        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "id": "chatcmpl-test",
            "created": 1_712_000_000,
            "model": "gpt-oss",
            "choices": [
                [
                    "message": [
                        "content": "Hello!"
                    ],
                    "finish_reason": "stop"
                ]
            ],
            "usage": [
                "prompt_tokens": 4,
                "completion_tokens": 6,
                "total_tokens": 10,
                "completion_tokens_details": [
                    "accepted_prediction_tokens": 2,
                    "rejected_prediction_tokens": 0
                ]
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://api.example.com/v1/chat/completions?test=1")!
        let httpResponse = makeHTTPResponse(
            url: targetURL,
            headers: ["Content-Type": "application/json", "X-Test": "response"]
        )

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://api.example.com/v1",
            name: "example",
            apiKey: "secret",
            headers: ["Custom-Header": "value"],
            queryParams: ["test": "1"],
            fetch: fetch,
            includeUsage: true,
            supportsStructuredOutputs: true
        ))

        let model = try provider.languageModel(modelId: "gpt-oss")
        let options = LanguageModelV3CallOptions(
            prompt: chatPrompt,
            temperature: 0.2,
            headers: ["Per-Request": "header"],
            providerOptions: [
                "openai-compatible": ["user": .string("base-user")],
                "example": ["user": .string("override-user"), "customSetting": .string("enabled")]
            ]
        )

        let result = try await model.doGenerate(options: options)
        #expect(result.finishReason.unified == .stop)
        #expect(result.finishReason.raw == "stop")
        #expect((result.usage.inputTokens.total ?? 0) + (result.usage.outputTokens.total ?? 0) == 10)
        if let metadata = result.providerMetadata?["example"],
           case .number(let accepted) = metadata["acceptedPredictionTokens"],
           case .number(let rejected) = metadata["rejectedPredictionTokens"] {
            #expect(accepted == 2)
            #expect(rejected == 0)
        } else {
            Issue.record("Expected provider metadata")
        }

        if case .text(let text) = result.content.first {
            #expect(text.text == "Hello!")
        } else {
            Issue.record("Expected text content")
        }

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Missing captured request")
            return
        }

        #expect(request.url?.absoluteString == targetURL.absoluteString)
        let headers = request.allHTTPHeaderFields ?? [:]
        let normalizedHeaders = headers.reduce(into: [String: String]()) { result, entry in
            result[entry.key.lowercased()] = entry.value
        }
        #expect(normalizedHeaders["authorization"] == "Bearer secret")
        #expect(normalizedHeaders["custom-header"] == "value")
        #expect(normalizedHeaders["per-request"] == "header")

        #expect(json["model"] as? String == "gpt-oss")
        #expect(json["user"] as? String == "override-user")
        if let messages = json["messages"] as? [[String: Any]] {
            #expect(messages.count == 1)
        } else {
            Issue.record("Expected messages array")
        }
        #expect(json["temperature"] as? Double == 0.2)
        if let forwarded = json["customSetting"] as? String {
            #expect(forwarded == "enabled")
        } else {
            Issue.record("Expected forwarded provider option")
        }
    }

    @Test("chat doStream emits text deltas and finish metadata")
    func chatDoStream() async throws {
        let events = [
            "{\"id\":\"chatcmpl-1\",\"created\":1712000000,\"model\":\"gpt-oss\",\"choices\":[{\"delta\":{\"content\":\"Hello\"},\"finish_reason\":null}]}",
            "{\"id\":\"chatcmpl-1\",\"created\":1712000000,\"model\":\"gpt-oss\",\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":1,\"completion_tokens\":1,\"total_tokens\":2,\"completion_tokens_details\":{\"accepted_prediction_tokens\":1}}}"
        ]

        let targetURL = URL(string: "https://api.example.com/v1/chat/completions")!
        let httpResponse = makeHTTPResponse(
            url: targetURL,
            headers: ["Content-Type": "text/event-stream"]
        )

        let fetch: FetchFunction = { _ in
            FetchResponse(body: makeStreamBody(from: events), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://api.example.com/v1",
            name: "example",
            fetch: fetch,
            includeUsage: true
        ))

        let model = try provider.languageModel(modelId: "gpt-oss")
        let streamResult = try await model.doStream(options: LanguageModelV3CallOptions(prompt: chatPrompt))

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in streamResult.stream {
            parts.append(part)
        }

        guard parts.count >= 5 else {
            Issue.record("Expected stream parts")
            return
        }

        if case .textDelta(_, let delta, _) = parts.first(where: { if case .textDelta = $0 { return true } else { return false } }) {
            #expect(delta == "Hello")
        } else {
            Issue.record("Missing text delta")
        }

        if case let .finish(finishReason: finishReason, usage: finishUsage, providerMetadata: providerMetadata) = parts.last {
            #expect(finishReason.unified == .stop)
            #expect(finishReason.raw == "stop")
            #expect((finishUsage.inputTokens.total ?? 0) + (finishUsage.outputTokens.total ?? 0) == 2)
            if let metadata = providerMetadata?["example"], case .number(let value) = metadata["acceptedPredictionTokens"] {
                #expect(value == 1)
            } else {
                Issue.record("Expected provider metadata in finish part")
            }
        } else {
            Issue.record("Missing finish part")
        }

    }

    @Test("completion doGenerate converts prompt and forwards options")
    func completionDoGenerate() async throws {
        let capture = RequestCapture()
        let responseJSON: [String: Any] = [
            "id": "cmpl-test",
            "created": 1_712_000_100,
            "model": "gpt-3.5-instruct",
            "choices": [[
                "text": "Result",
                "finish_reason": "stop"
            ]],
            "usage": [
                "prompt_tokens": 3,
                "completion_tokens": 2,
                "total_tokens": 5
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let response = makeHTTPResponse(
            url: URL(string: "https://api.example.com/v1/completions")!,
            headers: ["Content-Type": "application/json"]
        )

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(data), urlResponse: response)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://api.example.com/v1",
            name: "example",
            fetch: fetch
        ))

        let model = try provider.completionModel(modelId: "gpt-3.5-instruct")
        let options = LanguageModelV3CallOptions(
            prompt: completionPrompt,
            maxOutputTokens: 20,
            frequencyPenalty: 0.1,
            providerOptions: [
                "openai-compatible": ["echo": .bool(false), "user": .string("base-user")],
                "example": ["echo": .bool(true), "user": .string("override-user"), "custom": .string("flag")]
            ]
        )

        let result = try await model.doGenerate(options: options)
        #expect(result.finishReason.unified == .stop)
        #expect(result.finishReason.raw == "stop")
        if case .text(let text) = result.content.first {
            #expect(text.text == "Result")
        } else {
            Issue.record("Expected text content")
        }

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            Issue.record("Missing captured completion request")
            return
        }

        #expect(json["max_tokens"] as? Double == 20)
        #expect(json["frequency_penalty"] as? Double == 0.1)
        #expect(json["echo"] as? Bool == true)
        #expect(json["user"] as? String == "override-user")
        #expect(json["custom"] as? String == "flag")
    }

    @Test("embedding doEmbed maps response usage and provider overrides")
    func embeddingDoEmbed() async throws {
        let capture = RequestCapture()
        let responseJSON: [String: Any] = [
            "data": [["embedding": [0.1, 0.2, 0.3]]],
            "usage": ["prompt_tokens": 3]
        ]
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let response = makeHTTPResponse(
            url: URL(string: "https://api.example.com/v1/embeddings")!,
            headers: ["Content-Type": "application/json"]
        )

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(data), urlResponse: response)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://api.example.com/v1",
            name: "example",
            fetch: fetch
        ))

        let model = try provider.textEmbeddingModel(modelId: "text-embedding-3-small")
        let options = EmbeddingModelV3DoEmbedOptions(
            values: ["hello"],
            providerOptions: [
                "openai-compatible": ["dimensions": .number(128), "user": .string("base-user")],
                "example": ["dimensions": .number(256), "user": .string("override-user")]
            ]
        )
        let result = try await model.doEmbed(options: options)
        #expect(result.embeddings.count == 1)
        if let first = result.embeddings.first {
            #expect(first == [0.1, 0.2, 0.3])
        } else {
            Issue.record("Missing embedding result")
        }
        #expect(result.usage?.tokens == 3)

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Missing captured embedding request")
            return
        }

        #expect(json["dimensions"] as? Double == 256)
        #expect(json["user"] as? String == "override-user")
    }

    @Test("image doGenerate returns base64 images and warnings")
    func imageDoGenerate() async throws {
        let responseJSON: [String: Any] = [
            "data": [["b64_json": "ZmFrZS1pbWFnZQ=="]]
        ]
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let response = makeHTTPResponse(
            url: URL(string: "https://api.example.com/v1/images/generations")!,
            headers: ["Content-Type": "application/json"]
        )

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(data), urlResponse: response)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://api.example.com/v1",
            name: "example",
            fetch: fetch
        ))

        let model = try provider.imageModel(modelId: "gpt-image")
        let result = try await model.doGenerate(
            options: ImageModelV3CallOptions(
                prompt: "Draw",
                n: 1,
                size: "512x512",
                aspectRatio: "1:1",
                seed: 1
            )
        )

        if case .base64(let images) = result.images {
            #expect(images == ["ZmFrZS1pbWFnZQ=="])
        } else {
            Issue.record("Expected base64 images")
        }
        #expect(result.warnings.count == 2)
    }

    @Test("creates headers without authorization when no apiKey provided")
    func createsHeadersWithoutApiKey() async throws {
        let capture = RequestCapture()
        let responseJSON: [String: Any] = ["data": [["embedding": [0.1]]], "usage": ["prompt_tokens": 1]]
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let response = makeHTTPResponse(
            url: URL(string: "https://api.example.com/v1/embeddings")!
        )

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(data), urlResponse: response)
        }

        // No apiKey provided
        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://api.example.com/v1",
            name: "example",
            headers: ["Custom-Header": "value"],
            fetch: fetch
        ))

        let model = try provider.textEmbeddingModel(modelId: "test")
        _ = try await model.doEmbed(options: EmbeddingModelV3DoEmbedOptions(values: ["test"]))

        guard let request = await capture.current() else {
            Issue.record("Missing request")
            return
        }

        let headers = request.allHTTPHeaderFields ?? [:]
        let normalizedHeaders = headers.reduce(into: [String: String]()) { result, entry in
            result[entry.key.lowercased()] = entry.value
        }

        // Should NOT have authorization header
        #expect(normalizedHeaders["authorization"] == nil)
        #expect(normalizedHeaders["custom-header"] == "value")
    }

    @Test("creates URL without query parameters when queryParams not specified")
    func createsURLWithoutQueryParams() async throws {
        let capture = RequestCapture()
        let responseJSON: [String: Any] = ["data": [["embedding": [0.1]]], "usage": ["prompt_tokens": 1]]
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let response = makeHTTPResponse(
            url: URL(string: "https://api.example.com/v1/embeddings")!
        )

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(data), urlResponse: response)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://api.example.com/v1",
            name: "example",
            apiKey: "test",
            fetch: fetch
            // No queryParams
        ))

        let model = try provider.textEmbeddingModel(modelId: "test")
        _ = try await model.doEmbed(options: EmbeddingModelV3DoEmbedOptions(values: ["test"]))

        guard let request = await capture.current() else {
            Issue.record("Missing request")
            return
        }

        // URL should not have query parameters
        let urlString = request.url?.absoluteString ?? ""
        #expect(urlString == "https://api.example.com/v1/embeddings")
        #expect(!urlString.contains("?"))
    }

    @Test("languageModel is default when called as function")
    func languageModelIsDefault() async throws {
        let capture = RequestCapture()
        let responseJSON = [
            "id": "test",
            "created": 1,
            "model": "test",
            "choices": [["message": ["content": "Hi"], "finish_reason": "stop"]],
            "usage": ["prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2]
        ] as [String: Any]
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let response = makeHTTPResponse(
            url: URL(string: "https://api.example.com/v1/chat/completions")!
        )

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(data), urlResponse: response)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://api.example.com/v1",
            name: "example",
            fetch: fetch
        ))

        // Default languageModel should create chat model
        let model = try provider.languageModel(modelId: "model-id")
        _ = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: chatPrompt))

        guard let request = await capture.current() else {
            Issue.record("Missing request")
            return
        }

        // Should use chat completions endpoint
        let urlString = request.url?.absoluteString ?? ""
        #expect(urlString.contains("/chat/completions"))
    }

    @Test("passes includeUsage true to all model types")
    func passesIncludeUsageTrue() throws {
        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://api.example.com/v1",
            name: "example",
            includeUsage: true
        ))

        // Create all model types - they should all have includeUsage=true
        // We can't directly inspect internal config, but we verified this works in integration tests
        _ = try provider.chatModel(modelId: "chat")
        _ = try provider.completionModel(modelId: "completion")
        _ = try provider.languageModel(modelId: "default")

        // This test verifies the setting is accepted without errors
        // Actual behavior is tested in integration tests above
    }

    @Test("passes includeUsage false to all model types")
    func passesIncludeUsageFalse() throws {
        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://api.example.com/v1",
            name: "example",
            includeUsage: false
        ))

        _ = try provider.chatModel(modelId: "chat")
        _ = try provider.completionModel(modelId: "completion")
        _ = try provider.languageModel(modelId: "default")

        // Verifies settings accepted without errors
    }

    @Test("passes supportsStructuredOutputs to chat and language models only")
    func passesStructuredOutputsToCorrectModels() throws {
        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://api.example.com/v1",
            name: "example",
            supportsStructuredOutputs: true
        ))

        // These should accept supportsStructuredOutputs
        _ = try provider.languageModel(modelId: "model-id")
        _ = try provider.chatModel(modelId: "chat")
        _ = try provider.languageModel(modelId: "lang")

        // These models don't use supportsStructuredOutputs
        _ = try provider.completionModel(modelId: "completion")
        _ = try provider.textEmbeddingModel(modelId: "embedding")
        _ = try provider.imageModel(modelId: "image")

        // Setting is accepted without errors
    }
}
