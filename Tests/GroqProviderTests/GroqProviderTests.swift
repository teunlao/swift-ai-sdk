import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import GroqProvider

@Suite("GroqProvider")
struct GroqProviderTests {
    private static func encodeJSON(_ dict: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: dict)
    }

    @Test("supports upstream createGroq alias")
    func supportsCreateGroqAlias() throws {
        let provider = createGroq(settings: GroqProviderSettings(apiKey: "test-key"))
        let model = try provider.languageModel(modelId: "llama-3.3-70b-versatile")
        #expect(model.provider == "groq.chat")
    }

    @Test("uses default upstream base URL for chat requests")
    func usesDefaultBaseURLForChatRequests() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "id": "test-id",
            "model": "llama-3.3-70b-versatile",
            "created": 1_700_000_000,
            "choices": [[
                "index": 0,
                "message": [
                    "role": "assistant",
                    "content": "ok",
                ],
                "finish_reason": "stop",
            ]],
            "usage": [
                "prompt_tokens": 1,
                "completion_tokens": 1,
                "total_tokens": 2,
            ],
        ]

        let responseData = Self.encodeJSON(responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let provider = createGroq(settings: GroqProviderSettings(apiKey: "test-key", fetch: fetch))
        let model = try provider.languageModel(modelId: "llama-3.3-70b-versatile")
        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "hello"))], providerOptions: nil),
        ]
        _ = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: prompt))

        guard let request = await capture.value() else {
            Issue.record("Expected request capture")
            return
        }

        #expect(request.url?.absoluteString == "https://api.groq.com/openai/v1/chat/completions")
    }

    @Suite("auth behavior", .serialized)
    struct AuthBehaviorTests {
        @Test("missing API key throws LoadAPIKeyError at request time")
        func missingAPIKeyThrowsAtRequestTime() async throws {
            actor RequestCapture {
                var request: URLRequest?
                func store(_ request: URLRequest) { self.request = request }
                func value() -> URLRequest? { request }
            }

            let original = getenv("GROQ_API_KEY").flatMap { String(validatingCString: $0) }
            defer {
                if let original {
                    setenv("GROQ_API_KEY", original, 1)
                } else {
                    unsetenv("GROQ_API_KEY")
                }
            }

            unsetenv("GROQ_API_KEY")

            let capture = RequestCapture()
            let responseJSON: [String: Any] = [
                "id": "test-id",
                "model": "llama-3.3-70b-versatile",
                "created": 1_700_000_000,
                "choices": [[
                    "index": 0,
                    "message": [
                        "role": "assistant",
                        "content": "ok",
                    ],
                    "finish_reason": "stop",
                ]],
                "usage": [
                    "prompt_tokens": 1,
                    "completion_tokens": 1,
                    "total_tokens": 2,
                ],
            ]

            let responseData = GroqProviderTests.encodeJSON(responseJSON)
            let response = HTTPURLResponse(
                url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!

            let fetch: FetchFunction = { request in
                await capture.store(request)
                return FetchResponse(body: .data(responseData), urlResponse: response)
            }

            let provider = createGroq(settings: GroqProviderSettings(fetch: fetch))
            let model = try provider.languageModel(modelId: "llama-3.3-70b-versatile")
            let prompt: LanguageModelV3Prompt = [
                .user(content: [.text(.init(text: "hello"))], providerOptions: nil),
            ]

            do {
                _ = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: prompt))
                Issue.record("Expected missing API key error")
            } catch let error as LoadAPIKeyError {
                #expect(error.message.contains("GROQ_API_KEY environment variable"))
            } catch {
                Issue.record("Expected LoadAPIKeyError, got: \(error)")
            }

            #expect(await capture.value() == nil)
        }
    }
}
