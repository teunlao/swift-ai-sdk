import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import SwiftAISDK

@Suite("ProviderRegistry")
struct ProviderRegistryTests {
    @Test("custom provider aliases resolve through the current global provider lazily")
    func resolvesModelAliasesLazily() async throws {
        let model = TestEmbeddingModelV4 { options in
            .init(embeddings: options.values.map { [Double($0.utf8.count)] })
        }
        let aliases = customProvider(embeddingModels: ["alias": .string("real")])
        let global = customProviderV4(embeddingModels: ["real": model])
        try await withGlobalProviderV4(global) {
            let resolved = try aliases.embeddingModel(modelId: "alias")
            let result = try await embed(model: resolved, value: "é")
            #expect(result.embedding == [2])
        }
        #expect(throws: NoSuchModelError.self) { try aliases.speechModel(modelId: "missing") }
    }

    @Test("speech and transcription aliases use fallback when the global capability is absent")
    func mediaAliasesUseFallback() async throws {
        let speech = MockSpeechModelV4 { options in
            .init(
                audio: .binary(Data(options.text.utf8)),
                response: .init(timestamp: Date(), modelId: "fallback-speech")
            )
        }
        let transcription = MockTranscriptionModelV4 { _ in
            .init(
                text: "fallback transcript",
                segments: [],
                response: .init(timestamp: Date(), modelId: "fallback-transcription")
            )
        }
        let fallback = customProviderV4(
            transcriptionModels: ["alias": transcription],
            speechModels: ["alias": speech]
        )
        let aliases = customProvider(
            transcriptionModels: ["alias": .string("global-transcription")],
            speechModels: ["alias": .string("global-speech")],
            fallbackProvider: fallback
        )

        try await withGlobalProviderV4(MediaProvider()) {
            let resolvedSpeech = try aliases.speechModel(modelId: "alias")
            let speechModel = try #require(resolvedSpeech)
            let audio = try await generateSpeech(model: speechModel, text: "fallback audio")
            #expect(audio.audio.data == Data("fallback audio".utf8))
            #expect(audio.responses.first?.modelId == "fallback-speech")

            let resolvedTranscription = try aliases.transcriptionModel(modelId: "alias")
            let transcriptionModel = try #require(resolvedTranscription)
            let transcript = try await transcribe(model: transcriptionModel, audio: .data(Data([1])))
            #expect(transcript.text == "fallback transcript")
            #expect(transcript.responses.first?.modelId == "fallback-transcription")
        }
    }

    @Test("speech and transcription aliases preserve resolution errors instead of using fallback")
    func mediaAliasesPreserveResolutionErrors() {
        let fallback = customProviderV4(
            transcriptionModels: ["alias": MockTranscriptionModelV4()],
            speechModels: ["alias": MockSpeechModelV4()]
        )
        let aliases = customProvider(
            transcriptionModels: ["alias": .string("global-transcription")],
            speechModels: ["alias": .string("global-speech")],
            fallbackProvider: fallback
        )

        withGlobalProviderV4(customProviderV4()) {
            #expect {
                try aliases.speechModel(modelId: "alias")
            } throws: { error in
                guard let error = error as? NoSuchModelError else { return false }
                return error.modelId == "global-speech" && error.modelType == .speechModel
            }
            #expect {
                try aliases.transcriptionModel(modelId: "alias")
            } throws: { error in
                guard let error = error as? NoSuchModelError else { return false }
                return error.modelId == "global-transcription" && error.modelType == .transcriptionModel
            }
        }

        withGlobalProviderV4(MediaProvider(error: MediaResolutionError.unavailable)) {
            #expect(throws: MediaResolutionError.unavailable) {
                try aliases.speechModel(modelId: "alias")
            }
            #expect(throws: MediaResolutionError.unavailable) {
                try aliases.transcriptionModel(modelId: "alias")
            }
        }
    }

    @Test("V4 registry resolves video aliases into usable models")
    func videoAliasesGenerate() async throws {
        let model = MockVideoModelV4 { options in
            .init(videos: [.binary(data: Data((options.prompt ?? "").utf8), mediaType: "video/mp4")], response: .init(timestamp: Date(), modelId: "video-model"))
        }
        let provider = customProviderV4(videoModels: ["alias": .v4(model)])
        let registry = createProviderRegistry(providers: ["p": provider])
        let resolved = try registry.videoModel(id: "p:alias")
        let result = try await experimental_generateVideo(model: resolved, prompt: "video")
        #expect(result.video.data == Data("video".utf8))
        #expect(throws: NoSuchProviderError.self) { try registry.videoModel(id: "missing:model") }
    }

    @Test("registry image middleware transforms requests in declaration order")
    func imageMiddlewareComposition() async throws {
        let model = MockImageModelV4 { options in
            .init(images: .binary([Data((options.prompt ?? "").utf8)]), response: .init(timestamp: Date(), modelId: "image-model"))
        }
        func middleware(_ suffix: String) -> ImageModelMiddleware {
            .init(
                overrideSupportsFileInputs: { _ in true },
                transformParams: { params, _ in .init(prompt: (params.prompt ?? "") + suffix, n: params.n) },
                wrapGenerate: { generate, _, _ in
                    let result = try await generate()
                    guard case .binary(let images) = result.images else { return result }
                    return .init(images: .binary(images.map { $0 + Data(suffix.utf8) }), response: result.response)
                }
            )
        }
        let registry = createProviderRegistry(
            providers: ["p": customProviderV4(imageModels: ["alias": model])],
            options: .init(imageModelMiddleware: .multiple([middleware("A"), middleware("B")]))
        )
        let resolved = try registry.imageModel(id: "p:alias")
        let result = try await generateImage(model: resolved, prompt: "image")
        #expect(result.image.data == Data("imageABBA".utf8))
        #expect(try await resolved.supportsFileInputs == true)
    }

    @Test("returns base model when no middleware is configured")
    func returnsBaseModel() throws {
        let baseModel = TestLanguageModel(provider: "base", modelId: "model")
        let provider = customProvider(languageModels: ["model": baseModel])

        let registry = createProviderRegistry(providers: ["p": provider])
        let resolved = try registry.languageModel(id: "p:model")

        #expect(resolved.provider == "base")
        #expect(resolved.modelId == "model")
        #expect(resolved.specificationVersion == "v4")
    }

    @Test("returns direct V4 model from V4 registry")
    func returnsDirectV4ModelFromV4Registry() throws {
        let baseModel = MockLanguageModelV4(provider: "v4-base", modelId: "v4-model")
        let provider = customProviderV4(languageModels: ["model": baseModel])

        let registry = createProviderRegistry(providers: ["p": provider])
        let resolved = try registry.languageModel(id: "p:model")

        #expect(resolved.provider == "v4-base")
        #expect(resolved.modelId == "v4-model")
        #expect(resolved.specificationVersion == "v4")
    }

    @Test("applies V4 middleware to V4 registry language model")
    func appliesV4MiddlewareToV4RegistryLanguageModel() throws {
        let baseModel = MockLanguageModelV4(provider: "v4-base", modelId: "v4-model")
        let provider = customProviderV4(languageModels: ["model": baseModel])
        let middleware = LanguageModelV4Middleware(
            overrideProvider: { model in "\(model.provider)-wrapped" },
            overrideModelId: { model in "\(model.modelId)-wrapped" }
        )

        let registry = createProviderRegistry(
            providers: ["p": provider],
            options: ProviderRegistryOptions(languageModelMiddleware: middleware)
        )

        let resolved = try registry.languageModel(id: "p:model")

        #expect(resolved.provider == "v4-base-wrapped")
        #expect(resolved.modelId == "v4-model-wrapped")
        #expect(resolved.specificationVersion == "v4")
    }

    @Test("customProviderV4 adapts legacy language models")
    func customProviderV4AdaptsLegacyLanguageModels() throws {
        let baseModel = TestLanguageModel(provider: "legacy-base", modelId: "legacy-model")
        let provider = customProviderV4(legacyLanguageModels: ["model": baseModel])

        let resolved = try provider.languageModel(modelId: "model")

        #expect(resolved.provider == "legacy-base")
        #expect(resolved.modelId == "legacy-model")
        #expect(resolved.specificationVersion == "v4")
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
        let resolved = try registry.rerankingModel(id: "p:model")

        #expect(resolved.provider == "base")
        #expect(resolved.modelId == "model")
        #expect(resolved.specificationVersion == "v4")
    }

    @Test("returns base video model when configured")
    func returnsBaseVideoModel() throws {
        let baseModel = TestVideoModel(provider: "base", modelId: "model")
        let provider = customProvider(videoModels: ["model": baseModel])

        let registry = createProviderRegistry(providers: ["p": provider])
        let resolved = try registry.videoModel(id: "p:model")

        #expect(resolved.provider == "base")
        #expect(resolved.modelId == "model")
        #expect(resolved.specificationVersion == "v4")
    }

    @Test("supports custom separators when resolving video models")
    func supportsCustomSeparatorsForVideoModels() throws {
        let baseModel = TestVideoModel(provider: "base", modelId: "model")
        let provider = customProvider(videoModels: ["model": baseModel])

        let registry = createProviderRegistry(
            providers: ["p": provider],
            options: ProviderRegistryOptions(separator: " > ")
        )

        let resolved = try registry.videoModel(id: "p > model")

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

        let resolved = try registry.rerankingModel(id: "p > model")

        #expect(resolved.provider == "base")
        #expect(resolved.modelId == "model")
    }
}

private enum MediaResolutionError: Error, Equatable {
    case unavailable
}

private struct MediaProvider: ProviderV4 {
    var error: (any Error)? = nil

    func languageModel(modelId: String) throws -> any LanguageModelV4 {
        throw NoSuchModelError(modelId: modelId, modelType: .languageModel)
    }

    func embeddingModel(modelId: String) throws -> any EmbeddingModelV4 {
        throw NoSuchModelError(modelId: modelId, modelType: .embeddingModel)
    }

    func imageModel(modelId: String) throws -> any ImageModelV4 {
        throw NoSuchModelError(modelId: modelId, modelType: .imageModel)
    }

    func speechModel(modelId: String) throws -> (any SpeechModelV4)? {
        if let error { throw error }
        return nil
    }

    func transcriptionModel(modelId: String) throws -> (any TranscriptionModelV4)? {
        if let error { throw error }
        return nil
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

private final class TestVideoModel: VideoModelV3, @unchecked Sendable {
    public var specificationVersion: String { "v3" }
    public var provider: String { providerValue }
    public var modelId: String { modelIdentifier }
    public var maxVideosPerCall: VideoModelV3MaxVideosPerCall { .value(1) }

    private let providerValue: String
    private let modelIdentifier: String

    init(provider: String, modelId: String) {
        self.providerValue = provider
        self.modelIdentifier = modelId
    }

    func doGenerate(options: VideoModelV3CallOptions) async throws -> VideoModelV3GenerateResult {
        VideoModelV3GenerateResult(
            videos: [],
            warnings: [],
            providerMetadata: nil,
            response: VideoModelV3ResponseInfo(timestamp: Date(), modelId: modelIdentifier, headers: nil)
        )
    }
}
