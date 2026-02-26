import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import HuggingFaceProvider

@Suite("HuggingFaceProvider")
struct HuggingFaceProviderTests {
    @Test("supports upstream createHuggingFace alias")
    func supportsCreateHuggingFaceAlias() {
        let provider = createHuggingFace(settings: HuggingFaceProviderSettings(apiKey: "test-key"))
        let model = provider.responses(modelId: .qwen314B)
        #expect(model.provider == "huggingface.responses")
    }

    @Suite("auth behavior", .serialized)
    struct AuthBehaviorTests {
        @Test("missing API key throws LoadAPIKeyError at request time")
        func missingAPIKeyThrowsAtRequestTime() async throws {
            actor RequestCapture {
                var count: Int = 0
                func increment() { count += 1 }
                func value() -> Int { count }
            }

            let original = getenv("HUGGINGFACE_API_KEY").flatMap { String(validatingCString: $0) }
            defer {
                if let original {
                    setenv("HUGGINGFACE_API_KEY", original, 1)
                } else {
                    unsetenv("HUGGINGFACE_API_KEY")
                }
            }

            unsetenv("HUGGINGFACE_API_KEY")

            let capture = RequestCapture()
            let fetch: FetchFunction = { request in
                await capture.increment()

                let body = Data("{\"error\":{\"message\":\"unexpected\"}}".utf8)
                let response = HTTPURLResponse(
                    url: request.url ?? URL(string: "https://router.huggingface.co/v1/responses")!,
                    statusCode: 500,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
                return FetchResponse(body: .data(body), urlResponse: response)
            }

            let provider = createHuggingFace(settings: .init(fetch: fetch))
            let model = provider.responses(modelId: .qwen314B)
            let prompt: LanguageModelV3Prompt = [
                .user(content: [.text(.init(text: "hello"))], providerOptions: nil)
            ]

            do {
                _ = try await model.doGenerate(
                    options: .init(prompt: prompt)
                )
                Issue.record("Expected missing API key error")
            } catch let error as LoadAPIKeyError {
                #expect(error.message.contains("HUGGINGFACE_API_KEY environment variable"))
            } catch {
                Issue.record("Expected LoadAPIKeyError, got: \(error)")
            }

            #expect(await capture.value() == 0)
        }
    }
}
