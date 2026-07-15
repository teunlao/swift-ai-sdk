import AISDKProvider

public final class AnthropicProviderV4: ProviderV4 {
    private let provider: AnthropicProvider

    public init(wrapping provider: AnthropicProvider) {
        self.provider = provider
    }

    public var tools: AnthropicTools { provider.tools }

    public func languageModel(modelId: String) throws -> any LanguageModelV4 {
        provider.messagesV4(modelId: AnthropicMessagesModelId(rawValue: modelId))
    }

    public func languageModel(_ modelId: String) throws -> any LanguageModelV4 {
        try languageModel(modelId: modelId)
    }

    public func callAsFunction(_ modelId: String) throws -> any LanguageModelV4 {
        try languageModel(modelId: modelId)
    }

    public func chat(modelId: AnthropicMessagesModelId) -> AnthropicMessagesLanguageModelV4 {
        provider.chatV4(modelId: modelId)
    }

    public func chat(_ modelId: String) -> AnthropicMessagesLanguageModelV4 {
        chat(modelId: AnthropicMessagesModelId(rawValue: modelId))
    }

    public func messages(modelId: AnthropicMessagesModelId) -> AnthropicMessagesLanguageModelV4 {
        provider.messagesV4(modelId: modelId)
    }

    public func messages(_ modelId: String) -> AnthropicMessagesLanguageModelV4 {
        messages(modelId: AnthropicMessagesModelId(rawValue: modelId))
    }

    public func embeddingModel(modelId: String) throws -> any EmbeddingModelV4 {
        throw NoSuchModelError(modelId: modelId, modelType: .textEmbeddingModel)
    }

    public func imageModel(modelId: String) throws -> any ImageModelV4 {
        throw NoSuchModelError(modelId: modelId, modelType: .imageModel)
    }

    public func files() throws -> (any FilesV4)? {
        provider.files()
    }

    public func skills() throws -> (any SkillsV4)? {
        provider.skills()
    }
}

public func createAnthropic(settings: AnthropicProviderSettings = .init()) -> AnthropicProviderV4 {
    AnthropicProviderV4(wrapping: createAnthropicProvider(settings: settings))
}

public let anthropicV4: AnthropicProviderV4 = createAnthropic()
