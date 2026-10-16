import Foundation
import Testing
import AISDKProvider
import SwiftAISDK

private struct UploadAPI: FilesV4, SkillsV4 {
    let specificationVersion = "v4"
    let provider = "mock-provider"

    func uploadFile(options: FilesV4UploadFileCallOptions) async throws -> FilesV4UploadFileResult {
        throw CancellationError()
    }

    func uploadSkill(options: SkillsV4UploadSkillCallOptions) async throws -> SkillsV4UploadSkillResult {
        throw CancellationError()
    }
}

private struct StubProvider: ProviderV4 {
    var uploads: UploadAPI?

    func languageModel(modelId: String) throws -> any LanguageModelV4 {
        MockLanguageModelV4(modelId: modelId)
    }

    func embeddingModel(modelId: String) throws -> any EmbeddingModelV4 {
        TestEmbeddingModelV4(modelId: modelId) { _ in EmbeddingModelV4Result(embeddings: []) }
    }

    func imageModel(modelId: String) throws -> any ImageModelV4 {
        MockImageModelV4(modelId: modelId)
    }

    func files() throws -> (any FilesV4)? { uploads }
    func skills() throws -> (any SkillsV4)? { uploads }
}

@Suite("wrapProvider")
struct WrapProviderTests {
    private let overrideModelId = LanguageModelV4Middleware(overrideModelId: { "override-\($0.modelId)" })

    @Test("wraps every language model and forwards the other model kinds unchanged")
    func wrapsLanguageModels() throws {
        let wrapped = wrapProvider(provider: StubProvider(), languageModelMiddleware: overrideModelId)

        #expect(try wrapped.languageModel(modelId: "model-1").modelId == "override-model-1")
        #expect(try wrapped.languageModel(modelId: "model-2").modelId == "override-model-2")
        #expect(try wrapped.embeddingModel(modelId: "embedding-1").modelId == "embedding-1")
        #expect(try wrapped.imageModel(modelId: "image-1").modelId == "image-1")
    }

    @Test("preserves file and skill uploads, and adds none when unsupported")
    func uploads() throws {
        let supported = wrapProvider(provider: StubProvider(uploads: UploadAPI()), languageModelMiddleware: overrideModelId)
        #expect(try supported.files()?.provider == "mock-provider")
        #expect(try supported.skills()?.provider == "mock-provider")

        let unsupported = wrapProvider(provider: StubProvider(), languageModelMiddleware: overrideModelId)
        #expect(try unsupported.files() == nil)
        #expect(try unsupported.skills() == nil)
    }
}
