import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct DeepgramProviderSettings: Sendable {
    public var apiKey: String?
    public var headers: [String: String]?
    public var fetch: FetchFunction?

    public init(apiKey: String? = nil, headers: [String: String]? = nil, fetch: FetchFunction? = nil) {
        self.apiKey = apiKey
        self.headers = headers
        self.fetch = fetch
    }
}

public final class DeepgramProvider: ProviderV4 {
    public struct Models: Sendable {
        public let transcription: DeepgramTranscriptionModel
    }

    private let transcriptionConfig: DeepgramConfig
    private let speechConfig: DeepgramConfig

    init(settings: DeepgramProviderSettings) {
        let headers: @Sendable () throws -> [String: String?] = {
            let combined = combineHeaders(
                ["authorization": "Token \(try loadAPIKey(apiKey: settings.apiKey, environmentVariableName: "DEEPGRAM_API_KEY", description: "Deepgram"))"],
                settings.headers?.mapValues(Optional.some)
            )
            return withUserAgentSuffix(combined, "ai-sdk-deepgram/\(DEEPGRAM_VERSION)").mapValues(Optional.some)
        }
        transcriptionConfig = .init(provider: "deepgram.transcription", headers: headers, fetch: settings.fetch)
        speechConfig = .init(provider: "deepgram.speech", headers: headers, fetch: settings.fetch)
    }

    public func transcription(modelId: DeepgramTranscriptionModelId) -> DeepgramTranscriptionModel {
        .init(modelId: modelId, config: transcriptionConfig)
    }
    public func speech(modelId: DeepgramSpeechModelId) -> DeepgramSpeechModel {
        .init(modelId: modelId, config: speechConfig)
    }
    public func callAsFunction(_ modelId: DeepgramTranscriptionModelId) -> Models {
        .init(transcription: transcription(modelId: modelId))
    }
    public func transcriptionModel(modelId: String) -> (any TranscriptionModelV4)? {
        transcription(modelId: .init(rawValue: modelId))
    }
    public func speechModel(modelId: String) -> (any SpeechModelV4)? {
        speech(modelId: .init(rawValue: modelId))
    }
    public func languageModel(modelId: String) throws -> any LanguageModelV4 {
        throw NoSuchModelError(modelId: modelId, modelType: .languageModel, message: "Deepgram does not provide language models")
    }
    public func embeddingModel(modelId: String) throws -> any EmbeddingModelV4 {
        throw NoSuchModelError(modelId: modelId, modelType: .embeddingModel, message: "Deepgram does not provide text embedding models")
    }
    public func imageModel(modelId: String) throws -> any ImageModelV4 {
        throw NoSuchModelError(modelId: modelId, modelType: .imageModel, message: "Deepgram does not provide image models")
    }
}

public func createDeepgram(settings: DeepgramProviderSettings = .init()) -> DeepgramProvider { .init(settings: settings) }
public let deepgram = createDeepgram()
