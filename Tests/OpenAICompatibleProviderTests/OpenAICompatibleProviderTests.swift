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

        let model = provider.languageModel(modelId: "gpt-oss")
        let options = LanguageModelV3CallOptions(
            prompt: chatPrompt,
            temperature: 0.2,
            headers: ["Per-Request": "header"],
            providerOptions: [
                "openai-compatible": ["user": .string("tester")],
                "example": ["customSetting": .string("enabled")]
            ]
        )

        let result = try await model.doGenerate(options: options)
        #expect(result.finishReason == LanguageModelV3FinishReason.stop)
        #expect(result.usage.totalTokens == 10)
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

        let model = provider.languageModel(modelId: "gpt-oss")
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
            #expect(finishReason == LanguageModelV3FinishReason.stop)
            #expect(finishUsage.totalTokens == 2)
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

        let model = provider.completionModel(modelId: "gpt-3.5-instruct")
        let options = LanguageModelV3CallOptions(
            prompt: completionPrompt,
            maxOutputTokens: 20,
            frequencyPenalty: 0.1,
            providerOptions: [
                "openai-compatible": ["echo": .bool(true)],
                "example": ["custom": .string("flag")]
            ]
        )

        let result = try await model.doGenerate(options: options)
        #expect(result.finishReason == LanguageModelV3FinishReason.stop)
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
        #expect(json["custom"] as? String == "flag")
    }

    @Test("embedding doEmbed maps response usage")
    func embeddingDoEmbed() async throws {
        let responseJSON: [String: Any] = [
            "data": [["embedding": [0.1, 0.2, 0.3]]],
            "usage": ["prompt_tokens": 3]
        ]
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let response = makeHTTPResponse(
            url: URL(string: "https://api.example.com/v1/embeddings")!,
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

        let model = provider.textEmbeddingModel(modelId: "text-embedding-3-small")
        let result = try await model.doEmbed(options: EmbeddingModelV3DoEmbedOptions(values: ["hello"]))
        #expect(result.embeddings.count == 1)
        if let first = result.embeddings.first {
            #expect(first == [0.1, 0.2, 0.3])
        } else {
            Issue.record("Missing embedding result")
        }
        #expect(result.usage?.tokens == 3)
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

        let model = provider.imageModel(modelId: "gpt-image")
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
}
