import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import SwiftAISDK

@Suite("ProviderRegistry")
struct ProviderRegistryTests {
    @Test("returns base model when no middleware is configured")
    func returnsBaseModel() throws {
        let baseModel = TestLanguageModel(provider: "base", modelId: "model")
        let provider = customProvider(languageModels: ["model": baseModel])

        let registry = createProviderRegistry(providers: ["p": provider])
        let resolved = try registry.languageModel(id: "p:model")

        #expect(resolved.provider == "base")
        #expect(resolved.modelId == "model")
    }

    @Test("applies single middleware to language model")
    func appliesSingleMiddleware() throws {
        let baseModel = TestLanguageModel(provider: "base", modelId: "model")
        let middleware = LanguageModelV3Middleware(
            overrideProvider: { model in "\(model.provider)-wrapped" },
            overrideModelId: { model in "\(model.modelId)-wrapped" }
        )
        let provider = customProvider(languageModels: ["model": baseModel])

        let registry = createProviderRegistry(
            providers: ["p": provider],
            options: ProviderRegistryOptions(languageModelMiddleware: middleware)
        )

        let resolved = try registry.languageModel(id: "p:model")

        #expect(resolved.provider == "base-wrapped")
        #expect(resolved.modelId == "model-wrapped")
    }

    @Test("applies multiple middleware entries in declaration order")
    func appliesMultipleMiddleware() throws {
        let baseModel = TestLanguageModel(provider: "base", modelId: "model")
        let middlewareChain = [
            LanguageModelV3Middleware(
                overrideProvider: { model in "\(model.provider)-outer" },
                overrideModelId: { model in "\(model.modelId)-outer" }
            ),
            LanguageModelV3Middleware(
                overrideProvider: { model in "\(model.provider)-inner" },
                overrideModelId: { model in "\(model.modelId)-inner" }
            )
        ]
        let provider = customProvider(languageModels: ["model": baseModel])

        let registry = createProviderRegistry(
            providers: ["p": provider],
            options: ProviderRegistryOptions(languageModelMiddleware: middlewareChain)
        )

        let resolved = try registry.languageModel(id: "p:model")

        #expect(resolved.provider == "base-inner-outer")
        #expect(resolved.modelId == "model-inner-outer")
    }

    @Test("supports custom separators when resolving models")
    func supportsCustomSeparators() throws {
        let baseModel = TestLanguageModel(provider: "base", modelId: "model")
        let provider = customProvider(languageModels: ["model": baseModel])

        let registry = createProviderRegistry(
            providers: ["p": provider],
            options: ProviderRegistryOptions(separator: " > ")
        )

        let resolved = try registry.languageModel(id: "p > model")

        #expect(resolved.provider == "base")
        #expect(resolved.modelId == "model")
    }

    @Test("returns base reranking model when configured")
    func returnsBaseRerankingModel() throws {
        let baseModel = TestRerankingModel(provider: "base", modelId: "model")
        let provider = customProvider(rerankingModels: ["model": baseModel])

        let registry = createProviderRegistry(providers: ["p": provider])
        let resolved = registry.rerankingModel(id: "p:model")

        #expect(resolved.provider == "base")
        #expect(resolved.modelId == "model")
    }

    @Test("supports custom separators when resolving reranking models")
    func supportsCustomSeparatorsForRerankingModels() throws {
        let baseModel = TestRerankingModel(provider: "base", modelId: "model")
        let provider = customProvider(rerankingModels: ["model": baseModel])

        let registry = createProviderRegistry(
            providers: ["p": provider],
            options: ProviderRegistryOptions(separator: " > ")
        )

        let resolved = registry.rerankingModel(id: "p > model")

        #expect(resolved.provider == "base")
        #expect(resolved.modelId == "model")
    }
}

private final class TestLanguageModel: LanguageModelV3, @unchecked Sendable {
    let specificationVersion = "v3"
    let providerValue: String
    let modelIdentifier: String

    init(provider: String, modelId: String) {
        self.providerValue = provider
        self.modelIdentifier = modelId
    }

    var provider: String {
        providerValue
    }

    var modelId: String {
        modelIdentifier
    }

    var supportedUrls: [String: [NSRegularExpression]] {
        get async throws { [:] }
    }

    func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult {
        LanguageModelV3GenerateResult(
            content: [],
            finishReason: .stop,
            usage: LanguageModelV3Usage(inputTokens: .init(total: 0), outputTokens: .init(total: 0)),
            warnings: []
        )
    }

    func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult {
        LanguageModelV3StreamResult(stream: AsyncThrowingStream { $0.finish() })
    }
}

private final class TestRerankingModel: RerankingModelV3, @unchecked Sendable {
    let providerValue: String
    let modelIdentifier: String

    init(provider: String, modelId: String) {
        self.providerValue = provider
        self.modelIdentifier = modelId
    }

    var provider: String {
        providerValue
    }

    var modelId: String {
        modelIdentifier
    }

    func doRerank(options: RerankingModelV3CallOptions) async throws -> RerankingModelV3DoRerankResult {
        RerankingModelV3DoRerankResult(ranking: [])
    }
}
