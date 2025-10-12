/**
 Creates a custom provider with specified models and optional fallback.

 Port of `@ai-sdk/ai/src/registry/custom-provider.ts`.

 Creates a custom provider with specified language models, text embedding models, image models,
 transcription models, speech models, and an optional fallback provider.
 */

/**
 Creates a custom provider with specified language models, text embedding models, image models,
 transcription models, speech models, and an optional fallback provider.

 - Parameters:
   - languageModels: A dictionary of language models, where keys are model IDs and values are LanguageModelV3 instances.
   - textEmbeddingModels: A dictionary of text embedding models, where keys are model IDs and values are EmbeddingModelV3<String> instances.
   - imageModels: A dictionary of image models, where keys are model IDs and values are ImageModelV3 instances.
   - transcriptionModels: A dictionary of transcription models, where keys are model IDs and values are TranscriptionModelV3 instances.
   - speechModels: A dictionary of speech models, where keys are model IDs and values are SpeechModelV3 instances.
   - fallbackProvider: An optional fallback provider to use when a requested model is not found in the custom provider.

 - Returns: A ProviderV3 object with languageModel, textEmbeddingModel, imageModel, transcriptionModel,
   and speechModel methods.

 - Throws: `NoSuchModelError` when a requested model is not found and no fallback provider is available.
 */
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func customProvider(
    languageModels: [String: any LanguageModelV3]? = nil,
    textEmbeddingModels: [String: any EmbeddingModelV3<String>]? = nil,
    imageModels: [String: any ImageModelV3]? = nil,
    transcriptionModels: [String: any TranscriptionModelV3]? = nil,
    speechModels: [String: any SpeechModelV3]? = nil,
    fallbackProvider: (any ProviderV3)? = nil
) -> any ProviderV3 {
    return CustomProviderImpl(
        languageModels: languageModels,
        textEmbeddingModels: textEmbeddingModels,
        imageModels: imageModels,
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
    private let transcriptionModels: [String: any TranscriptionModelV3]?
    private let speechModels: [String: any SpeechModelV3]?
    private let fallbackProvider: (any ProviderV3)?

    init(
        languageModels: [String: any LanguageModelV3]?,
        textEmbeddingModels: [String: any EmbeddingModelV3<String>]?,
        imageModels: [String: any ImageModelV3]?,
        transcriptionModels: [String: any TranscriptionModelV3]?,
        speechModels: [String: any SpeechModelV3]?,
        fallbackProvider: (any ProviderV3)?
    ) {
        self.languageModels = languageModels
        self.textEmbeddingModels = textEmbeddingModels
        self.imageModels = imageModels
        self.transcriptionModels = transcriptionModels
        self.speechModels = speechModels
        self.fallbackProvider = fallbackProvider
    }

    public func languageModel(modelId: String) -> any LanguageModelV3 {
        if let models = languageModels, let model = models[modelId] {
            return model
        }

        if let fallback = fallbackProvider {
            return fallback.languageModel(modelId: modelId)
        }

        fatalError(NoSuchModelError(modelId: modelId, modelType: .languageModel).localizedDescription)
    }

    public func textEmbeddingModel(modelId: String) -> any EmbeddingModelV3<String> {
        if let models = textEmbeddingModels, let model = models[modelId] {
            return model
        }

        if let fallback = fallbackProvider {
            return fallback.textEmbeddingModel(modelId: modelId)
        }

        fatalError(NoSuchModelError(modelId: modelId, modelType: .textEmbeddingModel).localizedDescription)
    }

    public func imageModel(modelId: String) -> any ImageModelV3 {
        if let models = imageModels, let model = models[modelId] {
            return model
        }

        if let fallback = fallbackProvider {
            return fallback.imageModel(modelId: modelId)
        }

        fatalError(NoSuchModelError(modelId: modelId, modelType: .imageModel).localizedDescription)
    }

    public func transcriptionModel(modelId: String) -> (any TranscriptionModelV3)? {
        if let models = transcriptionModels, let model = models[modelId] {
            return model
        }

        if let fallback = fallbackProvider {
            return fallback.transcriptionModel(modelId: modelId)
        }

        // Throw error when model not found and no fallback (matches upstream behavior)
        fatalError(NoSuchModelError(modelId: modelId, modelType: .transcriptionModel).localizedDescription)
    }

    public func speechModel(modelId: String) -> (any SpeechModelV3)? {
        if let models = speechModels, let model = models[modelId] {
            return model
        }

        if let fallback = fallbackProvider {
            return fallback.speechModel(modelId: modelId)
        }

        // Throw error when model not found and no fallback (matches upstream behavior)
        fatalError(NoSuchModelError(modelId: modelId, modelType: .speechModel).localizedDescription)
    }
}
