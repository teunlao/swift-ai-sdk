import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/perplexity/src/perplexity-provider.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct PerplexityProviderSettings: Sendable {
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

public final class PerplexityProvider: ProviderV3 {
    private let languageModelFactory: @Sendable (PerplexityLanguageModelId) -> PerplexityLanguageModel

    init(languageModelFactory: @escaping @Sendable (PerplexityLanguageModelId) -> PerplexityLanguageModel) {
        self.languageModelFactory = languageModelFactory
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV3 {
        languageModelFactory(PerplexityLanguageModelId(rawValue: modelId))
    }

    public func chatModel(modelId: String) throws -> any LanguageModelV3 {
        try languageModel(modelId: modelId)
    }

    public func chat(modelId: PerplexityLanguageModelId) -> PerplexityLanguageModel {
        languageModelFactory(modelId)
    }

    public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
        throw NoSuchModelError(modelId: modelId, modelType: .textEmbeddingModel)
    }

    public func imageModel(modelId: String) throws -> any ImageModelV3 {
        throw NoSuchModelError(modelId: modelId, modelType: .imageModel)
    }

    public func callAsFunction(_ modelId: String) throws -> any LanguageModelV3 {
        try languageModel(modelId: modelId)
    }
}

private func defaultPerplexityFetchFunction() -> FetchFunction {
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

private func createPerplexityAuthFetch(
    apiKey: String?,
    customFetch: FetchFunction?
) -> FetchFunction {
    let baseFetch = customFetch ?? defaultPerplexityFetchFunction()

    return { request in
        var modified = request
        var headers = modified.allHTTPHeaderFields ?? [:]

        let resolved = try loadAPIKey(
            apiKey: apiKey,
            environmentVariableName: "PERPLEXITY_API_KEY",
            description: "Perplexity"
        )

        let hasAuthorization = headers.keys.contains { $0.lowercased() == "authorization" }
        if !hasAuthorization {
            headers["Authorization"] = "Bearer \(resolved)"
            modified.allHTTPHeaderFields = headers
        }

        return try await baseFetch(modified)
    }
}

public func createPerplexityProvider(settings: PerplexityProviderSettings = .init()) -> PerplexityProvider {
    let baseURL = withoutTrailingSlash(settings.baseURL) ?? "https://api.perplexity.ai"

    let headersClosure: @Sendable () -> [String: String?] = {
        var computed: [String: String?] = [:]
        if let headers = settings.headers {
            for (key, value) in headers {
                computed[key] = value
            }
        }

        let withUA = withUserAgentSuffix(computed.compactMapValues { $0 }, "ai-sdk/perplexity/\(PERPLEXITY_VERSION)")
        return withUA.mapValues { Optional($0) }
    }

    let fetch = createPerplexityAuthFetch(
        apiKey: settings.apiKey,
        customFetch: settings.fetch
    )

    let languageFactory: @Sendable (PerplexityLanguageModelId) -> PerplexityLanguageModel = { modelId in
        PerplexityLanguageModel(
            modelId: modelId,
            config: PerplexityLanguageModel.Config(
                baseURL: baseURL,
                headers: headersClosure,
                fetch: fetch,
                generateId: settings.generateId ?? generateID
            )
        )
    }

    return PerplexityProvider(languageModelFactory: languageFactory)
}

/// Alias matching the upstream naming (`createPerplexity`).
public func createPerplexity(settings: PerplexityProviderSettings = .init()) -> PerplexityProvider {
    createPerplexityProvider(settings: settings)
}

public let perplexity = createPerplexityProvider()
