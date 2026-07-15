import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import OpenAICompatibleProvider

@Suite("OpenAICompatibleEmbeddingModelV4")
struct OpenAICompatibleEmbeddingModelV4Tests {
    actor RequestCapture {
        private var request: URLRequest?

        func store(_ request: URLRequest) {
            self.request = request
        }

        func current() -> URLRequest? {
            request
        }
    }

    actor FetchProbe {
        private var callCount = 0

        func recordCall() {
            callCount += 1
        }

        func calls() -> Int {
            callCount
        }
    }

    private func makeHTTPResponse(
        url: URL,
        headers: [String: String] = [:]
    ) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    }

    private func makeResponseData() throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "data": [
                ["embedding": [0.1, 0.2]],
                ["embedding": [0.3, 0.4]]
            ],
            "usage": [
                "prompt_tokens": 8,
                "total_tokens": 8
            ],
            "providerMetadata": [
                "test-provider": ["trace": "ok"]
            ]
        ])
    }

    @Test("factory V4 preserves upstream option precedence warnings and response")
    func factoryV4PreservesOptionPrecedenceWarningsAndResponse() async throws {
        let capture = RequestCapture()
        let responseData = try makeResponseData()
        let targetURL = URL(string: "https://my.api.com/v1/embeddings")!
        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(
                body: .data(responseData),
                urlResponse: makeHTTPResponse(
                    url: targetURL,
                    headers: ["Content-Type": "application/json", "X-Embedding": "ok"]
                )
            )
        }
        let provider = createOpenAICompatible(settings: .init(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: ["Custom-Provider-Header": "provider"],
            fetch: fetch
        ))
        let model = try provider.embeddingModel(modelId: "text-embedding-3-large")

        let result = try await model.doEmbed(options: .init(
            values: ["sunny day", "rainy day"],
            providerOptions: [
                "openai-compatible": [
                    "dimensions": .number(32),
                    "user": .string("legacy-user")
                ],
                "openaiCompatible": [
                    "dimensions": .number(64),
                    "user": .string("compatible-user")
                ],
                "test-provider": [
                    "dimensions": .number(128),
                    "user": .string("provider-user")
                ]
            ],
            headers: ["Custom-Request-Header": "request"]
        ))

        #expect(result.warnings == [
            .deprecated(
                setting: "providerOptions key 'openai-compatible'",
                message: "Use 'openaiCompatible' instead."
            ),
            .deprecated(
                setting: "providerOptions key 'test-provider'",
                message: "Use 'testProvider' instead."
            )
        ])
        #expect(result.embeddings == [[0.1, 0.2], [0.3, 0.4]])
        #expect(result.usage == EmbeddingModelV4Usage(tokens: 8))
        #expect(result.providerMetadata == [
            "test-provider": ["trace": .string("ok")]
        ])
        #expect(result.response?.headers?["x-embedding"] == "ok")

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Missing captured native V4 embedding request")
            return
        }

        let normalizedHeaders = Dictionary(uniqueKeysWithValues:
            (request.allHTTPHeaderFields ?? [:]).map { ($0.key.lowercased(), $0.value) }
        )
        #expect(request.url == targetURL)
        #expect(normalizedHeaders["custom-provider-header"] == "provider")
        #expect(normalizedHeaders["custom-request-header"] == "request")
        #expect(json["model"] as? String == "text-embedding-3-large")
        #expect(json["input"] as? [String] == ["sunny day", "rainy day"])
        #expect(json["encoding_format"] as? String == "float")
        #expect((json["dimensions"] as? NSNumber)?.intValue == 128)
        #expect(json["user"] as? String == "provider-user")
    }

    @Test("camel provider namespace is warning-free without changing upstream option resolution")
    func camelProviderNamespaceIsWarningFree() async throws {
        let capture = RequestCapture()
        let responseData = try makeResponseData()
        let targetURL = URL(string: "https://my.api.com/v1/embeddings")!
        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(
                body: .data(responseData),
                urlResponse: makeHTTPResponse(url: targetURL)
            )
        }
        let provider = createOpenAICompatible(settings: .init(
            baseURL: "https://my.api.com/v1",
            name: "test-provider",
            fetch: fetch
        ))
        let model = try provider.embeddingModel(modelId: "text-embedding-3-large")

        let result = try await model.doEmbed(options: .init(
            values: ["value"],
            providerOptions: [
                "openaiCompatible": ["dimensions": .number(64)],
                "testProvider": ["dimensions": .number(128)]
            ]
        ))

        #expect(result.warnings.isEmpty)
        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Missing camel-case provider option request")
            return
        }
        #expect((json["dimensions"] as? NSNumber)?.intValue == 64)
    }

    @Test("V4 rejects usage objects without prompt_tokens")
    func v4RejectsMalformedUsage() async throws {
        let responseData = try JSONSerialization.data(withJSONObject: [
            "data": [["embedding": [0.1, 0.2]]],
            "usage": ["total_tokens": 2]
        ])
        let targetURL = URL(string: "https://my.api.com/v1/embeddings")!
        let fetch: FetchFunction = { _ in
            FetchResponse(
                body: .data(responseData),
                urlResponse: makeHTTPResponse(url: targetURL)
            )
        }
        let provider = createOpenAICompatible(settings: .init(
            baseURL: "https://my.api.com/v1",
            name: "test-provider",
            fetch: fetch
        ))
        let model = try provider.embeddingModel(modelId: "text-embedding-3-large")

        do {
            _ = try await model.doEmbed(options: .init(values: ["value"]))
            Issue.record("Expected malformed usage to fail response validation")
        } catch let error as APICallError {
            #expect(error.message == "Invalid JSON response")
            _ = try #require(error.cause as? TypeValidationError)
        } catch {
            Issue.record("Expected APICallError, got \(error)")
        }
    }

    @Test("direct V4 model enforces configured call limits before transport")
    func directV4ModelEnforcesConfiguredLimits() async throws {
        let probe = FetchProbe()
        let targetURL = URL(string: "https://my.api.com/v1/embeddings")!
        let responseData = try makeResponseData()
        let fetch: FetchFunction = { _ in
            await probe.recordCall()
            return FetchResponse(
                body: .data(responseData),
                urlResponse: makeHTTPResponse(url: targetURL)
            )
        }
        let model = OpenAICompatibleEmbeddingModelV4(
            modelId: .init(rawValue: "text-embedding-3-large"),
            config: .init(
                provider: "test-provider.embedding",
                url: { _ in targetURL.absoluteString },
                headers: { [:] },
                fetch: fetch,
                maxEmbeddingsPerCall: 1,
                supportsParallelCalls: false
            )
        )

        #expect(try await model.maxEmbeddingsPerCall == 1)
        #expect(try await model.supportsParallelCalls == false)

        do {
            _ = try await model.doEmbed(options: .init(values: ["one", "two"]))
            Issue.record("Expected TooManyEmbeddingValuesForCallError")
        } catch let error as TooManyEmbeddingValuesForCallError {
            #expect(error.provider == "test-provider.embedding")
            #expect(error.modelId == "text-embedding-3-large")
            #expect(error.maxEmbeddingsPerCall == 1)
            #expect(error.values.count == 2)
        }

        #expect(await probe.calls() == 0)
    }
}
