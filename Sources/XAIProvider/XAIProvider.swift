import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct XAIProviderSettings: Sendable {
    public var baseURL: String?
    public var apiKey: String?
    public var headers: [String: String]?
    public var fetch: FetchFunction?
    public var webSocket: XAIWebSocketFactory?

    public init(baseURL: String? = nil, apiKey: String? = nil, headers: [String: String]? = nil, fetch: FetchFunction? = nil, webSocket: XAIWebSocketFactory? = nil) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.headers = headers
        self.fetch = fetch
        self.webSocket = webSocket
    }
}

public final class XAIProvider: ProviderV4 {
    private let settings: XAIProviderSettings
    private let baseURL: String
    private let headers: @Sendable () throws -> [String: String?]
    public let tools = xaiTools

    init(settings: XAIProviderSettings) {
        self.settings = settings
        self.baseURL = withoutTrailingSlash(settings.baseURL) ?? "https://api.x.ai/v1"
        self.headers = {
            let apiKey = try loadAPIKey(apiKey: settings.apiKey, environmentVariableName: "XAI_API_KEY", description: "xAI API key")
            return withUserAgentSuffix(
                combineHeaders(["Authorization": "Bearer \(apiKey)"], settings.headers?.mapValues(Optional.some)),
                "ai-sdk-xai/\(XAI_PROVIDER_VERSION)"
            ).mapValues(Optional.some)
        }
    }

    public func languageModel(modelId: String) -> any LanguageModelV4 {
        responses(modelId: XAIResponsesModelId(rawValue: modelId))
    }

    public func responses(modelId: XAIResponsesModelId) -> XAIResponsesLanguageModel {
        XAIResponsesLanguageModel(modelId: modelId, config: .init(
            provider: "xai.responses", baseURL: baseURL, headers: headers, generateId: generateID, fetch: settings.fetch
        ))
    }

    public func responses(_ modelId: String) -> XAIResponsesLanguageModel {
        responses(modelId: XAIResponsesModelId(rawValue: modelId))
    }

    public func embeddingModel(modelId: String) throws -> any EmbeddingModelV4 {
        throw NoSuchModelError(modelId: modelId, modelType: .embeddingModel)
    }

    public func imageModel(modelId: String) -> any ImageModelV4 {
        image(modelId: XAIImageModelId(rawValue: modelId))
    }

    public func image(modelId: XAIImageModelId) -> XAIImageModel {
        XAIImageModel(modelId: modelId, config: .init(provider: "xai.image", baseURL: baseURL, headers: headers, fetch: settings.fetch))
    }

    public func transcription(modelId: XAITranscriptionModelId = "") -> XAITranscriptionModel {
        XAITranscriptionModel(modelId: modelId, config: .init(provider: "xai.transcription", baseURL: baseURL, headers: headers, fetch: settings.fetch, webSocket: settings.webSocket))
    }

    public func transcriptionModel() -> XAITranscriptionModel { transcription() }

    public func transcriptionModel(modelId: String) -> (any TranscriptionModelV4)? {
        transcription(modelId: XAITranscriptionModelId(rawValue: modelId))
    }

    public func files() -> (any FilesV4)? {
        XAIFiles(config: .init(provider: "xai.files", baseURL: baseURL, headers: headers, fetch: settings.fetch))
    }

    public func speech() -> XAISpeechModel {
        XAISpeechModel(config: .init(provider: "xai.speech", baseURL: baseURL, headers: headers, fetch: settings.fetch))
    }

    public func speechModel() -> XAISpeechModel { speech() }

    public func speechModel(modelId: String) -> (any SpeechModelV4)? { speech() }

    public func videoModel(modelId: String) -> XAIVideoModel {
        video(modelId: XAIVideoModelId(rawValue: modelId))
    }

    public func video(modelId: XAIVideoModelId) -> XAIVideoModel {
        XAIVideoModel(modelId: modelId, config: .init(provider: "xai.video", baseURL: baseURL, headers: headers, fetch: settings.fetch))
    }

    public func video(_ modelId: XAIVideoModelId) -> XAIVideoModel {
        video(modelId: modelId)
    }

    public func callAsFunction(_ modelId: String) -> any LanguageModelV4 {
        languageModel(modelId: modelId)
    }
}

public func createXai(settings: XAIProviderSettings = .init()) -> XAIProvider {
    XAIProvider(settings: settings)
}

public let xai = createXai()
