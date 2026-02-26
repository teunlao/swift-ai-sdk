import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import FireworksProvider

@Suite("FireworksProvider")
struct FireworksProviderTests {
    private static func encodeJSON(_ dict: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: dict)
    }

    @Test("supports upstream createFireworks alias")
    func supportsCreateFireworksAlias() throws {
        let provider = createFireworks(settings: FireworksProviderSettings(apiKey: "test-key"))
        let model = try provider.languageModel(modelId: FireworksChatModelId.deepseekV3.rawValue)
        #expect(model.provider == "fireworks.chat")
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
            "id": "chatcmpl-1",
            "object": "chat.completion",
            "created": 1_700_000_000,
            "model": FireworksChatModelId.deepseekV3.rawValue,
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
            url: URL(string: "https://api.fireworks.ai/inference/v1/chat/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let provider = createFireworks(settings: FireworksProviderSettings(
            apiKey: "test-key",
            fetch: fetch
        ))
        let model = try provider.languageModel(modelId: FireworksChatModelId.deepseekV3.rawValue)
        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "hello"))], providerOptions: nil),
        ]

        _ = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: prompt))

        guard let request = await capture.value() else {
            Issue.record("Expected request capture")
            return
        }

        #expect(request.url?.absoluteString == "https://api.fireworks.ai/inference/v1/chat/completions")
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

            let original = getenv("FIREWORKS_API_KEY").flatMap { String(validatingCString: $0) }
            defer {
                if let original {
                    setenv("FIREWORKS_API_KEY", original, 1)
                } else {
                    unsetenv("FIREWORKS_API_KEY")
                }
            }

            unsetenv("FIREWORKS_API_KEY")

            let capture = RequestCapture()
            let responseJSON: [String: Any] = [
                "id": "chatcmpl-1",
                "object": "chat.completion",
                "created": 1_700_000_000,
                "model": FireworksChatModelId.deepseekV3.rawValue,
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

            let responseData = FireworksProviderTests.encodeJSON(responseJSON)
            let response = HTTPURLResponse(
                url: URL(string: "https://api.fireworks.ai/inference/v1/chat/completions")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!

            let fetch: FetchFunction = { request in
                await capture.store(request)
                return FetchResponse(body: .data(responseData), urlResponse: response)
            }

            let provider = createFireworks(settings: FireworksProviderSettings(fetch: fetch))
            let model = try provider.languageModel(modelId: FireworksChatModelId.deepseekV3.rawValue)
            let prompt: LanguageModelV3Prompt = [
                .user(content: [.text(.init(text: "hello"))], providerOptions: nil),
            ]

            do {
                _ = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: prompt))
                Issue.record("Expected missing API key error")
            } catch let error as LoadAPIKeyError {
                #expect(error.message.contains("FIREWORKS_API_KEY environment variable"))
            } catch {
                Issue.record("Expected LoadAPIKeyError, got: \(error)")
            }

            #expect(await capture.value() == nil)
        }
    }
}
