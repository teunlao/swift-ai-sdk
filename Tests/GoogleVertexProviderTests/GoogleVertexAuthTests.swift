import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
@testable import GoogleVertexProvider

@Suite("GoogleVertex auth")
struct GoogleVertexAuthTests {
    actor RequestCapture {
        private(set) var lastRequest: URLRequest?
        func capture(_ request: URLRequest) { lastRequest = request }
    }

    private func normalizedHeaders(_ request: URLRequest) -> [String: String] {
        (request.allHTTPHeaderFields ?? [:]).reduce(into: [String: String]()) { result, pair in
            result[pair.key.lowercased()] = pair.value
        }
    }

    private func okEmbeddingResponse(for url: URL) throws -> FetchResponse {
        let responseBody: [String: Any] = [
            "predictions": [
                [
                    "embeddings": [
                        "values": [0.1],
                        "statistics": ["token_count": 1]
                    ]
                ]
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: responseBody, options: [.sortedKeys])
        let response = try #require(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        ))
        return FetchResponse(body: .data(data), urlResponse: response)
    }

    @Test("injects Authorization bearer token when apiKey is absent and baseURL is not provided")
    func injectsBearerToken() async throws {
        let capture = RequestCapture()

        actor TokenCalls {
            private(set) var count: Int = 0
            func next() -> String {
                count += 1
                return "test-access-token"
            }
        }

        let tokenCalls = TokenCalls()

        let fetch: FetchFunction = { request in
            await capture.capture(request)
            return try okEmbeddingResponse(for: try #require(request.url))
        }

        let provider = createGoogleVertex(settings: GoogleVertexProviderSettings(
            location: "us-central1",
            project: "test-project",
            fetch: fetch,
            accessTokenProvider: { await tokenCalls.next() }
        ))

        let model = try provider.textEmbeddingModel(modelId: "text-embedding-004")
        _ = try await model.doEmbed(options: .init(values: ["hello"]))

        let request = try #require(await capture.lastRequest)
        let headers = normalizedHeaders(request)
        #expect(headers["authorization"] == "Bearer test-access-token")
        #expect(await tokenCalls.count == 1)
    }

    @Test("does not override Authorization when provided via headers")
    func doesNotOverrideAuthorizationHeader() async throws {
        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.capture(request)
            return try okEmbeddingResponse(for: try #require(request.url))
        }

        let provider = createGoogleVertex(settings: GoogleVertexProviderSettings(
            location: "us-central1",
            project: "test-project",
            headers: ["Authorization": "Bearer custom"],
            fetch: fetch,
            accessTokenProvider: { "test-access-token" }
        ))

        let model = try provider.textEmbeddingModel(modelId: "text-embedding-004")
        _ = try await model.doEmbed(options: .init(values: ["hello"]))

        let request = try #require(await capture.lastRequest)
        let headers = normalizedHeaders(request)
        #expect(headers["authorization"] == "Bearer custom")
    }

    @Test("custom baseURL does not attempt to inject OAuth Authorization")
    func customBaseURLSkipsOAuthInjection() async throws {
        let capture = RequestCapture()

        actor TokenCalls {
            private(set) var count: Int = 0
            func next() -> String {
                count += 1
                return "test-access-token"
            }
        }

        let tokenCalls = TokenCalls()

        let fetch: FetchFunction = { request in
            await capture.capture(request)
            return try okEmbeddingResponse(for: try #require(request.url))
        }

        let provider = createGoogleVertex(settings: GoogleVertexProviderSettings(
            fetch: fetch,
            baseURL: "https://custom-endpoint.example.com",
            accessTokenProvider: { await tokenCalls.next() }
        ))

        let model = try provider.textEmbeddingModel(modelId: "text-embedding-004")
        _ = try await model.doEmbed(options: .init(values: ["hello"]))

        let request = try #require(await capture.lastRequest)
        let headers = normalizedHeaders(request)
        #expect(headers["authorization"] == nil)
        #expect(await tokenCalls.count == 0)
    }
}

