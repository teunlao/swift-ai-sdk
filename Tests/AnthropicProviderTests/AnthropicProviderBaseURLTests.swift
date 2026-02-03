import Foundation
import Testing
@testable import AnthropicProvider
import AISDKProvider
import AISDKProviderUtils

private let baseURLTestPrompt: LanguageModelV3Prompt = [
    .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
]

@Suite("AnthropicProvider baseURL configuration", .serialized)
struct AnthropicProviderBaseURLTests {
    actor URLCapture {
        private(set) var url: String?
        func store(_ url: String?) { self.url = url }
        func current() -> String? { url }
    }

    @Test("uses default Anthropic base URL")
    func usesDefaultBaseURL() async throws {
        let original = getenv("ANTHROPIC_BASE_URL").flatMap { String(validatingCString: $0) }
        defer {
            if let original {
                setenv("ANTHROPIC_BASE_URL", original, 1)
            } else {
                unsetenv("ANTHROPIC_BASE_URL")
            }
        }

        unsetenv("ANTHROPIC_BASE_URL")

        let capture = URLCapture()
        let provider = createAnthropicProvider(settings: .init(
            apiKey: "test-api-key",
            fetch: makeFetch(capture: capture)
        ))

        let model = provider.messages(modelId: .init(rawValue: "claude-3-haiku-20240307"))
        _ = try await model.doGenerate(options: .init(prompt: baseURLTestPrompt))

        let url = await capture.current()
        #expect(url == "https://api.anthropic.com/v1/messages")
    }

    @Test("uses ANTHROPIC_BASE_URL when set")
    func usesEnvironmentBaseURL() async throws {
        let original = getenv("ANTHROPIC_BASE_URL").flatMap { String(validatingCString: $0) }
        defer {
            if let original {
                setenv("ANTHROPIC_BASE_URL", original, 1)
            } else {
                unsetenv("ANTHROPIC_BASE_URL")
            }
        }

        setenv("ANTHROPIC_BASE_URL", "https://proxy.anthropic.example/v1/", 1)

        let capture = URLCapture()
        let provider = createAnthropicProvider(settings: .init(
            apiKey: "test-api-key",
            fetch: makeFetch(capture: capture)
        ))

        let model = provider.messages(modelId: .init(rawValue: "claude-3-haiku-20240307"))
        _ = try await model.doGenerate(options: .init(prompt: baseURLTestPrompt))

        let url = await capture.current()
        #expect(url == "https://proxy.anthropic.example/v1/messages")
    }

    @Test("prefers explicit baseURL option over environment")
    func prefersExplicitBaseURL() async throws {
        let original = getenv("ANTHROPIC_BASE_URL").flatMap { String(validatingCString: $0) }
        defer {
            if let original {
                setenv("ANTHROPIC_BASE_URL", original, 1)
            } else {
                unsetenv("ANTHROPIC_BASE_URL")
            }
        }

        setenv("ANTHROPIC_BASE_URL", "https://env.anthropic.example/v1", 1)

        let capture = URLCapture()
        let provider = createAnthropicProvider(settings: .init(
            baseURL: "https://option.anthropic.example/v1/",
            apiKey: "test-api-key",
            fetch: makeFetch(capture: capture)
        ))

        let model = provider.messages(modelId: .init(rawValue: "claude-3-haiku-20240307"))
        _ = try await model.doGenerate(options: .init(prompt: baseURLTestPrompt))

        let url = await capture.current()
        #expect(url == "https://option.anthropic.example/v1/messages")
    }

    private func makeFetch(capture: URLCapture) -> FetchFunction {
        let data = makeResponseData()
        let response = HTTPURLResponse(
            url: URL(string: "https://example.com")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        return { request in
            await capture.store(request.url?.absoluteString)
            return FetchResponse(body: .data(data), urlResponse: response)
        }
    }

    private func makeResponseData() -> Data {
        let json: [String: Any] = [
            "type": "message",
            "id": "msg_123",
            "model": "claude-3-haiku-20240307",
            "content": [["type": "text", "text": "Hi"]],
            "stop_reason": NSNull(),
            "stop_sequence": NSNull(),
            "usage": ["input_tokens": 1, "output_tokens": 1],
        ]
        return try! JSONSerialization.data(withJSONObject: json)
    }
}

