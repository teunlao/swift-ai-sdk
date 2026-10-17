import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct RevAIProviderSettings: Sendable {
    public var apiKey: String?
    public var headers: [String: String]?
    public var fetch: FetchFunction?

    public init(apiKey: String? = nil, headers: [String: String]? = nil, fetch: FetchFunction? = nil) {
        self.apiKey = apiKey
        self.headers = headers
        self.fetch = fetch
    }
}

public final class RevAIProvider: ProviderV4 {
    public struct Models: Sendable {
        public let transcription: RevAITranscriptionModel
    }

    private let config: RevAIConfig

    init(settings: RevAIProviderSettings) {
        config = RevAIConfig(
            provider: "revai.transcription",
            url: { "https://api.rev.ai\($0.path)" },
            headers: {
                let headers = combineHeaders(
                    ["authorization": "Bearer \(try loadAPIKey(apiKey: settings.apiKey, environmentVariableName: "REVAI_API_KEY", description: "Rev.ai"))"],
                    settings.headers?.mapValues(Optional.some)
                )
                return withUserAgentSuffix(headers, "ai-sdk-revai/\(REVAI_VERSION)").mapValues(Optional.some)
            },
            fetch: settings.fetch
        )
    }

    public func transcription(modelId: RevAITranscriptionModelId) -> RevAITranscriptionModel {
        RevAITranscriptionModel(modelId: modelId, config: config)
    }

    public func transcriptionModel(modelId: String) -> (any TranscriptionModelV4)? {
        transcription(modelId: .init(rawValue: modelId))
    }

    public func callAsFunction(_ modelId: RevAITranscriptionModelId) -> Models {
        Models(transcription: transcription(modelId: modelId))
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV4 {
        throw NoSuchModelError(modelId: "unknown", modelType: .languageModel, message: "Rev.ai does not provide language models")
    }

    public func embeddingModel(modelId: String) throws -> any EmbeddingModelV4 {
        throw NoSuchModelError(modelId: "unknown", modelType: .embeddingModel, message: "Rev.ai does not provide text embedding models")
    }

    public func imageModel(modelId: String) throws -> any ImageModelV4 {
        throw NoSuchModelError(modelId: "unknown", modelType: .imageModel, message: "Rev.ai does not provide image models")
    }
}

public func createRevAI(settings: RevAIProviderSettings = .init()) -> RevAIProvider {
    RevAIProvider(settings: settings)
}

public let revai = createRevAI()
