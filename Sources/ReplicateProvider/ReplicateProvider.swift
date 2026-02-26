import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Settings for configuring the Replicate provider.
/// Mirrors `packages/replicate/src/replicate-provider.ts`.
public struct ReplicateProviderSettings: Sendable {
    /// API token sent via the Authorization header (env: REPLICATE_API_TOKEN)
    public var apiToken: String?

    /// Custom base URL for API calls (default: https://api.replicate.com/v1)
    public var baseURL: String?

    /// Custom headers to include in requests
    public var headers: [String: String]?

    /// Custom fetch implementation
    public var fetch: FetchFunction?

    public init(
        apiToken: String? = nil,
        baseURL: String? = nil,
        headers: [String: String]? = nil,
        fetch: FetchFunction? = nil
    ) {
        self.apiToken = apiToken
        self.baseURL = baseURL
        self.headers = headers
        self.fetch = fetch
    }
}

public final class ReplicateProvider: ProviderV3 {
    private let imageFactory: @Sendable (ReplicateImageModelId) -> ReplicateImageModel

    init(imageFactory: @escaping @Sendable (ReplicateImageModelId) -> ReplicateImageModel) {
        self.imageFactory = imageFactory
    }

    // MARK: ProviderV3
    public func languageModel(modelId: String) throws -> any LanguageModelV3 {
        throw NoSuchModelError(modelId: modelId, modelType: .languageModel)
    }

    public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
        throw NoSuchModelError(modelId: modelId, modelType: .textEmbeddingModel)
    }

    public func imageModel(modelId: String) throws -> any ImageModelV3 {
        imageFactory(ReplicateImageModelId(rawValue: modelId))
    }

    // MARK: Convenience
    public func image(_ modelId: ReplicateImageModelId) -> ReplicateImageModel {
        imageFactory(modelId)
    }

    public func imageModel(_ modelId: ReplicateImageModelId) -> ReplicateImageModel {
        imageFactory(modelId)
    }
}

/// Create a Replicate provider instance.
public func createReplicate(settings: ReplicateProviderSettings = .init()) -> ReplicateProvider {
    let baseURL = withoutTrailingSlash(settings.baseURL) ?? "https://api.replicate.com/v1"

    func defaultReplicateFetchFunction() -> FetchFunction {
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

    func createReplicateAuthFetch(apiToken: String?, customFetch: FetchFunction?) -> FetchFunction {
        let baseFetch = customFetch ?? defaultReplicateFetchFunction()

        return { request in
            var modified = request
            var headers = modified.allHTTPHeaderFields ?? [:]

            let hasAuthorization = headers.keys.contains { $0.lowercased() == "authorization" }
            if !hasAuthorization {
                let resolved = try loadAPIKey(
                    apiKey: apiToken,
                    environmentVariableName: "REPLICATE_API_TOKEN",
                    description: "Replicate"
                )
                headers["Authorization"] = "Bearer \(resolved)"
                modified.allHTTPHeaderFields = headers
            }

            return try await baseFetch(modified)
        }
    }

    let fetch = createReplicateAuthFetch(
        apiToken: settings.apiToken,
        customFetch: settings.fetch
    )

    let headersClosure: @Sendable () -> [String: String?] = {
        var headers: [String: String?] = [:]

        if let extra = settings.headers {
            for (k, v) in extra { headers[k] = v }
        }

        let withUA = withUserAgentSuffix(headers, "ai-sdk/replicate/\(REPLICATE_PROVIDER_VERSION)")
        return withUA.mapValues { Optional($0) }
    }

    let factory: @Sendable (ReplicateImageModelId) -> ReplicateImageModel = { modelId in
        ReplicateImageModel(
            modelId,
            config: ReplicateImageModelConfig(
                provider: "replicate",
                baseURL: baseURL,
                headers: headersClosure,
                fetch: fetch
            )
        )
    }

    return ReplicateProvider(imageFactory: factory)
}

/// Default Replicate provider instance.
public let replicate: ReplicateProvider = createReplicate()
