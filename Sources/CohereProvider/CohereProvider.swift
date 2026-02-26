import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/cohere/src/cohere-provider.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct CohereProviderSettings: Sendable {
    public var baseURL: String?
    public var apiKey: String?
    public var headers: [String: String]?
    public var fetch: FetchFunction?
    public var generateId: IDGenerator?

    public init(
        baseURL: String? = nil,
        apiKey: String? = nil,
        headers: [String: String]? = nil,
        fetch: FetchFunction? = nil,
        generateId: IDGenerator? = nil
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.headers = headers
        self.fetch = fetch
        self.generateId = generateId
    }
}

public final class CohereProvider: ProviderV3 {
    private let chatFactory: @Sendable (CohereChatModelId) -> CohereChatLanguageModel
    private let embeddingFactory: @Sendable (CohereEmbeddingModelId) -> CohereEmbeddingModel
    private let rerankingFactory: @Sendable (CohereRerankingModelId) -> CohereRerankingModel

    init(
        chatFactory: @escaping @Sendable (CohereChatModelId) -> CohereChatLanguageModel,
        embeddingFactory: @escaping @Sendable (CohereEmbeddingModelId) -> CohereEmbeddingModel,
        rerankingFactory: @escaping @Sendable (CohereRerankingModelId) -> CohereRerankingModel
    ) {
        self.chatFactory = chatFactory
        self.embeddingFactory = embeddingFactory
        self.rerankingFactory = rerankingFactory
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV3 {
        chatFactory(CohereChatModelId(rawValue: modelId))
    }

    public func chatModel(modelId: String) throws -> any LanguageModelV3 {
        try languageModel(modelId: modelId)
    }

    public func chat(modelId: CohereChatModelId) -> CohereChatLanguageModel {
        chatFactory(modelId)
    }

    public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
        embeddingFactory(CohereEmbeddingModelId(rawValue: modelId))
    }

    public func embedding(modelId: CohereEmbeddingModelId) -> CohereEmbeddingModel {
        embeddingFactory(modelId)
    }

    public func rerankingModel(modelId: String) throws -> (any RerankingModelV3)? {
        rerankingFactory(CohereRerankingModelId(rawValue: modelId))
    }

    public func reranking(modelId: CohereRerankingModelId) -> CohereRerankingModel {
        rerankingFactory(modelId)
    }

    public func imageModel(modelId: String) throws -> any ImageModelV3 {
        throw NoSuchModelError(modelId: modelId, modelType: .imageModel)
    }

    public func callAsFunction(_ modelId: String) throws -> any LanguageModelV3 {
        try languageModel(modelId: modelId)
    }
}

private func defaultCohereFetchFunction() -> FetchFunction {
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

private func createCohereAuthFetch(
    apiKey: String?,
    customFetch: FetchFunction?
) -> FetchFunction {
    let baseFetch = customFetch ?? defaultCohereFetchFunction()

    return { request in
        var modified = request
        var headers = modified.allHTTPHeaderFields ?? [:]

        let resolved = try loadAPIKey(
            apiKey: apiKey,
            environmentVariableName: "COHERE_API_KEY",
            description: "Cohere"
        )

        let hasAuthorization = headers.keys.contains { $0.lowercased() == "authorization" }
        if !hasAuthorization {
            headers["Authorization"] = "Bearer \(resolved)"
            modified.allHTTPHeaderFields = headers
        }

        return try await baseFetch(modified)
    }
}

public func createCohereProvider(settings: CohereProviderSettings = .init()) -> CohereProvider {
    let baseURL = withoutTrailingSlash(settings.baseURL) ?? "https://api.cohere.com/v2"

    let headersClosure: @Sendable () -> [String: String?] = {
        var computed: [String: String?] = [:]
        if let headers = settings.headers {
            for (key, value) in headers {
                computed[key] = value
            }
        }

        let withUA = withUserAgentSuffix(computed.compactMapValues { $0 }, "ai-sdk/cohere/\(COHERE_VERSION)")
        return withUA.mapValues { Optional($0) }
    }

    let fetch = createCohereAuthFetch(
        apiKey: settings.apiKey,
        customFetch: settings.fetch
    )

    let chatFactory: @Sendable (CohereChatModelId) -> CohereChatLanguageModel = { modelId in
        CohereChatLanguageModel(
            modelId: modelId,
            config: CohereChatLanguageModel.Config(
                provider: "cohere.chat",
                baseURL: baseURL,
                headers: headersClosure,
                fetch: fetch,
                generateId: settings.generateId ?? generateID
            )
        )
    }

    let embeddingFactory: @Sendable (CohereEmbeddingModelId) -> CohereEmbeddingModel = { modelId in
        CohereEmbeddingModel(
            modelId: modelId,
            config: CohereEmbeddingModel.Config(
                provider: "cohere.textEmbedding",
                baseURL: baseURL,
                headers: headersClosure,
                fetch: fetch
            )
        )
    }

    let rerankingFactory: @Sendable (CohereRerankingModelId) -> CohereRerankingModel = { modelId in
        CohereRerankingModel(
            modelId: modelId,
            config: CohereRerankingModel.Config(
                provider: "cohere.reranking",
                baseURL: baseURL,
                headers: headersClosure,
                fetch: fetch
            )
        )
    }

    return CohereProvider(
        chatFactory: chatFactory,
        embeddingFactory: embeddingFactory,
        rerankingFactory: rerankingFactory
    )
}

/// Alias matching the upstream naming (`createCohere`).
public func createCohere(settings: CohereProviderSettings = .init()) -> CohereProvider {
    createCohereProvider(settings: settings)
}

public let cohere = createCohereProvider()
