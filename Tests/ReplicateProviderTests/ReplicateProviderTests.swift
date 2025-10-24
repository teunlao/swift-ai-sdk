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
}

