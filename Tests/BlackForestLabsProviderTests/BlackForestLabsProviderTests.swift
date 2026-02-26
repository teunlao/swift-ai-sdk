import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import BlackForestLabsProvider

@Suite("BlackForestLabsProvider")
struct BlackForestLabsProviderTests {
    @Test("creates image models via .image")
    func createsImageModels() throws {
        let provider = createBlackForestLabsProvider(settings: .init(apiKey: "test-key"))

        let model = provider.image(modelId: .fluxPro11)
        let model2 = provider.image(.fluxPro11)
        #expect(model.provider == "black-forest-labs.image")
        #expect(model.modelId == "flux-pro-1.1")
        #expect(model2.modelId == "flux-pro-1.1")
        #expect(model.specificationVersion == "v3")
    }

    @Test("throws NoSuchModelError for unsupported model types")
    func throwsForUnsupportedTypes() async throws {
        let provider = createBlackForestLabsProvider(settings: .init(apiKey: "test-key"))

        #expect(throws: NoSuchModelError.self) {
            _ = try provider.languageModel(modelId: "some-id")
        }

        #expect(throws: NoSuchModelError.self) {
            _ = try provider.textEmbeddingModel(modelId: "some-id")
        }
    }

    @Test("supports upstream naming createBlackForestLabs")
    func supportsUpstreamNamingAlias() throws {
        let provider = createBlackForestLabs(settings: .init(apiKey: "test-key"))
        let model = provider.image(.fluxPro11)
        #expect(model.provider == "black-forest-labs.image")
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

            let original = getenv("BFL_API_KEY").flatMap { String(validatingCString: $0) }
            defer {
                if let original {
                    setenv("BFL_API_KEY", original, 1)
                } else {
                    unsetenv("BFL_API_KEY")
                }
            }

            unsetenv("BFL_API_KEY")

            let capture = RequestCapture()
            let fetch: FetchFunction = { request in
                await capture.increment()
                let response = HTTPURLResponse(
                    url: request.url ?? URL(string: "https://api.example.com/v1/flux-pro-1.1")!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
                return FetchResponse(body: .data(Data("{}".utf8)), urlResponse: response)
            }

            let provider = createBlackForestLabsProvider(settings: .init(
                baseURL: "https://api.example.com/v1",
                fetch: fetch
            ))
            let model = provider.image(.fluxPro11)

            do {
                _ = try await model.doGenerate(options: .init(
                    prompt: "A test image",
                    n: 1,
                    aspectRatio: "1:1",
                    providerOptions: [:]
                ))
                Issue.record("Expected missing API key error")
            } catch let error as LoadAPIKeyError {
                #expect(error.message.contains("BFL_API_KEY environment variable"))
            } catch {
                Issue.record("Expected LoadAPIKeyError, got: \(error)")
            }

            #expect(await capture.value() == 0)
        }
    }
}
