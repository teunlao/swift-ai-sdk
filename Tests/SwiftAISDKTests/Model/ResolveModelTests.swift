import Testing
import Foundation
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import SwiftAISDK

/**
 Tests for model resolution functions.

 Port of `@ai-sdk/ai/src/model/resolve-model.test.ts`.

 Tests both language model and embedding model resolution, including:
 - V3 model pass-through
 - V2 to V3 adaptation
 - String ID resolution with global provider
 - String ID resolution without global provider (should use gateway/default)
 */

@Suite("resolveLanguageModel Tests")
struct ResolveLanguageModelTests {

    // MARK: - V3 Model Tests

    @Test("when a language model v3 is provided - should return the language model v3")
    func returnsV3ModelAsIs() async throws {
        let mockModel = MockLanguageModelV3(
            provider: "test-provider",
            modelId: "test-model-id"
        )

        let resolvedModel = try resolveLanguageModel(.v3(mockModel))

        #expect(resolvedModel.provider == "test-provider")
        #expect(resolvedModel.modelId == "test-model-id")
        #expect(resolvedModel.specificationVersion == "v3")
    }

    // MARK: - V2 Adaptation Tests

    @Test("when a language model v2 is provided - should adapt to v3 and preserve prototype methods")
    func adaptsV2ToV3() async throws {
        let v2Model = MockLanguageModelV2(
            provider: "test-provider",
            modelId: "test-model-id"
        )

        let resolvedModel = try resolveLanguageModel(.v2(v2Model))

        #expect(resolvedModel.provider == "test-provider")
        #expect(resolvedModel.modelId == "test-model-id")
        #expect(resolvedModel.specificationVersion == "v3")

        // Test that methods work
        let _ = try await resolvedModel.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: [.user(content: [.text(LanguageModelV3TextPart(text: "hello"))], providerOptions: nil)]
            )
        )

        let streamResult = try await resolvedModel.doStream(
            options: LanguageModelV3CallOptions(
                prompt: [.user(content: [.text(LanguageModelV3TextPart(text: "hello"))], providerOptions: nil)]
            )
        )
        // Stream is not nil (it's a non-optional AsyncThrowingStream)
    }

    // MARK: - String Resolution Tests

    @Test("when a string is provided and global provider is not set - should throw error")
    func throwsWhenNoGlobalProvider() async throws {
        globalDefaultProvider = nil
        try await withGlobalProviderDisabled {
            #expect(throws: NoSuchProviderError.self) {
                try resolveLanguageModel(.string("test-model-id"))
            }
        }
    }

    @Test("when a string is provided and global provider is set - should return model from global provider")
    func resolvesFromGlobalProvider() async throws {
        // Set up global provider with mock model
        let mockModel = MockLanguageModelV3(
            provider: "global-test-provider",
            modelId: "actual-test-model-id"
        )

        let provider = customProvider(languageModels: ["test-model-id": mockModel])
        let resolvedModel = try withGlobalProvider(provider) {
            try resolveLanguageModel(.string("test-model-id"))
        }

        #expect(resolvedModel.provider == "global-test-provider")
        #expect(resolvedModel.modelId == "actual-test-model-id")
    }
}

@Suite("resolveEmbeddingModel Tests")
struct ResolveEmbeddingModelTests {

    // MARK: - V2 Adaptation Tests

    @Test("when an embedding model v2 is provided - should adapt to v3 and preserve prototype methods")
    func adaptsV2ToV3() async throws {
        let v2Model = MockEmbeddingModelV2(
            provider: "test-provider",
            modelId: "test-model-id"
        )

        let resolvedModel = try resolveEmbeddingModel(.v2(v2Model))

        #expect(resolvedModel.provider == "test-provider")
        #expect(resolvedModel.modelId == "test-model-id")
        #expect(resolvedModel.specificationVersion == "v3")

        // Test that method works
        let result = try await resolvedModel.doEmbed(
            options: EmbeddingModelV3DoEmbedOptions(values: ["hello"])
        )
        #expect(result.embeddings.count == 1)
    }

    // MARK: - V3 Model Tests

    @Test("when an embedding model v3 is provided - should return the embedding model v3")
    func returnsV3ModelAsIs() async throws {
        let mockModel = MockEmbeddingModelV3(
            provider: "test-provider",
            modelId: "test-model-id"
        )

        let resolvedModel = try resolveEmbeddingModel(.v3(mockModel))

        #expect(resolvedModel.provider == "test-provider")
        #expect(resolvedModel.modelId == "test-model-id")
        #expect(resolvedModel.specificationVersion == "v3")
    }

    // MARK: - String Resolution Tests

    @Test("when a string is provided and global provider is not set - should throw error")
    func throwsWhenNoGlobalProvider() async throws {
        // Ensure no global provider is set and isolate from parallel suites
        globalDefaultProvider = nil
        try await withGlobalProviderDisabled {
            #expect(throws: NoSuchProviderError.self) {
                let _: any EmbeddingModelV3<String> = try resolveEmbeddingModel(.string("test-model-id"))
            }
        }
    }

    @Test("when a string is provided and global provider is set - should return model from global provider")
    func resolvesFromGlobalProvider() async throws {
        // Set up global provider with mock model
        let mockModel = MockEmbeddingModelV3(
            provider: "global-test-provider",
            modelId: "actual-test-model-id"
        )

        let provider = customProvider(textEmbeddingModels: ["test-model-id": mockModel])
        let resolvedModel: any EmbeddingModelV3<String> = try withGlobalProvider(provider) {
            try resolveEmbeddingModel(.string("test-model-id"))
        }

        #expect(resolvedModel.provider == "global-test-provider")
        #expect(resolvedModel.modelId == "actual-test-model-id")
    }
}

// MARK: - Mock Models

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private final class MockLanguageModelV3: LanguageModelV3, @unchecked Sendable {
    let specificationVersion = "v3"
    let provider: String
    let modelId: String

    init(provider: String, modelId: String) {
        self.provider = provider
        self.modelId = modelId
    }

    func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult {
        return LanguageModelV3GenerateResult(
            content: [],
            finishReason: .stop,
            usage: LanguageModelV3Usage(inputTokens: .init(total: 0), outputTokens: .init(total: 0)),
            warnings: []
        )
    }

    func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult {
        let stream = AsyncThrowingStream<LanguageModelV3StreamPart, Error> { continuation in
            continuation.finish()
        }
        return LanguageModelV3StreamResult(stream: stream)
    }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private final class MockLanguageModelV2: LanguageModelV2, @unchecked Sendable {
    let specificationVersion = "v2"
    let provider: String
    let modelId: String

    init(provider: String, modelId: String) {
        self.provider = provider
        self.modelId = modelId
    }

    func doGenerate(options: LanguageModelV2CallOptions) async throws -> LanguageModelV2GenerateResult {
        return LanguageModelV2GenerateResult(
            content: [],
            finishReason: .stop,
            usage: LanguageModelV2Usage(inputTokens: 0, outputTokens: 0, totalTokens: 0),
            warnings: []
        )
    }

    func doStream(options: LanguageModelV2CallOptions) async throws -> LanguageModelV2StreamResult {
        let stream = AsyncThrowingStream<LanguageModelV2StreamPart, Error> { continuation in
            continuation.finish()
        }
        return LanguageModelV2StreamResult(stream: stream)
    }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private final class MockEmbeddingModelV3: @unchecked Sendable {
    let specificationVersion = "v3"
    let provider: String
    let modelId: String

    init(provider: String, modelId: String) {
        self.provider = provider
        self.modelId = modelId
    }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension MockEmbeddingModelV3: EmbeddingModelV3 {
    typealias VALUE = String

    var maxEmbeddingsPerCall: Int? {
        get async throws { 1 }
    }

    var supportsParallelCalls: Bool {
        get async throws { false }
    }

    func doEmbed(options: EmbeddingModelV3DoEmbedOptions<String>) async throws -> EmbeddingModelV3DoEmbedResult {
        return EmbeddingModelV3DoEmbedResult(embeddings: [[0.1, 0.2, 0.3]])
    }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private final class MockEmbeddingModelV2: @unchecked Sendable {
    let specificationVersion = "v2"
    let provider: String
    let modelId: String

    init(provider: String, modelId: String) {
        self.provider = provider
        self.modelId = modelId
    }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
extension MockEmbeddingModelV2: EmbeddingModelV2 {
    typealias VALUE = String

    var maxEmbeddingsPerCall: Int? {
        get async throws { 1 }
    }

    var supportsParallelCalls: Bool {
        get async throws { false }
    }

    func doEmbed(options: EmbeddingModelV2DoEmbedOptions<String>) async throws -> EmbeddingModelV2DoEmbedResult {
        return EmbeddingModelV2DoEmbedResult(embeddings: [[0.1, 0.2, 0.3]])
    }
}
