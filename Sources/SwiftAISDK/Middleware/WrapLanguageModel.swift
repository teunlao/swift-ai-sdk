import Foundation
import AISDKProvider
import AISDKProviderUtils

public enum LanguageModelMiddlewareInput: Sendable {
    case single(LanguageModelV4Middleware)
    case multiple([LanguageModelV4Middleware])
}

public func wrapLanguageModel(
    model: any LanguageModelV4,
    middleware: LanguageModelMiddlewareInput,
    modelId: String? = nil,
    providerId: String? = nil
) -> any LanguageModelV4 {
    let middlewares: [LanguageModelV4Middleware]
    switch middleware {
    case .single(let middleware): middlewares = [middleware]
    case .multiple(let middleware): middlewares = middleware
    }
    return middlewares.reversed().reduce(model) {
        WrappedLanguageModel(model: $0, middleware: $1, modelId: modelId, providerId: providerId)
    }
}

public func wrapLanguageModel(
    model: any LanguageModelV4,
    middleware: LanguageModelV4Middleware,
    modelId: String? = nil,
    providerId: String? = nil
) -> any LanguageModelV4 {
    wrapLanguageModel(model: model, middleware: .single(middleware), modelId: modelId, providerId: providerId)
}

public func wrapLanguageModel(
    model: any LanguageModelV4,
    middleware: [LanguageModelV4Middleware],
    modelId: String? = nil,
    providerId: String? = nil
) -> any LanguageModelV4 {
    wrapLanguageModel(model: model, middleware: .multiple(middleware), modelId: modelId, providerId: providerId)
}

private final class WrappedLanguageModel: LanguageModelV4, @unchecked Sendable {
    let specificationVersion = "v4"
    private let baseModel: any LanguageModelV4
    private let middleware: LanguageModelV4Middleware
    private let customModelId: String?
    private let customProviderId: String?

    init(model: any LanguageModelV4, middleware: LanguageModelV4Middleware, modelId: String?, providerId: String?) {
        baseModel = model
        self.middleware = middleware
        customModelId = modelId
        customProviderId = providerId
    }

    var provider: String {
        if let customProviderId { return customProviderId }
        return middleware.overrideProvider?(baseModel) ?? baseModel.provider
    }

    var modelId: String {
        if let customModelId { return customModelId }
        return middleware.overrideModelId?(baseModel) ?? baseModel.modelId
    }

    var supportedUrls: [String: [NSRegularExpression]] {
        get async throws {
            if let override = middleware.overrideSupportedUrls { return try await override(baseModel) }
            return try await baseModel.supportedUrls
        }
    }

    func doGenerate(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4GenerateResult {
        let options = try await transform(options, type: .generate)
        let base = baseModel
        let generate: @Sendable () async throws -> LanguageModelV4GenerateResult = { try await base.doGenerate(options: options) }
        let stream: @Sendable () async throws -> LanguageModelV4StreamResult = { try await base.doStream(options: options) }
        if let wrap = middleware.wrapGenerate { return try await wrap(generate, stream, options, baseModel) }
        return try await generate()
    }

    func doStream(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4StreamResult {
        let options = try await transform(options, type: .stream)
        let base = baseModel
        let generate: @Sendable () async throws -> LanguageModelV4GenerateResult = { try await base.doGenerate(options: options) }
        let stream: @Sendable () async throws -> LanguageModelV4StreamResult = { try await base.doStream(options: options) }
        if let wrap = middleware.wrapStream { return try await wrap(generate, stream, options, baseModel) }
        return try await stream()
    }

    private func transform(_ options: LanguageModelV4CallOptions, type: LanguageModelV4Middleware.OperationType) async throws -> LanguageModelV4CallOptions {
        if let transform = middleware.transformParams { return try await transform(type, options, baseModel) }
        return options
    }
}
