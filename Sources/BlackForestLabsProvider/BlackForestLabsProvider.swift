import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/black-forest-labs/src/black-forest-labs-provider.ts
// Upstream commit: f3a72bc2a
//===----------------------------------------------------------------------===//

public struct BlackForestLabsProviderSettings: Sendable {
    /// Black Forest Labs API key. Default value is taken from the `BFL_API_KEY` environment variable.
    public var apiKey: String?

    /// Base URL for the API calls. Defaults to `https://api.bfl.ai/v1`.
    public var baseURL: String?

    /// Custom headers to include in the requests.
    public var headers: [String: String]?

    /// Custom fetch implementation.
    public var fetch: FetchFunction?

    /// Poll interval in milliseconds between status checks. Defaults to 500ms.
    public var pollIntervalMillis: Int?

    /// Overall timeout in milliseconds for polling before giving up. Defaults to 60s.
    public var pollTimeoutMillis: Int?

    public init(
        apiKey: String? = nil,
        baseURL: String? = nil,
        headers: [String: String]? = nil,
        fetch: FetchFunction? = nil,
        pollIntervalMillis: Int? = nil,
        pollTimeoutMillis: Int? = nil
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.headers = headers
        self.fetch = fetch
        self.pollIntervalMillis = pollIntervalMillis
        self.pollTimeoutMillis = pollTimeoutMillis
    }
}

private let defaultBaseURL = "https://api.bfl.ai/v1"

private func defaultBlackForestLabsFetchFunction() -> FetchFunction {
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

private func createBlackForestLabsAuthFetch(
    apiKey: String?,
    customFetch: FetchFunction?
) -> FetchFunction {
    let baseFetch = customFetch ?? defaultBlackForestLabsFetchFunction()

    return { request in
        var modified = request
        var headers = modified.allHTTPHeaderFields ?? [:]

        let hasXKey = headers.keys.contains { $0.lowercased() == "x-key" }
        if !hasXKey {
            let resolved = try loadAPIKey(
                apiKey: apiKey,
                environmentVariableName: "BFL_API_KEY",
                description: "Black Forest Labs"
            )
            headers["x-key"] = resolved
            modified.allHTTPHeaderFields = headers
        }

        return try await baseFetch(modified)
    }
}

public final class BlackForestLabsProvider: ProviderV3 {
    private let imageFactory: @Sendable (BlackForestLabsImageModelId) -> BlackForestLabsImageModel

    init(imageFactory: @escaping @Sendable (BlackForestLabsImageModelId) -> BlackForestLabsImageModel) {
        self.imageFactory = imageFactory
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV3 {
        throw NoSuchModelError(modelId: modelId, modelType: .languageModel)
    }

    public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
        throw NoSuchModelError(modelId: modelId, modelType: .textEmbeddingModel)
    }

    public func imageModel(modelId: String) throws -> any ImageModelV3 {
        imageFactory(BlackForestLabsImageModelId(rawValue: modelId))
    }

    public func callAsFunction(_ modelId: String) throws -> any LanguageModelV3 {
        try languageModel(modelId: modelId)
    }

    public func image(modelId: BlackForestLabsImageModelId) -> BlackForestLabsImageModel {
        imageFactory(modelId)
    }

    public func image(_ modelId: BlackForestLabsImageModelId) -> BlackForestLabsImageModel {
        imageFactory(modelId)
    }

    public func imageModel(_ modelId: BlackForestLabsImageModelId) -> BlackForestLabsImageModel {
        imageFactory(modelId)
    }
}

public func createBlackForestLabsProvider(settings: BlackForestLabsProviderSettings = .init()) -> BlackForestLabsProvider {
    let baseURL = withoutTrailingSlash(settings.baseURL) ?? defaultBaseURL

    let headersClosure: @Sendable () -> [String: String?] = {
        var computed: [String: String?] = [:]

        if let customHeaders = settings.headers {
            for (key, value) in customHeaders {
                computed[key] = value
            }
        }

        let withUA = withUserAgentSuffix(computed, "ai-sdk/black-forest-labs/\(BLACK_FOREST_LABS_VERSION)")
        return withUA.mapValues { Optional($0) }
    }

    let fetch = createBlackForestLabsAuthFetch(
        apiKey: settings.apiKey,
        customFetch: settings.fetch
    )

    let imageFactory: @Sendable (BlackForestLabsImageModelId) -> BlackForestLabsImageModel = { modelId in
        BlackForestLabsImageModel(
            modelId: modelId,
            config: BlackForestLabsImageModelConfig(
                provider: "black-forest-labs.image",
                baseURL: baseURL,
                headers: headersClosure,
                fetch: fetch,
                pollIntervalMillis: settings.pollIntervalMillis,
                pollTimeoutMillis: settings.pollTimeoutMillis
            )
        )
    }

    return BlackForestLabsProvider(imageFactory: imageFactory)
}

/// Alias matching upstream naming (`createBlackForestLabs`).
public func createBlackForestLabs(settings: BlackForestLabsProviderSettings = .init()) -> BlackForestLabsProvider {
    createBlackForestLabsProvider(settings: settings)
}

public let blackForestLabs = createBlackForestLabsProvider()
