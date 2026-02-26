import Foundation
import AISDKProvider
import AISDKProviderUtils
import OpenAICompatibleProvider

/// Settings for configuring the Baseten provider.
/// Mirrors `packages/baseten/src/baseten-provider.ts`.
public struct BasetenProviderSettings: Sendable {
    public var apiKey: String?
    public var baseURL: String?
    public var modelURL: String?
    public var headers: [String: String]?
    public var fetch: FetchFunction?

    public init(
        apiKey: String? = nil,
        baseURL: String? = nil,
        modelURL: String? = nil,
        headers: [String: String]? = nil,
        fetch: FetchFunction? = nil
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.modelURL = modelURL
        self.headers = headers
        self.fetch = fetch
    }
}

/// Baseten provider implementation with chat and embedding support.
/// Mirrors `packages/baseten/src/baseten-provider.ts`.
struct BasetenProviderError: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}

public final class BasetenProvider: ProviderV3 {
    private let chatFactory: @Sendable (BasetenChatModelId?) throws -> OpenAICompatibleChatLanguageModel
    private let embeddingFactory: @Sendable (BasetenEmbeddingModelId?) throws -> any EmbeddingModelV3<String>

    init(
        chatFactory: @escaping @Sendable (BasetenChatModelId?) throws -> OpenAICompatibleChatLanguageModel,
        embeddingFactory: @escaping @Sendable (BasetenEmbeddingModelId?) throws -> any EmbeddingModelV3<String>
    ) {
        self.chatFactory = chatFactory
        self.embeddingFactory = embeddingFactory
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV3 {
        try chatFactory(BasetenChatModelId(rawValue: modelId))
    }

    public func chatModel(modelId: String) throws -> any LanguageModelV3 {
        try chatFactory(BasetenChatModelId(rawValue: modelId))
    }

    public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
        return try embeddingFactory(BasetenEmbeddingModelId(rawValue: modelId))
    }

    public func imageModel(modelId: String) throws -> any ImageModelV3 {
        throw NoSuchModelError(modelId: modelId, modelType: .imageModel)
    }

    public func callAsFunction(_ modelId: String) throws -> any LanguageModelV3 {
        try languageModel(modelId: modelId)
    }

    public func chat(modelId: BasetenChatModelId? = nil) throws -> OpenAICompatibleChatLanguageModel {
        try chatFactory(modelId)
    }

    public func languageModel(_ modelId: BasetenChatModelId? = nil) throws -> OpenAICompatibleChatLanguageModel {
        try chatFactory(modelId)
    }

    public func textEmbeddingModel(_ modelId: BasetenEmbeddingModelId? = nil) throws -> any EmbeddingModelV3<String> {
        try embeddingFactory(modelId)
    }
}

private let defaultBasetenBaseURL = "https://inference.baseten.co/v1"

private func defaultBasetenFetchFunction() -> FetchFunction {
    { request in
        let session = URLSession.shared

        if #available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *) {
            let (bytes, response) = try await session.bytes(for: request)
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                Task {
                    var buffer = Data()
                    buffer.reserveCapacity(16_384)

                    do {
                        for try await byte in bytes {
                            buffer.append(byte)

                            if buffer.count >= 16_384 {
                                continuation.yield(buffer)
                                buffer.removeAll(keepingCapacity: true)
                            }
                        }

                        if !buffer.isEmpty {
                            continuation.yield(buffer)
                        }

                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }

            return FetchResponse(body: .stream(stream), urlResponse: response)
        } else {
            let (data, response) = try await session.data(for: request)
            return FetchResponse(body: .data(data), urlResponse: response)
        }
    }
}

private func createBasetenAuthFetch(
    apiKey: String?,
    customFetch: FetchFunction?
) -> FetchFunction {
    let baseFetch = customFetch ?? defaultBasetenFetchFunction()

    return { request in
        var modified = request
        var headers = modified.allHTTPHeaderFields ?? [:]

        let hasAuthorization = headers.keys.contains { $0.lowercased() == "authorization" }
        if !hasAuthorization {
            let resolved = try loadAPIKey(
                apiKey: apiKey,
                environmentVariableName: "BASETEN_API_KEY",
                description: "Baseten API key"
            )
            headers["Authorization"] = "Bearer \(resolved)"
            modified.allHTTPHeaderFields = headers
        }

        return try await baseFetch(modified)
    }
}

public func createBasetenProvider(settings: BasetenProviderSettings = .init()) -> BasetenProvider {
    let baseURL = withoutTrailingSlash(settings.baseURL) ?? defaultBasetenBaseURL

    let headersClosure: @Sendable () -> [String: String] = {
        var baseHeaders: [String: String?] = [:]

        if let customHeaders = settings.headers {
            for (key, value) in customHeaders {
                baseHeaders[key] = value
            }
        }

        return withUserAgentSuffix(baseHeaders, "ai-sdk/baseten/\(BASETEN_PROVIDER_VERSION)")
    }

    @Sendable func makeURLBuilder(modelType: String, customURL: String?) -> @Sendable (OpenAICompatibleURLOptions) -> String {
        { options in
            if let customURL {
                if modelType == "embedding", customURL.contains("/sync"), !customURL.contains("/sync/v1") {
                    return "\(customURL)/v1\(options.path)"
                }
                return "\(customURL)\(options.path)"
            }

            return "\(baseURL)\(options.path)"
        }
    }

    let fetch = createBasetenAuthFetch(
        apiKey: settings.apiKey,
        customFetch: settings.fetch
    )

    let chatFactory: @Sendable (BasetenChatModelId?) throws -> OpenAICompatibleChatLanguageModel = { modelId in
        let customURL = settings.modelURL
        if let customURL, customURL.contains("/predict") {
            throw BasetenProviderError(message: "Not supported. You must use a /sync/v1 endpoint for chat models.")
        }

        let isOpenAICompatible = customURL?.contains("/sync/v1") == true
        let effectiveURL = isOpenAICompatible ? customURL : nil
        let defaultModelId = isOpenAICompatible ? "placeholder" : "chat"
        let resolvedModelId = OpenAICompatibleChatModelId(rawValue: modelId?.rawValue ?? defaultModelId)
        let urlBuilder = makeURLBuilder(modelType: "chat", customURL: effectiveURL)

        let config = OpenAICompatibleChatConfig(
            provider: "baseten.chat",
            headers: headersClosure,
            url: urlBuilder,
            fetch: fetch,
            errorConfiguration: basetenErrorConfiguration
        )

        return OpenAICompatibleChatLanguageModel(modelId: resolvedModelId, config: config)
    }

    let embeddingFactory: @Sendable (BasetenEmbeddingModelId?) throws -> any EmbeddingModelV3<String> = { modelId in
        guard let modelURL = settings.modelURL else {
            throw BasetenProviderError(message: "No model URL provided for embeddings. Please set modelURL option for embeddings.")
        }

        if modelURL.contains("/predict") {
            throw BasetenProviderError(message: "Not supported. You must use a /sync or /sync/v1 endpoint for embeddings.")
        }

        let urlBuilder = makeURLBuilder(modelType: "embedding", customURL: modelURL)
        let resolvedModelId = OpenAICompatibleEmbeddingModelId(rawValue: modelId?.rawValue ?? "embeddings")

        let embeddingConfig = OpenAICompatibleEmbeddingConfig(
            provider: "baseten.embedding",
            url: urlBuilder,
            headers: headersClosure,
            fetch: fetch,
            errorConfiguration: basetenErrorConfiguration,
            maxEmbeddingsPerCall: nil,
            supportsParallelCalls: nil
        )

        let baseEmbeddingModel = OpenAICompatibleEmbeddingModel(
            modelId: resolvedModelId,
            config: embeddingConfig
        )

        let performanceClient: BasetenPerformanceClient?
        if modelURL.contains("/sync") {
            performanceClient = BasetenPerformanceClient(
                urlBuilder: urlBuilder,
                errorConfiguration: basetenErrorConfiguration,
                fetch: fetch
            )
        } else {
            performanceClient = nil
        }

        return BasetenEmbeddingModel(
            delegate: baseEmbeddingModel,
            headers: headersClosure,
            urlBuilder: urlBuilder,
            fetch: fetch,
            errorConfiguration: basetenErrorConfiguration,
            performanceClient: performanceClient
        )
    }

    return BasetenProvider(
        chatFactory: chatFactory,
        embeddingFactory: embeddingFactory
    )
}

/// Alias matching the upstream naming (`createBaseten`).
public func createBaseten(settings: BasetenProviderSettings = .init()) -> BasetenProvider {
    createBasetenProvider(settings: settings)
}

/// Default Baseten provider instance (`export const baseten = createBaseten()`).
public let baseten: BasetenProvider = createBasetenProvider()
