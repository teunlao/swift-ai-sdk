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

    let headersClosure: @Sendable () -> [String: String?] = {
        var headers: [String: String?] = [:]

        let token: String
        do {
            token = try loadAPIKey(
                apiKey: settings.apiToken,
                environmentVariableName: "REPLICATE_API_TOKEN",
                description: "Replicate"
            )
        } catch {
            fatalError("Replicate API token is missing: \(error)")
        }

        headers["Authorization"] = "Bearer \(token)"

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
                fetch: settings.fetch
            )
        )
    }

    return ReplicateProvider(imageFactory: factory)
}

/// Default Replicate provider instance.
public let replicate: ReplicateProvider = createReplicate()

