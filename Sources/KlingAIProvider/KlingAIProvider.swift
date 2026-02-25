import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/klingai/src/klingai-provider.ts
// Upstream commit: 73d5c59
//===----------------------------------------------------------------------===//

public struct KlingAIProviderSettings: Sendable {
    /// KlingAI Access key. Defaults to `KLINGAI_ACCESS_KEY`.
    public var accessKey: String?

    /// KlingAI Secret key. Defaults to `KLINGAI_SECRET_KEY`.
    public var secretKey: String?

    /// Base URL for the API calls.
    public var baseURL: String?

    /// Custom headers to include in the requests.
    public var headers: [String: String]?

    /// Custom fetch implementation.
    public var fetch: FetchFunction?

    public init(
        accessKey: String? = nil,
        secretKey: String? = nil,
        baseURL: String? = nil,
        headers: [String: String]? = nil,
        fetch: FetchFunction? = nil
    ) {
        self.accessKey = accessKey
        self.secretKey = secretKey
        self.baseURL = baseURL
        self.headers = headers
        self.fetch = fetch
    }
}

public final class KlingAIProvider: ProviderV3 {
    private let videoFactory: @Sendable (KlingAIVideoModelId) -> KlingAIVideoModel

    init(videoFactory: @escaping @Sendable (KlingAIVideoModelId) -> KlingAIVideoModel) {
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
        videoFactory(KlingAIVideoModelId(rawValue: modelId))
    }

    public func video(modelId: KlingAIVideoModelId) -> KlingAIVideoModel {
        videoFactory(modelId)
    }

    public func video(_ modelId: KlingAIVideoModelId) -> KlingAIVideoModel {
        videoFactory(modelId)
    }
}

private let defaultKlingAIBaseURL = "https://api-singapore.klingai.com"

/// Create a KlingAI provider instance.
public func createKlingAIProvider(
    settings: KlingAIProviderSettings = .init()
) -> KlingAIProvider {
    let baseURL = withoutTrailingSlash(settings.baseURL ?? defaultKlingAIBaseURL) ?? defaultKlingAIBaseURL

    let headersClosure: @Sendable () async throws -> [String: String?] = {
        let token = try await generateKlingAIAuthToken(
            accessKey: settings.accessKey,
            secretKey: settings.secretKey
        )

        var headers: [String: String?] = [
            "Authorization": "Bearer \(token)"
        ]

        if let custom = settings.headers {
            for (key, value) in custom {
                headers[key] = value
            }
        }

        let withUA = withUserAgentSuffix(headers, "ai-sdk/klingai/\(VERSION)")
        return withUA.mapValues { Optional($0) }
    }

    let videoFactory: @Sendable (KlingAIVideoModelId) -> KlingAIVideoModel = { modelId in
        KlingAIVideoModel(
            modelId: modelId,
            config: KlingAIVideoModelConfig(
                provider: "klingai.video",
                baseURL: baseURL,
                headers: headersClosure,
                fetch: settings.fetch
            )
        )
    }

    return KlingAIProvider(videoFactory: videoFactory)
}

/// Alias matching upstream naming (`createKlingAI`).
public func createKlingAI(
    settings: KlingAIProviderSettings = .init()
) -> KlingAIProvider {
    createKlingAIProvider(settings: settings)
}

/// Default KlingAI provider instance.
public let klingai: KlingAIProvider = createKlingAIProvider()

