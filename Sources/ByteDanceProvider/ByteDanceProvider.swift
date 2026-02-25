import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/bytedance/src/bytedance-provider.ts
// Upstream commit: 73d5c59
//===----------------------------------------------------------------------===//

public struct ByteDanceProviderSettings: Sendable {
    /// ByteDance Ark API key. Defaults to `ARK_API_KEY`.
    public var apiKey: String?

    /// Base URL for the API calls.
    /// Default: `https://ark.ap-southeast.bytepluses.com/api/v3`
    public var baseURL: String?

    /// Custom headers to include in the requests.
    public var headers: [String: String]?

    /// Custom fetch implementation.
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

public final class ByteDanceProvider: ProviderV3 {
    private let videoFactory: @Sendable (ByteDanceVideoModelId) -> ByteDanceVideoModel

    init(videoFactory: @escaping @Sendable (ByteDanceVideoModelId) -> ByteDanceVideoModel) {
        self.videoFactory = videoFactory
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV3 {
        throw NoSuchModelError(modelId: modelId, modelType: .languageModel)
    }

    public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
        throw NoSuchModelError(modelId: modelId, modelType: .textEmbeddingModel)
    }

    public func imageModel(modelId: String) throws -> any ImageModelV3 {
        throw NoSuchModelError(modelId: modelId, modelType: .imageModel)
    }

    public func videoModel(modelId: String) throws -> (any VideoModelV3)? {
        videoFactory(ByteDanceVideoModelId(rawValue: modelId))
    }

    public func video(modelId: ByteDanceVideoModelId) -> ByteDanceVideoModel {
        videoFactory(modelId)
    }

    public func video(_ modelId: ByteDanceVideoModelId) -> ByteDanceVideoModel {
        videoFactory(modelId)
    }
}

private let defaultByteDanceBaseURL = "https://ark.ap-southeast.bytepluses.com/api/v3"

/// Create a ByteDance provider instance.
public func createByteDanceProvider(
    settings: ByteDanceProviderSettings = .init()
) -> ByteDanceProvider {
    let baseURL = withoutTrailingSlash(settings.baseURL ?? defaultByteDanceBaseURL) ?? defaultByteDanceBaseURL

    let headersClosure: @Sendable () throws -> [String: String?] = {
        let apiKey = try loadAPIKey(
            apiKey: settings.apiKey,
            environmentVariableName: "ARK_API_KEY",
            description: "ByteDance ModelArk"
        )

        var headers: [String: String?] = [
            "Authorization": "Bearer \(apiKey)",
            "Content-Type": "application/json",
        ]

        if let custom = settings.headers {
            for (key, value) in custom {
                headers[key] = value
            }
        }

        let withUA = withUserAgentSuffix(headers, "ai-sdk/bytedance/\(BYTEDANCE_VERSION)")
        return withUA.mapValues { Optional($0) }
    }

    let videoFactory: @Sendable (ByteDanceVideoModelId) -> ByteDanceVideoModel = { modelId in
        ByteDanceVideoModel(
            modelId: modelId,
            config: ByteDanceVideoModelConfig(
                provider: "bytedance.video",
                baseURL: baseURL,
                headers: headersClosure,
                fetch: settings.fetch
            )
        )
    }

    return ByteDanceProvider(videoFactory: videoFactory)
}

/// Alias matching upstream naming (`createByteDance`).
public func createByteDance(
    settings: ByteDanceProviderSettings = .init()
) -> ByteDanceProvider {
    createByteDanceProvider(settings: settings)
}

/// Default ByteDance provider instance.
public let byteDance: ByteDanceProvider = createByteDanceProvider()

