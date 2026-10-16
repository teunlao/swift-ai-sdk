import AISDKProvider

/**
 Wraps a provider so that every language model it returns has the middleware applied.

 Port of `@ai-sdk/ai/src/middleware/wrap-provider.ts`. Every other model kind,
 file uploads and skill uploads are forwarded to the wrapped provider unchanged.

 When multiple middlewares are provided, the first middleware transforms the
 input first, and the last middleware is wrapped directly around the model.
 */
public func wrapProvider(
    provider: any ProviderV4,
    languageModelMiddleware: [LanguageModelV4Middleware]
) -> any ProviderV4 {
    MiddlewareProvider(provider: provider, languageModelMiddleware: languageModelMiddleware)
}

public func wrapProvider(
    provider: any ProviderV4,
    languageModelMiddleware: LanguageModelV4Middleware
) -> any ProviderV4 {
    wrapProvider(provider: provider, languageModelMiddleware: [languageModelMiddleware])
}

/// Wraps a V3 provider, resolving it to V4 first.
public func wrapProvider(
    provider: any ProviderV3,
    languageModelMiddleware: [LanguageModelV4Middleware]
) -> any ProviderV4 {
    wrapProvider(provider: asProviderV4(provider), languageModelMiddleware: languageModelMiddleware)
}

/// Wraps a V3 provider, resolving it to V4 first.
public func wrapProvider(
    provider: any ProviderV3,
    languageModelMiddleware: LanguageModelV4Middleware
) -> any ProviderV4 {
    wrapProvider(provider: asProviderV4(provider), languageModelMiddleware: [languageModelMiddleware])
}

private struct MiddlewareProvider: ProviderV4 {
    let provider: any ProviderV4
    let languageModelMiddleware: [LanguageModelV4Middleware]

    func languageModel(modelId: String) throws -> any LanguageModelV4 {
        wrapLanguageModel(
            model: try provider.languageModel(modelId: modelId),
            middleware: languageModelMiddleware
        )
    }

    func embeddingModel(modelId: String) throws -> any EmbeddingModelV4 {
        try provider.embeddingModel(modelId: modelId)
    }

    func imageModel(modelId: String) throws -> any ImageModelV4 {
        try provider.imageModel(modelId: modelId)
    }

    func transcriptionModel(modelId: String) throws -> (any TranscriptionModelV4)? {
        try provider.transcriptionModel(modelId: modelId)
    }

    func speechModel(modelId: String) throws -> (any SpeechModelV4)? {
        try provider.speechModel(modelId: modelId)
    }

    func rerankingModel(modelId: String) throws -> (any RerankingModelV4)? {
        try provider.rerankingModel(modelId: modelId)
    }

    func files() throws -> (any FilesV4)? {
        try provider.files()
    }

    func skills() throws -> (any SkillsV4)? {
        try provider.skills()
    }
}
