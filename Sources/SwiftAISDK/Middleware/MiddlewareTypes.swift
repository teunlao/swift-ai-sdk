import AISDKProvider

/**
 Middleware types exported by the `ai` package.

 Port of `@ai-sdk/ai/src/types/{language,embedding,image}-model-middleware.ts`.
 Middleware uses the current provider contracts.
 */
public typealias LanguageModelMiddleware = LanguageModelV4Middleware

public typealias EmbeddingModelMiddleware = EmbeddingModelV4Middleware
