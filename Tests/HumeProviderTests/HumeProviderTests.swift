import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import HumeProvider

@Suite("HumeProvider")
struct HumeProviderTests {
    @Test("creates speech model via createHume")
    func createsSpeechModel() {
        let provider = createHume(settings: HumeProviderSettings(apiKey: "test-key"))
        let model = provider.speech()
        #expect(model.provider == "hume.speech")
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

            let original = getenv("HUME_API_KEY").flatMap { String(validatingCString: $0) }
            defer {
                if let original {
                    setenv("HUME_API_KEY", original, 1)
                } else {
                    unsetenv("HUME_API_KEY")
                }
            }

            unsetenv("HUME_API_KEY")

            let capture = RequestCapture()
            let fetch: FetchFunction = { request in
                await capture.increment()

                let response = HTTPURLResponse(
                    url: request.url ?? URL(string: "https://api.hume.ai/v0/tts/file")!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "audio/mpeg"]
                )!
                return FetchResponse(body: .data(Data([0x00, 0x01])), urlResponse: response)
            }

            let provider = createHume(settings: .init(fetch: fetch))
            let model = provider.speech()

            do {
                _ = try await model.doGenerate(options: .init(text: "hello"))
                Issue.record("Expected missing API key error")
            } catch let error as LoadAPIKeyError {
                #expect(error.message.contains("HUME_API_KEY environment variable"))
            } catch {
                Issue.record("Expected LoadAPIKeyError, got: \(error)")
            }

            #expect(await capture.value() == 0)
        }
    }
}
