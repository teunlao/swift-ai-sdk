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
        #expect(model.provider == "black-forest-labs.image")
        #expect(model.modelId == "flux-pro-1.1")
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
}

