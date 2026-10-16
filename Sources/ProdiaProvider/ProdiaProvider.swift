import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct ProdiaProviderSettings: Sendable {
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

public final class ProdiaProvider: ProviderV4 {
    private let settings: ProdiaProviderSettings
    private let baseURL: String
    init(settings: ProdiaProviderSettings) {
        self.settings = settings
        self.baseURL = withoutTrailingSlash(settings.baseURL) ?? "https://inference.prodia.com/v2"
    }
    public func languageModel(modelId: String) throws -> any LanguageModelV4 {
        languageModel(ProdiaLanguageModelId(rawValue: modelId))
    }
    public func languageModel(_ modelId: ProdiaLanguageModelId) -> ProdiaLanguageModel {
        ProdiaLanguageModel(modelId: modelId, config: config(provider: "prodia.language"))
    }
    public func embeddingModel(modelId: String) throws -> any EmbeddingModelV4 {
        throw NoSuchModelError(modelId: modelId, modelType: .embeddingModel)
    }
    public func imageModel(modelId: String) -> any ImageModelV4 { image(.init(rawValue: modelId)) }
    public func image(modelId: ProdiaImageModelId) -> ProdiaImageModel { image(modelId) }
    public func image(_ modelId: ProdiaImageModelId) -> ProdiaImageModel {
        ProdiaImageModel(modelId: modelId, config: config(provider: "prodia.image"))
    }
    public func imageModel(_ modelId: ProdiaImageModelId) -> ProdiaImageModel { image(modelId) }

    public func video(modelId: ProdiaVideoModelId) -> ProdiaVideoModel { video(modelId) }
    public func video(_ modelId: ProdiaVideoModelId) -> ProdiaVideoModel {
        ProdiaVideoModel(modelId: modelId, config: config(provider: "prodia.video"))
    }
    public func videoModel(modelId: String) -> ProdiaVideoModel { video(.init(rawValue: modelId)) }

    private func config(provider: String) -> ProdiaModelConfig {
        ProdiaModelConfig(provider: provider, baseURL: baseURL, headers: { try self.headers() }, fetch: settings.fetch)
    }
    private func headers() throws -> [String: String?] {
        let key = try loadAPIKey(apiKey: settings.apiKey, environmentVariableName: "PRODIA_TOKEN", description: "Prodia")
        var headers: [String: String?] = ["Authorization": "Bearer \(key)"]
        for (key, value) in settings.headers ?? [:] { headers[key] = value }
        return withUserAgentSuffix(headers, "ai-sdk-prodia/\(VERSION)").mapValues { Optional($0) }
    }
}

public func createProdia(settings: ProdiaProviderSettings = .init()) -> ProdiaProvider { ProdiaProvider(settings: settings) }
public let prodia = createProdia()
