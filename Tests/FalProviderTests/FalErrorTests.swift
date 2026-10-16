import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import FalProvider

@Suite("FalError")
struct FalErrorTests {
    @Test("speech API errors retain the Fal envelope and retryable HTTP context")
    func speechAPIError() async throws {
        let body = #"{"error":{"message":"Resource exhausted","code":429.5}}"#
        let fetch: FetchFunction = { request in
            FetchResponse(body: .data(Data(body.utf8)), urlResponse: HTTPURLResponse(
                url: request.url!, statusCode: 429, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json", "x-request-id": "failed-request"]
            )!)
        }
        let model = createFal(settings: .init(apiKey: "test-key", fetch: fetch)).speech("fal-ai/minimax/speech-02-hd")
        do {
            _ = try await model.doGenerate(options: .init(text: "Hello"))
            Issue.record("Expected API error")
        } catch let error as APICallError {
            #expect(error.message == "Resource exhausted")
            #expect(error.statusCode == 429)
            #expect(error.isRetryable)
            #expect(error.url == "https://fal.run/fal-ai/minimax/speech-02-hd")
            #expect(error.responseBody == body)
            #expect(error.responseHeaders?["x-request-id"] == "failed-request")
            #expect((error.data as? FalErrorData)?.error.code == 429.5)
        }
    }
}
