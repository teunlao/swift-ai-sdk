/**
 Wraps a LanguageModelV3 instance with middleware functionality.

 Port of `@ai-sdk/ai/src/middleware/wrap-language-model.ts`.

 This function allows you to apply middleware to transform parameters,
 wrap generate operations, and wrap stream operations of a language model.
 */

import Foundation

/**
 Wraps a LanguageModelV3 instance with middleware functionality.

 - Parameters:
   - model: The original LanguageModelV3 instance to be wrapped.
   - middleware: The middleware to be applied to the language model. When multiple middlewares are provided, the first middleware will transform the input first, and the last middleware will be wrapped directly around the model.
   - modelId: Optional custom model ID to override the original model's ID.
   - providerId: Optional custom provider ID to override the original model's provider ID.
 - Returns: A new LanguageModelV3 instance with middleware applied.
 */
public func wrapLanguageModel(
    model: any LanguageModelV3,
    middleware: MiddlewareInput,
    modelId: String? = nil,
    providerId: String? = nil
) -> any LanguageModelV3 {
    // Convert middleware input to array and reverse it
    let middlewareArray: [LanguageModelV3Middleware]

    switch middleware {
    case .single(let m):
        middlewareArray = [m]
    case .multiple(let arr):
        middlewareArray = arr
    }

    // Apply middlewares in reverse order using reduce
    return middlewareArray.reversed().reduce(model) { wrappedModel, mw in
        doWrap(
            model: wrappedModel,
            middleware: mw,
            modelId: modelId,
            providerId: providerId
        )
    }
}

/// Input type for middleware parameter - can be single or multiple
public enum MiddlewareInput {
    case single(LanguageModelV3Middleware)
    case multiple([LanguageModelV3Middleware])
}

/// Internal function that wraps a model with a single middleware
private func doWrap(
    model: any LanguageModelV3,
    middleware: LanguageModelV3Middleware,
    modelId: String?,
    providerId: String?
) -> any LanguageModelV3 {
    return WrappedLanguageModel(
        model: model,
        middleware: middleware,
        modelId: modelId,
        providerId: providerId
    )
}

/// Internal wrapped language model implementation
private final class WrappedLanguageModel: LanguageModelV3, @unchecked Sendable {
    let specificationVersion: String = "v3"

    private let baseModel: any LanguageModelV3
    private let middleware: LanguageModelV3Middleware
    private let customModelId: String?
    private let customProviderId: String?

    init(
        model: any LanguageModelV3,
        middleware: LanguageModelV3Middleware,
        modelId: String?,
        providerId: String?
    ) {
        self.baseModel = model
        self.middleware = middleware
        self.customModelId = modelId
        self.customProviderId = providerId
    }

    var provider: String {
        if let customProviderId = customProviderId {
            return customProviderId
        }
        if let overrideProvider = middleware.overrideProvider {
            return overrideProvider(baseModel)
        }
        return baseModel.provider
    }

    var modelId: String {
        if let customModelId = customModelId {
            return customModelId
        }
        if let overrideModelId = middleware.overrideModelId {
            return overrideModelId(baseModel)
        }
        return baseModel.modelId
    }

    var supportedUrls: [String: [NSRegularExpression]] {
        get async throws {
            if let overrideSupportedUrls = middleware.overrideSupportedUrls {
                return try await overrideSupportedUrls(baseModel)
            }
            return try await baseModel.supportedUrls
        }
    }

    func doGenerate(
        options: LanguageModelV3CallOptions
    ) async throws -> LanguageModelV3GenerateResult {
        // Transform options if middleware provides transformer
        let transformedOptions = try await doTransform(
            options: options,
            type: .generate
        )

        // Create closures for doGenerate and doStream
        let doGenerateClosure: @Sendable () async throws -> LanguageModelV3GenerateResult = {
            try await self.baseModel.doGenerate(options: transformedOptions)
        }

        let doStreamClosure: @Sendable () async throws -> LanguageModelV3StreamResult = {
            try await self.baseModel.doStream(options: transformedOptions)
        }

        // If middleware provides wrapGenerate, use it; otherwise call directly
        if let wrapGenerate = middleware.wrapGenerate {
            return try await wrapGenerate(
                doGenerateClosure,
                doStreamClosure,
                transformedOptions,
                baseModel
            )
        } else {
            return try await doGenerateClosure()
        }
    }

    func doStream(
        options: LanguageModelV3CallOptions
    ) async throws -> LanguageModelV3StreamResult {
        // Transform options if middleware provides transformer
        let transformedOptions = try await doTransform(
            options: options,
            type: .stream
        )

        // Create closures for doGenerate and doStream
        let doGenerateClosure: @Sendable () async throws -> LanguageModelV3GenerateResult = {
            try await self.baseModel.doGenerate(options: transformedOptions)
        }

        let doStreamClosure: @Sendable () async throws -> LanguageModelV3StreamResult = {
            try await self.baseModel.doStream(options: transformedOptions)
        }

        // If middleware provides wrapStream, use it; otherwise call directly
        if let wrapStream = middleware.wrapStream {
            return try await wrapStream(
                doGenerateClosure,
                doStreamClosure,
                transformedOptions,
                baseModel
            )
        } else {
            return try await doStreamClosure()
        }
    }

    /// Internal helper to transform options
    private func doTransform(
        options: LanguageModelV3CallOptions,
        type: LanguageModelV3Middleware.OperationType
    ) async throws -> LanguageModelV3CallOptions {
        if let transformParams = middleware.transformParams {
            return try await transformParams(type, options, baseModel)
        }
        return options
    }
}
