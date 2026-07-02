import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import OpenAICompatibleProvider

private let v4ChatPrompt: LanguageModelV4Prompt = [
    .user(
        content: [.text(LanguageModelV4TextPart(text: "Hello"))],
        providerOptions: nil
    )
]

@Suite("OpenAICompatibleProvider V4")
struct OpenAICompatibleProviderV4Tests {
    actor RequestCapture {
        private(set) var request: URLRequest?

        func store(_ request: URLRequest) {
            self.request = request
        }

        func current() -> URLRequest? {
            request
        }
    }

    private func makeHTTPResponse(
        url: URL,
        statusCode: Int = 200,
        headers: [String: String] = [:]
    ) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    private func makeStreamBody(from events: [String]) -> ProviderHTTPResponseBody {
        .stream(AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(Data("data: \(event)\n\n".utf8))
            }
            continuation.finish()
        })
    }

    @Test("factory exposes V4 provider and model surfaces")
    func factoryExposesV4Surfaces() throws {
        let provider = createOpenAICompatible(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://api.example.com/v1",
            name: "example"
        ))

        #expect(provider.specificationVersion == "v4")

        let languageModel = try provider.languageModel(modelId: "gpt-oss")
        #expect(languageModel.specificationVersion == "v4")
        #expect(languageModel.provider == "example.chat")
        #expect(languageModel.modelId == "gpt-oss")

        let chatModel = try provider.chatModel(modelId: "gpt-oss")
        #expect(chatModel.specificationVersion == "v4")
        #expect(chatModel.provider == "example.chat")

        let completionModel = try provider.completionModel(modelId: "gpt-3.5-instruct")
        #expect(completionModel.specificationVersion == "v4")
        #expect(completionModel.provider == "example.completion")

        let embeddingModel = try provider.embeddingModel(modelId: "text-embedding-3-large")
        #expect(embeddingModel.specificationVersion == "v4")
        #expect(embeddingModel.provider == "example.embedding")

        let textEmbeddingModel = try provider.textEmbeddingModel(modelId: "text-embedding-3-small")
        #expect(textEmbeddingModel.specificationVersion == "v4")
        #expect(textEmbeddingModel.provider == "example.embedding")

        let imageModel = try provider.imageModel(modelId: "dall-e-3")
        #expect(imageModel.specificationVersion == "v4")
        #expect(imageModel.provider == "example.image")
    }

    @Test("language model forwards supportedUrls")
    func languageModelSupportedUrls() async throws {
        let urlPattern = try NSRegularExpression(pattern: #"^https://files\.example/"#)
        let provider = createOpenAICompatible(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://api.example.com/v1",
            name: "example",
            supportedUrls: { ["image/*": [urlPattern]] }
        ))

        let model = try provider.languageModel(modelId: "gpt-oss")
        let supportedUrls = try await model.supportedUrls

        #expect(supportedUrls["image/*"]?.first?.pattern == #"^https://files\.example/"#)
    }

    @Test("language doGenerate forwards V4 options and maps V4 result")
    func languageDoGenerateUsesV4Surface() async throws {
        let capture = RequestCapture()
        let responseJSON: [String: Any] = [
            "id": "chatcmpl-v4",
            "created": 1_712_000_000,
            "model": "gpt-oss",
            "choices": [
                [
                    "message": ["content": "Hello from V4"],
                    "finish_reason": "stop"
                ]
            ],
            "usage": [
                "prompt_tokens": 4,
                "completion_tokens": 6,
                "total_tokens": 10
            ]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://api.example.com/v1/chat/completions?trace=1")!
        let httpResponse = makeHTTPResponse(
            url: targetURL,
            headers: ["Content-Type": "application/json", "X-Response": "ok"]
        )

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatible(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://api.example.com/v1/",
            name: "example",
            apiKey: "secret",
            headers: ["Custom-Header": "provider"],
            queryParams: ["trace": "1"],
            fetch: fetch
        ))
        let model = try provider.languageModel(modelId: "gpt-oss")

        let result = try await model.doGenerate(options: LanguageModelV4CallOptions(
            prompt: v4ChatPrompt,
            temperature: 0.25,
            headers: ["Per-Request": "request"],
            providerOptions: [
                "openai-compatible": ["user": .string("base-user")],
                "example": ["user": .string("override-user")]
            ]
        ))

        #expect(result.finishReason.unified == .stop)
        #expect(result.finishReason.raw == "stop")
        #expect((result.usage.inputTokens.total ?? 0) + (result.usage.outputTokens.total ?? 0) == 10)
        #expect(result.response?.headers?["x-response"] == "ok")

        if case .text(let text) = result.content.first {
            #expect(text.text == "Hello from V4")
        } else {
            Issue.record("Expected V4 text content")
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
        #expect(normalizedHeaders["custom-header"] == "provider")
        #expect(normalizedHeaders["per-request"] == "request")
        #expect(json["model"] as? String == "gpt-oss")
        #expect(json["temperature"] as? Double == 0.25)
        #expect(json["user"] as? String == "override-user")
    }

    @Test("language doStream maps V4 text delta and finish")
    func languageDoStreamUsesV4Surface() async throws {
        let events = [
            "{\"id\":\"chatcmpl-v4\",\"created\":1712000000,\"model\":\"gpt-oss\",\"choices\":[{\"delta\":{\"content\":\"Hello\"},\"finish_reason\":null}]}",
            "{\"id\":\"chatcmpl-v4\",\"created\":1712000000,\"model\":\"gpt-oss\",\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":1,\"completion_tokens\":1,\"total_tokens\":2}}"
        ]
        let targetURL = URL(string: "https://api.example.com/v1/chat/completions")!
        let httpResponse = makeHTTPResponse(
            url: targetURL,
            headers: ["Content-Type": "text/event-stream"]
        )

        let fetch: FetchFunction = { _ in
            FetchResponse(body: makeStreamBody(from: events), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatible(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://api.example.com/v1",
            name: "example",
            fetch: fetch,
            includeUsage: true
        ))
        let model = try provider.languageModel(modelId: "gpt-oss")
        let result = try await model.doStream(options: LanguageModelV4CallOptions(prompt: v4ChatPrompt))

        var parts: [LanguageModelV4StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        if case .textDelta(_, let delta, _) = parts.first(where: { if case .textDelta = $0 { true } else { false } }) {
            #expect(delta == "Hello")
        } else {
            Issue.record("Missing V4 text delta")
        }

        if case let .finish(finishReason, usage, _) = parts.last {
            #expect(finishReason.unified == .stop)
            #expect((usage.inputTokens.total ?? 0) + (usage.outputTokens.total ?? 0) == 2)
        } else {
            Issue.record("Missing V4 finish")
        }
    }

    @Test("embedding doEmbed maps V4 result metadata and usage")
    func embeddingDoEmbedUsesV4Surface() async throws {
        let responseJSON: [String: Any] = [
            "data": [
                ["embedding": [0.1, 0.2]],
                ["embedding": [0.3, 0.4]]
            ],
            "usage": [
                "prompt_tokens": 8,
                "total_tokens": 8
            ],
            "providerMetadata": [
                "example": ["trace": "ok"]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://api.example.com/v1/embeddings")!
        let httpResponse = makeHTTPResponse(url: targetURL, headers: ["X-Embedding": "ok"])

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatible(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://api.example.com/v1",
            name: "example",
            fetch: fetch
        ))
        let model = try provider.embeddingModel(modelId: "text-embedding-3-large")

        let result = try await model.doEmbed(options: EmbeddingModelV4CallOptions(values: ["one", "two"]))

        #expect(result.embeddings == [[0.1, 0.2], [0.3, 0.4]])
        #expect(result.usage?.tokens == 8)
        #expect(result.response?.headers?["x-embedding"] == "ok")
        if case .string(let trace) = result.providerMetadata?["example"]?["trace"] {
            #expect(trace == "ok")
        } else {
            Issue.record("Expected V4 embedding provider metadata")
        }
    }

    @Test("image doGenerate maps V4 base64 images warnings and response")
    func imageDoGenerateUsesV4Surface() async throws {
        let capture = RequestCapture()
        let responseJSON: [String: Any] = [
            "data": [
                ["b64_json": "image-1"],
                ["b64_json": "image-2"]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://api.example.com/v1/images/generations")!
        let httpResponse = makeHTTPResponse(url: targetURL, headers: ["X-Image": "ok"])

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatible(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://api.example.com/v1",
            name: "example",
            fetch: fetch
        ))
        let model = try provider.imageModel(modelId: "dall-e-3")

        let result = try await model.doGenerate(options: ImageModelV4CallOptions(
            prompt: "A geometric city",
            n: 2,
            size: "1024x1024",
            aspectRatio: "1:1",
            seed: 42,
            providerOptions: ["openai": ["quality": .string("hd")]]
        ))

        if case .base64(let images) = result.images {
            #expect(images == ["image-1", "image-2"])
        } else {
            Issue.record("Expected V4 base64 images")
        }

        #expect(result.warnings.count == 2)
        #expect(result.response.modelId == "dall-e-3")
        #expect(result.response.headers?["x-image"] == "ok")

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Missing captured request")
            return
        }

        #expect(json["model"] as? String == "dall-e-3")
        #expect(json["prompt"] as? String == "A geometric city")
        #expect(json["n"] as? Double == 2)
        #expect(json["size"] as? String == "1024x1024")
        #expect(json["quality"] as? String == "hd")
        #expect(json["response_format"] as? String == "b64_json")
    }
}
