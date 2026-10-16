import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct BlackForestLabsProviderSettings: Sendable {
    public var apiKey: String?
    public var baseURL: String?
    public var headers: [String: String]?
    public var fetch: FetchFunction?
    public var pollIntervalMillis: Int?
    public var pollTimeoutMillis: Int?

    public init(apiKey: String? = nil, baseURL: String? = nil, headers: [String: String]? = nil, fetch: FetchFunction? = nil, pollIntervalMillis: Int? = nil, pollTimeoutMillis: Int? = nil) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.headers = headers
        self.fetch = fetch
        self.pollIntervalMillis = pollIntervalMillis
        self.pollTimeoutMillis = pollTimeoutMillis
    }
}

public final class BlackForestLabsProvider: ProviderV4 {
    private let settings: BlackForestLabsProviderSettings
    private let baseURL: String

    init(settings: BlackForestLabsProviderSettings) {
        self.settings = settings
        self.baseURL = withoutTrailingSlash(settings.baseURL) ?? "https://api.bfl.ai/v1"
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV4 {
        throw NoSuchModelError(modelId: modelId, modelType: .languageModel)
    }
    public func embeddingModel(modelId: String) throws -> any EmbeddingModelV4 {
        throw NoSuchModelError(modelId: modelId, modelType: .embeddingModel)
    }
    public func imageModel(modelId: String) throws -> any ImageModelV4 {
        image(.init(rawValue: modelId))
    }
    public func image(modelId: BlackForestLabsImageModelId) -> BlackForestLabsImageModel { image(modelId) }
    public func image(_ modelId: BlackForestLabsImageModelId) -> BlackForestLabsImageModel {
        BlackForestLabsImageModel(modelId: modelId, config: .init(provider: "black-forest-labs.image", baseURL: baseURL, headers: { try self.headers() }, fetch: settings.fetch, pollIntervalMillis: settings.pollIntervalMillis, pollTimeoutMillis: settings.pollTimeoutMillis))
    }
    public func imageModel(_ modelId: BlackForestLabsImageModelId) -> BlackForestLabsImageModel { image(modelId) }
    public func videoModel(modelId: String) -> any VideoModelV4 { video(.init(rawValue: modelId)) }
    public func video(_ modelId: BlackForestLabsVideoModelId) -> BlackForestLabsVideoModel {
        BlackForestLabsVideoModel(modelId: modelId, config: .init(provider: "black-forest-labs.video", baseURL: baseURL, headers: { try self.headers() }, fetch: settings.fetch, pollIntervalMillis: settings.pollIntervalMillis, pollTimeoutMillis: settings.pollTimeoutMillis))
    }
    public func videoModel(_ modelId: BlackForestLabsVideoModelId) -> BlackForestLabsVideoModel { video(modelId) }

    private func headers() throws -> [String: String?] {
        let key = try loadAPIKey(apiKey: settings.apiKey, environmentVariableName: "BFL_API_KEY", description: "Black Forest Labs")
        var headers: [String: String?] = ["x-key": key]
        for (key, value) in settings.headers ?? [:] { headers[key] = value }
        return withUserAgentSuffix(headers, "ai-sdk-black-forest-labs/\(BLACK_FOREST_LABS_VERSION)").mapValues { Optional($0) }
    }
}

public func createBlackForestLabs(settings: BlackForestLabsProviderSettings = .init()) -> BlackForestLabsProvider {
    BlackForestLabsProvider(settings: settings)
}

public let blackForestLabs = createBlackForestLabs()
