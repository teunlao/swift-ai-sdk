import Foundation
import AISDKProvider
import AISDKProviderUtils
import OpenAICompatibleProvider

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/togetherai/src/togetherai-provider.ts
// Upstream commit: f3a72bc2a
//===----------------------------------------------------------------------===//

public struct TogetherAIProviderSettings: Sendable {
    public var apiKey: String?
    public var baseURL: String?
    public var headers: [String: String]?
    public var fetch: FetchFunction?

    public init(
        apiKey: String? = nil,
        baseURL: String? = nil,
        headers: [String: String]? = nil,
        fetch: FetchFunction? = nil
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.headers = headers
        self.fetch = fetch
    }
}

private func defaultTogetherAIFetchFunction() -> FetchFunction {
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

private func createTogetherAIAuthFetch(
    apiKey: String?,
    customFetch: FetchFunction?
) -> FetchFunction {
    let baseFetch = customFetch ?? defaultTogetherAIFetchFunction()

    return { request in
        var modified = request
        var headers = modified.allHTTPHeaderFields ?? [:]

        let resolved = try loadAPIKey(
            apiKey: apiKey,
            environmentVariableName: "TOGETHER_AI_API_KEY",
            description: "TogetherAI"
        )

        let hasAuthorization = headers.keys.contains { $0.lowercased() == "authorization" }
        if !hasAuthorization {
            headers["Authorization"] = "Bearer \(resolved)"
            modified.allHTTPHeaderFields = headers
        }

        return try await baseFetch(modified)
    }
}

public final class TogetherAIProvider: ProviderV3 {
    private let chatFactory: @Sendable (TogetherAIChatModelId) -> OpenAICompatibleChatLanguageModel
    private let completionFactory: @Sendable (TogetherAICompletionModelId) -> OpenAICompatibleCompletionLanguageModel
    private let embeddingFactory: @Sendable (TogetherAIEmbeddingModelId) -> OpenAICompatibleEmbeddingModel
    private let imageFactory: @Sendable (TogetherAIImageModelId) -> TogetherAIImageModel
    private let rerankingFactory: @Sendable (TogetherAIRerankingModelId) -> TogetherAIRerankingModel

    init(
        chatFactory: @escaping @Sendable (TogetherAIChatModelId) -> OpenAICompatibleChatLanguageModel,
        completionFactory: @escaping @Sendable (TogetherAICompletionModelId) -> OpenAICompatibleCompletionLanguageModel,
        embeddingFactory: @escaping @Sendable (TogetherAIEmbeddingModelId) -> OpenAICompatibleEmbeddingModel,
        imageFactory: @escaping @Sendable (TogetherAIImageModelId) -> TogetherAIImageModel,
        rerankingFactory: @escaping @Sendable (TogetherAIRerankingModelId) -> TogetherAIRerankingModel
    ) {
        self.chatFactory = chatFactory
        self.completionFactory = completionFactory
        self.embeddingFactory = embeddingFactory
        self.imageFactory = imageFactory
        self.rerankingFactory = rerankingFactory
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV3 {
        chatFactory(TogetherAIChatModelId(rawValue: modelId))
    }

    public func chatModel(modelId: String) throws -> any LanguageModelV3 {
        try languageModel(modelId: modelId)
    }

    public func completionModel(modelId: String) throws -> any LanguageModelV3 {
        completionFactory(TogetherAICompletionModelId(rawValue: modelId))
    }

    public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
        embeddingFactory(TogetherAIEmbeddingModelId(rawValue: modelId))
    }

    public func imageModel(modelId: String) throws -> any ImageModelV3 {
        imageFactory(TogetherAIImageModelId(rawValue: modelId))
    }

    public func rerankingModel(modelId: String) throws -> (any RerankingModelV3)? {
        rerankingFactory(TogetherAIRerankingModelId(rawValue: modelId))
    }

    public func callAsFunction(_ modelId: String) throws -> any LanguageModelV3 {
        try languageModel(modelId: modelId)
    }

    public func chat(modelId: TogetherAIChatModelId) -> OpenAICompatibleChatLanguageModel {
        chatFactory(modelId)
    }

    public func chat(_ modelId: TogetherAIChatModelId) -> OpenAICompatibleChatLanguageModel {
        chat(modelId: modelId)
    }

    public func completion(modelId: TogetherAICompletionModelId) -> OpenAICompatibleCompletionLanguageModel {
        completionFactory(modelId)
    }

    public func completion(_ modelId: TogetherAICompletionModelId) -> OpenAICompatibleCompletionLanguageModel {
        completion(modelId: modelId)
    }

    public func embedding(modelId: TogetherAIEmbeddingModelId) -> OpenAICompatibleEmbeddingModel {
        embeddingFactory(modelId)
    }

    public func embedding(_ modelId: TogetherAIEmbeddingModelId) -> OpenAICompatibleEmbeddingModel {
        embedding(modelId: modelId)
    }

    public func image(modelId: TogetherAIImageModelId) -> TogetherAIImageModel {
        imageFactory(modelId)
    }

    public func image(_ modelId: TogetherAIImageModelId) -> TogetherAIImageModel {
        image(modelId: modelId)
    }

    public func reranking(modelId: TogetherAIRerankingModelId) -> TogetherAIRerankingModel {
        rerankingFactory(modelId)
    }

    public func reranking(_ modelId: TogetherAIRerankingModelId) -> TogetherAIRerankingModel {
        reranking(modelId: modelId)
    }
}

public func createTogetherAIProvider(settings: TogetherAIProviderSettings = .init()) -> TogetherAIProvider {
    let baseURL = withoutTrailingSlash(settings.baseURL) ?? "https://api.together.xyz/v1"

    let headersClosure: @Sendable () -> [String: String] = {
        var computed: [String: String?] = [:]

        if let customHeaders = settings.headers {
            for (key, value) in customHeaders {
                computed[key] = value
            }
        }

        return withUserAgentSuffix(
            computed.compactMapValues { $0 },
            "ai-sdk/togetherai/\(TOGETHERAI_VERSION)"
        )
    }

    let optionalHeadersClosure: @Sendable () -> [String: String?] = {
        headersClosure().mapValues { Optional($0) }
    }

    let fetch = createTogetherAIAuthFetch(
        apiKey: settings.apiKey,
        customFetch: settings.fetch
    )

    let urlBuilder: @Sendable (OpenAICompatibleURLOptions) -> String = { options in
        "\(baseURL)\(options.path)"
    }

    let chatFactory: @Sendable (TogetherAIChatModelId) -> OpenAICompatibleChatLanguageModel = { modelId in
        let config = OpenAICompatibleChatConfig(
            provider: "togetherai.chat",
            headers: headersClosure,
            url: urlBuilder,
            fetch: fetch
        )
        return OpenAICompatibleChatLanguageModel(
            modelId: OpenAICompatibleChatModelId(rawValue: modelId.rawValue),
            config: config
        )
    }

    let completionFactory: @Sendable (TogetherAICompletionModelId) -> OpenAICompatibleCompletionLanguageModel = { modelId in
        let config = OpenAICompatibleCompletionConfig(
            provider: "togetherai.completion",
            headers: headersClosure,
            url: urlBuilder,
            fetch: fetch
        )
        return OpenAICompatibleCompletionLanguageModel(
            modelId: OpenAICompatibleCompletionModelId(rawValue: modelId.rawValue),
            config: config
        )
    }

    let embeddingFactory: @Sendable (TogetherAIEmbeddingModelId) -> OpenAICompatibleEmbeddingModel = { modelId in
        let config = OpenAICompatibleEmbeddingConfig(
            provider: "togetherai.embedding",
            url: urlBuilder,
            headers: headersClosure,
            fetch: fetch
        )
        return OpenAICompatibleEmbeddingModel(
            modelId: OpenAICompatibleEmbeddingModelId(rawValue: modelId.rawValue),
            config: config
        )
    }

    let imageFactory: @Sendable (TogetherAIImageModelId) -> TogetherAIImageModel = { modelId in
        TogetherAIImageModel(
            modelId: modelId,
            config: TogetherAIImageModelConfig(
                provider: "togetherai.image",
                baseURL: baseURL,
                headers: optionalHeadersClosure,
                fetch: fetch
            )
        )
    }

    let rerankingFactory: @Sendable (TogetherAIRerankingModelId) -> TogetherAIRerankingModel = { modelId in
        TogetherAIRerankingModel(
            modelId: modelId,
            config: TogetherAIRerankingModel.Config(
                provider: "togetherai.reranking",
                baseURL: baseURL,
                headers: optionalHeadersClosure,
                fetch: fetch
            )
        )
    }

    return TogetherAIProvider(
        chatFactory: chatFactory,
        completionFactory: completionFactory,
        embeddingFactory: embeddingFactory,
        imageFactory: imageFactory,
        rerankingFactory: rerankingFactory
    )
}

/// Alias matching upstream naming (`createTogetherAI`).
public func createTogetherAI(settings: TogetherAIProviderSettings = .init()) -> TogetherAIProvider {
    createTogetherAIProvider(settings: settings)
}

public let togetherai = createTogetherAIProvider()
