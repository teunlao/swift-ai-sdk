import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
@testable import GatewayProvider

@Suite("Gateway o11y headers", .serialized)
struct GatewayO11yHeadersTests {
    actor RequestCapture {
        private(set) var request: URLRequest?
        func store(_ request: URLRequest) { self.request = request }
        func value() -> URLRequest? { request }
    }

    private struct EnvSnapshot {
        let deploymentId: String?
        let environment: String?
        let region: String?

        init() {
            deploymentId = getenv("VERCEL_DEPLOYMENT_ID").flatMap { String(validatingCString: $0) }
            environment = getenv("VERCEL_ENV").flatMap { String(validatingCString: $0) }
            region = getenv("VERCEL_REGION").flatMap { String(validatingCString: $0) }
        }

        func restore() {
            if let deploymentId {
                setenv("VERCEL_DEPLOYMENT_ID", deploymentId, 1)
            } else {
                unsetenv("VERCEL_DEPLOYMENT_ID")
            }

            if let environment {
                setenv("VERCEL_ENV", environment, 1)
            } else {
                unsetenv("VERCEL_ENV")
            }

            if let region {
                setenv("VERCEL_REGION", region, 1)
            } else {
                unsetenv("VERCEL_REGION")
            }
        }
    }

    private func normalizedHeaders(_ request: URLRequest) -> [String: String] {
        Dictionary(uniqueKeysWithValues: (request.allHTTPHeaderFields ?? [:]).map { ($0.key.lowercased(), $0.value) })
    }

    @Test("language-model requests include ai-o11y-* headers when Vercel env vars and request id are available")
    func includesO11yHeaders() async throws {
        let snapshot = EnvSnapshot()
        defer { snapshot.restore() }

        setenv("VERCEL_DEPLOYMENT_ID", "test-deployment", 1)
        setenv("VERCEL_ENV", "test", 1)
        setenv("VERCEL_REGION", "iad1", 1)

        let capture = RequestCapture()

        let responseBody: [String: Any] = [
            "content": ["type": "text", "text": "ok"],
            "finish_reason": "stop",
            "usage": ["prompt_tokens": 1, "completion_tokens": 1],
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseBody, options: [.sortedKeys])

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let url = try #require(request.url)
            let httpResponse = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            ))
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let provider = createGatewayProvider(settings: .init(apiKey: "test-api-key", fetch: fetch))
        let model = provider.languageModel(modelId: GatewayModelId(rawValue: "test-model"))

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "Hello"))], providerOptions: nil),
        ]

        _ = try await GatewayVercelRequestContext.$headers.withValue(
            ["x-vercel-id": "req_123"]
        ) {
            try await model.doGenerate(options: .init(prompt: prompt))
        }

        guard let request = await capture.value() else {
            Issue.record("Expected request to be captured")
            return
        }

        let headers = normalizedHeaders(request)

        #expect(headers["ai-o11y-deployment-id"] == "test-deployment")
        #expect(headers["ai-o11y-environment"] == "test")
        #expect(headers["ai-o11y-region"] == "iad1")
        #expect(headers["ai-o11y-request-id"] == "req_123")
    }
}
