import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import GladiaProvider

@Suite("GladiaProvider")
struct GladiaProviderTests {
    @Test("supports upstream createGladia alias")
    func supportsCreateGladiaAlias() {
        let provider = createGladia(settings: GladiaProviderSettings(apiKey: "test-key"))
        let model = provider.transcription()
        #expect(model.provider == "gladia.transcription")
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

            let original = getenv("GLADIA_API_KEY").flatMap { String(validatingCString: $0) }
            defer {
                if let original {
                    setenv("GLADIA_API_KEY", original, 1)
                } else {
                    unsetenv("GLADIA_API_KEY")
                }
            }

            unsetenv("GLADIA_API_KEY")

            let capture = RequestCapture()
            let fetch: FetchFunction = { request in
                await capture.increment()

                let body = Data("{\"error\":\"unexpected\"}".utf8)
                let response = HTTPURLResponse(
                    url: request.url ?? URL(string: "https://api.gladia.io/v2/upload")!,
                    statusCode: 500,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
                return FetchResponse(body: .data(body), urlResponse: response)
            }

            let provider = createGladia(settings: .init(fetch: fetch))
            let model = provider.transcription()

            do {
                _ = try await model.doGenerate(
                    options: .init(
                        audio: .binary(Data([0x01, 0x02])),
                        mediaType: "audio/wav"
                    )
                )
                Issue.record("Expected missing API key error")
            } catch let error as LoadAPIKeyError {
                #expect(error.message.contains("GLADIA_API_KEY environment variable"))
            } catch {
                Issue.record("Expected LoadAPIKeyError, got: \(error)")
            }

            #expect(await capture.value() == 0)
        }
    }
}
