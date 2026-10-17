import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import RevAIProvider

@Suite("RevAI HTTP errors")
struct RevAIErrorTests {
    @Test("Preserves structured API errors with source-valid fractional and huge codes", arguments: [0.25, 1e100])
    func apiFailure(code: Double) async throws {
        let body = "{\"error\":{\"message\":\"Quota exhausted\",\"code\":\(code)}}"
        let fetch: FetchFunction = { request in
            FetchResponse(body: .data(Data(body.utf8)), urlResponse: HTTPURLResponse(
                url: request.url!, statusCode: 429, httpVersion: nil,
                headerFields: ["Content-Type": "application/json", "x-request-id": "failure"]
            )!)
        }
        do {
            _ = try await createRevAI(settings: .init(apiKey: "key", fetch: fetch)).transcription(modelId: .machine).doGenerate(options: .init(
                audio: .binary(Data()), mediaType: "audio/wav"
            ))
            Issue.record("Expected API failure")
        } catch let error as APICallError {
            #expect(error.message == "Quota exhausted")
            #expect(error.statusCode == 429)
            #expect(error.isRetryable)
            #expect(error.responseHeaders?["x-request-id"] == "failure")
            #expect(error.responseBody == body)
            #expect(error.url == "https://api.rev.ai/speechtotext/v1/jobs")
        }
    }
}
