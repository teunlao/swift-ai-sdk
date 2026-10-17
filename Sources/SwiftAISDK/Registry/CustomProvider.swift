import AISDKProvider
import AISDKProviderUtils

public func customProvider(
    languageModels: [String: any LanguageModelConvertible]? = nil,
    embeddingModels: [String: any EmbeddingModelConvertible]? = nil,
    imageModels: [String: any ImageModelConvertible]? = nil,
    transcriptionModels: [String: any TranscriptionModelConvertible]? = nil,
    speechModels: [String: any SpeechModelConvertible]? = nil,
    rerankingModels: [String: any RerankingModelConvertible]? = nil,
    videoModels: [String: any VideoModelConvertible]? = nil,
    files: (any FilesV4)? = nil,
    skills: (any SkillsV4)? = nil,
    fallbackProvider: (any ProviderV4)? = nil
) -> any ProviderV4 & VideoProviderV4 {
    CustomProvider(
        languageModels: languageModels, embeddingModels: embeddingModels, imageModels: imageModels,
        rerankingModels: rerankingModels, transcriptionModels: transcriptionModels, speechModels: speechModels,
        videoModels: videoModels, files: files, skills: skills, fallbackProvider: fallbackProvider
    )
}

private final class CustomProvider: ProviderV4, VideoProviderV4 {
    private let languageModels: [String: any LanguageModelConvertible]?
    private let embeddingModels: [String: any EmbeddingModelConvertible]?
    private let imageModels: [String: any ImageModelConvertible]?
    private let rerankingModels: [String: any RerankingModelConvertible]?
    private let transcriptionModels: [String: any TranscriptionModelConvertible]?
    private let speechModels: [String: any SpeechModelConvertible]?
    private let videoModels: [String: any VideoModelConvertible]?
    private let filesInterface: (any FilesV4)?
    private let skillsInterface: (any SkillsV4)?
    private let fallbackProvider: (any ProviderV4)?

    init(
        languageModels: [String: any LanguageModelConvertible]?, embeddingModels: [String: any EmbeddingModelConvertible]?,
        imageModels: [String: any ImageModelConvertible]?, rerankingModels: [String: any RerankingModelConvertible]?,
        transcriptionModels: [String: any TranscriptionModelConvertible]?, speechModels: [String: any SpeechModelConvertible]?,
        videoModels: [String: any VideoModelConvertible]?, files: (any FilesV4)?, skills: (any SkillsV4)?,
        fallbackProvider: (any ProviderV4)?
    ) {
        self.languageModels = languageModels
        self.embeddingModels = embeddingModels
        self.imageModels = imageModels
        self.rerankingModels = rerankingModels
        self.transcriptionModels = transcriptionModels
        self.speechModels = speechModels
        self.videoModels = videoModels
        filesInterface = files
        skillsInterface = skills
        self.fallbackProvider = fallbackProvider
    }

    func languageModel(modelId: String) throws -> any LanguageModelV4 {
        if let model = languageModels?[modelId] { return try resolveLanguageModel(model) }
        if let fallbackProvider { return try fallbackProvider.languageModel(modelId: modelId) }
        throw NoSuchModelError(modelId: modelId, modelType: .languageModel)
    }

    func embeddingModel(modelId: String) throws -> any EmbeddingModelV4 {
        if let model = embeddingModels?[modelId] { return try resolveEmbeddingModel(model) }
        if let fallbackProvider { return try fallbackProvider.embeddingModel(modelId: modelId) }
        throw NoSuchModelError(modelId: modelId, modelType: .embeddingModel)
    }

    func imageModel(modelId: String) throws -> any ImageModelV4 {
        if let model = imageModels?[modelId] { return try resolveImageModel(model) }
        if let fallbackProvider { return try fallbackProvider.imageModel(modelId: modelId) }
        throw NoSuchModelError(modelId: modelId, modelType: .imageModel)
    }

    func transcriptionModel(modelId: String) throws -> (any TranscriptionModelV4)? {
        if let model = transcriptionModels?[modelId], let resolved = try resolveTranscriptionModel(model) { return resolved }
        if let model = try fallbackProvider?.transcriptionModel(modelId: modelId) { return model }
        throw NoSuchModelError(modelId: modelId, modelType: .transcriptionModel)
    }

    func speechModel(modelId: String) throws -> (any SpeechModelV4)? {
        if let model = speechModels?[modelId], let resolved = try resolveSpeechModel(model) { return resolved }
        if let model = try fallbackProvider?.speechModel(modelId: modelId) { return model }
        throw NoSuchModelError(modelId: modelId, modelType: .speechModel)
    }

    func rerankingModel(modelId: String) throws -> (any RerankingModelV4)? {
        if let model = rerankingModels?[modelId] { return try resolveRerankingModel(model) }
        if let model = try fallbackProvider?.rerankingModel(modelId: modelId) { return model }
        throw NoSuchModelError(modelId: modelId, modelType: .rerankingModel)
    }

    func videoModel(modelId: String) throws -> any VideoModelV4 {
        if let model = videoModels?[modelId] { return try resolveVideoModel(model) }
        if let provider = fallbackProvider as? any VideoProviderV4 { return try provider.videoModel(modelId: modelId) }
        throw NoSuchModelError(modelId: modelId, modelType: .videoModel)
    }

    func files() throws -> (any FilesV4)? {
        if let filesInterface { return filesInterface }
        return try fallbackProvider?.files()
    }

    func skills() throws -> (any SkillsV4)? {
        if let skillsInterface { return skillsInterface }
        return try fallbackProvider?.skills()
    }
}
