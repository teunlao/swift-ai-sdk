import Foundation
import Testing
@testable import ReplicateProvider
@testable import AISDKProvider
@testable import AISDKProviderUtils

@Suite("ReplicateProvider")
struct ReplicateProviderTests {
    @Test("creates a provider with required settings")
    func createProviderWithRequiredSettings() throws {
        let provider = createReplicate(settings: ReplicateProviderSettings(apiToken: "test-token"))
        // Smoke: create an image model factory exists via typed convenience
        let model = provider.image("black-forest-labs/flux-schnell")
        #expect(model.provider == "replicate")
    }

    @Test("creates a provider with custom baseURL")
    func createProviderWithCustomSettings() throws {
        let provider = createReplicate(settings: ReplicateProviderSettings(
            apiToken: "test-token",
            baseURL: "https://custom.replicate.com"
        ))
        let model = provider.image("black-forest-labs/flux-schnell")
        #expect(model.provider == "replicate")
    }

    @Test("creates an image model instance")
    func createsImageModelInstance() throws {
        let provider = createReplicate(settings: ReplicateProviderSettings(apiToken: "test-token"))
        let model = provider.image("black-forest-labs/flux-schnell")
        #expect(type(of: model) == ReplicateImageModel.self)
    }

    @Suite("auth behavior", .serialized)
    struct AuthBehaviorTests {
        @Test("missing API token throws LoadAPIKeyError at request time")
        func missingAPITokenThrowsAtRequestTime() async throws {
            actor RequestCapture {
                var count: Int = 0
                func increment() { count += 1 }
                func value() -> Int { count }
            }

            let original = getenv("REPLICATE_API_TOKEN").flatMap { String(validatingCString: $0) }
            defer {
                if let original {
                    setenv("REPLICATE_API_TOKEN", original, 1)
                } else {
                    unsetenv("REPLICATE_API_TOKEN")
                }
            }

            unsetenv("REPLICATE_API_TOKEN")

            let capture = RequestCapture()
            let fetch: FetchFunction = { request in
                await capture.increment()
                let response = HTTPURLResponse(
                    url: request.url ?? URL(string: "https://api.replicate.com/v1/models/black-forest-labs/flux-schnell/predictions")!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!
                return FetchResponse(body: .data(Data("{}".utf8)), urlResponse: response)
            }

            let provider = createReplicate(settings: .init(fetch: fetch))
            let model = provider.image("black-forest-labs/flux-schnell")

            do {
                _ = try await model.doGenerate(options: .init(
                    prompt: "Auth regression",
                    n: 1,
                    providerOptions: [:]
                ))
                Issue.record("Expected missing API token error")
            } catch let error as LoadAPIKeyError {
                #expect(error.message.contains("REPLICATE_API_TOKEN environment variable"))
            } catch {
                Issue.record("Expected LoadAPIKeyError, got: \(error)")
            }

            #expect(await capture.value() == 0)
        }
    }
}
