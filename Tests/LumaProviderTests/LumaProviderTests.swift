import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import LumaProvider

@Suite("LumaProvider")
struct LumaProviderTests {
    @Test("supports upstream createLuma alias")
    func supportsCreateLumaAlias() {
        let provider = createLuma(settings: LumaProviderSettings(apiKey: "test-key"))
        let model = provider.image(modelId: .photon1)
        #expect(model.provider == "luma.image")
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

            let original = getenv("LUMA_API_KEY").flatMap { String(validatingCString: $0) }
            defer {
                if let original {
                    setenv("LUMA_API_KEY", original, 1)
                } else {
                    unsetenv("LUMA_API_KEY")
                }
            }

            unsetenv("LUMA_API_KEY")

            let capture = RequestCapture()
            let fetch: FetchFunction = { request in
                await capture.increment()

                let body = Data("{\"error\":\"unexpected\"}".utf8)
                let response = HTTPURLResponse(
                    url: request.url ?? URL(string: "https://api.lumalabs.ai/dream-machine/v1/generations/image")!,
                    statusCode: 500,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
                return FetchResponse(body: .data(body), urlResponse: response)
            }

            let provider = createLuma(settings: .init(fetch: fetch))
            let model = provider.image(modelId: .photon1)

            do {
                _ = try await model.doGenerate(
                    options: .init(prompt: "A red kite over mountains", n: 1)
                )
                Issue.record("Expected missing API key error")
            } catch let error as LoadAPIKeyError {
                #expect(error.message.contains("LUMA_API_KEY environment variable"))
            } catch {
                Issue.record("Expected LoadAPIKeyError, got: \(error)")
            }

            #expect(await capture.value() == 0)
        }
    }
}
