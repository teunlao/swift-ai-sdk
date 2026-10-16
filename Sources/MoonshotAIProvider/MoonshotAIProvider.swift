import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct MoonshotAIProviderSettings: Sendable {
    public var apiKey: String?
    public var baseURL: String?
    public var headers: [String: String]?
    public var fetch: FetchFunction?
    public init(apiKey: String? = nil, baseURL: String? = nil, headers: [String: String]? = nil, fetch: FetchFunction? = nil) { self.apiKey = apiKey; self.baseURL = baseURL; self.headers = headers; self.fetch = fetch }
}

public final class MoonshotAIProvider: ProviderV4 {
    private let settings: MoonshotAIProviderSettings
    private let baseURL: String
    init(settings: MoonshotAIProviderSettings) { self.settings = settings; self.baseURL = withoutTrailingSlash(settings.baseURL ?? "https://api.moonshot.ai/v1") ?? "https://api.moonshot.ai/v1" }
    public func languageModel(modelId: String) -> any LanguageModelV4 { chatModel(modelId: modelId) }
    public func chatModel(modelId: String) -> MoonshotAIChatLanguageModel {
        let settings = settings
        return MoonshotAIChatLanguageModel(modelId: .init(rawValue: modelId), config: .init(provider: "moonshotai.chat", headers: {
            let key = try loadAPIKey(apiKey: settings.apiKey, environmentVariableName: "MOONSHOT_API_KEY", description: "Moonshot API key")
            return withUserAgentSuffix(combineHeaders(["Authorization": "Bearer \(key)"], settings.headers?.mapValues(Optional.some)), "ai-sdk-moonshotai/\(MOONSHOTAI_VERSION)").mapValues(Optional.some)
        }, url: { [baseURL] in "\(baseURL)\($0.path)" }, fetch: settings.fetch, includeUsage: true, supportsStructuredOutputs: getModelStructuredOutputSupport(.init(rawValue: modelId))))
    }
    public func callAsFunction(_ modelId: String) -> MoonshotAIChatLanguageModel { chatModel(modelId: modelId) }
    public func embeddingModel(modelId: String) throws -> any EmbeddingModelV4 { throw NoSuchModelError(modelId: modelId, modelType: .embeddingModel) }
    public func imageModel(modelId: String) throws -> any ImageModelV4 { throw NoSuchModelError(modelId: modelId, modelType: .imageModel) }
}

public func getModelStructuredOutputSupport(_ modelId: MoonshotAIChatModelId) -> Bool { true }
public func createMoonshotAI(settings: MoonshotAIProviderSettings = .init()) -> MoonshotAIProvider { MoonshotAIProvider(settings: settings) }
public let moonshotai = createMoonshotAI()
