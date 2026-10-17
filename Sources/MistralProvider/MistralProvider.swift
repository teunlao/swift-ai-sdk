import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct MistralProviderSettings: Sendable {
    public var baseURL: String?
    public var apiKey: String?
    public var headers: [String: String]?
    public var fetch: FetchFunction?
    public var generateId: IDGenerator?

    public init(baseURL: String? = nil, apiKey: String? = nil, headers: [String: String]? = nil,
                fetch: FetchFunction? = nil, generateId: IDGenerator? = nil) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.headers = headers
        self.fetch = fetch
        self.generateId = generateId
    }
}

public final class MistralProvider: ProviderV4 {
    private let settings: MistralProviderSettings
    private let baseURL: String
    private let headers: @Sendable () throws -> [String: String?]
    public let tools = MistralTools()

    init(settings: MistralProviderSettings) {
        self.settings = settings
        self.baseURL = withoutTrailingSlash(settings.baseURL) ?? "https://api.mistral.ai/v1"
        self.headers = {
            let headers = combineHeaders(
                ["Authorization": "Bearer \(try loadAPIKey(apiKey: settings.apiKey, environmentVariableName: "MISTRAL_API_KEY", description: "Mistral"))"],
                settings.headers?.mapValues { Optional($0) }
            ).compactMapValues { $0 }
            return withUserAgentSuffix(headers, "ai-sdk-mistral/\(MISTRAL_VERSION)").mapValues { Optional($0) }
        }
    }

    public func languageModel(modelId: String) -> any LanguageModelV4 { chat(modelId: .init(rawValue: modelId)) }

    public func chat(modelId: MistralChatModelId) -> MistralChatLanguageModel {
        .init(modelId: modelId, config: .init(provider: "mistral.chat", baseURL: baseURL,
                                            headers: headers, fetch: settings.fetch, generateId: settings.generateId ?? generateID))
    }

    public func conversation(modelId: MistralConversationModelId) -> MistralConversationLanguageModel {
        .init(modelId: modelId, config: .init(provider: "mistral.conversation", baseURL: baseURL,
                                            headers: headers, fetch: settings.fetch, generateId: settings.generateId ?? generateID))
    }

    public func embeddingModel(modelId: String) -> any EmbeddingModelV4 { embedding(.init(rawValue: modelId)) }

    public func embedding(_ modelId: MistralEmbeddingModelId) -> MistralEmbeddingModel {
        .init(modelId: modelId, config: .init(provider: "mistral.embedding", baseURL: baseURL, headers: headers, fetch: settings.fetch))
    }

    public func speechModel(modelId: String) -> (any SpeechModelV4)? { speech(.init(rawValue: modelId)) }

    public func speech(_ modelId: MistralSpeechModelId) -> MistralSpeechModel {
        .init(modelId: modelId, config: .init(provider: "mistral.speech", baseURL: baseURL, headers: headers, fetch: settings.fetch))
    }

    public func transcriptionModel(modelId: String) -> (any TranscriptionModelV4)? { transcription(.init(rawValue: modelId)) }

    public func transcription(_ modelId: MistralTranscriptionModelId) -> MistralTranscriptionModel {
        .init(modelId: modelId, config: .init(provider: "mistral.transcription", baseURL: baseURL, headers: headers, fetch: settings.fetch))
    }

    public func imageModel(modelId: String) throws -> any ImageModelV4 {
        throw NoSuchModelError(modelId: modelId, modelType: .imageModel)
    }

    public func callAsFunction(_ modelId: String) -> any LanguageModelV4 { languageModel(modelId: modelId) }
}

public func createMistral(settings: MistralProviderSettings = .init()) -> MistralProvider { .init(settings: settings) }

public let mistral = createMistral()
