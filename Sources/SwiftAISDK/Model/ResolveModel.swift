import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Model resolution logic for language and embedding models.

 Port of `@ai-sdk/ai/src/model/resolve-model.ts`.

 Provides functions to resolve model references (string IDs or direct model instances)
 into standardized V3 model interfaces. Handles V2-to-V3 model adaptation transparently.
 */

// MARK: - V2 to V3 Adapters

/**
 Adapter that wraps a `LanguageModelV2` to conform to `LanguageModelV3`.

 Swift adaptation: Uses delegation pattern instead of JavaScript Proxy.
 All properties and methods are forwarded to the underlying V2 model,
 except `specificationVersion` which returns "v3".
 */
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private final class LanguageModelV2ToV3Adapter: LanguageModelV3, @unchecked Sendable {
    /// Always returns "v3" to indicate V3 specification
    public let specificationVersion = "v3"

    private let wrappedModel: any LanguageModelV2

    /// Provider identifier (forwarded from V2 model)
    public var provider: String {
        wrappedModel.provider
    }

    /// Model identifier (forwarded from V2 model)
    public var modelId: String {
        wrappedModel.modelId
    }

    /// Supported URL patterns (forwarded from V2 model)
    public var supportedUrls: [String: [NSRegularExpression]] {
        get async throws {
            try await wrappedModel.supportedUrls
        }
    }

    init(wrapping model: any LanguageModelV2) {
        self.wrappedModel = model
    }

    public func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult {
        // Swift adaptation: V2 and V3 CallOptions have identical structure but different types.
        // In TypeScript, structural typing allows direct usage. In Swift, we must explicitly
        // cast the options. This is safe because both V2 and V3 have the same memory layout.
        // The wrapped model is a V2 model that will return V2 results, which are also
        // structurally identical to V3 results, so we unsafely cast them.
        let v2Result = try await wrappedModel.doGenerate(options: unsafeBitCast(options, to: LanguageModelV2CallOptions.self))
        return unsafeBitCast(v2Result, to: LanguageModelV3GenerateResult.self)
    }

    public func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult {
        // Swift adaptation: Same as doGenerate - use unsafeBitCast for type conversion.
        // V2 and V3 types are structurally identical (verified by upstream parity).
        let v2Result = try await wrappedModel.doStream(options: unsafeBitCast(options, to: LanguageModelV2CallOptions.self))
        return unsafeBitCast(v2Result, to: LanguageModelV3StreamResult.self)
    }
}

/**
 Adapter that wraps an `EmbeddingModelV2` to conform to `EmbeddingModelV3`.

 Swift adaptation: Uses delegation pattern instead of JavaScript Proxy.
 All properties and methods are forwarded to the underlying V2 model,
 except `specificationVersion` which returns "v3".
 */
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private final class EmbeddingModelV2ToV3Adapter<VALUE: Sendable>: EmbeddingModelV3, @unchecked Sendable {
    /// Always returns "v3" to indicate V3 specification
    public let specificationVersion = "v3"

    private let wrappedModel: any EmbeddingModelV2<VALUE>

    /// Provider identifier (forwarded from V2 model)
    public var provider: String {
        wrappedModel.provider
    }

    /// Model identifier (forwarded from V2 model)
    public var modelId: String {
        wrappedModel.modelId
    }

    /// Maximum embeddings per call (forwarded from V2 model)
    public var maxEmbeddingsPerCall: Int? {
        get async throws {
            try await wrappedModel.maxEmbeddingsPerCall
        }
    }

    /// Whether parallel calls are supported (forwarded from V2 model)
    public var supportsParallelCalls: Bool {
        get async throws {
            try await wrappedModel.supportsParallelCalls
        }
    }

    init(wrapping model: any EmbeddingModelV2<VALUE>) {
        self.wrappedModel = model
    }

    public func doEmbed(options: EmbeddingModelV3DoEmbedOptions<VALUE>) async throws -> EmbeddingModelV3DoEmbedResult {
        // Swift adaptation: V2 and V3 options have identical structure but different types.
        // Use unsafeBitCast to convert between structurally identical types.
        let v2Result = try await wrappedModel.doEmbed(options: unsafeBitCast(options, to: EmbeddingModelV2DoEmbedOptions<VALUE>.self))
        return unsafeBitCast(v2Result, to: EmbeddingModelV3DoEmbedResult.self)
    }
}

// MARK: - Global Provider

/**
 Global default provider for model resolution.

 When a model is specified as a string ID, this provider is used to resolve
 the ID to an actual model instance.

 Swift adaptation: Uses a nonisolated(unsafe) static property instead of JavaScript's `globalThis`.
 In TypeScript, this is `globalThis.AI_SDK_DEFAULT_PROVIDER`.

 If no custom provider is set, a default gateway provider should be used
 (gateway functionality is not included in this port, so it must be set explicitly).

 Thread safety: This is marked `nonisolated(unsafe)` to match the JavaScript behavior
 where globalThis can be mutated from any context. Users should ensure proper synchronization
 if accessing from multiple threads.
 */
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
nonisolated(unsafe) public var globalDefaultProvider: (any ProviderV3)? = nil

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

// MARK: - Resolution Functions

/**
 Resolves a language model reference into a `LanguageModelV3` instance.

 Port of `resolveLanguageModel` from `@ai-sdk/ai/src/model/resolve-model.ts`.

 **Behavior**:
 - If the input is already a V3 model, returns it as-is
 - If the input is a V2 model, wraps it in an adapter that presents a V3 interface
 - If the input is a string ID, resolves it using the global default provider
 - If the input is an unsupported model version, throws `UnsupportedModelVersionError`

 - Parameter model: The language model to resolve (string ID, V2, or V3 model)
 - Returns: A `LanguageModelV3` instance ready for use
 - Throws: `UnsupportedModelVersionError` if the model version is not v2 or v3,
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
        return provider.languageModel(modelId: id)

    case .v3(let model):
        // Already V3, return as-is
        return model

    case .v2(let model):
        // Adapt V2 to V3 interface
        return LanguageModelV2ToV3Adapter(wrapping: model)
    }
}

/**
 Resolves an embedding model reference into an `EmbeddingModelV3` instance.

 Port of `resolveEmbeddingModel` from `@ai-sdk/ai/src/model/resolve-model.ts`.

 **Behavior**:
 - If the input is already a V3 model, returns it as-is
 - If the input is a V2 model, wraps it in an adapter that presents a V3 interface
 - If the input is a string ID, resolves it using the global default provider
 - If the input is an unsupported model version, throws `UnsupportedModelVersionError`

 - Parameter model: The embedding model to resolve (string ID, V2, or V3 model)
 - Returns: An `EmbeddingModelV3` instance ready for use
 - Throws: `UnsupportedModelVersionError` if the model version is not v2 or v3,
           or `NoSuchProviderError` if no global provider is set for string resolution
 */
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func resolveEmbeddingModel<VALUE: Sendable>(_ model: EmbeddingModel<VALUE>) throws -> any EmbeddingModelV3<VALUE> {
    switch model {
    case .string(let id):
        // Resolve string ID using task-local override or global provider
        let disabled = disableGlobalProviderForStringResolution || _ResolveModelContext.disableGlobalProvider
        let provider = _ResolveModelContext.overrideProvider ?? (disabled ? nil : globalDefaultProvider)
        guard let provider else {
            // TypeScript uses gateway as fallback, but we require explicit provider setup
            throw NoSuchProviderError(
                modelId: id,
                modelType: .textEmbeddingModel,
                providerId: "default",
                availableProviders: [],
                message: "No global default provider set. Set `globalDefaultProvider` before resolving string model IDs."
            )
        }
        // TODO AI SDK 6: figure out how to cleanly support different generic types
        // For now, we trust that the provider returns the correct VALUE type.
        // Swift adaptation: Provider returns EmbeddingModelV3<String>, but we need EmbeddingModelV3<VALUE>.
        // We use force cast (as!) which will fail at runtime if types don't match.
        // This matches the TypeScript behavior where type mismatches are caught at runtime.
        return provider.textEmbeddingModel(modelId: id) as! any EmbeddingModelV3<VALUE>

    case .v3(let model):
        // Already V3, return as-is
        return model

    case .v2(let model):
        // Adapt V2 to V3 interface
        return EmbeddingModelV2ToV3Adapter(wrapping: model)
    }
}
