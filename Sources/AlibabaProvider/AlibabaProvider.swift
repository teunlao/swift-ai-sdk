import AISDKProvider
import AISDKProviderUtils

public struct AlibabaProviderSettings: Sendable {
    public var baseURL: String?
    public var videoBaseURL: String?
    public var embeddingBaseURL: String?
    public var apiKey: String?
    public var headers: [String: String]?
    public var fetch: FetchFunction?
    public var includeUsage: Bool?

    public init(baseURL: String? = nil, videoBaseURL: String? = nil, embeddingBaseURL: String? = nil,
                apiKey: String? = nil, headers: [String: String]? = nil, fetch: FetchFunction? = nil, includeUsage: Bool? = nil) {
        self.baseURL = baseURL; self.videoBaseURL = videoBaseURL; self.embeddingBaseURL = embeddingBaseURL
        self.apiKey = apiKey; self.headers = headers; self.fetch = fetch; self.includeUsage = includeUsage
    }
}

public final class AlibabaProvider: ProviderV4 {
    private let chatConfig: AlibabaConfig
    private let embeddingConfig: AlibabaConfig
    private let videoConfig: AlibabaVideoModelConfig

    init(settings: AlibabaProviderSettings) {
        let headers: @Sendable () throws -> [String: String?] = {
            let headers = combineHeaders(
                ["Authorization": "Bearer \(try loadAPIKey(apiKey: settings.apiKey, environmentVariableName: "ALIBABA_API_KEY", description: "Alibaba Cloud (DashScope)"))"],
                settings.headers?.mapValues(Optional.some)
            )
            return withUserAgentSuffix(headers, "ai-sdk-alibaba/\(ALIBABA_VERSION)").mapValues(Optional.some)
        }
        chatConfig = .init(provider: "alibaba.chat", baseURL: withoutTrailingSlash(settings.baseURL) ?? "https://dashscope-intl.aliyuncs.com/compatible-mode/v1", headers: headers, fetch: settings.fetch, includeUsage: settings.includeUsage ?? true)
        embeddingConfig = .init(provider: "alibaba.embedding", baseURL: withoutTrailingSlash(settings.embeddingBaseURL) ?? "https://dashscope-intl.aliyuncs.com/api/v1", headers: headers, fetch: settings.fetch)
        videoConfig = .init(provider: "alibaba.video", baseURL: withoutTrailingSlash(settings.videoBaseURL) ?? "https://dashscope-intl.aliyuncs.com", headers: headers, fetch: settings.fetch)
    }
    public func languageModel(modelId: String) -> any LanguageModelV4 { languageModel(.init(rawValue: modelId)) }
    public func languageModel(_ modelId: AlibabaChatModelId) -> AlibabaChatLanguageModel { .init(modelId: modelId, config: chatConfig) }
    public func chatModel(_ modelId: AlibabaChatModelId) -> AlibabaChatLanguageModel { languageModel(modelId) }
    public func callAsFunction(_ modelId: AlibabaChatModelId) -> AlibabaChatLanguageModel { languageModel(modelId) }
    public func embeddingModel(modelId: String) -> any EmbeddingModelV4 { embedding(.init(rawValue: modelId)) }
    public func embedding(_ modelId: AlibabaEmbeddingModelId) -> AlibabaEmbeddingModel { .init(modelId: modelId, config: embeddingConfig) }
    public func videoModel(modelId: String) -> (any VideoModelV4)? { video(.init(rawValue: modelId)) }
    public func video(_ modelId: AlibabaVideoModelId) -> AlibabaVideoModel { .init(modelId: modelId, config: videoConfig) }
    public func videoModel(_ modelId: AlibabaVideoModelId) -> AlibabaVideoModel { video(modelId) }
    public func imageModel(modelId: String) throws -> any ImageModelV4 { throw NoSuchModelError(modelId: modelId, modelType: .imageModel) }
}

public func createAlibaba(settings: AlibabaProviderSettings = .init()) -> AlibabaProvider { .init(settings: settings) }
public let alibaba = createAlibaba()
