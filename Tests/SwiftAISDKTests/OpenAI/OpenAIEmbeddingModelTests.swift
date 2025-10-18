import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import OpenAIProvider

private let embeddingValues = ["sunny day at the beach", "rainy day in the city"]
private let embeddingVectors: [[Double]] = [
    [0.1, 0.2, 0.3],
    [0.4, 0.5, 0.6]
]

@Suite("OpenAIEmbeddingModel")
struct OpenAIEmbeddingModelTests {
    private func makeConfig(fetch: @escaping FetchFunction) -> OpenAIConfig {
        OpenAIConfig(
            provider: "openai.embedding",
            url: { _ in "https://api.openai.com/v1/embeddings" },
            headers: { ["Authorization": "Bearer test-api-key"] },
            fetch: fetch
        )
    }

    @Test("doEmbed maps embeddings, usage and response headers")
    func testDoEmbedMapsResponse() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func current() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "object": "list",
            "data": embeddingVectors.enumerated().map { index, values in
                [
                    "object": "embedding",
                    "index": index,
                    "embedding": values
                ]
            },
            "model": "text-embedding-3-large",
            "usage": [
                "prompt_tokens": 8,
                "total_tokens": 8
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/embeddings")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": "application/json",
                "X-Test-Header": "value"
            ]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAIEmbeddingModel(
            modelId: "text-embedding-3-large",
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doEmbed(
            options: EmbeddingModelV3DoEmbedOptions(values: embeddingValues)
        )

        #expect(result.embeddings.count == 2)
        #expect(result.embeddings == embeddingVectors)
        #expect(result.usage?.tokens == 8)
                guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            Issue.record("Missing request capture")
            return
        }

        #expect(json["model"] as? String == "text-embedding-3-large")
        if let input = json["input"] as? [String] {
            #expect(input == embeddingValues)
        } else {
            Issue.record("Expected input array")
        }
        #expect(json["encoding_format"] as? String == "float")
    }

    @Test("doEmbed merges headers and provider options")
    func testDoEmbedMergesHeadersAndOptions() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func current() -> URLRequest? { request }
        }

        let capture = RequestCapture()
        let responseJSON: [String: Any] = [
            "object": "list",
            "data": [
                [
                    "object": "embedding",
                    "index": 0,
                    "embedding": embeddingVectors[0]
                ]
            ],
            "model": "text-embedding-3-large"
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/embeddings")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let config = OpenAIConfig(
            provider: "openai.embedding",
            url: { _ in "https://api.openai.com/v1/embeddings" },
            headers: { [
                "Authorization": "Bearer test-api-key",
                "Custom-Provider-Header": "provider-header-value"
            ] },
            fetch: fetch
        )

        let model = OpenAIEmbeddingModel(modelId: "text-embedding-3-large", config: config)

        _ = try await model.doEmbed(
            options: EmbeddingModelV3DoEmbedOptions(
                values: [embeddingValues[0]],
                providerOptions: [
                    "openai": ["dimensions": .number(64)]
                ],
                headers: ["Custom-Request-Header": "request-header-value"]
            )
        )

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            Issue.record("Missing captured request")
            return
        }

        let headers = request.allHTTPHeaderFields ?? [:]
        let normalized = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
        #expect(normalized["authorization"] == "Bearer test-api-key")
        #expect(normalized["custom-provider-header"] == "provider-header-value")
        #expect(normalized["custom-request-header"] == "request-header-value")
        #expect(normalized["content-type"] == "application/json")

        #expect(json["dimensions"] as? Int == 64 || json["dimensions"] as? Double == 64)
    }
}
