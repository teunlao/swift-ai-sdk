import Foundation
import AISDKProvider
import AISDKProviderUtils

public protocol ProviderRegistryProvider: Sendable {
    func languageModel(id: String) throws -> any LanguageModelV4
    func embeddingModel(id: String) throws -> any EmbeddingModelV4
    func imageModel(id: String) throws -> any ImageModelV4
    func videoModel(id: String) throws -> any VideoModelV4
    func rerankingModel(id: String) throws -> any RerankingModelV4
    func transcriptionModel(id: String) throws -> any TranscriptionModelV4
    func speechModel(id: String) throws -> any SpeechModelV4
    func files(id: String) throws -> any FilesV4
    func skills(id: String) throws -> any SkillsV4
}

public struct ProviderRegistryOptions: Sendable {
    public var separator: String
    public var languageModelMiddleware: LanguageModelMiddlewareInput?
    public var imageModelMiddleware: ImageModelMiddlewareInput?

    public init(separator: String = ":", languageModelMiddleware: LanguageModelMiddlewareInput? = nil, imageModelMiddleware: ImageModelMiddlewareInput? = nil) {
        self.separator = separator
        self.languageModelMiddleware = languageModelMiddleware
        self.imageModelMiddleware = imageModelMiddleware
    }

    public init(separator: String = ":", languageModelMiddleware: [LanguageModelV4Middleware]) {
        self.separator = separator
        self.languageModelMiddleware = languageModelMiddleware.isEmpty ? nil : .multiple(languageModelMiddleware)
        imageModelMiddleware = nil
    }

    public init(separator: String = ":", languageModelMiddleware: LanguageModelV4Middleware) {
        self.separator = separator
        self.languageModelMiddleware = .single(languageModelMiddleware)
        imageModelMiddleware = nil
    }
}

public func createProviderRegistry(
    providers: [String: any ProviderV4],
    options: ProviderRegistryOptions = ProviderRegistryOptions()
) -> ProviderRegistryProvider {
    DefaultProviderRegistry(separator: options.separator, languageModelMiddleware: options.languageModelMiddleware,
        imageModelMiddleware: options.imageModelMiddleware, providers: providers)
}

final class DefaultProviderRegistry: ProviderRegistryProvider {
    private let providers: [String: any ProviderV4]
    private let separator: String
    private let languageModelMiddleware: LanguageModelMiddlewareInput?
    private let imageModelMiddleware: ImageModelMiddlewareInput?

    init(separator: String, languageModelMiddleware: LanguageModelMiddlewareInput?, imageModelMiddleware: ImageModelMiddlewareInput? = nil,
         providers: [String: any ProviderV4] = [:]) {
        self.separator = separator
        self.languageModelMiddleware = languageModelMiddleware
        self.imageModelMiddleware = imageModelMiddleware
        self.providers = providers
    }

    func registerProvider(id: String, provider: any ProviderV4) -> DefaultProviderRegistry {
        var providers = providers
        providers[id] = provider
        return DefaultProviderRegistry(separator: separator, languageModelMiddleware: languageModelMiddleware,
            imageModelMiddleware: imageModelMiddleware, providers: providers)
    }

    private func getProvider(id: String, modelType: NoSuchModelError.ModelType) throws -> any ProviderV4 {
        guard let provider = providers[id] else {
            throw NoSuchProviderError(modelId: id, modelType: modelType, providerId: id, availableProviders: Array(providers.keys))
        }
        return provider
    }

    private func splitId(id: String, modelType: NoSuchModelError.ModelType) throws -> (providerId: String, modelId: String) {
        guard let range = id.range(of: separator) else {
            throw NoSuchModelError(modelId: id, modelType: modelType,
                message: "Invalid \(modelType.rawValue) id for registry: \(id) (must be in the format \"providerId\(separator)modelId\")")
        }
        return (String(id[..<range.lowerBound]), String(id[range.upperBound...]))
    }

    func languageModel(id: String) throws -> any LanguageModelV4 {
        let (providerId, modelId) = try splitId(id: id, modelType: .languageModel)
        let model = try getProvider(id: providerId, modelType: .languageModel).languageModel(modelId: modelId)
        return languageModelMiddleware.map { wrapLanguageModel(model: model, middleware: $0) } ?? model
    }

    func embeddingModel(id: String) throws -> any EmbeddingModelV4 {
        let (providerId, modelId) = try splitId(id: id, modelType: .embeddingModel)
        return try getProvider(id: providerId, modelType: .embeddingModel).embeddingModel(modelId: modelId)
    }

    func imageModel(id: String) throws -> any ImageModelV4 {
        let (providerId, modelId) = try splitId(id: id, modelType: .imageModel)
        let model = try getProvider(id: providerId, modelType: .imageModel).imageModel(modelId: modelId)
        return imageModelMiddleware.map { wrapImageModel(model: model, middleware: $0) } ?? model
    }

    func videoModel(id: String) throws -> any VideoModelV4 {
        let (providerId, modelId) = try splitId(id: id, modelType: .videoModel)
        guard let provider = try getProvider(id: providerId, modelType: .videoModel) as? any VideoProviderV4 else {
            throw NoSuchModelError(modelId: id, modelType: .videoModel)
        }
        return try provider.videoModel(modelId: modelId)
    }

    func rerankingModel(id: String) throws -> any RerankingModelV4 {
        let (providerId, modelId) = try splitId(id: id, modelType: .rerankingModel)
        guard let model = try getProvider(id: providerId, modelType: .rerankingModel).rerankingModel(modelId: modelId) else {
            throw NoSuchModelError(modelId: id, modelType: .rerankingModel)
        }
        return model
    }

    func transcriptionModel(id: String) throws -> any TranscriptionModelV4 {
        let (providerId, modelId) = try splitId(id: id, modelType: .transcriptionModel)
        guard let model = try getProvider(id: providerId, modelType: .transcriptionModel).transcriptionModel(modelId: modelId) else {
            throw NoSuchModelError(modelId: id, modelType: .transcriptionModel)
        }
        return model
    }

    func speechModel(id: String) throws -> any SpeechModelV4 {
        let (providerId, modelId) = try splitId(id: id, modelType: .speechModel)
        guard let model = try getProvider(id: providerId, modelType: .speechModel).speechModel(modelId: modelId) else {
            throw NoSuchModelError(modelId: id, modelType: .speechModel)
        }
        return model
    }

    func files(id: String) throws -> any FilesV4 {
        guard let files = try getProvider(id: id, modelType: .languageModel).files() else {
            throw ProviderRegistryCapabilityError(message: "The provider \"\(id)\" does not support file uploads. Make sure it exposes a files() method.")
        }
        return files
    }

    func skills(id: String) throws -> any SkillsV4 {
        guard let skills = try getProvider(id: id, modelType: .languageModel).skills() else {
            throw ProviderRegistryCapabilityError(message: "The provider \"\(id)\" does not support skills. Make sure it exposes a skills() method.")
        }
        return skills
    }
}

private struct ProviderRegistryCapabilityError: Error, LocalizedError, CustomStringConvertible, Sendable {
    let message: String
    var errorDescription: String? { message }
    var description: String { message }
}
