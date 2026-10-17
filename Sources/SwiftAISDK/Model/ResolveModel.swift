import Foundation
import AISDKProvider
import AISDKProviderUtils
import GatewayProvider

/**
 Model resolution logic for language and embedding models.

 Port of `@ai-sdk/ai/src/model/resolve-model.ts`.

 Provides functions to resolve model references (string IDs or direct model instances)
 into standardized V3 model interfaces.
 */

// MARK: - Global Provider

/**
 Global default provider for model resolution.

 When a model is specified as a string ID, this provider is used to resolve
 the ID to an actual model instance.

 Swift adaptation: Uses a nonisolated(unsafe) static property instead of JavaScript's `globalThis`.
 In TypeScript, this is `globalThis.AI_SDK_DEFAULT_PROVIDER`.

 V4 string model references use the native Gateway provider when no custom provider is set.

 Thread safety: This is marked `nonisolated(unsafe)` to match the JavaScript behavior
 where globalThis can be mutated from any context. Users should ensure proper synchronization
 if accessing from multiple threads.
 */
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
nonisolated(unsafe) public var globalDefaultProvider: (any ProviderV3)? = nil

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
nonisolated(unsafe) public var globalDefaultProviderV4: (any ProviderV4)? = nil

/**
 Test-only switch to disable usage of `globalDefaultProvider` for string model resolution.

 When `true`, `resolveLanguageModel(.string(_))` and `resolveEmbeddingModel(.string(_))`
 behave as if no global provider is set, regardless of the actual global state.
 This helps eliminate flaky cross-suite interference when tests run in parallel.

 Default: `false`. Do not enable in production code.
 */
// Task-local switch to disable usage of `globalDefaultProvider` for string model resolution.
// Default is `false`. Used by tests to avoid cross-suite interference under parallel execution.
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
enum _ResolveModelContext {
    @TaskLocal static var disableGlobalProvider: Bool = false
    @TaskLocal static var overrideProvider: (any ProviderV3)? = nil
    @TaskLocal static var overrideProviderV4: (any ProviderV4)? = nil
}

// Kept for backward-compat toggling in rare cases; prefer task-local helpers below.
nonisolated(unsafe) public var disableGlobalProviderForStringResolution: Bool = false

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
@discardableResult
public func withGlobalProviderDisabled<T>(_ operation: () throws -> T) rethrows -> T {
    try _ResolveModelContext.$disableGlobalProvider.withValue(true) { try operation() }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
@discardableResult
public func withGlobalProviderDisabled<T>(operation: () async throws -> T) async rethrows -> T {
    try await _ResolveModelContext.$disableGlobalProvider.withValue(true) { try await operation() }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
@discardableResult
public func withGlobalProvider<T>(_ provider: any ProviderV3, _ operation: () throws -> T) rethrows -> T {
    try _ResolveModelContext.$overrideProvider.withValue(provider) { try operation() }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
@discardableResult
public func withGlobalProvider<T>(_ provider: any ProviderV3, operation: () async throws -> T) async rethrows -> T {
    try await _ResolveModelContext.$overrideProvider.withValue(provider) { try await operation() }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
@discardableResult
public func withGlobalProviderV4<T>(_ provider: any ProviderV4, _ operation: () throws -> T) rethrows -> T {
    try _ResolveModelContext.$overrideProviderV4.withValue(provider) { try operation() }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
@discardableResult
public func withGlobalProviderV4<T>(_ provider: any ProviderV4, operation: () async throws -> T) async rethrows -> T {
    try await _ResolveModelContext.$overrideProviderV4.withValue(provider) { try await operation() }
}

// MARK: - Resolution Functions

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
func _resolveGlobalProviderV4(modelId: String, modelType: NoSuchModelError.ModelType) throws -> any ProviderV4 {
    let disabled = disableGlobalProviderForStringResolution || _ResolveModelContext.disableGlobalProvider

    if let provider = _ResolveModelContext.overrideProviderV4 {
        return provider
    }

    if let provider = _ResolveModelContext.overrideProvider {
        return asProviderV4(provider)
    }

    if !disabled {
        if let provider = globalDefaultProviderV4 {
            return provider
        }

        if let provider = globalDefaultProvider {
            return asProviderV4(provider)
        }
        return gateway
    }

    throw NoSuchProviderError(
        modelId: modelId,
        modelType: modelType,
        providerId: "default",
        availableProviders: [],
        message: "No global default provider set. Set `globalDefaultProviderV4` before resolving string model IDs."
    )
}

/**
 Resolves a language model reference into a `LanguageModelV3` instance.

 Port of `resolveLanguageModel` from `@ai-sdk/ai/src/model/resolve-model.ts`.

 **Behavior**:
 - If the input is a V4 model, throws because this is the legacy V3 resolver
 - If the input is already a V3 model, returns it as-is
 - If the input is a string ID, resolves it using the global default provider
 - If the input is an unsupported model version, throws `UnsupportedModelVersionError`

 - Parameter model: The language model to resolve (string ID, V3, or V4 model)
 - Returns: A `LanguageModelV3` instance ready for use
 - Throws: `UnsupportedModelVersionError` if a V4 model is passed to this legacy V3 resolver,
           or `NoSuchProviderError` if no global provider is set for string resolution
 */
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func resolveLanguageModel(_ model: LanguageModel) throws -> any LanguageModelV3 {
    switch model {
    case .string(let id):
        // Resolve string ID using task-local override or global provider
        let disabled = disableGlobalProviderForStringResolution || _ResolveModelContext.disableGlobalProvider
        let provider = _ResolveModelContext.overrideProvider ?? (disabled ? nil : globalDefaultProvider)
        guard let provider else {
            // TypeScript uses gateway as fallback, but we require explicit provider setup
            throw NoSuchProviderError(
                modelId: id,
                modelType: .languageModel,
                providerId: "default",
                availableProviders: [],
                message: "No global default provider set. Set `globalDefaultProvider` before resolving string model IDs."
            )
        }
        return try provider.languageModel(modelId: id)

    case .v4(let model):
        throw UnsupportedModelVersionError(
            version: model.specificationVersion,
            provider: model.provider,
            modelId: model.modelId
        )

    case .v3(let model):
        // Already V3, return as-is
        return model
    }
}

/**
 Resolves an embedding model reference into an `EmbeddingModelV3` instance.

 Port of `resolveEmbeddingModel` from `@ai-sdk/ai/src/model/resolve-model.ts`.

 **Behavior**:
 - If the input is already a V3 model, returns it as-is
 - If the input is a string ID, resolves it using the global default provider
 - If the input is an unsupported model version, throws `UnsupportedModelVersionError`

 - Parameter model: The embedding model to resolve (string ID, V3, or V4 model)
 - Returns: An `EmbeddingModelV3` instance ready for use
 - Throws: `UnsupportedModelVersionError` if a V4 model is passed to this legacy V3 resolver,
           or `NoSuchProviderError` if no global provider is set for string resolution
 */
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func resolveEmbeddingModel(_ model: EmbeddingModel) throws -> any EmbeddingModelV3<String> {
    switch model {
    case .string(let id):
        // Resolve string ID using task-local override or global provider
        let disabled = disableGlobalProviderForStringResolution || _ResolveModelContext.disableGlobalProvider
        let provider = _ResolveModelContext.overrideProvider ?? (disabled ? nil : globalDefaultProvider)
        guard let provider else {
            // TypeScript uses gateway as fallback, but we require explicit provider setup
            throw NoSuchProviderError(
                modelId: id,
                modelType: .embeddingModel,
                providerId: "default",
                availableProviders: [],
                message: "No global default provider set. Set `globalDefaultProvider` before resolving string model IDs."
            )
        }
        return try provider.textEmbeddingModel(modelId: id)

    case .v4(let model):
        throw UnsupportedModelVersionError(
            version: model.specificationVersion,
            provider: model.provider,
            modelId: model.modelId
        )

    case .v3(let model):
        // Already V3, return as-is
        return model
    }
}
