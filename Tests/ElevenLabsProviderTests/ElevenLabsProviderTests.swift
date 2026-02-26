import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import ElevenLabsProvider

@Suite("ElevenLabsProvider")
struct ElevenLabsProviderTests {
    @Test("supports upstream createElevenLabs alias")
    func supportsCreateElevenLabsAlias() {
        let provider = createElevenLabs(settings: ElevenLabsProviderSettings(apiKey: "test-key"))
        let model = provider.transcription(modelId: .scribeV1)
        #expect(model.provider == "elevenlabs.transcription")
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

            let original = getenv("ELEVENLABS_API_KEY").flatMap { String(validatingCString: $0) }
            defer {
                if let original {
                    setenv("ELEVENLABS_API_KEY", original, 1)
                } else {
                    unsetenv("ELEVENLABS_API_KEY")
                }
            }

            unsetenv("ELEVENLABS_API_KEY")

            let capture = RequestCapture()
            let fetch: FetchFunction = { request in
                await capture.increment()

                let body = Data(
                    """
                    {
                      "language_code": "en",
                      "language_probability": 0.99,
                      "text": "ok",
                      "words": []
                    }
                    """.utf8
                )

                let response = HTTPURLResponse(
                    url: request.url ?? URL(string: "https://api.elevenlabs.io/v1/speech-to-text")!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
                return FetchResponse(body: .data(body), urlResponse: response)
            }

            let provider = createElevenLabs(settings: .init(fetch: fetch))
            let model = provider.transcription(modelId: .scribeV1)

            do {
                _ = try await model.doGenerate(
                    options: .init(
                        audio: .binary(Data([0x01, 0x02])),
                        mediaType: "audio/wav"
                    )
                )
                Issue.record("Expected missing API key error")
            } catch let error as LoadAPIKeyError {
                #expect(error.message.contains("ELEVENLABS_API_KEY environment variable"))
            } catch {
                Issue.record("Expected LoadAPIKeyError, got: \(error)")
            }

            #expect(await capture.value() == 0)
        }
    }
}
