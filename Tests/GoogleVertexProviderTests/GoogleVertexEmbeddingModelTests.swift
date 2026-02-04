import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
@testable import GoogleVertexProvider

@Suite("GoogleVertexEmbeddingModel")
struct GoogleVertexEmbeddingModelTests {
    actor RequestCapture {
        private(set) var lastRequest: URLRequest?
        private(set) var callCount: Int = 0

        func capture(_ request: URLRequest) {
            lastRequest = request
            callCount += 1
        }
    }

    private func headerValue(_ name: String, in request: URLRequest) -> String? {
        request.allHTTPHeaderFields?.first(where: { $0.key.lowercased() == name.lowercased() })?.value
    }

    private func normalizedHeaders(_ request: URLRequest) -> [String: String] {
        (request.allHTTPHeaderFields ?? [:]).reduce(into: [String: String]()) { result, pair in
            result[pair.key.lowercased()] = pair.value
        }
    }

    private func makePredictionsData(
        embeddings: [[Double]],
        tokenCounts: [Int],
        url: URL
    ) throws -> (data: Data, response: HTTPURLResponse) {
        let body: [String: Any] = [
            "predictions": zip(embeddings, tokenCounts).map { values, tokenCount in
                [
                    "embeddings": [
                        "values": values,
                        "statistics": ["token_count": tokenCount]
                    ]
                ]
            }
        ]

        let data = try JSONSerialization.data(withJSONObject: body)
        let response = try #require(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        ))

        return (data, response)
    }

    private func makeModel(fetch: @escaping FetchFunction) -> GoogleVertexEmbeddingModel {
        GoogleVertexEmbeddingModel(
            modelId: GoogleVertexEmbeddingModelId(rawValue: "textembedding-gecko@001"),
            config: GoogleVertexEmbeddingConfig(
                provider: "google-vertex",
                baseURL: "https://us-central1-aiplatform.googleapis.com/v1beta1/projects/test-project/locations/us-central1/publishers/google",
                headers: { [:] as [String: String?] },
                fetch: fetch
            )
        )
    }

    @Test("should extract embeddings")
    func extractEmbeddings() async throws {
        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.capture(request)

            let url = try #require(request.url)
            let (data, response) = try makePredictionsData(
                embeddings: [[0.1, 0.2, 0.3], [0.4, 0.5, 0.6]],
                tokenCounts: [1, 1],
                url: url
            )
            return FetchResponse(body: .data(data), urlResponse: response)
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doEmbed(options: .init(values: ["test text one", "test text two"]))
        #expect(result.embeddings == [[0.1, 0.2, 0.3], [0.4, 0.5, 0.6]])
    }

    @Test("should expose the raw response")
    func exposeRawResponse() async throws {
        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.capture(request)

            let url = try #require(request.url)
            let body: [String: Any] = [
                "predictions": [
                    ["embeddings": ["values": [0.1, 0.2, 0.3], "statistics": ["token_count": 1]]]
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: body)
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: [
                    "Content-Type": "application/json",
                    "test-header": "test-value",
                    "Content-Length": "\(data.count)"
                ]
            ))

            return FetchResponse(body: .data(data), urlResponse: response)
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doEmbed(options: .init(values: ["test text one", "test text two"]))

        #expect(result.response != nil)
        if let response = result.response {
            #expect(response.headers?["test-header"] == "test-value")
            #expect(response.headers?["content-type"] == "application/json")
            #expect(response.headers?["content-length"] != nil)
        } else {
            Issue.record("Expected response metadata")
        }
    }

    @Test("should extract usage")
    func extractUsage() async throws {
        let fetch: FetchFunction = { request in
            let url = try #require(request.url)
            let (data, response) = try makePredictionsData(
                embeddings: [[0.1], [0.2]],
                tokenCounts: [10, 15],
                url: url
            )
            return FetchResponse(body: .data(data), urlResponse: response)
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doEmbed(options: .init(values: ["test text one", "test text two"]))
        #expect(result.usage?.tokens == 25)
    }

    @Test("should pass the model parameters correctly")
    func passModelParametersCorrectly() async throws {
        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.capture(request)

            let url = try #require(request.url)
            let (data, response) = try makePredictionsData(
                embeddings: [[0.1], [0.2]],
                tokenCounts: [1, 1],
                url: url
            )
            return FetchResponse(body: .data(data), urlResponse: response)
        }

        let model = makeModel(fetch: fetch)
        _ = try await model.doEmbed(options: .init(
            values: ["test text one", "test text two"],
            providerOptions: [
                "google": [
                    "outputDimensionality": .number(768),
                    "taskType": .string("SEMANTIC_SIMILARITY"),
                    "title": .string("test title"),
                    "autoTruncate": .bool(false)
                ]
            ]
        ))

        let request = try #require(await capture.lastRequest)
        let body = try #require(request.httpBody)
        let json = try JSONSerialization.jsonObject(with: body)
        let dict = try #require(json as? [String: Any])

        let instances = try #require(dict["instances"] as? [[String: Any]])
        #expect(instances.count == 2)
        #expect(instances[0]["content"] as? String == "test text one")
        #expect(instances[0]["task_type"] as? String == "SEMANTIC_SIMILARITY")
        #expect(instances[0]["title"] as? String == "test title")
        #expect(instances[1]["content"] as? String == "test text two")
        #expect(instances[1]["task_type"] as? String == "SEMANTIC_SIMILARITY")
        #expect(instances[1]["title"] as? String == "test title")

        let parameters = try #require(dict["parameters"] as? [String: Any])
        #expect((parameters["outputDimensionality"] as? NSNumber)?.intValue == 768)
        #expect(parameters["autoTruncate"] as? Bool == false)
    }

    @Test("should pass the taskType setting in instances")
    func passTaskTypeInInstances() async throws {
        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.capture(request)

            let url = try #require(request.url)
            let (data, response) = try makePredictionsData(
                embeddings: [[0.1]],
                tokenCounts: [1],
                url: url
            )
            return FetchResponse(body: .data(data), urlResponse: response)
        }

        let model = makeModel(fetch: fetch)
        _ = try await model.doEmbed(options: .init(
            values: ["test text one"],
            providerOptions: [
                "google": [
                    "taskType": .string("SEMANTIC_SIMILARITY")
                ]
            ]
        ))

        let request = try #require(await capture.lastRequest)
        let body = try #require(request.httpBody)
        let json = try JSONSerialization.jsonObject(with: body)
        let dict = try #require(json as? [String: Any])
        let instances = try #require(dict["instances"] as? [[String: Any]])
        let first = try #require(instances.first)
        #expect(first["task_type"] as? String == "SEMANTIC_SIMILARITY")

        let parameters = try #require(dict["parameters"] as? [String: Any])
        #expect(parameters.isEmpty)
    }

    @Test("should pass the title setting in instances")
    func passTitleInInstances() async throws {
        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.capture(request)

            let url = try #require(request.url)
            let (data, response) = try makePredictionsData(
                embeddings: [[0.1]],
                tokenCounts: [1],
                url: url
            )
            return FetchResponse(body: .data(data), urlResponse: response)
        }

        let model = makeModel(fetch: fetch)
        _ = try await model.doEmbed(options: .init(
            values: ["test text one"],
            providerOptions: [
                "google": [
                    "title": .string("test title")
                ]
            ]
        ))

        let request = try #require(await capture.lastRequest)
        let body = try #require(request.httpBody)
        let json = try JSONSerialization.jsonObject(with: body)
        let dict = try #require(json as? [String: Any])
        let instances = try #require(dict["instances"] as? [[String: Any]])
        let first = try #require(instances.first)
        #expect(first["title"] as? String == "test title")

        let parameters = try #require(dict["parameters"] as? [String: Any])
        #expect(parameters.isEmpty)
    }

    @Test("should pass headers correctly and include user-agent suffix")
    func passHeadersCorrectly() async throws {
        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.capture(request)

            let url = try #require(request.url)
            let (data, response) = try makePredictionsData(
                embeddings: [[0.1]],
                tokenCounts: [1],
                url: url
            )
            return FetchResponse(body: .data(data), urlResponse: response)
        }

        let provider = createGoogleVertex(settings: GoogleVertexProviderSettings(
            location: "us-central1",
            project: "test-project",
            headers: ["X-Custom-Header": "custom-value"],
            fetch: fetch
        ))

        let model = try provider.textEmbeddingModel(modelId: "textembedding-gecko@001")
        _ = try await model.doEmbed(options: EmbeddingModelV3DoEmbedOptions(
            values: ["test text one", "test text two"],
            providerOptions: [
                "google": [
                    "outputDimensionality": .number(768)
                ]
            ],
            headers: ["X-Request-Header": "request-value"]
        ))

        let request = try #require(await capture.lastRequest)
        let headers = normalizedHeaders(request)
        #expect(headers["content-type"] == "application/json")
        #expect(headers["x-custom-header"] == "custom-value")
        #expect(headers["x-request-header"] == "request-value")

        let userAgent = try #require(headerValue("user-agent", in: request))
        #expect(userAgent.contains("ai-sdk/google-vertex/\(GOOGLE_VERTEX_VERSION)"))
    }

    @Test("should throw TooManyEmbeddingValuesForCallError when too many values provided")
    func throwTooManyEmbeddingValuesForCallError() async throws {
        let model = GoogleVertexEmbeddingModel(
            modelId: GoogleVertexEmbeddingModelId(rawValue: "textembedding-gecko@001"),
            config: GoogleVertexEmbeddingConfig(
                provider: "google-vertex",
                baseURL: "https://custom-endpoint.com",
                headers: { [:] as [String: String?] },
                fetch: nil
            )
        )

        let tooManyValues = Array(repeating: "test", count: 2049)

        do {
            _ = try await model.doEmbed(options: .init(values: tooManyValues))
            Issue.record("Expected error to be thrown")
        } catch let error as TooManyEmbeddingValuesForCallError {
            #expect(error.provider == "google-vertex")
            #expect(error.modelId == "textembedding-gecko@001")
            #expect(error.maxEmbeddingsPerCall == 2048)
            #expect(error.values.count == 2049)
        } catch {
            Issue.record("Expected TooManyEmbeddingValuesForCallError, got: \(error)")
        }
    }

    @Test("should use custom baseURL when provided")
    func useCustomBaseURL() async throws {
        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.capture(request)

            let url = try #require(request.url)
            let (data, response) = try makePredictionsData(
                embeddings: [[0.1, 0.2, 0.3], [0.4, 0.5, 0.6]],
                tokenCounts: [1, 1],
                url: url
            )
            return FetchResponse(body: .data(data), urlResponse: response)
        }

        let provider = createGoogleVertex(settings: GoogleVertexProviderSettings(
            location: "us-central1",
            project: "test-project",
            fetch: fetch,
            baseURL: "https://custom-endpoint.com"
        ))

        let model = try provider.textEmbeddingModel(modelId: "textembedding-gecko@001")
        let result = try await model.doEmbed(options: EmbeddingModelV3DoEmbedOptions(
            values: ["test text one", "test text two"],
            providerOptions: [
                "google": ["outputDimensionality": .number(768)]
            ]
        ))

        #expect(result.embeddings == [[0.1, 0.2, 0.3], [0.4, 0.5, 0.6]])

        let request = try #require(await capture.lastRequest)
        #expect(request.url?.absoluteString == "https://custom-endpoint.com/models/textembedding-gecko@001:predict")
    }

    @Test("should use custom fetch when provided and include proper request content")
    func useCustomFetch_andIncludeProperRequestContent() async throws {
        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.capture(request)

            let url = try #require(request.url)
            let (data, response) = try makePredictionsData(
                embeddings: [[0.1], [0.2]],
                tokenCounts: [1, 1],
                url: url
            )
            return FetchResponse(body: .data(data), urlResponse: response)
        }

        let model = GoogleVertexEmbeddingModel(
            modelId: GoogleVertexEmbeddingModelId(rawValue: "textembedding-gecko@001"),
            config: GoogleVertexEmbeddingConfig(
                provider: "google-vertex",
                baseURL: "https://custom-endpoint.com",
                headers: { [:] as [String: String?] },
                fetch: fetch
            )
        )

        let result = try await model.doEmbed(options: .init(
            values: ["test text one", "test text two"],
            providerOptions: [
                "google": [
                    "outputDimensionality": .number(768)
                ]
            ]
        ))

        #expect(result.embeddings == [[0.1], [0.2]])
        #expect(await capture.callCount == 1)

        let request = try #require(await capture.lastRequest)
        #expect(request.url?.absoluteString == "https://custom-endpoint.com/models/textembedding-gecko@001:predict")

        let body = try #require(request.httpBody)
        let json = try JSONSerialization.jsonObject(with: body)
        let dict = try #require(json as? [String: Any])

        let instances = try #require(dict["instances"] as? [[String: Any]])
        #expect(instances.count == 2)
        #expect(instances[0]["content"] as? String == "test text one")
        #expect(instances[1]["content"] as? String == "test text two")

        let parameters = try #require(dict["parameters"] as? [String: Any])
        #expect((parameters["outputDimensionality"] as? NSNumber)?.intValue == 768)
    }
}
