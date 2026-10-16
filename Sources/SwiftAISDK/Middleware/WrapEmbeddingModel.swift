import AISDKProvider
import AISDKProviderUtils

/**
 Wraps an embedding model with middleware functionality.

 Port of `@ai-sdk/ai/src/middleware/wrap-embedding-model.ts`.

 When multiple middlewares are provided, the first middleware transforms the
 input first, and the last middleware is wrapped directly around the model.
 `modelId` and `providerId` override the wrapped model's identifiers.
 */
public func wrapEmbeddingModel(
    model: any EmbeddingModelV4,
    middleware: [EmbeddingModelV4Middleware],
    modelId: String? = nil,
    providerId: String? = nil
) -> any EmbeddingModelV4 {
    middleware.reversed().reduce(model) { wrappedModel, middleware in
        makeWrappedEmbeddingModel(
            model: wrappedModel,
            middleware: middleware,
            modelId: modelId,
            providerId: providerId
        )
    }
}

public func wrapEmbeddingModel(
    model: any EmbeddingModelV4,
    middleware: EmbeddingModelV4Middleware,
    modelId: String? = nil,
    providerId: String? = nil
) -> any EmbeddingModelV4 {
    wrapEmbeddingModel(model: model, middleware: [middleware], modelId: modelId, providerId: providerId)
}

/// Wraps a V3 embedding model, resolving it to V4 first.
public func wrapEmbeddingModel(
    model: any EmbeddingModelV3<String>,
    middleware: [EmbeddingModelV4Middleware],
    modelId: String? = nil,
    providerId: String? = nil
) -> any EmbeddingModelV4 {
    wrapEmbeddingModel(model: asEmbeddingModelV4(model), middleware: middleware, modelId: modelId, providerId: providerId)
}

/// Wraps a V3 embedding model, resolving it to V4 first.
public func wrapEmbeddingModel(
    model: any EmbeddingModelV3<String>,
    middleware: EmbeddingModelV4Middleware,
    modelId: String? = nil,
    providerId: String? = nil
) -> any EmbeddingModelV4 {
    wrapEmbeddingModel(model: asEmbeddingModelV4(model), middleware: [middleware], modelId: modelId, providerId: providerId)
}

private func makeWrappedEmbeddingModel(
    model: any EmbeddingModelV4,
    middleware: EmbeddingModelV4Middleware,
    modelId: String?,
    providerId: String?
) -> any EmbeddingModelV4 {
    // The experimental capabilities are forwarded from the inner model; a
    // provider options transformer is only claimed when the inner model has one.
    if let transformer = model as? any EmbeddingModelProviderOptionsTransformer {
        return TransformingWrappedEmbeddingModel(
            model: model,
            middleware: middleware,
            modelId: modelId,
            providerId: providerId,
            transformer: transformer
        )
    }
    return WrappedEmbeddingModel(
        model: model,
        middleware: middleware,
        modelId: modelId,
        providerId: providerId
    )
}

private class WrappedEmbeddingModel: EmbeddingModelV4, EmbeddingModelMaxInputBytesPerCall, @unchecked Sendable {
    let specificationVersion = "v4"
    let provider: String
    let modelId: String

    private let model: any EmbeddingModelV4
    private let middleware: EmbeddingModelV4Middleware

    init(
        model: any EmbeddingModelV4,
        middleware: EmbeddingModelV4Middleware,
        modelId: String?,
        providerId: String?
    ) {
        self.model = model
        self.middleware = middleware
        self.provider = providerId ?? middleware.overrideProvider?(model) ?? model.provider
        self.modelId = modelId ?? middleware.overrideModelId?(model) ?? model.modelId
    }

    var maxEmbeddingsPerCall: Int? {
        get async throws {
            if let override = middleware.overrideMaxEmbeddingsPerCall,
               let value = try await override(model) {
                return value
            }
            return try await model.maxEmbeddingsPerCall
        }
    }

    var supportsParallelCalls: Bool {
        get async throws {
            if let override = middleware.overrideSupportsParallelCalls {
                return try await override(model)
            }
            return try await model.supportsParallelCalls
        }
    }

    var maxInputBytesPerCall: Int? {
        get async throws {
            try await (model as? any EmbeddingModelMaxInputBytesPerCall)?.maxInputBytesPerCall
        }
    }

    func doEmbed(options: EmbeddingModelV4CallOptions) async throws -> EmbeddingModelV4Result {
        let transformedOptions = try await middleware.transformParams?(options, model) ?? options
        let model = self.model
        let doEmbed: @Sendable () async throws -> EmbeddingModelV4Result = {
            try await model.doEmbed(options: transformedOptions)
        }
        if let wrapEmbed = middleware.wrapEmbed {
            return try await wrapEmbed(doEmbed, transformedOptions, model)
        }
        return try await doEmbed()
    }
}

private final class TransformingWrappedEmbeddingModel: WrappedEmbeddingModel, EmbeddingModelProviderOptionsTransformer, @unchecked Sendable {
    private let transformer: any EmbeddingModelProviderOptionsTransformer

    init(
        model: any EmbeddingModelV4,
        middleware: EmbeddingModelV4Middleware,
        modelId: String?,
        providerId: String?,
        transformer: any EmbeddingModelProviderOptionsTransformer
    ) {
        self.transformer = transformer
        super.init(model: model, middleware: middleware, modelId: modelId, providerId: providerId)
    }

    func transformProviderOptions(
        _ options: EmbeddingModelProviderOptionsTransformerOptions
    ) async throws -> SharedV4ProviderOptions? {
        try await transformer.transformProviderOptions(options)
    }
}
