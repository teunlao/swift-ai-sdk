import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Creates a custom provider with specified models and optional fallback.

 Port of `@ai-sdk/ai/src/registry/custom-provider.ts`.

 Model references resolve lazily through the configured provider.
 Typed V3 and V4 overloads remain available for existing callers.
 */

/**
 Creates a legacy V3 custom provider with specified language models, text embedding models,
 image models, video models, transcription models, speech models, and an optional fallback provider.

 - Parameters:
   - languageModels: A dictionary of language models, where keys are model IDs and values are LanguageModelV3 instances.
   - textEmbeddingModels: A dictionary of text embedding models, where keys are model IDs and values are EmbeddingModelV3<String> instances.
   - imageModels: A dictionary of image models, where keys are model IDs and values are ImageModelV3 instances.
   - videoModels: A dictionary of video models, where keys are model IDs and values are VideoModelV3 instances.
   - transcriptionModels: A dictionary of transcription models, where keys are model IDs and values are TranscriptionModelV3 instances.
   - speechModels: A dictionary of speech models, where keys are model IDs and values are SpeechModelV3 instances.
   - fallbackProvider: An optional fallback provider to use when a requested model is not found in the custom provider.

 - Returns: A ProviderV3 object with languageModel, textEmbeddingModel, imageModel, videoModel,
   transcriptionModel, speechModel, and rerankingModel methods.

 - Throws: `NoSuchModelError` when a requested model is not found and no fallback provider is available.
 */
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
@_disfavoredOverload
public func customProvider(
    languageModels: [String: any LanguageModelV3]? = nil,
    textEmbeddingModels: [String: any EmbeddingModelV3<String>]? = nil,
    imageModels: [String: any ImageModelV3]? = nil,
    videoModels: [String: any VideoModelV3]? = nil,
    rerankingModels: [String: any RerankingModelV3]? = nil,
    transcriptionModels: [String: any TranscriptionModelV3]? = nil,
    speechModels: [String: any SpeechModelV3]? = nil,
    fallbackProvider: (any ProviderV3)? = nil
) -> any ProviderV3 {
    CustomProviderImpl(
        languageModels: languageModels,
        textEmbeddingModels: textEmbeddingModels,
        imageModels: imageModels,
        videoModels: videoModels,
        rerankingModels: rerankingModels,
        transcriptionModels: transcriptionModels,
        speechModels: speechModels,
        fallbackProvider: fallbackProvider
    )
}

public func customProvider(
    languageModels: [String: LanguageModel]? = nil,
    embeddingModels: [String: EmbeddingModel]? = nil,
    imageModels: [String: ImageModel]? = nil,
    transcriptionModels: [String: TranscriptionModel]? = nil,
    speechModels: [String: SpeechModel]? = nil,
    rerankingModels: [String: RerankingModel]? = nil,
    videoModels: [String: VideoModel]? = nil,
    files: (any FilesV4)? = nil,
    skills: (any SkillsV4)? = nil,
    fallbackProvider: (any ProviderV4)? = nil,
    legacyFallbackProvider: (any ProviderV3)? = nil
) -> any ProviderV4 & VideoProviderV4 {
    CustomProviderV4Impl(
        languageModels: languageModels, legacyLanguageModels: nil,
        embeddingModels: embeddingModels, legacyTextEmbeddingModels: nil,
        imageModels: imageModels, legacyImageModels: nil,
        rerankingModels: rerankingModels, legacyRerankingModels: nil,
        transcriptionModels: transcriptionModels, legacyTranscriptionModels: nil,
        speechModels: speechModels, legacySpeechModels: nil,
        videoModels: videoModels, files: files, skills: skills,
        fallbackProvider: fallbackProvider, legacyFallbackProvider: legacyFallbackProvider
    )
}

/**
 Creates a V4 custom provider.

 Swift adaptation of upstream's union-typed `customProvider`: V4 dictionaries use the
 primary labels, while legacy V3 dictionaries use `legacy*` labels and are adapted
 through `asProviderV4` / `as*ModelV4`.
 */
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func customProviderV4(
    languageModels: [String: any LanguageModelV4]? = nil,
    legacyLanguageModels: [String: any LanguageModelV3]? = nil,
    embeddingModels: [String: any EmbeddingModelV4]? = nil,
    legacyTextEmbeddingModels: [String: any EmbeddingModelV3<String>]? = nil,
    imageModels: [String: any ImageModelV4]? = nil,
    legacyImageModels: [String: any ImageModelV3]? = nil,
    rerankingModels: [String: any RerankingModelV4]? = nil,
    legacyRerankingModels: [String: any RerankingModelV3]? = nil,
    transcriptionModels: [String: any TranscriptionModelV4]? = nil,
    legacyTranscriptionModels: [String: any TranscriptionModelV3]? = nil,
    speechModels: [String: any SpeechModelV4]? = nil,
    legacySpeechModels: [String: any SpeechModelV3]? = nil,
    videoModels: [String: VideoModel]? = nil,
    files: (any FilesV4)? = nil,
    skills: (any SkillsV4)? = nil,
    fallbackProvider: (any ProviderV4)? = nil,
    legacyFallbackProvider: (any ProviderV3)? = nil
) -> any ProviderV4 & VideoProviderV4 {
    CustomProviderV4Impl(
        languageModels: languageModels?.mapValues(LanguageModel.v4),
        legacyLanguageModels: legacyLanguageModels,
        embeddingModels: embeddingModels?.mapValues(EmbeddingModel.v4),
        legacyTextEmbeddingModels: legacyTextEmbeddingModels,
        imageModels: imageModels?.mapValues(ImageModel.v4),
        legacyImageModels: legacyImageModels,
        rerankingModels: rerankingModels?.mapValues(RerankingModel.v4),
        legacyRerankingModels: legacyRerankingModels,
        transcriptionModels: transcriptionModels?.mapValues(TranscriptionModel.v4),
        legacyTranscriptionModels: legacyTranscriptionModels,
        speechModels: speechModels?.mapValues(SpeechModel.v4),
        legacySpeechModels: legacySpeechModels,
        videoModels: videoModels,
        files: files,
        skills: skills,
        fallbackProvider: fallbackProvider,
        legacyFallbackProvider: legacyFallbackProvider
    )
}

/// Internal implementation of legacy V3 custom provider.
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private final class CustomProviderImpl: ProviderV3 {
    private let languageModels: [String: any LanguageModelV3]?
    private let textEmbeddingModels: [String: any EmbeddingModelV3<String>]?
    private let imageModels: [String: any ImageModelV3]?
    private let videoModels: [String: any VideoModelV3]?
    private let rerankingModels: [String: any RerankingModelV3]?
    private let transcriptionModels: [String: any TranscriptionModelV3]?
    private let speechModels: [String: any SpeechModelV3]?
    private let fallbackProvider: (any ProviderV3)?

    init(
        languageModels: [String: any LanguageModelV3]?,
        textEmbeddingModels: [String: any EmbeddingModelV3<String>]?,
        imageModels: [String: any ImageModelV3]?,
        videoModels: [String: any VideoModelV3]?,
        rerankingModels: [String: any RerankingModelV3]?,
        transcriptionModels: [String: any TranscriptionModelV3]?,
        speechModels: [String: any SpeechModelV3]?,
        fallbackProvider: (any ProviderV3)?
    ) {
        self.languageModels = languageModels
        self.textEmbeddingModels = textEmbeddingModels
        self.imageModels = imageModels
        self.videoModels = videoModels
        self.rerankingModels = rerankingModels
        self.transcriptionModels = transcriptionModels
        self.speechModels = speechModels
        self.fallbackProvider = fallbackProvider
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV3 {
        if let models = languageModels, let model = models[modelId] {
            return model
        }

        if let fallback = fallbackProvider {
            return try fallback.languageModel(modelId: modelId)
        }

        throw NoSuchModelError(modelId: modelId, modelType: .languageModel)
    }

    public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
        if let models = textEmbeddingModels, let model = models[modelId] {
            return model
        }

        if let fallback = fallbackProvider {
            return try fallback.textEmbeddingModel(modelId: modelId)
        }

        throw NoSuchModelError(modelId: modelId, modelType: .embeddingModel)
    }

    public func imageModel(modelId: String) throws -> any ImageModelV3 {
        if let models = imageModels, let model = models[modelId] {
            return model
        }

        if let fallback = fallbackProvider {
            return try fallback.imageModel(modelId: modelId)
        }

        throw NoSuchModelError(modelId: modelId, modelType: .imageModel)
    }

    public func videoModel(modelId: String) throws -> (any VideoModelV3)? {
        if let models = videoModels, let model = models[modelId] {
            return model
        }

        if let fallback = fallbackProvider {
            return try fallback.videoModel(modelId: modelId)
        }

        throw NoSuchModelError(modelId: modelId, modelType: .videoModel)
    }

    public func rerankingModel(modelId: String) throws -> (any RerankingModelV3)? {
        if let models = rerankingModels, let model = models[modelId] {
            return model
        }

        if let fallback = fallbackProvider, let model = try fallback.rerankingModel(modelId: modelId) {
            return model
        }

        throw NoSuchModelError(modelId: modelId, modelType: .rerankingModel)
    }

    public func transcriptionModel(modelId: String) throws -> (any TranscriptionModelV3)? {
        if let models = transcriptionModels, let model = models[modelId] {
            return model
        }

        if let fallback = fallbackProvider {
            return try fallback.transcriptionModel(modelId: modelId)
        }

        throw NoSuchModelError(modelId: modelId, modelType: .transcriptionModel)
    }

    public func speechModel(modelId: String) throws -> (any SpeechModelV3)? {
        if let models = speechModels, let model = models[modelId] {
            return model
        }

        if let fallback = fallbackProvider {
            return try fallback.speechModel(modelId: modelId)
        }

        throw NoSuchModelError(modelId: modelId, modelType: .speechModel)
    }
}

/// Internal implementation of upstream-style V4 custom provider.
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private final class CustomProviderV4Impl: ProviderV4, VideoProviderV4 {
    let specificationVersion = "v4"

    private let languageModels: [String: LanguageModel]?
    private let legacyLanguageModels: [String: any LanguageModelV3]?
    private let embeddingModels: [String: EmbeddingModel]?
    private let legacyTextEmbeddingModels: [String: any EmbeddingModelV3<String>]?
    private let imageModels: [String: ImageModel]?
    private let legacyImageModels: [String: any ImageModelV3]?
    private let rerankingModels: [String: RerankingModel]?
    private let legacyRerankingModels: [String: any RerankingModelV3]?
    private let transcriptionModels: [String: TranscriptionModel]?
    private let legacyTranscriptionModels: [String: any TranscriptionModelV3]?
    private let speechModels: [String: SpeechModel]?
    private let legacySpeechModels: [String: any SpeechModelV3]?
    private let videoModels: [String: VideoModel]?
    private let filesInterface: (any FilesV4)?
    private let skillsInterface: (any SkillsV4)?
    private let fallbackProvider: (any ProviderV4)?

    init(
        languageModels: [String: LanguageModel]?,
        legacyLanguageModels: [String: any LanguageModelV3]?,
        embeddingModels: [String: EmbeddingModel]?,
        legacyTextEmbeddingModels: [String: any EmbeddingModelV3<String>]?,
        imageModels: [String: ImageModel]?,
        legacyImageModels: [String: any ImageModelV3]?,
        rerankingModels: [String: RerankingModel]?,
        legacyRerankingModels: [String: any RerankingModelV3]?,
        transcriptionModels: [String: TranscriptionModel]?,
        legacyTranscriptionModels: [String: any TranscriptionModelV3]?,
        speechModels: [String: SpeechModel]?,
        legacySpeechModels: [String: any SpeechModelV3]?,
        videoModels: [String: VideoModel]?,
        files: (any FilesV4)?,
        skills: (any SkillsV4)?,
        fallbackProvider: (any ProviderV4)?,
        legacyFallbackProvider: (any ProviderV3)?
    ) {
        self.languageModels = languageModels
        self.legacyLanguageModels = legacyLanguageModels
        self.embeddingModels = embeddingModels
        self.legacyTextEmbeddingModels = legacyTextEmbeddingModels
        self.imageModels = imageModels
        self.legacyImageModels = legacyImageModels
        self.rerankingModels = rerankingModels
        self.legacyRerankingModels = legacyRerankingModels
        self.transcriptionModels = transcriptionModels
        self.legacyTranscriptionModels = legacyTranscriptionModels
        self.speechModels = speechModels
        self.legacySpeechModels = legacySpeechModels
        self.videoModels = videoModels
        self.filesInterface = files
        self.skillsInterface = skills
        self.fallbackProvider = fallbackProvider ?? legacyFallbackProvider.map(asProviderV4)
    }

    func languageModel(modelId: String) throws -> any LanguageModelV4 {
        if let models = languageModels, let model = models[modelId] {
            return try resolveLanguageModelV4(model)
        }

        if let models = legacyLanguageModels, let model = models[modelId] {
            return asLanguageModelV4(model)
        }

        if let fallbackProvider {
            return try fallbackProvider.languageModel(modelId: modelId)
        }

        throw NoSuchModelError(modelId: modelId, modelType: .languageModel)
    }

    func embeddingModel(modelId: String) throws -> any EmbeddingModelV4 {
        if let models = embeddingModels, let model = models[modelId] {
            return try resolveEmbeddingModelV4(model)
        }

        if let models = legacyTextEmbeddingModels, let model = models[modelId] {
            return asEmbeddingModelV4(model)
        }

        if let fallbackProvider {
            return try fallbackProvider.embeddingModel(modelId: modelId)
        }

        throw NoSuchModelError(modelId: modelId, modelType: .embeddingModel)
    }

    func imageModel(modelId: String) throws -> any ImageModelV4 {
        if let models = imageModels, let model = models[modelId] {
            return try resolveImageModelV4(model)
        }

        if let models = legacyImageModels, let model = models[modelId] {
            return asImageModelV4(model)
        }

        if let fallbackProvider {
            return try fallbackProvider.imageModel(modelId: modelId)
        }

        throw NoSuchModelError(modelId: modelId, modelType: .imageModel)
    }

    func transcriptionModel(modelId: String) throws -> (any TranscriptionModelV4)? {
        if let models = transcriptionModels, let model = models[modelId] {
            return try resolveTranscriptionModelV4(model)
        }

        if let models = legacyTranscriptionModels, let model = models[modelId] {
            return asTranscriptionModelV4(model)
        }

        if let fallbackProvider { return try fallbackProvider.transcriptionModel(modelId: modelId) }
        throw NoSuchModelError(modelId: modelId, modelType: .transcriptionModel)
    }

    func speechModel(modelId: String) throws -> (any SpeechModelV4)? {
        if let models = speechModels, let model = models[modelId] {
            return try resolveSpeechModelV4(model)
        }

        if let models = legacySpeechModels, let model = models[modelId] {
            return asSpeechModelV4(model)
        }

        if let fallbackProvider { return try fallbackProvider.speechModel(modelId: modelId) }
        throw NoSuchModelError(modelId: modelId, modelType: .speechModel)
    }

    func rerankingModel(modelId: String) throws -> (any RerankingModelV4)? {
        if let models = rerankingModels, let model = models[modelId] {
            return try resolveRerankingModelV4(model)
        }

        if let models = legacyRerankingModels, let model = models[modelId] {
            return asRerankingModelV4(model)
        }

        if let fallbackProvider { return try fallbackProvider.rerankingModel(modelId: modelId) }
        throw NoSuchModelError(modelId: modelId, modelType: .rerankingModel)
    }

    func videoModel(modelId: String) throws -> any VideoModelV4 {
        if let model = videoModels?[modelId] { return try resolveVideoModelV4(model) }
        if let provider = fallbackProvider as? any VideoProviderV4 {
            return try provider.videoModel(modelId: modelId)
        }
        throw NoSuchModelError(modelId: modelId, modelType: .videoModel)
    }

    func files() throws -> (any FilesV4)? {
        if let filesInterface {
            return filesInterface
        }
        return try fallbackProvider?.files()
    }

    func skills() throws -> (any SkillsV4)? {
        if let skillsInterface {
            return skillsInterface
        }
        return try fallbackProvider?.skills()
    }
}
