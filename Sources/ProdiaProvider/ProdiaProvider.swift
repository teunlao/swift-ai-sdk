import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/prodia/src/prodia-provider.ts
// Upstream commit: f3a72bc2a
//===----------------------------------------------------------------------===//

public struct ProdiaProviderSettings: Sendable {
    /// Prodia API key. Default value is taken from the `PRODIA_TOKEN` environment variable.
    public var apiKey: String?

    /// Base URL for the API calls. Defaults to `https://inference.prodia.com/v2`.
    public var baseURL: String?

    /// Custom headers to include in the requests.
    public var headers: [String: String]?

    /// Custom fetch implementation (useful for tests / middleware).
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

public final class ProdiaProvider: ProviderV3 {
    private let imageFactory: @Sendable (ProdiaImageModelId) -> ProdiaImageModel

    init(imageFactory: @escaping @Sendable (ProdiaImageModelId) -> ProdiaImageModel) {
        self.imageFactory = imageFactory
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV3 {
        throw NoSuchModelError(modelId: modelId, modelType: .languageModel)
    }

    public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
        throw NoSuchModelError(modelId: modelId, modelType: .textEmbeddingModel)
    }

    public func imageModel(modelId: String) throws -> any ImageModelV3 {
        imageFactory(ProdiaImageModelId(rawValue: modelId))
    }

    public func image(modelId: ProdiaImageModelId) -> ProdiaImageModel {
        imageFactory(modelId)
    }

    public func image(_ modelId: ProdiaImageModelId) -> ProdiaImageModel {
        imageFactory(modelId)
    }

    public func imageModel(_ modelId: ProdiaImageModelId) -> ProdiaImageModel {
        imageFactory(modelId)
    }
}

private let defaultBaseURL = "https://inference.prodia.com/v2"

private func defaultProdiaFetchFunction() -> FetchFunction {
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

private func createProdiaAuthFetch(
    apiKey: String?,
    customFetch: FetchFunction?
) -> FetchFunction {
    let baseFetch = customFetch ?? defaultProdiaFetchFunction()

    return { request in
        var modified = request
        var headers = modified.allHTTPHeaderFields ?? [:]

        let hasAuthorization = headers.keys.contains { $0.lowercased() == "authorization" }
        if !hasAuthorization {
            let resolved = try loadAPIKey(
                apiKey: apiKey,
                environmentVariableName: "PRODIA_TOKEN",
                description: "Prodia"
            )
            headers["Authorization"] = "Bearer \(resolved)"
            modified.allHTTPHeaderFields = headers
        }

        return try await baseFetch(modified)
    }
}

public func createProdiaProvider(settings: ProdiaProviderSettings = .init()) -> ProdiaProvider {
    let baseURL = withoutTrailingSlash(settings.baseURL) ?? defaultBaseURL

    let headersClosure: @Sendable () -> [String: String?] = {
        var computed: [String: String?] = [:]

        if let customHeaders = settings.headers {
            for (key, value) in customHeaders {
                computed[key] = value
            }
        }

        let withUA = withUserAgentSuffix(
            computed.compactMapValues { $0 },
            "ai-sdk/prodia/\(PRODIA_VERSION)"
        )
        return withUA.mapValues { Optional($0) }
    }

    let fetch = createProdiaAuthFetch(
        apiKey: settings.apiKey,
        customFetch: settings.fetch
    )

    let imageFactory: @Sendable (ProdiaImageModelId) -> ProdiaImageModel = { modelId in
        ProdiaImageModel(
            modelId: modelId,
            config: ProdiaImageModelConfig(
                provider: "prodia.image",
                baseURL: baseURL,
                headers: headersClosure,
                fetch: fetch
            )
        )
    }

    return ProdiaProvider(imageFactory: imageFactory)
}

/// Alias matching upstream naming (`createProdia`).
public func createProdia(settings: ProdiaProviderSettings = .init()) -> ProdiaProvider {
    createProdiaProvider(settings: settings)
}

public let prodia = createProdiaProvider()
