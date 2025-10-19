import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import GoogleProvider

private func makeEmbeddingConfig(fetch: @escaping FetchFunction) -> GoogleGenerativeAIEmbeddingConfig {
    GoogleGenerativeAIEmbeddingConfig(
        provider: "google.generative-ai",
        baseURL: "https://generativelanguage.googleapis.com/v1beta",
        headers: { ["x-goog-api-key": "test"] },
        fetch: fetch
    )
}

@Suite("GoogleGenerativeAIEmbeddingModel")
struct GoogleGenerativeAIEmbeddingModelTests {
    @Test("single value uses embedContent endpoint and maps response")
    func singleEmbeddingRequest() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()
        let responseJSON: [String: Any] = [
            "embedding": [
                "values": [0.1, 0.2, 0.3]
            ]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/text-embedding-004:embedContent")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAIEmbeddingModel(
            modelId: GoogleGenerativeAIEmbeddingModelId(rawValue: "text-embedding-004"),
            config: makeEmbeddingConfig(fetch: fetch)
        )

        let result = try await model.doEmbed(options: .init(values: ["hello world"]))
        #expect(result.embeddings == [[0.1, 0.2, 0.3]])

        guard let request = await capture.value(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Missing request payload")
            return
        }

        #expect(json["model"] as? String == "models/text-embedding-004")
        if let content = json["content"] as? [String: Any],
           let parts = content["parts"] as? [[String: Any]] {
            #expect(parts.first?["text"] as? String == "hello world")
        } else {
            Issue.record("Expected content parts")
        }
    }

    @Test("batch values use batch endpoint and apply provider options")
    func batchEmbeddingRequest() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()
        let responseJSON: [String: Any] = [
            "embeddings": [
                ["values": [0.1]],
                ["values": [0.2]]
            ]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/text-embedding-004:batchEmbedContents")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAIEmbeddingModel(
            modelId: GoogleGenerativeAIEmbeddingModelId(rawValue: "text-embedding-004"),
            config: makeEmbeddingConfig(fetch: fetch)
        )

        _ = try await model.doEmbed(
            options: EmbeddingModelV3DoEmbedOptions(
                values: ["a", "b"],
                providerOptions: [
                    "google": [
                        "outputDimensionality": .number(64),
                        "taskType": .string("SEMANTIC_SIMILARITY")
                    ]
                ]
            )
        )

        guard let request = await capture.value(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any],
              let requests = json["requests"] as? [[String: Any]] else {
            Issue.record("Missing batch payload")
            return
        }

        #expect(requests.count == 2)
        if let first = requests.first {
            #expect(first["model"] as? String == "models/text-embedding-004")
            #expect(first["outputDimensionality"] as? Int == 64)
            #expect(first["taskType"] as? String == "SEMANTIC_SIMILARITY")
        }
    }
}
