import Foundation
import Testing
@testable import AISDKProvider
@testable import TogetherAIProvider

@Suite("TogetherAIProvider")
struct TogetherAIProviderTests {
    @Test("creates chat/completion/embedding/image/reranking models")
    func createsModels() throws {
        let provider = createTogetherAIProvider(settings: TogetherAIProviderSettings(apiKey: "test-key"))

        let chat = try provider.languageModel(modelId: "meta-llama/Llama-3.3-70B-Instruct-Turbo")
        #expect(chat.provider == "togetherai.chat")

        let completion = try provider.completionModel(modelId: "mistralai/Mistral-7B-v0.1")
        #expect(completion.provider == "togetherai.completion")

        let embedding = try provider.textEmbeddingModel(modelId: "BAAI/bge-base-en-v1.5")
        #expect(embedding.provider == "togetherai.embedding")

        let image = try provider.imageModel(modelId: "stabilityai/stable-diffusion-xl-base-1.0")
        #expect(image.provider == "togetherai.image")
        #expect(type(of: image) == TogetherAIImageModel.self)

        let reranking = try provider.rerankingModel(modelId: "Salesforce/Llama-Rank-v1")
        #expect(reranking != nil)
        #expect(reranking?.provider == "togetherai.reranking")
    }
}

