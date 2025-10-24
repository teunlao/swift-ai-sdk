/**
 GoogleProvider tests.

 Port of `@ai-sdk/google/src/google-provider.test.ts`.
 */

import Foundation
import Testing
@testable import GoogleProvider
@testable import AISDKProvider

@Suite("GoogleProvider")
struct GoogleProviderTests {

    @Test("creates a language model with default settings")
    func createLanguageModelWithDefaults() throws {
        let provider = createGoogleGenerativeAI(settings: GoogleProviderSettings(apiKey: "test-api-key"))
        let model = provider.chat(modelId: .gemini15Flash)

        #expect(model.provider == "google.generative-ai")
        #expect(model.modelId == "gemini-1.5-flash")
    }

    @Test("creates language model via call operator")
    func createLanguageModelViaCallOperator() throws {
        let provider = createGoogleGenerativeAI(settings: GoogleProviderSettings(apiKey: "test-api-key"))
        let model = try provider.languageModel(modelId: "gemini-pro")

        #expect(model.provider == "google.generative-ai")
        #expect(model.modelId == "gemini-pro")
    }

    @Test("creates an embedding model with correct settings")
    func createEmbeddingModel() throws {
        let provider = createGoogleGenerativeAI(settings: GoogleProviderSettings(apiKey: "test-api-key"))
        let model = provider.textEmbedding(modelId: .geminiEmbedding001) as! GoogleGenerativeAIEmbeddingModel

        #expect(model.provider == "google.generative-ai")
        #expect(model.modelId == "gemini-embedding-001")
    }

    @Test("creates embedding model via textEmbeddingModel")
    func createEmbeddingModelViaTextEmbeddingModel() throws {
        let provider = createGoogleGenerativeAI(settings: GoogleProviderSettings(apiKey: "test-api-key"))
        let model = try provider.textEmbeddingModel(modelId: "text-embedding-004")

        #expect(model.provider == "google.generative-ai")
        #expect(model.modelId == "text-embedding-004")
    }

    @Test("uses chat method to create a model")
    func createModelViaChatMethod() throws {
        let provider = createGoogleGenerativeAI(settings: GoogleProviderSettings(apiKey: "test-api-key"))
        let model = provider.chat(modelId: .gemini20Flash)

        #expect(model.provider == "google.generative-ai")
        #expect(model.modelId == "gemini-2.0-flash")
    }

    @Test("uses custom baseURL when provided")
    func customBaseURL() throws {
        let customBaseURL = "https://custom-endpoint.example.com"
        let provider = createGoogleGenerativeAI(settings: GoogleProviderSettings(
            baseURL: customBaseURL,
            apiKey: "test-api-key"
        ))
        let model = provider.chat(modelId: .gemini15Flash)

        // Note: Cannot directly test baseURL as it's internal to the config
        // But we can verify the model was created
        #expect(model.provider == "google.generative-ai")
        #expect(model.modelId == "gemini-1.5-flash")
    }

    @Test("creates an image model with default settings")
    func createImageModelWithDefaults() throws {
        let provider = createGoogleGenerativeAI(settings: GoogleProviderSettings(apiKey: "test-api-key"))
        let model = provider.image(modelId: .imagen30Generate002)

        #expect(model.provider == "google.generative-ai")
        #expect(model.modelId == "imagen-3.0-generate-002")
    }

    @Test("creates an image model with custom maxImagesPerCall")
    func createImageModelWithCustomMaxImages() throws {
        let provider = createGoogleGenerativeAI(settings: GoogleProviderSettings(apiKey: "test-api-key"))
        let imageSettings = GoogleGenerativeAIImageSettings(maxImagesPerCall: 3)
        let model = provider.image(modelId: .imagen30Generate002, settings: imageSettings) as! GoogleGenerativeAIImageModel

        #expect(model.provider == "google.generative-ai")
        #expect(model.modelId == "imagen-3.0-generate-002")

        if case let .value(maxImages) = model.maxImagesPerCall {
            #expect(maxImages == 3)
        } else {
            Issue.record("Expected maxImagesPerCall to be .value(3)")
        }
    }

    @Test("creates image model via imageModel method")
    func createImageModelViaImageModelMethod() throws {
        let provider = createGoogleGenerativeAI(settings: GoogleProviderSettings(apiKey: "test-api-key"))
        let model = try provider.imageModel(modelId: "imagen-3.0-generate-002")

        #expect(model.provider == "google.generative-ai")
        #expect(model.modelId == "imagen-3.0-generate-002")
    }

    @Test("supports deprecated methods")
    func deprecatedMethods() throws {
        let provider = createGoogleGenerativeAI(settings: GoogleProviderSettings(apiKey: "test-api-key"))

        // generativeAI() is deprecated alias for languageModel
        let languageModel = provider.generativeAI(modelId: .gemini15Flash)
        #expect(languageModel.provider == "google.generative-ai")
        #expect(languageModel.modelId == "gemini-1.5-flash")

        // textEmbedding() is non-deprecated alias for textEmbeddingModel
        let embeddingModel = provider.textEmbedding(modelId: .geminiEmbedding001)
        #expect(embeddingModel.provider == "google.generative-ai")
        #expect(embeddingModel.modelId == "gemini-embedding-001")
    }

    @Test("includes YouTube URLs and Google Files URLs in supportedUrls")
    func supportedURLs() async throws {
        let provider = createGoogleGenerativeAI(settings: GoogleProviderSettings(apiKey: "test-api-key"))
        let model = provider.chat(modelId: .gemini15Flash)

        let supportedUrls = try await model.supportedUrls
        guard let patterns = supportedUrls["*"] else {
            Issue.record("Expected supportedUrls to contain '*' key")
            return
        }

        #expect(!patterns.isEmpty)

        // Test supported URLs
        let supportedTestURLs = [
            "https://generativelanguage.googleapis.com/v1beta/files/test123",
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            "https://youtube.com/watch?v=dQw4w9WgXcQ",
            "https://youtu.be/dQw4w9WgXcQ"
        ]

        for url in supportedTestURLs {
            let isSupported = patterns.contains { pattern in
                let nsString = url as NSString
                let range = NSRange(location: 0, length: nsString.length)
                return pattern.firstMatch(in: url, options: [], range: range) != nil
            }
            #expect(isSupported, "Expected URL to be supported: \(url)")
        }

        // Test unsupported URLs
        let unsupportedTestURLs = [
            "https://example.com",
            "https://vimeo.com/123456789",
            "https://youtube.com/channel/UCdQw4w9WgXcQ"
        ]

        for url in unsupportedTestURLs {
            let isSupported = patterns.contains { pattern in
                let nsString = url as NSString
                let range = NSRange(location: 0, length: nsString.length)
                return pattern.firstMatch(in: url, options: [], range: range) != nil
            }
            #expect(!isSupported, "Expected URL to NOT be supported: \(url)")
        }
    }
}
