import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Creates a custom provider with specified models and optional fallback.

 Port of `@ai-sdk/ai/src/registry/custom-provider.ts`.

 Creates a custom provider with specified language models, text embedding models, image models,
 video models, transcription models, speech models, and an optional fallback provider.
 */

/**
 Creates a custom provider with specified language models, text embedding models, image models,
 video models, transcription models, speech models, and an optional fallback provider.

 - Parameters:
   - languageModels: A dictionary of language models, where keys are model IDs and values are LanguageModelV3 instances.
   - textEmbeddingModels: A dictionary of text embedding models, where keys are model IDs and values are EmbeddingModelV3<String> instances.
   - imageModels: A dictionary of image models, where keys are model IDs and values are ImageModelV3 instances.
   - videoModels: A dictionary of video models, where keys are model IDs and values are VideoModelV3 instances.
   - transcriptionModels: A dictionary of transcription models, where keys are model IDs and values are TranscriptionModelV3 instances.
   - speechModels: A dictionary of speech models, where keys are model IDs and values are SpeechModelV3 instances.
   - fallbackProvider: An optional fallback provider to use when a requested model is not found in the custom provider.

 - Returns: A ProviderV3 object with languageModel, textEmbeddingModel, imageModel, transcriptionModel,
   videoModel, transcriptionModel, and speechModel methods.

 - Throws: `NoSuchModelError` when a requested model is not found and no fallback provider is available.
 */
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
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
    return CustomProviderImpl(
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

/// Internal implementation of custom provider
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

        throw NoSuchModelError(modelId: modelId, modelType: .textEmbeddingModel)
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

        if let fallback = fallbackProvider {
            if let model = try fallback.rerankingModel(modelId: modelId) {
                return model
            }
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

        // Throw error when model not found and no fallback (matches upstream behavior)
        throw NoSuchModelError(modelId: modelId, modelType: .transcriptionModel)
    }

    public func speechModel(modelId: String) throws -> (any SpeechModelV3)? {
        if let models = speechModels, let model = models[modelId] {
            return model
        }

        if let fallback = fallbackProvider {
            return try fallback.speechModel(modelId: modelId)
        }

        // Throw error when model not found and no fallback (matches upstream behavior)
        throw NoSuchModelError(modelId: modelId, modelType: .speechModel)
    }
}
