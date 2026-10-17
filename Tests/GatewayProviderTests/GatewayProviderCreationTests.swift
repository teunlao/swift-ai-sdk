import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
@testable import GatewayProvider

@Suite("GatewayProvider (createGateway)")
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

    @Test("metadata refresh serves the cached catalog while refreshing in the background")
    func metadataStaleWhileRevalidate() async throws {
        final class Clock: @unchecked Sendable {
            private let lock = NSLock()
            private var date = Date(timeIntervalSince1970: 0)
            func now() -> Date { lock.withLock { date } }
            func advance() { lock.withLock { date = Date(timeIntervalSince1970: 1) } }
        }
        actor Catalog {
            var revision = 0
            func next() -> String {
                revision += 1
                return #"{"models":[{"id":"model-\#(revision)","name":"model","specification":{"specificationVersion":"v4","provider":"test","modelId":"model"}}]}"#
            }
        }
        let clock = Clock()
        let catalog = Catalog()
        let provider = createGateway(settings: .init(apiKey: "key", fetch: { request in
            let body = await catalog.next()
            return FetchResponse(body: .data(Data(body.utf8)), urlResponse: try httpResponse(for: request, headers: ["Content-Type": "application/json"]))
        }, metadataCacheRefreshMillis: 1, _internal: .init(currentDate: { clock.now() })))
        let initial = try await provider.getAvailableModels()
        #expect(initial.models.first?.id == "model-1")
        clock.advance()
        let stale = try await provider.getAvailableModels()
        #expect(stale.models.first?.id == "model-1")
    }

    @Test("default baseURL uses https://ai-gateway.vercel.sh/v4/ai")
    func defaultBaseURLIsV4() async throws {
        let capture = RequestCapture()

        let responseBody: [String: Any] = [
            "content": [["type": "text", "text": "ok"]],
            "finishReason": ["unified": "stop"],
            "usage": ["inputTokens": ["total": 1], "outputTokens": ["total": 1]],
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseBody, options: [.sortedKeys])

        let fetch: FetchFunction = { request in
            await capture.append(request)
            let httpResponse = try httpResponse(for: request, headers: ["Content-Type": "application/json"])
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let provider = createGateway(settings: .init(apiKey: "test-api-key", fetch: fetch))
        let model = try provider.languageModel(modelId: "test-model")

        let prompt: LanguageModelV4Prompt = [
            .user(content: [.text(LanguageModelV4TextPart(text: "Hello"))], providerOptions: nil),
        ]

        _ = try await model.doGenerate(options: .init(prompt: prompt))

        guard let request = await capture.last() else {
            Issue.record("Expected a request to be captured")
            return
        }

        #expect(request.url?.absoluteString == "https://ai-gateway.vercel.sh/v4/ai/language-model")
    }
}

