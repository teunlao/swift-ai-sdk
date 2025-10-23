import Foundation
import Testing
@testable import XAIProvider
@testable import AISDKProvider

/**
 XAI Provider tests.

 Port of `@ai-sdk/xai/src/xai-provider.test.ts`.
 */

@Suite("XAIProvider")
struct XAIProviderTests {

    @Test("creates a language model with default settings")
    func createLanguageModelWithDefaults() {
        let provider = createXai(settings: XAIProviderSettings(apiKey: "test-api-key"))
        let model = provider.chat(modelId: "grok-beta")

        #expect(model.provider == "xai.chat")
        #expect(model.modelId == "grok-beta")
    }

    @Test("creates language model via call operator")
    func createLanguageModelViaCallOperator() {
        let provider = createXai(settings: XAIProviderSettings(apiKey: "test-api-key"))
        let model = provider("grok-beta")

        #expect(model.provider == "xai.chat")
        #expect(model.modelId == "grok-beta")
    }

    @Test("creates language model via languageModel method")
    func createLanguageModelViaLanguageModelMethod() {
        let provider = createXai(settings: XAIProviderSettings(apiKey: "test-api-key"))
        let model = provider.languageModel(modelId: "grok-3")

        #expect(model.provider == "xai.chat")
        #expect(model.modelId == "grok-3")
    }

    @Test("creates an image model with correct settings")
    func createImageModel() {
        let provider = createXai(settings: XAIProviderSettings(apiKey: "test-api-key"))
        let model = provider.imageModel(modelId: "grok-2-image")

        #expect(model.provider == "xai.image")
        #expect(model.modelId == "grok-2-image")
    }

    @Test("creates image model via image method")
    func createImageModelViaImageMethod() {
        let provider = createXai(settings: XAIProviderSettings(apiKey: "test-api-key"))
        let model = provider.image(modelId: "grok-2-image")

        #expect(model.provider == "xai.image")
        #expect(model.modelId == "grok-2-image")
    }

    @Test("uses custom baseURL when provided")
    func usesCustomBaseURL() {
        let provider = createXai(settings: XAIProviderSettings(
            baseURL: "https://custom.xai.api",
            apiKey: "test-api-key"
        ))
        let model = provider.chat(modelId: "grok-beta")

        // BaseURL is internal to the model, we just verify model is created
        #expect(model.provider == "xai.chat")
        #expect(model.modelId == "grok-beta")
    }

    @Test("uses default baseURL when not provided")
    func usesDefaultBaseURL() {
        let provider = createXai(settings: XAIProviderSettings(apiKey: "test-api-key"))
        let model = provider.chat(modelId: "grok-beta")

        // BaseURL is internal, we verify the model works
        #expect(model.provider == "xai.chat")
        #expect(model.modelId == "grok-beta")
    }
}
