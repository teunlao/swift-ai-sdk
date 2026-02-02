import Testing
@testable import OpenAIProvider

@Suite("OpenAI image options – default response format")
struct OpenAIImageOptionsTests {
    @Test("hasDefaultResponseFormat matches prefix behavior")
    func hasDefaultResponseFormatUsesPrefixes() {
        #expect(openAIImageHasDefaultResponseFormat(modelId: "gpt-image-1"))
        #expect(openAIImageHasDefaultResponseFormat(modelId: "gpt-image-1-mini"))
        #expect(openAIImageHasDefaultResponseFormat(modelId: "gpt-image-1.5"))

        // Azure deployment names often embed date suffixes.
        #expect(openAIImageHasDefaultResponseFormat(modelId: "gpt-image-1-2024-12-17"))
        #expect(openAIImageHasDefaultResponseFormat(modelId: "gpt-image-1-mini-2024-12-17"))
        #expect(openAIImageHasDefaultResponseFormat(modelId: "gpt-image-1.5-2024-12-17"))

        // Ensure we don't accidentally match unrelated models.
        #expect(!openAIImageHasDefaultResponseFormat(modelId: "dall-e-3"))
        #expect(!openAIImageHasDefaultResponseFormat(modelId: "dall-e-2"))
        #expect(!openAIImageHasDefaultResponseFormat(modelId: "gpt-4o"))
        #expect(!openAIImageHasDefaultResponseFormat(modelId: ""))
    }
}

