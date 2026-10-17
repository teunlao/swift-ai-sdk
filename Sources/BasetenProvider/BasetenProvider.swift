import Foundation
import AISDKProvider
import AISDKProviderUtils
import OpenAICompatibleProvider

public struct BasetenProviderSettings: Sendable {
    public var apiKey: String?
    public var baseURL: String?
    public var modelURL: String?
    public var headers: [String: String]?
    public var fetch: FetchFunction?
    public var performanceClient: BasetenPerformanceClientConstructor?
    public init(apiKey: String? = nil, baseURL: String? = nil, modelURL: String? = nil,
                headers: [String: String]? = nil, fetch: FetchFunction? = nil,
                performanceClient: BasetenPerformanceClientConstructor? = nil) {
        self.apiKey = apiKey; self.baseURL = baseURL; self.modelURL = modelURL
        self.headers = headers; self.fetch = fetch; self.performanceClient = performanceClient
    }
}

struct BasetenProviderError: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}

public final class BasetenProvider: ProviderV4 {
    private let settings: BasetenProviderSettings
    private let baseURL: String
    init(settings: BasetenProviderSettings) {
        self.settings = settings; baseURL = withoutTrailingSlash(settings.baseURL) ?? "https://inference.baseten.co/v1"
    }
    public func callAsFunction(_ modelId: String? = nil) throws -> OpenAICompatibleChatLanguageModel { try chat(modelId: modelId.map(BasetenChatModelId.init(rawValue:))) }
    public func languageModel(modelId: String) throws -> any LanguageModelV4 { try chat(modelId: .init(rawValue: modelId)) }
    public func chatModel(modelId: String) throws -> any LanguageModelV4 { try languageModel(modelId: modelId) }
    public func languageModel(_ modelId: BasetenChatModelId? = nil) throws -> OpenAICompatibleChatLanguageModel { try chat(modelId: modelId) }
    public func chat(modelId: BasetenChatModelId? = nil) throws -> OpenAICompatibleChatLanguageModel {
        let modelURL = settings.modelURL
        let dedicated = modelURL?.contains("/sync/v1") == true
        if !dedicated, modelURL?.contains("/predict") == true {
            throw BasetenProviderError(message: "Not supported. You must use a /sync/v1 endpoint for chat models.")
        }
        return .init(modelId: .init(rawValue: modelId?.rawValue ?? (dedicated ? "placeholder" : "chat")), config: .init(
            provider: "baseten.chat", headers: headerFactory(), url: urlFactory(customURL: dedicated ? modelURL : nil, embedding: false),
            fetch: settings.fetch, includeUsage: true, errorConfiguration: basetenErrorConfiguration, supportsStructuredOutputs: true
        ))
    }
    public func embeddingModel(modelId: String) throws -> any EmbeddingModelV4 { try embeddingModel(.init(rawValue: modelId)) }
    public func embeddingModel(_ modelId: BasetenEmbeddingModelId? = nil) throws -> any EmbeddingModelV4 {
        guard let modelURL = settings.modelURL else {
            throw BasetenProviderError(message: "No model URL provided for embeddings. Please set modelURL option for embeddings.")
        }
        guard modelURL.contains("/sync") else {
            throw BasetenProviderError(message: "Not supported. You must use a /sync or /sync/v1 endpoint for embeddings.")
        }
        let model = modelId?.rawValue ?? "embeddings"
        if let constructor = settings.performanceClient {
            var url = modelURL
            if let range = url.range(of: "/sync/v1") { url.replaceSubrange(range, with: "/sync") }
            let client = try constructor(url, loadAPIKey(apiKey: settings.apiKey, environmentVariableName: "BASETEN_API_KEY", description: "Baseten API key"))
            return BasetenEmbeddingModel(modelId: model, client: client)
        }
        return OpenAICompatibleEmbeddingModel(modelId: .init(rawValue: model), config: .init(
            provider: "baseten.embedding", url: urlFactory(customURL: modelURL, embedding: true), headers: headerFactory(),
            fetch: settings.fetch, errorConfiguration: basetenErrorConfiguration, maxEmbeddingsPerCall: 128
        ))
    }
    public func imageModel(modelId: String) throws -> any ImageModelV4 { throw NoSuchModelError(modelId: modelId, modelType: .imageModel) }
    private func urlFactory(customURL: String?, embedding: Bool) -> @Sendable (OpenAICompatibleURLOptions) -> String {
        let base = customURL ?? baseURL
        return { options in
            let suffix = embedding && customURL?.contains("/sync") == true && customURL?.contains("/sync/v1") == false ? "/v1" : ""
            return base + suffix + options.path
        }
    }
    private func headerFactory() -> @Sendable () throws -> [String: String] {
        let settings = self.settings
        return {
            let key = try loadAPIKey(apiKey: settings.apiKey, environmentVariableName: "BASETEN_API_KEY", description: "Baseten API key")
            let headers: [String: String?] = ["Authorization": "Bearer \(key)"]
            return withUserAgentSuffix(combineHeaders(headers, settings.headers?.mapValues(Optional.some)), "ai-sdk-baseten/\(BASETEN_PROVIDER_VERSION)")
        }
    }
}
public func createBaseten(settings: BasetenProviderSettings = .init()) -> BasetenProvider { .init(settings: settings) }
public let baseten = createBaseten()
