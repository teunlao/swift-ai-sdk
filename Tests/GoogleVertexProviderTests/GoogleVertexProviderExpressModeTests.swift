import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
@testable import GoogleVertexProvider

@Suite("GoogleVertexProvider (express mode)")
struct GoogleVertexProviderExpressModeTests {
    actor RequestCapture {
        private(set) var lastRequest: URLRequest?

        func set(_ request: URLRequest) {
            lastRequest = request
        }
    }

    private func headerValue(_ name: String, in request: URLRequest) -> String? {
        request.allHTTPHeaderFields?.first(where: { $0.key.lowercased() == name.lowercased() })?.value
    }

    @Test("should use express mode baseURL and always override x-goog-api-key header")
    func expressMode_setsApiKeyHeader_andUsesExpressBaseURL() async throws {
        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.set(request)

            let url = try #require(request.url)
            let json = #"{"predictions":[{"embeddings":{"values":[0.1],"statistics":{"token_count":1}}}]}"#
            let data = Data(json.utf8)
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            return FetchResponse(body: .data(data), urlResponse: response)
        }

        let provider = createGoogleVertex(settings: GoogleVertexProviderSettings(
            apiKey: "KEY",
            fetch: fetch
        ))

        let model = try provider.textEmbeddingModel(modelId: "text-embedding-004")
        _ = try await model.doEmbed(options: EmbeddingModelV3DoEmbedOptions(
            values: ["hello"],
            headers: ["X-Goog-Api-Key": "WRONG"]
        ))

        let lastRequest = await capture.lastRequest
        let request = try #require(lastRequest)
        #expect(request.url?.absoluteString == "https://aiplatform.googleapis.com/v1/publishers/google/models/text-embedding-004:predict")
        #expect(headerValue("x-goog-api-key", in: request) == "KEY")
    }

    @Test("should use project/location baseURL when apiKey is not provided")
    func nonExpressMode_usesRegionalBaseURL_withoutApiKeyHeader() async throws {
        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.set(request)

            let url = try #require(request.url)
            let json = #"{"predictions":[{"embeddings":{"values":[0.1],"statistics":{"token_count":1}}}]}"#
            let data = Data(json.utf8)
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            return FetchResponse(body: .data(data), urlResponse: response)
        }

        let provider = createGoogleVertex(settings: GoogleVertexProviderSettings(
            location: "us-central1",
            project: "test-project",
            fetch: fetch
        ))

        let model = try provider.textEmbeddingModel(modelId: "text-embedding-004")
        _ = try await model.doEmbed(options: EmbeddingModelV3DoEmbedOptions(values: ["hello"]))

        let lastRequest = await capture.lastRequest
        let request = try #require(lastRequest)
        #expect(request.url?.absoluteString == "https://us-central1-aiplatform.googleapis.com/v1beta1/projects/test-project/locations/us-central1/publishers/google/models/text-embedding-004:predict")
        #expect(headerValue("x-goog-api-key", in: request) == nil)
    }

    @Test("should read embedding providerOptions from `vertex` key (upstream parity)")
    func embeddingProviderOptions_acceptVertexKey() async throws {
        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.set(request)

            let url = try #require(request.url)
            let json = #"{"predictions":[{"embeddings":{"values":[0.1],"statistics":{"token_count":1}}}]}"#
            let data = Data(json.utf8)
            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            return FetchResponse(body: .data(data), urlResponse: response)
        }

        let provider = createGoogleVertex(settings: GoogleVertexProviderSettings(
            location: "us-central1",
            project: "test-project",
            fetch: fetch
        ))

        let model = try provider.textEmbeddingModel(modelId: "text-embedding-004")
        _ = try await model.doEmbed(options: EmbeddingModelV3DoEmbedOptions(
            values: ["hello"],
            providerOptions: [
                "vertex": [
                    "taskType": .string("SEMANTIC_SIMILARITY")
                ]
            ]
        ))

        let lastRequest = await capture.lastRequest
        let request = try #require(lastRequest)
        let body = try #require(request.httpBody)
        let json = try JSONSerialization.jsonObject(with: body)
        let dict = try #require(json as? [String: Any])
        let instances = try #require(dict["instances"] as? [[String: Any]])
        let first = try #require(instances.first)
        #expect(first["task_type"] as? String == "SEMANTIC_SIMILARITY")
    }
}
