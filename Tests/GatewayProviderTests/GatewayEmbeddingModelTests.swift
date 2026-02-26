import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
@testable import GatewayProvider

@Suite("GatewayEmbeddingModel")
struct GatewayEmbeddingModelTests {
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

    private func httpResponse(for request: URLRequest, statusCode: Int = 200, headers: [String: String] = [:]) throws -> HTTPURLResponse {
        let url = try #require(request.url)
        return try #require(HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ))
    }

    private func makeModel(
        fetch: @escaping FetchFunction,
        o11yHeaders: [String: String] = [:]
    ) -> GatewayEmbeddingModel {
        GatewayEmbeddingModel(
            modelId: GatewayEmbeddingModelId(rawValue: "openai/text-embedding-3-small"),
            config: GatewayEmbeddingModelConfig(
                provider: "gateway",
                baseURL: "https://api.test.com",
                headers: { () async throws -> [String: String?] in
                    [
                        "Authorization": "Bearer test-token",
                        GATEWAY_AUTH_METHOD_HEADER: "api-key",
                    ]
                },
                fetch: fetch,
                o11yHeaders: { () async throws -> [String: String?] in
                    o11yHeaders.mapValues { Optional($0) }
                }
            )
        )
    }

    @Test("doEmbed passes headers and sends values array")
    func doEmbedHeadersAndBody() async throws {
        let capture = RequestCapture()

        let responseBody: [String: Any] = [
            "embeddings": [
                [0.1, 0.2, 0.3],
                [0.4, 0.5, 0.6],
            ],
            "usage": ["tokens": 8],
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseBody, options: [.sortedKeys])

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let httpResponse = try httpResponse(for: request, headers: ["Content-Type": "application/json"])
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let o11yHeaders: [String: String] = [
            "ai-o11y-deployment-id": "deployment-1",
            "ai-o11y-environment": "production",
            "ai-o11y-region": "iad1",
        ]

        let model = makeModel(fetch: fetch, o11yHeaders: o11yHeaders)

        _ = try await model.doEmbed(options: .init(
            values: ["sunny", "rainy"],
            headers: ["Custom-Header": "test-value"]
        ))

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            Issue.record("Missing request capture")
            return
        }

        #expect(request.url?.absoluteString == "https://api.test.com/embedding-model")

        let headers = normalizedHeaders(request)
        #expect(headers["authorization"] == "Bearer test-token")
        #expect(headers["custom-header"] == "test-value")
        #expect(headers["ai-embedding-model-specification-version"] == "3")
        #expect(headers["ai-model-id"] == "openai/text-embedding-3-small")
        for (key, value) in o11yHeaders {
            #expect(headers[key] == value)
        }

        guard let values = json["values"] as? [String] else {
            Issue.record("Expected values array")
            return
        }
        #expect(values == ["sunny", "rainy"])
        #expect(json["providerOptions"] == nil)
    }

    @Test("doEmbed passes providerOptions when provided")
    func doEmbedProviderOptions() async throws {
        let capture = RequestCapture()

        let responseBody: [String: Any] = [
            "embeddings": [[0.1]],
            "usage": ["tokens": 1],
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseBody, options: [.sortedKeys])

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let httpResponse = try httpResponse(for: request, headers: ["Content-Type": "application/json"])
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = makeModel(fetch: fetch)

        _ = try await model.doEmbed(options: .init(
            values: ["a"],
            providerOptions: [
                "openai": ["dimensions": .number(64)]
            ]
        ))

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            Issue.record("Missing request capture")
            return
        }

        guard let providerOptions = json["providerOptions"] as? [String: Any],
              let openai = providerOptions["openai"] as? [String: Any]
        else {
            Issue.record("Expected providerOptions.openai")
            return
        }

        #expect(openai["dimensions"] as? Double == 64)
    }

    @Test("doEmbed extracts embeddings/usage and providerMetadata")
    func doEmbedResponseMapping() async throws {
        let responseBody: [String: Any] = [
            "embeddings": [
                [0.1, 0.2, 0.3],
                [0.4, 0.5, 0.6],
            ],
            "usage": ["tokens": 42],
            "providerMetadata": [
                "gateway": [
                    "routing": ["test": true]
                ]
            ],
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseBody, options: [.sortedKeys])

        let fetch: FetchFunction = { request in
            let httpResponse = try httpResponse(for: request, headers: ["Content-Type": "application/json"])
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = makeModel(fetch: fetch)
        let result = try await model.doEmbed(options: .init(values: ["a", "b"]))

        #expect(result.embeddings == [
            [0.1, 0.2, 0.3],
            [0.4, 0.5, 0.6],
        ])
        #expect(result.usage?.tokens == 42)
        #expect(result.providerMetadata?["gateway"]?["routing"] == .object(["test": .bool(true)]))

        guard let body = result.response?.body as? [String: Any],
              let providerMetadata = body["providerMetadata"] as? [String: Any]
        else {
            Issue.record("Expected providerMetadata in response body")
            return
        }

        #expect(providerMetadata["gateway"] != nil)
    }

    @Test("doEmbed converts gateway error responses")
    func doEmbedErrorMapping() async throws {
        func makeErrorFetch(statusCode: Int, type: String, message: String) throws -> FetchFunction {
            let body = [
                "error": [
                    "message": message,
                    "type": type,
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])

            return { request in
                let httpResponse = try httpResponse(for: request, statusCode: statusCode, headers: ["Content-Type": "application/json"])
                return FetchResponse(body: .data(data), urlResponse: httpResponse)
            }
        }

        do {
            let model = makeModel(fetch: try makeErrorFetch(statusCode: 400, type: "invalid_request_error", message: "Invalid input"))
            _ = try await model.doEmbed(options: .init(values: ["a"]))
            Issue.record("Expected error")
        } catch {
            #expect(GatewayInvalidRequestError.isInstance(error))
            if let err = error as? GatewayInvalidRequestError {
                #expect(err.statusCode == 400)
            }
        }

        do {
            let model = makeModel(fetch: try makeErrorFetch(statusCode: 500, type: "internal_server_error", message: "Server blew up"))
            _ = try await model.doEmbed(options: .init(values: ["a"]))
            Issue.record("Expected error")
        } catch {
            #expect(GatewayInternalServerError.isInstance(error))
            if let err = error as? GatewayInternalServerError {
                #expect(err.statusCode == 500)
            }
        }
    }
}

