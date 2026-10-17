import Foundation
import AISDKProvider
import AISDKProviderUtils
import GatewayProvider

nonisolated(unsafe) public var globalDefaultProvider: (any ProviderV4)? = nil

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
enum _ResolveModelContext {
    @TaskLocal static var disableGlobalProvider: Bool = false
    @TaskLocal static var overrideProviderV4: (any ProviderV4)? = nil
}

nonisolated(unsafe) public var disableGlobalProviderForStringResolution: Bool = false

@discardableResult
public func withGlobalProviderDisabled<T>(_ operation: () throws -> T) rethrows -> T {
    try _ResolveModelContext.$disableGlobalProvider.withValue(true) { try operation() }
}

@discardableResult
public func withGlobalProviderDisabled<T>(operation: () async throws -> T) async rethrows -> T {
    try await _ResolveModelContext.$disableGlobalProvider.withValue(true) { try await operation() }
}

@discardableResult
public func withGlobalProvider<T>(_ provider: any ProviderV4, _ operation: () throws -> T) rethrows -> T {
    try _ResolveModelContext.$overrideProviderV4.withValue(provider) { try operation() }
}

@discardableResult
public func withGlobalProvider<T>(_ provider: any ProviderV4, operation: () async throws -> T) async rethrows -> T {
    try await _ResolveModelContext.$overrideProviderV4.withValue(provider) { try await operation() }
}

func _resolveGlobalProvider(modelId: String, modelType: NoSuchModelError.ModelType) throws -> any ProviderV4 {
    if let provider = _ResolveModelContext.overrideProviderV4 { return provider }
    if !(disableGlobalProviderForStringResolution || _ResolveModelContext.disableGlobalProvider) {
        return globalDefaultProvider ?? gateway
    }
    throw NoSuchProviderError(
        modelId: modelId, modelType: modelType, providerId: "default", availableProviders: [],
        message: "No global default provider set. Set `globalDefaultProvider` before resolving string model IDs."
    )
}

public func resolveLanguageModel(_ model: any LanguageModelConvertible) throws -> any LanguageModelV4 {
    switch model.languageModel {
    case .model(let model):
        try validateModelSpecification(model.specificationVersion, provider: model.provider, modelId: model.modelId)
        return model
    case .id(let id):
        return try _resolveGlobalProvider(modelId: id, modelType: .languageModel).languageModel(modelId: id)
    }
}

public func resolveEmbeddingModel(_ model: any EmbeddingModelConvertible) throws -> any EmbeddingModelV4 {
    switch model.embeddingModel {
    case .model(let model):
        try validateModelSpecification(model.specificationVersion, provider: model.provider, modelId: model.modelId)
        return model
    case .id(let id):
        return try _resolveGlobalProvider(modelId: id, modelType: .embeddingModel).embeddingModel(modelId: id)
    }
}

public func resolveImageModel(_ model: any ImageModelConvertible) throws -> any ImageModelV4 {
    switch model.imageModel {
    case .model(let model):
        try validateModelSpecification(model.specificationVersion, provider: model.provider, modelId: model.modelId)
        return model
    case .id(let id):
        return try _resolveGlobalProvider(modelId: id, modelType: .imageModel).imageModel(modelId: id)
    }
}

public func resolveRerankingModel(_ model: any RerankingModelConvertible) throws -> any RerankingModelV4 {
    switch model.rerankingModel {
    case .model(let model):
        try validateModelSpecification(model.specificationVersion, provider: model.provider, modelId: model.modelId)
        return model
    case .id(let id):
        guard let model = try _resolveGlobalProvider(modelId: id, modelType: .rerankingModel).rerankingModel(modelId: id) else {
            throw ModelResolutionFailure(message: "The default provider does not support reranking models. Please use a RerankingModel object from a provider (e.g., gateway.rerankingModel(\"model-id\")).")
        }
        return model
    }
}

public func resolveSpeechModel(_ model: any SpeechModelConvertible) throws -> (any SpeechModelV4)? {
    switch model.speechModel {
    case .model(let model):
        try validateModelSpecification(model.specificationVersion, provider: model.provider, modelId: model.modelId)
        return model
    case .id(let id):
        return try _resolveGlobalProvider(modelId: id, modelType: .speechModel).speechModel(modelId: id)
    }
}

public func resolveTranscriptionModel(_ model: any TranscriptionModelConvertible) throws -> (any TranscriptionModelV4)? {
    switch model.transcriptionModel {
    case .model(let model):
        try validateModelSpecification(model.specificationVersion, provider: model.provider, modelId: model.modelId)
        return model
    case .id(let id):
        return try _resolveGlobalProvider(modelId: id, modelType: .transcriptionModel).transcriptionModel(modelId: id)
    }
}

public func resolveVideoModel(_ model: any VideoModelConvertible) throws -> any VideoModelV4 {
    switch model.videoModel {
    case .model(let model):
        try validateModelSpecification(model.specificationVersion, provider: model.provider, modelId: model.modelId)
        return model
    case .id(let id):
        guard let provider = try _resolveGlobalProvider(modelId: id, modelType: .videoModel) as? any VideoProviderV4 else {
            throw ModelResolutionFailure(message: "The default provider does not support video models. Please use a video model object from a provider (e.g., vertex.video(\"model-id\")).")
        }
        return try provider.videoModel(modelId: id)
    }
}

struct ModelResolutionFailure: Error, LocalizedError, CustomStringConvertible {
    let message: String
    var errorDescription: String? { message }
    var description: String { message }
}

private func validateModelSpecification(_ version: String, provider: String, modelId: String) throws {
    guard version == "v4" else {
        throw UnsupportedModelVersionError(version: version, provider: provider, modelId: modelId)
    }
}
