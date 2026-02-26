import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import DeepgramProvider

@Suite("DeepgramProvider")
struct DeepgramProviderTests {
    @Test("supports upstream createDeepgram alias")
    func supportsCreateDeepgramAlias() {
        let provider = createDeepgram(settings: DeepgramProviderSettings(apiKey: "test-key"))
        let model = provider.transcription(modelId: .nova3)
        #expect(model.provider == "deepgram.transcription")
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

            let original = getenv("DEEPGRAM_API_KEY").flatMap { String(validatingCString: $0) }
            defer {
                if let original {
                    setenv("DEEPGRAM_API_KEY", original, 1)
                } else {
                    unsetenv("DEEPGRAM_API_KEY")
                }
            }

            unsetenv("DEEPGRAM_API_KEY")

            let capture = RequestCapture()
            let fetch: FetchFunction = { request in
                await capture.increment()

                let body = Data(
                    """
                    {
                      "metadata": { "duration": 1.2 },
                      "results": {
                        "channels": [{
                          "alternatives": [{
                            "transcript": "ok",
                            "words": []
                          }]
                        }]
                      }
                    }
                    """.utf8
                )

                let response = HTTPURLResponse(
                    url: request.url ?? URL(string: "https://api.deepgram.com/v1/listen")!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
                return FetchResponse(body: .data(body), urlResponse: response)
            }

            let provider = createDeepgram(settings: .init(fetch: fetch))
            let model = provider.transcription(modelId: .nova3)

            do {
                _ = try await model.doGenerate(
                    options: .init(
                        audio: .binary(Data([0x01, 0x02])),
                        mediaType: "audio/wav"
                    )
                )
                Issue.record("Expected missing API key error")
            } catch let error as LoadAPIKeyError {
                #expect(error.message.contains("DEEPGRAM_API_KEY environment variable"))
            } catch {
                Issue.record("Expected LoadAPIKeyError, got: \(error)")
            }

            #expect(await capture.value() == 0)
        }
    }
}
