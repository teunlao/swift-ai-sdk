import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
@testable import GatewayProvider

@Suite("GatewayProvider (createGatewayProvider)")
struct GatewayProviderCreationTests {
    actor RequestCapture {
        private(set) var requests: [URLRequest] = []
        func append(_ request: URLRequest) { requests.append(request) }
        func last() -> URLRequest? { requests.last }
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

    @Test("default baseURL uses https://ai-gateway.vercel.sh/v3/ai")
    func defaultBaseURLIsV3() async throws {
        let capture = RequestCapture()

        let responseBody: [String: Any] = [
            "content": ["type": "text", "text": "ok"],
            "finish_reason": "stop",
            "usage": ["prompt_tokens": 1, "completion_tokens": 1],
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseBody, options: [.sortedKeys])

        let fetch: FetchFunction = { request in
            await capture.append(request)
            let httpResponse = try httpResponse(for: request, headers: ["Content-Type": "application/json"])
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let provider = createGatewayProvider(settings: .init(apiKey: "test-api-key", fetch: fetch))
        let model = try provider.languageModel(modelId: "test-model")

        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil),
        ]

        _ = try await model.doGenerate(options: .init(prompt: prompt))

        guard let request = await capture.last() else {
            Issue.record("Expected a request to be captured")
            return
        }

        #expect(request.url?.absoluteString == "https://ai-gateway.vercel.sh/v3/ai/language-model")
    }
}

