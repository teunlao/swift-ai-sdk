import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import OpenAIProvider

@Suite("OpenAIEmbeddingModel")
struct OpenAIEmbeddingModelTests {
    private actor RequestCapture {
        var request: URLRequest?
        func store(_ request: URLRequest) { self.request = request }
        func value() -> URLRequest? { request }
    }

    @Test("embedding requests honor portable dimensions and provider precedence", arguments: [false, true])
    func dimensionsAndResponse(providerOverride: Bool) async throws {
        let capture = RequestCapture()
        let responseBody = Data(#"{"data":[{"embedding":[0.1,0.2]}],"usage":{"prompt_tokens":8},"model":"text-embedding-3-small"}"#.utf8)
        let provider: any ProviderV4 = try createOpenAI(settings: .init(
            baseURL: "https://proxy.example/v1/",
            apiKey: "test-api-key",
            headers: ["X-Provider": "provider"],
            fetch: { request in
                await capture.store(request)
                return FetchResponse(body: .data(responseBody), urlResponse: HTTPURLResponse(
                    url: request.url!, statusCode: 200, httpVersion: nil,
                    headerFields: ["Content-Type": "application/json", "X-Response": "response"]
                )!)
            }
        ))
        let model = try provider.embeddingModel(modelId: "text-embedding-3-small")
        let result = try await model.doEmbed(options: .init(
            values: ["hello"],
            dimensions: 32,
            providerOptions: ["openai": providerOverride
                ? ["dimensions": .number(64), "user": .string("test-user")]
                : ["user": .string("test-user")]],
            headers: ["X-Request": "request"]
        ))

        #expect(result.embeddings == [[0.1, 0.2]])
        #expect(result.usage?.tokens == 8)
        #expect(result.warnings.isEmpty)
        #expect(result.response?.headers?["x-response"] == "response")
        let raw = try #require(result.response?.body as? [String: Any])
        #expect(raw["model"] as? String == "text-embedding-3-small")
        let request = try #require(await capture.value())
        #expect(request.url?.absoluteString == "https://proxy.example/v1/embeddings")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-api-key")
        #expect(request.value(forHTTPHeaderField: "X-Provider") == "provider")
        #expect(request.value(forHTTPHeaderField: "X-Request") == "request")
        let data = try #require(request.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["model"] as? String == "text-embedding-3-small")
        #expect(body["input"] as? [String] == ["hello"])
        #expect(body["encoding_format"] as? String == "float")
        #expect(body["dimensions"] as? Int == (providerOverride ? 64 : 32))
        #expect(body["user"] as? String == "test-user")
    }

    @Test("missing usage and dimensions stay optional at the API boundary")
    func optionalUsageAndDimensions() async throws {
        let capture = RequestCapture()
        let model = OpenAIEmbeddingModel(modelId: "custom-embedding", config: .init(
            provider: "custom.embedding",
            url: { _ in "https://example.com/embeddings" },
            headers: { [:] },
            fetch: { request in
                await capture.store(request)
                return FetchResponse(
                    body: .data(Data(#"{"data":[{"embedding":[1,2]}]}"#.utf8)),
                    urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
                )
            }
        ))
        let result = try await model.doEmbed(options: .init(values: ["hello"]))
        #expect(result.embeddings == [[1, 2]])
        #expect(result.usage == nil)
        let request = try #require(await capture.value())
        let data = try #require(request.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["dimensions"] == nil)
    }

    @Test("invalid provider dimensions produce a typed option error", arguments: [JSONValue.null, .number(.infinity)])
    func invalidDimensions(value: JSONValue) async throws {
        let provider = try createOpenAI(settings: .init(apiKey: "test-api-key", fetch: { request in
            FetchResponse(
                body: .data(Data(#"{"data":[{"embedding":[1]}]}"#.utf8)),
                urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            )
        }))
        do {
            _ = try await provider.embedding("text-embedding-3-small").doEmbed(options: .init(
                values: ["hello"], providerOptions: ["openai": ["dimensions": value]]
            ))
            Issue.record("Expected invalid provider dimensions to be rejected")
        } catch let error as InvalidArgumentError {
            #expect(error.argument == "providerOptions")
            #expect(error.cause is TypeValidationError)
        }
    }

    @Test("the per-call count limit accepts its boundary and rejects excess values")
    func countLimit() async throws {
        let model = OpenAIEmbeddingModel(modelId: "text-embedding-3-small", config: .init(
            provider: "openai.embedding",
            url: { _ in "https://example.com/embeddings" },
            headers: { [:] },
            fetch: { request in
                let data = try #require(request.httpBody)
                let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
                #expect((body["input"] as? [String])?.count == 2048)
                return FetchResponse(
                    body: .data(Data(#"{"data":[{"embedding":[1]}]}"#.utf8)),
                    urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
                )
            }
        ))
        let result = try await model.doEmbed(options: .init(values: Array(repeating: "x", count: 2048)))
        #expect(result.embeddings == [[1]])
        do {
            _ = try await model.doEmbed(options: .init(values: Array(repeating: "x", count: 2049)))
            Issue.record("Expected the embedding count boundary to reject the call")
        } catch let error as TooManyEmbeddingValuesForCallError {
            #expect(error.provider == "openai.embedding")
            #expect(error.modelId == "text-embedding-3-small")
            #expect(error.maxEmbeddingsPerCall == 2048)
            #expect(error.values.count == 2049)
        }
    }
}
