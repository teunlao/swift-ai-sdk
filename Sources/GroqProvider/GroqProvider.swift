import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct GroqProviderSettings: Sendable {
    public var baseURL: String?
    public var apiKey: String?
    public var headers: [String: String]?
    public var fetch: FetchFunction?

    public init(baseURL: String? = nil, apiKey: String? = nil, headers: [String: String]? = nil, fetch: FetchFunction? = nil) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.headers = headers
        self.fetch = fetch
    }
}

public final class GroqProvider: ProviderV4 {
    private let settings: GroqProviderSettings
    private let baseURL: String
    private let headers: @Sendable () throws -> [String: String?]
    public let tools = GroqTools()

    init(settings: GroqProviderSettings) {
        self.settings = settings
        baseURL = withoutTrailingSlash(settings.baseURL) ?? "https://api.groq.com/openai/v1"
        headers = {
            let headers = combineHeaders(
                ["Authorization": "Bearer \(try loadAPIKey(apiKey: settings.apiKey, environmentVariableName: "GROQ_API_KEY", description: "Groq"))"],
                settings.headers?.mapValues(Optional.some)
            )
            return withUserAgentSuffix(headers, "ai-sdk-groq/\(GROQ_PROVIDER_VERSION)").mapValues(Optional.some)
        }
    }

    public func languageModel(modelId: String) -> any LanguageModelV4 { chat(modelId: .init(rawValue: modelId)) }
    public func callAsFunction(_ modelId: GroqChatModelId) -> GroqChatLanguageModel { chat(modelId: modelId) }

    public func chat(modelId: GroqChatModelId) -> GroqChatLanguageModel {
        let baseURL = self.baseURL
        return .init(modelId: modelId, config: .init(provider: "groq.chat", url: { baseURL + $0.path }, headers: headers, fetch: settings.fetch))
    }

    public func embeddingModel(modelId: String) throws -> any EmbeddingModelV4 {
        throw NoSuchModelError(modelId: modelId, modelType: .embeddingModel)
    }
    public func imageModel(modelId: String) throws -> any ImageModelV4 {
        throw NoSuchModelError(modelId: modelId, modelType: .imageModel)
    }
    public func transcription(modelId: GroqTranscriptionModelId) -> GroqTranscriptionModel {
        let baseURL = self.baseURL
        return .init(modelId: modelId, config: .init(provider: "groq.transcription", url: { baseURL + $0.path }, headers: headers, fetch: settings.fetch, currentDate: { Date() }))
    }
    public func transcriptionModel(modelId: String) -> (any TranscriptionModelV4)? { transcription(modelId: .init(rawValue: modelId)) }
}

public func createGroq(settings: GroqProviderSettings = .init()) -> GroqProvider { .init(settings: settings) }
public let groq = createGroq()
