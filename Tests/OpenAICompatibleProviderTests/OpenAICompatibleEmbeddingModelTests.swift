import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import OpenAICompatibleProvider

/**
 Tests for OpenAICompatibleEmbeddingModel.

 Port of `@ai-sdk/openai-compatible/src/embedding/openai-compatible-embedding-model.test.ts`.
 */

@Suite("OpenAICompatibleEmbeddingModel")
struct OpenAICompatibleEmbeddingModelTests {
    actor RequestCapture {
        private(set) var request: URLRequest?
        func store(_ request: URLRequest) { self.request = request }
        func current() -> URLRequest? { request }
    }

    private func makeHTTPResponse(url: URL, statusCode: Int = 200, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    private let dummyEmbeddings = [
        [0.1, 0.2, 0.3, 0.4, 0.5],
        [0.6, 0.7, 0.8, 0.9, 1.0]
    ]

    private let testValues = ["sunny day at the beach", "rainy day in the city"]

    @Test("should extract embedding")
    func extractEmbedding() async throws {
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
            "model": "text-embedding-3-large",
            "usage": [
                "prompt_tokens": 8,
                "total_tokens": 8
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/embeddings")!
        let httpResponse = makeHTTPResponse(url: targetURL)

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch
        ))

        let model = provider.textEmbeddingModel(modelId: "text-embedding-3-large")
        let result = try await model.doEmbed(options: EmbeddingModelV3DoEmbedOptions(values: testValues))

        #expect(result.embeddings == dummyEmbeddings)
    }

    @Test("should expose the raw response headers")
    func exposeResponseHeaders() async throws {
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
            "model": "text-embedding-3-large",
            "usage": [
                "prompt_tokens": 8,
                "total_tokens": 8
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/embeddings")!
        let httpResponse = makeHTTPResponse(url: targetURL, headers: ["test-header": "test-value"])

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch
        ))

        let model = provider.textEmbeddingModel(modelId: "text-embedding-3-large")
        let result = try await model.doEmbed(options: EmbeddingModelV3DoEmbedOptions(values: testValues))

        #expect(result.response?.headers?["test-header"] == "test-value")
    }

    @Test("should extract usage")
    func extractUsage() async throws {
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
            "model": "text-embedding-3-large",
            "usage": [
                "prompt_tokens": 20,
                "total_tokens": 20
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/embeddings")!
        let httpResponse = makeHTTPResponse(url: targetURL)

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch
        ))

        let model = provider.textEmbeddingModel(modelId: "text-embedding-3-large")
        let result = try await model.doEmbed(options: EmbeddingModelV3DoEmbedOptions(values: testValues))

        #expect(result.usage?.tokens == 20)
    }

    @Test("should pass the model and the values")
    func passModelAndValues() async throws {
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
            "model": "text-embedding-3-large",
            "usage": [
                "prompt_tokens": 8,
                "total_tokens": 8
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/embeddings")!
        let httpResponse = makeHTTPResponse(url: targetURL)

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch
        ))

        let model = provider.textEmbeddingModel(modelId: "text-embedding-3-large")
        _ = try await model.doEmbed(options: EmbeddingModelV3DoEmbedOptions(values: testValues))

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Missing captured request")
            return
        }

        #expect(json["model"] as? String == "text-embedding-3-large")
        if let input = json["input"] as? [String] {
            #expect(input == testValues)
        } else {
            Issue.record("Expected input array")
        }
        #expect(json["encoding_format"] as? String == "float")
    }

    @Test("should pass the dimensions setting")
    func passDimensionsSetting() async throws {
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
            "model": "text-embedding-3-large",
            "usage": [
                "prompt_tokens": 8,
                "total_tokens": 8
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/embeddings")!
        let httpResponse = makeHTTPResponse(url: targetURL)

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch
        ))

        let model = provider.textEmbeddingModel(modelId: "text-embedding-3-large")
        _ = try await model.doEmbed(
            options: EmbeddingModelV3DoEmbedOptions(
                values: testValues,
                providerOptions: [
                    "openai-compatible": ["dimensions": .number(64)]
                ]
            )
        )

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Missing captured request")
            return
        }

        #expect(json["model"] as? String == "text-embedding-3-large")
        if let input = json["input"] as? [String] {
            #expect(input == testValues)
        } else {
            Issue.record("Expected input array")
        }
        #expect(json["encoding_format"] as? String == "float")
        #expect(json["dimensions"] as? Double == 64)
    }

    @Test("should pass headers")
    func passHeaders() async throws {
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
            "model": "text-embedding-3-large",
            "usage": [
                "prompt_tokens": 8,
                "total_tokens": 8
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/embeddings")!
        let httpResponse = makeHTTPResponse(url: targetURL)

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: [
                "Authorization": "Bearer test-api-key",
                "Custom-Provider-Header": "provider-header-value"
            ],
            fetch: fetch
        ))

        let model = provider.textEmbeddingModel(modelId: "text-embedding-3-large")
        _ = try await model.doEmbed(
            options: EmbeddingModelV3DoEmbedOptions(
                values: testValues,
                headers: ["Custom-Request-Header": "request-header-value"]
            )
        )

        guard let request = await capture.current() else {
            Issue.record("Missing captured request")
            return
        }

        let headers = request.allHTTPHeaderFields ?? [:]
        let normalizedHeaders = headers.reduce(into: [String: String]()) { result, entry in
            result[entry.key.lowercased()] = entry.value
        }

        #expect(normalizedHeaders["authorization"] == "Bearer test-api-key")
        #expect(normalizedHeaders["custom-provider-header"] == "provider-header-value")
        #expect(normalizedHeaders["custom-request-header"] == "request-header-value")
    }
}
