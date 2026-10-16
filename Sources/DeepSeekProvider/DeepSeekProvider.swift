import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct DeepSeekProviderSettings: Sendable {
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

public final class DeepSeekProvider: ProviderV4, FilesProvider {
    private let settings: DeepSeekProviderSettings
    private let baseURL: String
    init(settings: DeepSeekProviderSettings) {
        self.settings = settings
        baseURL = withoutTrailingSlash(settings.baseURL) ?? "https://api.deepseek.com"
    }
    public func languageModel(modelId: String) throws -> any LanguageModelV4 { chat(.init(rawValue: modelId)) }
    public func chatModel(modelId: String) throws -> any LanguageModelV4 { chat(.init(rawValue: modelId)) }
    public func embeddingModel(modelId: String) throws -> any EmbeddingModelV4 {
        throw NoSuchModelError(modelId: modelId, modelType: .embeddingModel)
    }
    public func imageModel(modelId: String) throws -> any ImageModelV4 {
        throw NoSuchModelError(modelId: modelId, modelType: .imageModel)
    }
    public func callAsFunction(_ modelId: String) -> DeepSeekChatLanguageModel { chat(.init(rawValue: modelId)) }
    public func languageModel(_ modelId: DeepSeekChatModelId) -> DeepSeekChatLanguageModel { chat(modelId) }
    public func chat(_ modelId: DeepSeekChatModelId) -> DeepSeekChatLanguageModel {
        let baseURL = self.baseURL
        return .init(modelId: modelId, config: .init(
            provider: "deepseek.chat", headers: headerFactory(), url: { baseURL + $0.path }, fetch: settings.fetch,
            supportsAssistantPrefixCompletion: baseURL.hasSuffix("/beta"), supportsStrictToolCalls: baseURL.hasSuffix("/beta")
        ))
    }
    public func files() -> any FilesV4 { DeepSeekFiles(baseURL: baseURL, headers: headerFactory(), fetch: settings.fetch) }
    private func headerFactory() -> @Sendable () throws -> [String: String] {
        let settings = self.settings
        return {
            var headers: [String: String?] = ["Authorization": "Bearer \(try loadAPIKey(apiKey: settings.apiKey, environmentVariableName: "DEEPSEEK_API_KEY", description: "DeepSeek API key"))"]
            for (key, value) in settings.headers ?? [:] { headers[key] = value }
            return withUserAgentSuffix(headers, "ai-sdk-deepseek/\(DEEPSEEK_PROVIDER_VERSION)")
        }
    }
}

public func createDeepSeek(settings: DeepSeekProviderSettings = .init()) -> DeepSeekProvider { .init(settings: settings) }
public let deepSeek = createDeepSeek()
