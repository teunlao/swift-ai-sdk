/**
 Provider for language, embedding, image generation, transcription, speech,
 reranking, files, and skills surfaces.

 Port of `@ai-sdk/provider/src/provider/v4/provider-v4.ts`.
 */
public protocol ProviderV4: Sendable {
    var specificationVersion: String { get }

    func languageModel(modelId: String) throws -> any LanguageModelV4
    func embeddingModel(modelId: String) throws -> any EmbeddingModelV4
    func imageModel(modelId: String) throws -> any ImageModelV4
    func transcriptionModel(modelId: String) throws -> (any TranscriptionModelV4)?
    func speechModel(modelId: String) throws -> (any SpeechModelV4)?
    func rerankingModel(modelId: String) throws -> (any RerankingModelV4)?
    func files() throws -> (any FilesV4)?
    func skills() throws -> (any SkillsV4)?
}

extension ProviderV4 {
    public var specificationVersion: String { "v4" }

    public func transcriptionModel(modelId: String) throws -> (any TranscriptionModelV4)? {
        nil
    }

    public func speechModel(modelId: String) throws -> (any SpeechModelV4)? {
        nil
    }

    public func rerankingModel(modelId: String) throws -> (any RerankingModelV4)? {
        nil
    }

    public func files() throws -> (any FilesV4)? {
        nil
    }

    public func skills() throws -> (any SkillsV4)? {
        nil
    }
}
