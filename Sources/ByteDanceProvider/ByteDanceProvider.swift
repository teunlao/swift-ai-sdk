import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct ByteDanceProviderSettings: Sendable {
    public var apiKey: String?
    public var baseURL: String?
    public var headers: [String: String]?
    public var fetch: FetchFunction?

    public init(apiKey: String? = nil, baseURL: String? = nil, headers: [String: String]? = nil, fetch: FetchFunction? = nil) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.headers = headers
        self.fetch = fetch
    }
}

public final class ByteDanceProvider: ProviderV4 {
    private let videoFactory: @Sendable (ByteDanceVideoModelId) -> ByteDanceVideoModel

    init(videoFactory: @escaping @Sendable (ByteDanceVideoModelId) -> ByteDanceVideoModel) {
        self.videoFactory = videoFactory
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV4 {
        throw NoSuchModelError(modelId: modelId, modelType: .languageModel)
    }

    public func embeddingModel(modelId: String) throws -> any EmbeddingModelV4 {
        throw NoSuchModelError(modelId: modelId, modelType: .embeddingModel)
    }

    public func imageModel(modelId: String) throws -> any ImageModelV4 {
        throw NoSuchModelError(modelId: modelId, modelType: .imageModel)
    }

    public func videoModel(modelId: String) -> ByteDanceVideoModel {
        videoFactory(ByteDanceVideoModelId(rawValue: modelId))
    }

    public func video(modelId: ByteDanceVideoModelId) -> ByteDanceVideoModel {
        videoFactory(modelId)
    }

    public func video(_ modelId: ByteDanceVideoModelId) -> ByteDanceVideoModel {
        videoFactory(modelId)
    }
}

public func createByteDance(settings: ByteDanceProviderSettings = .init()) -> ByteDanceProvider {
    let defaultBaseURL = "https://ark.ap-southeast.bytepluses.com/api/v3"
    let baseURL = withoutTrailingSlash(settings.baseURL ?? defaultBaseURL) ?? defaultBaseURL
    let headers: @Sendable () throws -> [String: String?] = {
        var values: [String: String?] = [
            "Authorization": "Bearer \(try loadAPIKey(apiKey: settings.apiKey, environmentVariableName: "ARK_API_KEY", description: "ByteDance ModelArk"))",
            "Content-Type": "application/json",
        ]
        for (key, value) in settings.headers ?? [:] { values[key] = value }
        return withUserAgentSuffix(values, "ai-sdk-bytedance/\(VERSION)").mapValues { Optional($0) }
    }
    return ByteDanceProvider(videoFactory: { modelId in
        ByteDanceVideoModel(modelId: modelId, config: .init(provider: "bytedance.video", baseURL: baseURL,
                                                          headers: headers, fetch: settings.fetch))
    })
}

public let byteDance = createByteDance()
