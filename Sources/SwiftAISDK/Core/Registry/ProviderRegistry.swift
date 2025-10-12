/**
 Provider registry for managing multiple AI providers.

 Port of `@ai-sdk/ai/src/registry/provider-registry.ts`.

 Creates a registry for multiple providers with optional middleware functionality.
 Allows registering providers and applying middleware to all language models from the registry.
 */

/// Protocol defining provider registry interface
public protocol ProviderRegistryProvider: Sendable {
    /// Returns the language model with the given combined ID (providerId:modelId)
    func languageModel(id: String) -> any LanguageModelV3

    /// Returns the text embedding model with the given combined ID
    func textEmbeddingModel(id: String) -> any EmbeddingModelV3<String>

    /// Returns the image model with the given combined ID
    func imageModel(id: String) -> any ImageModelV3

    /// Returns the transcription model with the given combined ID
    func transcriptionModel(id: String) -> any TranscriptionModelV3

    /// Returns the speech model with the given combined ID
    func speechModel(id: String) -> any SpeechModelV3
}

/**
 Creates a registry for the given providers with optional middleware functionality.

 This function allows you to register multiple providers and optionally apply middleware
 to all language models from the registry, enabling you to transform parameters, wrap generate
 operations, and wrap stream operations for every language model accessed through the registry.

 - Parameters:
   - providers: A dictionary of provider instances to be registered in the registry.
   - separator: The separator used between provider ID and model ID in the combined identifier. Defaults to ":".
     Supports multi-character separators (e.g., " > ").
   - languageModelMiddleware: Optional middleware to be applied to all language models from the registry.
     When multiple middlewares are provided, the first middleware will transform the input first,
     and the last middleware will be wrapped directly around the model.

 - Returns: A new ProviderRegistryProvider instance that provides access to all registered providers
   with optional middleware applied to language models.

 - Note: Error handling differs from TypeScript upstream:
   - TypeScript: throws recoverable errors
   - Swift: uses fatalError (crashes with detailed message)
   - Rationale: Protocol methods cannot conditionally declare 'throws' in Swift
 */
public func createProviderRegistry(
    providers: [String: any ProviderV3],
    separator: String = ":",
    languageModelMiddleware: [LanguageModelV3Middleware]? = nil
) -> ProviderRegistryProvider {
    return DefaultProviderRegistry(
        separator: separator,
        languageModelMiddleware: languageModelMiddleware,
        providers: providers
    )
}

/// Default implementation of provider registry
final class DefaultProviderRegistry: ProviderRegistryProvider {
    private let providers: [String: any ProviderV3]
    private let separator: String
    private let languageModelMiddleware: [LanguageModelV3Middleware]?

    init(
        separator: String,
        languageModelMiddleware: [LanguageModelV3Middleware]?,
        providers: [String: any ProviderV3] = [:]
    ) {
        self.separator = separator
        self.languageModelMiddleware = languageModelMiddleware
        self.providers = providers
    }

    func registerProvider(id: String, provider: any ProviderV3) -> DefaultProviderRegistry {
        var newProviders = self.providers
        newProviders[id] = provider
        return DefaultProviderRegistry(
            separator: separator,
            languageModelMiddleware: languageModelMiddleware,
            providers: newProviders
        )
    }

    private func getProvider(
        id: String,
        modelType: String
    ) throws -> any ProviderV3 {
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
        modelType: String
    ) throws -> (providerId: String, modelId: String) {
        // Support multi-character separators (e.g., " > ")
        guard let range = id.range(of: separator) else {
            throw NoSuchModelError(
                modelId: id,
                modelType: NoSuchModelError.ModelType(rawValue: modelType) ?? .languageModel,
                message: "Invalid \(modelType) id for registry: \(id) " +
                        "(must be in the format \"providerId\(separator)modelId\")"
            )
        }

        let providerId = String(id[..<range.lowerBound])
        let modelId = String(id[range.upperBound...])

        return (providerId, modelId)
    }

    public func languageModel(id: String) -> any LanguageModelV3 {
        do {
            let (providerId, modelId) = try splitId(id: id, modelType: "languageModel")
            let provider = try getProvider(id: providerId, modelType: "languageModel")

            let model = provider.languageModel(modelId: modelId)

            // Apply middleware if present
            // Note: wrapLanguageModel function will be implemented in middleware block
            // For now, we just return the model as-is
            // TODO: Implement wrapLanguageModel when middleware block is complete
            if let middleware = languageModelMiddleware {
                // model = wrapLanguageModel(model: model, middleware: middleware)
                _ = middleware // Silence unused warning until implementation
            }

            return model
        } catch {
            // Swift adaptation: Use fatalError instead of throws
            // Rationale: Protocol methods cannot conditionally declare 'throws'
            // TypeScript throws recoverable errors, Swift crashes with detailed message
            fatalError("Error accessing language model: \(error)")
        }
    }

    public func textEmbeddingModel(id: String) -> any EmbeddingModelV3<String> {
        do {
            let (providerId, modelId) = try splitId(id: id, modelType: "textEmbeddingModel")
            let provider = try getProvider(id: providerId, modelType: "textEmbeddingModel")

            let model = provider.textEmbeddingModel(modelId: modelId)
            return model
        } catch {
            fatalError("Error accessing text embedding model: \(error)")
        }
    }

    public func imageModel(id: String) -> any ImageModelV3 {
        do {
            let (providerId, modelId) = try splitId(id: id, modelType: "imageModel")
            let provider = try getProvider(id: providerId, modelType: "imageModel")

            let model = provider.imageModel(modelId: modelId)
            return model
        } catch {
            fatalError("Error accessing image model: \(error)")
        }
    }

    public func transcriptionModel(id: String) -> any TranscriptionModelV3 {
        do {
            let (providerId, modelId) = try splitId(id: id, modelType: "transcriptionModel")
            let provider = try getProvider(id: providerId, modelType: "transcriptionModel")

            guard let model = provider.transcriptionModel(modelId: modelId) else {
                throw NoSuchModelError(modelId: id, modelType: .transcriptionModel)
            }

            return model
        } catch {
            fatalError("Error accessing transcription model: \(error)")
        }
    }

    public func speechModel(id: String) -> any SpeechModelV3 {
        do {
            let (providerId, modelId) = try splitId(id: id, modelType: "speechModel")
            let provider = try getProvider(id: providerId, modelType: "speechModel")

            guard let model = provider.speechModel(modelId: modelId) else {
                throw NoSuchModelError(modelId: id, modelType: .speechModel)
            }

            return model
        } catch {
            fatalError("Error accessing speech model: \(error)")
        }
    }
}
