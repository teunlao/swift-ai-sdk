import Foundation
import Testing
@testable import AnthropicProvider
import AISDKProvider
import AISDKProviderUtils

private let providerSettingsTestPrompt: LanguageModelV3Prompt = [
    .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
]

private actor RequestCapture {
    private var request: URLRequest?
    func store(_ request: URLRequest) { self.request = request }
    func current() -> URLRequest? { request }
}

private func makeAnthropicTestResponseData(model: String) throws -> Data {
    let json: [String: Any] = [
        "type": "message",
        "id": "msg_test",
        "model": model,
        "content": [],
        "stop_reason": "end_turn",
        "stop_sequence": NSNull(),
        "usage": [
            "input_tokens": 1,
            "output_tokens": 1,
        ],
    ]
    return try JSONSerialization.data(withJSONObject: json)
}

private func makeAnthropicTestHTTPResponse() -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: "https://api.anthropic.com/v1/messages")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
    )!
}

@Suite("AnthropicProvider settings")
struct AnthropicProviderSettingsTests {
    @Test("uses authToken as Authorization: Bearer and omits x-api-key")
    func usesAuthTokenHeader() async throws {
        let capture = RequestCapture()
        let responseData = try makeAnthropicTestResponseData(model: "claude-3-haiku-20240307")

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: makeAnthropicTestHTTPResponse())
        }

        let provider = createAnthropicProvider(settings: .init(
            authToken: "test-auth-token",
            fetch: fetch
        ))

        let model = provider.messages(modelId: .init(rawValue: "claude-3-haiku-20240307"))
        _ = try await model.doGenerate(options: .init(prompt: providerSettingsTestPrompt))

        guard let request = await capture.current() else {
            Issue.record("Expected request to be captured")
            return
        }

        let headers = request.allHTTPHeaderFields ?? [:]
        let authorization = headers["authorization"] ?? headers["Authorization"]

        #expect(authorization == "Bearer test-auth-token")
        #expect(headers["x-api-key"] == nil)
        #expect(headers["anthropic-version"] == "2023-06-01")
    }

    @Test("uses custom provider name when provided")
    func usesCustomProviderName() throws {
        let provider = createAnthropicProvider(settings: .init(
            apiKey: "test-key",
            name: "custom-anthropic"
        ))

        let model = provider.messages(modelId: .init(rawValue: "claude-3-opus-20240229"))
        #expect(model.provider == "custom-anthropic")
    }

    @Test("defaults provider name to anthropic.messages")
    func defaultsProviderName() throws {
        let provider = createAnthropicProvider(settings: .init(apiKey: "test-key"))
        let model = provider.messages(modelId: .init(rawValue: "claude-3-opus-20240229"))
        #expect(model.provider == "anthropic.messages")
    }
}
