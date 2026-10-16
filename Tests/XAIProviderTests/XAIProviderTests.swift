import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
@testable import XAIProvider

@Suite("XAIProvider")
struct XAIProviderTests {
    @Test("provider routes language calls through responses with configured authentication")
    func responsesRequest() async throws {
        let provider = createXai(settings: .init(baseURL: "https://custom.example/v1/", apiKey: "key", headers: ["X-Custom": "value"], fetch: { request in
            #expect(request.url?.absoluteString == "https://custom.example/v1/responses")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer key")
            #expect(request.value(forHTTPHeaderField: "X-Custom") == "value")
            #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("ai-sdk-xai/") == true)
            guard case .object(let body) = try JSONDecoder().decode(JSONValue.self, from: request.httpBody!) else { throw CancellationError() }
            #expect(body["model"] == .string("grok-4.6"))
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            return FetchResponse(body: .data(Data(#"{"object":"response","status":"completed","output":[{"type":"message","id":"msg","status":"completed","role":"assistant","content":[{"type":"output_text","text":"answer"}]}]}"#.utf8)), urlResponse: response)
        }))
        let model = provider.responses("grok-4.6")
        let result = try await model.doGenerate(options: LanguageModelV4CallOptions(prompt: [.user(content: [.text(.init(text: "hello"))], providerOptions: nil)]))
        #expect(result.content == [.text(.init(text: "answer"))])
        #expect(result.finishReason.unified == .stop)
    }

    @Test("missing API keys fail lazily at request time")
    func missingAPIKey() async throws {
        let original = getenv("XAI_API_KEY").map { String(cString: $0) }
        unsetenv("XAI_API_KEY")
        defer {
            if let original { setenv("XAI_API_KEY", original, 1) } else { unsetenv("XAI_API_KEY") }
        }
        let model = createXai(settings: .init(fetch: { _ in
            Issue.record("A request cannot be sent without credentials")
            throw CancellationError()
        })).responses("grok-4.6")
        await #expect(throws: LoadAPIKeyError.self) {
            _ = try await model.doGenerate(options: .init(prompt: []))
        }
    }

    @Test("embedding requests fail with the unsupported model type")
    func unsupportedEmbedding() throws {
        let provider = createXai()
        #expect(throws: NoSuchModelError.self) { _ = try provider.embeddingModel(modelId: "embedding") }
    }
}
