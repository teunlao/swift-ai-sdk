import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Provider registry for managing multiple AI providers.

 Port of `@ai-sdk/ai/src/registry/provider-registry.ts`.

 The registry is V4-first internally: legacy V3 providers are accepted by the
 compatibility factory and normalized through `asProviderV4` at registration time.
 */

/// Protocol defining provider registry interface.
public protocol ProviderRegistryProvider: Sendable {
    /// Returns the language model with the given combined ID (providerId:modelId).
    func languageModel(id: String) throws -> any LanguageModelV4

    /// Returns the embedding model with the given combined ID.
    func embeddingModel(id: String) throws -> any EmbeddingModelV4

    /// Backward-compatible alias for `embeddingModel(id:)`.
    func textEmbeddingModel(id: String) throws -> any EmbeddingModelV4

    /// Returns the image model with the given combined ID.
    func imageModel(id: String) throws -> any ImageModelV4

    /// Returns the video model with the given combined ID when the original provider exposes a legacy video model.
    func videoModel(id: String) throws -> any VideoModelV4

    /// Returns the reranking model with the given combined ID.
    func rerankingModel(id: String) throws -> any RerankingModelV4

    /// Returns the transcription model with the given combined ID.
    func transcriptionModel(id: String) throws -> any TranscriptionModelV4

    /// Returns the speech model with the given combined ID.
    func speechModel(id: String) throws -> any SpeechModelV4

    /// Returns the files API for a provider ID.
    func files(id: String) throws -> any FilesV4

    /// Returns the skills API for a provider ID.
    func skills(id: String) throws -> any SkillsV4
}

/**
 Creates a registry for legacy V3 providers with optional middleware functionality.

 Legacy providers are normalized to the V4 surface immediately. Language model
 middleware remains V3-based for compatibility and is applied before V4 adaptation.
 */
public struct ProviderRegistryOptions: Sendable {
    public var separator: String
    public var languageModelMiddleware: LanguageModelMiddlewareInput?

    public init(
        separator: String = ":",
        languageModelMiddleware: LanguageModelMiddlewareInput? = nil
    ) {
        self.separator = separator
        self.languageModelMiddleware = languageModelMiddleware
    }

    public init(
        separator: String = ":",
        languageModelMiddleware: [LanguageModelV3Middleware]
    ) {
        self.separator = separator
        if languageModelMiddleware.isEmpty {
            self.languageModelMiddleware = nil
        } else if languageModelMiddleware.count == 1, let middleware = languageModelMiddleware.first {
            self.languageModelMiddleware = .single(middleware)
        } else {
            self.languageModelMiddleware = .multiple(languageModelMiddleware)
        }
    }

    public init(
        separator: String = ":",
        languageModelMiddleware: LanguageModelV3Middleware
    ) {
        self.separator = separator
        self.languageModelMiddleware = .single(languageModelMiddleware)
    }
}

public func createProviderRegistry(
    providers: [String: any ProviderV3],
    options: ProviderRegistryOptions = ProviderRegistryOptions()
) -> ProviderRegistryProvider {
    DefaultProviderRegistry(
        separator: options.separator,
        languageModelMiddleware: options.languageModelMiddleware,
        providers: providers.mapValues(asProviderV4),
        legacyProviders: providers
    )
}

public func createProviderRegistry(
    providers: [String: any ProviderV4],
    options: ProviderRegistryOptions = ProviderRegistryOptions()
) -> ProviderRegistryProvider {
    createProviderRegistryV4(providers: providers, options: options)
}

public func createProviderRegistryV4(
    providers: [String: any ProviderV4],
    options: ProviderRegistryOptions = ProviderRegistryOptions()
) -> ProviderRegistryProvider {
    DefaultProviderRegistry(
        separator: options.separator,
        languageModelMiddleware: options.languageModelMiddleware,
        providers: providers,
        legacyProviders: [:]
    )
}

/// Default implementation of provider registry.
final class DefaultProviderRegistry: ProviderRegistryProvider {
    private let providers: [String: any ProviderV4]
    private let legacyProviders: [String: any ProviderV3]
    private let separator: String
    private let languageModelMiddleware: LanguageModelMiddlewareInput?

    init(
        separator: String,
        languageModelMiddleware: LanguageModelMiddlewareInput?,
        providers: [String: any ProviderV4] = [:],
        legacyProviders: [String: any ProviderV3] = [:]
    ) {
        self.separator = separator
        self.languageModelMiddleware = languageModelMiddleware
        self.providers = providers
        self.legacyProviders = legacyProviders
    }

    func registerProvider(id: String, provider: any ProviderV3) -> DefaultProviderRegistry {
        var newProviders = providers
        var newLegacyProviders = legacyProviders
        newProviders[id] = asProviderV4(provider)
        newLegacyProviders[id] = provider
        return DefaultProviderRegistry(
            separator: separator,
            languageModelMiddleware: languageModelMiddleware,
            providers: newProviders,
            legacyProviders: newLegacyProviders
        )
    }

    func registerProviderV4(id: String, provider: any ProviderV4) -> DefaultProviderRegistry {
        var newProviders = providers
        newProviders[id] = provider
        return DefaultProviderRegistry(
            separator: separator,
            languageModelMiddleware: languageModelMiddleware,
            providers: newProviders,
            legacyProviders: legacyProviders
        )
    }

    private func getProvider(
        id: String,
        modelType: NoSuchModelError.ModelType
    ) throws -> any ProviderV4 {
        guard let provider = providers[id] else {
            throw NoSuchProviderError(
                modelId: id,
                modelType: modelType,
                providerId: id,
                availableProviders: Array(providers.keys)
            )
        }
        return provider
    }

    private func splitId(
        id: String,
        modelType: NoSuchModelError.ModelType
    ) throws -> (providerId: String, modelId: String) {
        guard let range = id.range(of: separator) else {
            throw NoSuchModelError(
                modelId: id,
                modelType: modelType,
                message: "Invalid \(modelType.rawValue) id for registry: \(id) " +
                    "(must be in the format \"providerId\(separator)modelId\")"
            )
        }

        return (String(id[..<range.lowerBound]), String(id[range.upperBound...]))
    }

    public func languageModel(id: String) throws -> any LanguageModelV4 {
        let (providerId, modelId) = try splitId(id: id, modelType: .languageModel)

        if let middleware = languageModelMiddleware, let legacyProvider = legacyProviders[providerId] {
            let legacyModel = try legacyProvider.languageModel(modelId: modelId)
            return asLanguageModelV4(wrapLanguageModel(model: legacyModel, middleware: middleware))
        }

        let provider = try getProvider(id: providerId, modelType: .languageModel)
        return try provider.languageModel(modelId: modelId)
    }

    public func embeddingModel(id: String) throws -> any EmbeddingModelV4 {
        let (providerId, modelId) = try splitId(id: id, modelType: .textEmbeddingModel)
        let provider = try getProvider(id: providerId, modelType: .textEmbeddingModel)
        return try provider.embeddingModel(modelId: modelId)
    }

    public func textEmbeddingModel(id: String) throws -> any EmbeddingModelV4 {
        try embeddingModel(id: id)
    }

    public func imageModel(id: String) throws -> any ImageModelV4 {
        let (providerId, modelId) = try splitId(id: id, modelType: .imageModel)
        let provider = try getProvider(id: providerId, modelType: .imageModel)
        return try provider.imageModel(modelId: modelId)
    }

    public func videoModel(id: String) throws -> any VideoModelV4 {
        let (providerId, modelId) = try splitId(id: id, modelType: .videoModel)

        guard let legacyProvider = legacyProviders[providerId],
              let model = try legacyProvider.videoModel(modelId: modelId)
        else {
            throw NoSuchModelError(modelId: id, modelType: .videoModel)
        }

        return asVideoModelV4(model)
    }

    public func rerankingModel(id: String) throws -> any RerankingModelV4 {
        let (providerId, modelId) = try splitId(id: id, modelType: .rerankingModel)
        let provider = try getProvider(id: providerId, modelType: .rerankingModel)

        guard let model = try provider.rerankingModel(modelId: modelId) else {
            throw NoSuchModelError(modelId: id, modelType: .rerankingModel)
        }

        return model
    }

    public func transcriptionModel(id: String) throws -> any TranscriptionModelV4 {
        let (providerId, modelId) = try splitId(id: id, modelType: .transcriptionModel)
        let provider = try getProvider(id: providerId, modelType: .transcriptionModel)

        guard let model = try provider.transcriptionModel(modelId: modelId) else {
            throw NoSuchModelError(modelId: id, modelType: .transcriptionModel)
        }

        return model
    }

    public func speechModel(id: String) throws -> any SpeechModelV4 {
        let (providerId, modelId) = try splitId(id: id, modelType: .speechModel)
        let provider = try getProvider(id: providerId, modelType: .speechModel)

        guard let model = try provider.speechModel(modelId: modelId) else {
            throw NoSuchModelError(modelId: id, modelType: .speechModel)
        }

        return model
    }

    public func files(id: String) throws -> any FilesV4 {
        let provider = try getProvider(id: id, modelType: .languageModel)

        guard let files = try provider.files() else {
            throw ProviderRegistryCapabilityError(
                message: "The provider \"\(id)\" does not support file uploads. Make sure it exposes a files() method."
            )
        }

        return files
    }

    public func skills(id: String) throws -> any SkillsV4 {
        let provider = try getProvider(id: id, modelType: .languageModel)

        guard let skills = try provider.skills() else {
            throw ProviderRegistryCapabilityError(
                message: "The provider \"\(id)\" does not support skills. Make sure it exposes a skills() method."
            )
        }

        return skills
    }
}

private struct ProviderRegistryCapabilityError: Error, CustomStringConvertible, Sendable {
    let message: String

    var description: String {
        message
    }
}
