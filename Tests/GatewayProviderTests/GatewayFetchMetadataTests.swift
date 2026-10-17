import Foundation
import Testing
import AISDKProviderUtils
@testable import GatewayProvider

@Suite("GatewayFetchMetadata")
struct GatewayFetchMetadataTests {
    actor RequestCapture {
        private(set) var request: URLRequest?
        func store(_ request: URLRequest) { self.request = request }
        func current() -> URLRequest? { request }
    }

    private func normalizedHeaders(_ request: URLRequest) -> [String: String] {
        (request.allHTTPHeaderFields ?? [:]).reduce(into: [String: String]()) { result, pair in
            let key = pair.key.lowercased()
            if key == "user-agent" { return }
            result[key] = pair.value
        }
    }

    private func okJSONResponse(for request: URLRequest, data: Data) throws -> FetchResponse {
        let url = try #require(request.url)
        let httpResponse = try #require(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        ))
        return FetchResponse(body: .data(data), urlResponse: httpResponse)
    }

    @Test("Credits route team identity through the endpoint query", arguments: [" team_123 ", "workspace-name", "  "])
    func creditsTeamRouting(team: String) async throws {
        let metadata = GatewayFetchMetadata(config: GatewayConfig(
            baseURL: "https://api.example.com/some/path?old=value",
            headers: { ["X-Vercel-AI-Gateway-Team": team] },
            fetch: { request in
                let url = try #require(request.url)
                let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                switch team {
                case " team_123 ": #expect(query == [.init(name: "teamId", value: "team_123")])
                case "workspace-name": #expect(query == [.init(name: "slug", value: "workspace-name")])
                default: #expect(query.isEmpty)
                }
                return try okJSONResponse(for: request, data: Data(#"{"balance":"1","total_used":"2"}"#.utf8))
            }
        ))
        let result = try await metadata.getCredits()
        #expect(result.balance == "1")
    }

    @Test("getAvailableModels hits /config and maps cache pricing fields")
    func getAvailableModelsMapsCachePricing() async throws {
        let capture = RequestCapture()

        let responseBody: [String: Any] = [
            "models": [
                [
                    "id": "model-1",
                    "name": "Model One",
                    "description": "A test model",
                    "pricing": [
                        "input": "0.000003",
                        "output": "0.000015",
                        "input_cache_read": "0.0000003",
                        "input_cache_write": "0.00000375",
                    ],
                    "specification": [
                        "specificationVersion": "v4",
                        "provider": "test-provider",
                        "modelId": "model-1",
                    ],
                    "modelType": "language",
                ]
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseBody, options: [.sortedKeys])

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return try okJSONResponse(for: request, data: responseData)
        }

        let metadata = GatewayFetchMetadata(config: GatewayConfig(
            baseURL: "https://api.example.com",
            headers: { () async throws -> [String: String?] in
                ["Authorization": "Bearer test-token"]
            },
            fetch: fetch
        ))

        let result = try await metadata.getAvailableModels()

        guard let request = await capture.current() else {
            Issue.record("Missing request capture")
            return
        }

        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://api.example.com/config")

        let headers = normalizedHeaders(request)
        #expect(headers["authorization"] == "Bearer test-token")

        #expect(result.models.count == 1)
        guard let pricing = result.models.first?.pricing else {
            Issue.record("Expected pricing")
            return
        }

        #expect(pricing.input == "0.000003")
        #expect(pricing.output == "0.000015")
        #expect(pricing.cachedInputTokens == "0.0000003")
        #expect(pricing.cacheCreationInputTokens == "0.00000375")
    }

    @Test("getAvailableModels filters unknown model types")
    func getAvailableModelsFiltersUnknownModelTypes() async throws {
        let responseBody: [String: Any] = [
            "models": [
                [
                    "id": "model-invalid-type",
                    "name": "Invalid Type Model",
                    "specification": [
                        "specificationVersion": "v4",
                        "provider": "test-provider",
                        "modelId": "model-invalid-type",
                    ],
                    "modelType": "text",
                ],
                [
                    "id": "speech-model", "name": "Speech",
                    "specification": ["specificationVersion": "v4", "provider": "test", "modelId": "speech-model"],
                    "modelType": "speech",
                ],
                [
                    "id": "untyped-model", "name": "Untyped",
                    "specification": ["specificationVersion": "v4", "provider": "test", "modelId": "untyped-model"],
                    "modelType": NSNull(),
                ],
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseBody, options: [.sortedKeys])

        let fetch: FetchFunction = { request in
            try okJSONResponse(for: request, data: responseData)
        }

        let metadata = GatewayFetchMetadata(config: GatewayConfig(
            baseURL: "https://api.example.com",
            headers: { () async throws -> [String: String?] in
                ["Authorization": "Bearer test-token"]
            },
            fetch: fetch
        ))

        let result = try await metadata.getAvailableModels()
        #expect(result.models.map(\.id) == ["speech-model", "untyped-model"])
        #expect(result.models.first?.specification.specificationVersion == "v4")
    }

    @Test("getCredits uses baseURL origin and maps total_used")
    func getCreditsUsesOrigin() async throws {
        let capture = RequestCapture()

        let responseBody: [String: Any] = [
            "balance": "150.50",
            "total_used": "75.25",
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseBody, options: [.sortedKeys])

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return try okJSONResponse(for: request, data: responseData)
        }

        let metadata = GatewayFetchMetadata(config: GatewayConfig(
            baseURL: "https://api.example.com/some/path",
            headers: { () async throws -> [String: String?] in
                ["Authorization": "Bearer test-token"]
            },
            fetch: fetch
        ))

        let result = try await metadata.getCredits()

        guard let request = await capture.current() else {
            Issue.record("Missing request capture")
            return
        }

        #expect(request.httpMethod == "GET")
        #expect(request.url?.absoluteString == "https://api.example.com/v1/credits")
        #expect(result.balance == "150.50")
        #expect(result.totalUsed == "75.25")
    }
}
