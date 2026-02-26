import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import CohereProvider

@Suite("CohereProvider")
struct CohereProviderTests {
    private static func encodeJSON(_ dict: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: dict)
    }

    @Test("supports upstream createCohere alias")
    func supportsCreateCohereAlias() throws {
        let provider = createCohere(settings: CohereProviderSettings(apiKey: "test-key"))
        let model = try provider.languageModel(modelId: CohereChatModelId.commandR082024.rawValue)
        #expect(model.provider == "cohere.chat")
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
            "generation_id": "gen-1",
            "message": [
                "role": "assistant",
                "content": [[
                    "type": "text",
                    "text": "ok",
                ]],
            ],
            "finish_reason": "COMPLETE",
            "usage": [
                "tokens": [
                    "input_tokens": 1,
                    "output_tokens": 1,
                ]
            ],
        ]

        let responseData = Self.encodeJSON(responseJSON)
        let response = HTTPURLResponse(
            url: URL(string: "https://api.cohere.com/v2/chat")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: response)
        }

        let provider = createCohere(settings: CohereProviderSettings(apiKey: "test-key", fetch: fetch))
        let model = try provider.languageModel(modelId: CohereChatModelId.commandR082024.rawValue)
        let prompt: LanguageModelV3Prompt = [
            .user(content: [.text(.init(text: "hello"))], providerOptions: nil),
        ]

        _ = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: prompt))

        guard let request = await capture.value() else {
            Issue.record("Expected request capture")
            return
        }

        #expect(request.url?.absoluteString == "https://api.cohere.com/v2/chat")
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

            let original = getenv("COHERE_API_KEY").flatMap { String(validatingCString: $0) }
            defer {
                if let original {
                    setenv("COHERE_API_KEY", original, 1)
                } else {
                    unsetenv("COHERE_API_KEY")
                }
            }

            unsetenv("COHERE_API_KEY")

            let capture = RequestCapture()
            let responseJSON: [String: Any] = [
                "generation_id": "gen-1",
                "message": [
                    "role": "assistant",
                    "content": [[
                        "type": "text",
                        "text": "ok",
                    ]],
                ],
                "finish_reason": "COMPLETE",
                "usage": [
                    "tokens": [
                        "input_tokens": 1,
                        "output_tokens": 1,
                    ]
                ],
            ]

            let responseData = CohereProviderTests.encodeJSON(responseJSON)
            let response = HTTPURLResponse(
                url: URL(string: "https://api.cohere.com/v2/chat")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!

            let fetch: FetchFunction = { request in
                await capture.store(request)
                return FetchResponse(body: .data(responseData), urlResponse: response)
            }

            let provider = createCohere(settings: CohereProviderSettings(fetch: fetch))
            let model = try provider.languageModel(modelId: CohereChatModelId.commandR082024.rawValue)
            let prompt: LanguageModelV3Prompt = [
                .user(content: [.text(.init(text: "hello"))], providerOptions: nil),
            ]

            do {
                _ = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: prompt))
                Issue.record("Expected missing API key error")
            } catch let error as LoadAPIKeyError {
                #expect(error.message.contains("COHERE_API_KEY environment variable"))
            } catch {
                Issue.record("Expected LoadAPIKeyError, got: \(error)")
            }

            #expect(await capture.value() == nil)
        }
    }
}
