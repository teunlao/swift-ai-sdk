import AISDKProvider

public final class OpenAIProviderV4: ProviderV4 {
    private let provider: OpenAIProvider

    public init(wrapping provider: OpenAIProvider) {
        self.provider = provider
    }

    public var tools: OpenAITools { provider.tools }
    public var options: OpenAIOptionsFacade { provider.options }
    public var experimental_realtime: any RealtimeFactoryV4 { provider.experimental_realtime }

    public func languageModel(modelId: String) throws -> any LanguageModelV4 {
        provider.responsesV4(OpenAIResponsesModelId(rawValue: modelId))
    }

    public func languageModel(_ modelId: String) throws -> any LanguageModelV4 {
        try languageModel(modelId: modelId)
    }

    public func callAsFunction(_ modelId: String) throws -> any LanguageModelV4 {
        try languageModel(modelId: modelId)
    }

    public func responses(modelId: OpenAIResponsesModelId) -> OpenAIResponsesLanguageModelV4 {
        provider.responsesV4(modelId)
    }

    public func responses(_ modelId: String) -> OpenAIResponsesLanguageModelV4 {
        responses(modelId: OpenAIResponsesModelId(rawValue: modelId))
    }

    public func chat(modelId: OpenAIChatModelId) -> OpenAIChatLanguageModelV4 {
        provider.chatV4(modelId)
    }

    public func chat(_ modelId: String) -> OpenAIChatLanguageModelV4 {
        chat(modelId: OpenAIChatModelId(rawValue: modelId))
    }

    public func chatModel(modelId: String) throws -> any LanguageModelV4 {
        provider.chatV4(OpenAIChatModelId(rawValue: modelId))
    }

    public func chatModel(_ modelId: OpenAIChatModelId) -> OpenAIChatLanguageModelV4 {
        chat(modelId: modelId)
    }

    public func completion(modelId: OpenAICompletionModelId) -> OpenAICompletionLanguageModelV4 {
        provider.completionV4(modelId)
    }

    public func completion(_ modelId: String) -> OpenAICompletionLanguageModelV4 {
        completion(modelId: OpenAICompletionModelId(rawValue: modelId))
    }

    public func completionModel(modelId: String) throws -> any LanguageModelV4 {
        provider.completionV4(OpenAICompletionModelId(rawValue: modelId))
    }

    public func completionModel(_ modelId: OpenAICompletionModelId) -> OpenAICompletionLanguageModelV4 {
        completion(modelId: modelId)
    }

    public func embedding(modelId: OpenAIEmbeddingModelId) -> OpenAIEmbeddingModelV4 {
        provider.embeddingV4(modelId)
    }

    public func embedding(_ modelId: String) -> OpenAIEmbeddingModelV4 {
        embedding(modelId: OpenAIEmbeddingModelId(rawValue: modelId))
    }

    public func embeddingModel(modelId: String) throws -> any EmbeddingModelV4 {
        provider.embeddingV4(OpenAIEmbeddingModelId(rawValue: modelId))
    }

    public func embeddingModel(_ modelId: OpenAIEmbeddingModelId) -> OpenAIEmbeddingModelV4 {
        embedding(modelId: modelId)
    }

    public func textEmbedding(modelId: OpenAIEmbeddingModelId) -> OpenAIEmbeddingModelV4 {
        provider.textEmbeddingV4(modelId)
    }

    public func textEmbedding(_ modelId: String) -> OpenAIEmbeddingModelV4 {
        embedding(modelId)
    }

    public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV4 {
        try embeddingModel(modelId: modelId)
    }

    public func textEmbeddingModel(_ modelId: OpenAIEmbeddingModelId) -> OpenAIEmbeddingModelV4 {
        embedding(modelId: modelId)
    }

    public func image(modelId: OpenAIImageModelId) -> OpenAIImageModelV4 {
        provider.imageV4(modelId)
    }

    public func image(_ modelId: String) -> OpenAIImageModelV4 {
        image(modelId: OpenAIImageModelId(rawValue: modelId))
    }

    public func imageModel(modelId: String) throws -> any ImageModelV4 {
        provider.imageV4(OpenAIImageModelId(rawValue: modelId))
    }

    public func imageModel(_ modelId: OpenAIImageModelId) -> OpenAIImageModelV4 {
        image(modelId: modelId)
    }

    public func transcription(modelId: OpenAITranscriptionModelId) -> OpenAITranscriptionModelV4 {
        provider.transcriptionV4(modelId)
    }

    public func transcription(_ modelId: String) -> OpenAITranscriptionModelV4 {
        transcription(modelId: OpenAITranscriptionModelId(rawValue: modelId))
    }

    public func transcriptionModel(modelId: String) throws -> (any TranscriptionModelV4)? {
        provider.transcriptionV4(OpenAITranscriptionModelId(rawValue: modelId))
    }

    public func transcriptionModel(_ modelId: OpenAITranscriptionModelId) -> OpenAITranscriptionModelV4 {
        transcription(modelId: modelId)
    }

    public func speech(modelId: OpenAISpeechModelId) -> OpenAISpeechModelV4 {
        provider.speechV4(modelId)
    }

    public func speech(_ modelId: String) -> OpenAISpeechModelV4 {
        speech(modelId: OpenAISpeechModelId(rawValue: modelId))
    }

    public func speechModel(modelId: String) throws -> (any SpeechModelV4)? {
        provider.speechV4(OpenAISpeechModelId(rawValue: modelId))
    }

    public func speechModel(_ modelId: OpenAISpeechModelId) -> OpenAISpeechModelV4 {
        speech(modelId: modelId)
    }

    public func files() throws -> (any FilesV4)? {
        provider.files()
    }

    public func skills() throws -> (any SkillsV4)? {
        provider.skills()
    }
}

public func createOpenAI(settings: OpenAIProviderSettings = .init()) throws -> OpenAIProviderV4 {
    OpenAIProviderV4(wrapping: try createOpenAIProvider(settings: settings))
}

public let openaiV4: OpenAIProviderV4 = try! createOpenAI()
