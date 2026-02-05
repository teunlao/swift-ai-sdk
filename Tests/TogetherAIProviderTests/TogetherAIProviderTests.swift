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
        #expect(provider.chat("meta-llama/Meta-Llama-3.1-8B-Instruct-Turbo").provider == "togetherai.chat")

        let completion = try provider.completionModel(modelId: "mistralai/Mistral-7B-v0.1")
        #expect(completion.provider == "togetherai.completion")
        #expect(provider.completion("mistralai/Mistral-7B-v0.1").provider == "togetherai.completion")

        let embedding = try provider.textEmbeddingModel(modelId: "BAAI/bge-base-en-v1.5")
        #expect(embedding.provider == "togetherai.embedding")
        #expect(provider.embedding("BAAI/bge-base-en-v1.5").provider == "togetherai.embedding")

        let image = try provider.imageModel(modelId: "stabilityai/stable-diffusion-xl-base-1.0")
        #expect(image.provider == "togetherai.image")
        #expect(type(of: image) == TogetherAIImageModel.self)
        #expect(provider.image("stabilityai/stable-diffusion-xl-base-1.0").provider == "togetherai.image")

        let reranking = try provider.rerankingModel(modelId: "Salesforce/Llama-Rank-v1")
        #expect(reranking != nil)
        #expect(reranking?.provider == "togetherai.reranking")
        #expect(provider.reranking("Salesforce/Llama-Rank-v1").provider == "togetherai.reranking")
    }

    @Test("supports upstream naming createTogetherAI")
    func supportsUpstreamNamingAlias() throws {
        let provider = createTogetherAI(settings: TogetherAIProviderSettings(apiKey: "test-key"))
        let chat = try provider.languageModel(modelId: "meta-llama/Llama-3.3-70B-Instruct-Turbo")
        #expect(chat.provider == "togetherai.chat")
    }
}
