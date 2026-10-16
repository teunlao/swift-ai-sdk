import AISDKProvider

/**
 Middleware types exported by the `ai` package.

 Port of `@ai-sdk/ai/src/types/{language,embedding,image}-model-middleware.ts`.
 Upstream relaxes `specificationVersion` to any optional string so V3 middleware
 objects keep working; the Swift V4 middleware structs already take any
 `specificationVersion` string, so the `ai` names alias them directly.
 */
public typealias LanguageModelMiddleware = LanguageModelV4Middleware

public typealias EmbeddingModelMiddleware = EmbeddingModelV4Middleware

public typealias ImageModelMiddleware = ImageModelV4Middleware
