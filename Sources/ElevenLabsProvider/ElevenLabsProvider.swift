import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct ElevenLabsProviderSettings: Sendable {
    public var apiKey: String?
    public var headers: [String: String]?
    public var fetch: FetchFunction?
    public var webSocket: WebSocketConstructor?

    public init(
        apiKey: String? = nil,
        headers: [String: String]? = nil,
        fetch: FetchFunction? = nil,
        webSocket: WebSocketConstructor? = nil
    ) {
        self.apiKey = apiKey
        self.headers = headers
        self.fetch = fetch
        self.webSocket = webSocket
    }
}

public final class ElevenLabsProvider: ProviderV4 {
    public struct Models: Sendable {
        public let transcription: ElevenLabsTranscriptionModel
    }

    private let settings: ElevenLabsProviderSettings

    init(settings: ElevenLabsProviderSettings) {
        self.settings = settings
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV4 {
        throw NoSuchModelError(modelId: modelId, modelType: .languageModel, message: "ElevenLabs does not provide language models")
    }

    public func embeddingModel(modelId: String) throws -> any EmbeddingModelV4 {
        throw NoSuchModelError(modelId: modelId, modelType: .embeddingModel, message: "ElevenLabs does not provide embedding models")
    }

    public func imageModel(modelId: String) throws -> any ImageModelV4 {
        throw NoSuchModelError(modelId: modelId, modelType: .imageModel, message: "ElevenLabs does not provide image models")
    }

    public func transcriptionModel(modelId: String) throws -> (any TranscriptionModelV4)? {
        transcription(modelId: .init(rawValue: modelId))
    }

    public func speechModel(modelId: String) throws -> (any SpeechModelV4)? {
        speech(modelId: .init(rawValue: modelId))
    }

    public func transcription(modelId: ElevenLabsTranscriptionModelId) -> ElevenLabsTranscriptionModel {
        ElevenLabsTranscriptionModel(modelId: modelId, config: config(provider: "elevenlabs.transcription"))
    }

    public func speech(modelId: ElevenLabsSpeechModelId) -> ElevenLabsSpeechModel {
        ElevenLabsSpeechModel(modelId: modelId, config: config(provider: "elevenlabs.speech"))
    }

    public func callAsFunction(_ modelId: ElevenLabsTranscriptionModelId) -> Models {
        Models(transcription: transcription(modelId: modelId))
    }

    private func config(provider: String) -> ElevenLabsConfig {
        let settings = self.settings
        return ElevenLabsConfig(
            provider: provider,
            url: { "https://api.elevenlabs.io\($0.path)" },
            headers: {
                let key = try loadAPIKey(
                    apiKey: settings.apiKey,
                    environmentVariableName: "ELEVENLABS_API_KEY",
                    description: "ElevenLabs"
                )
                return withUserAgentSuffix(
                    combineHeaders(["xi-api-key": key], settings.headers?.mapValues(Optional.some)),
                    "ai-sdk-elevenlabs/\(ELEVENLABS_VERSION)"
                ).mapValues(Optional.some)
            },
            fetch: settings.fetch,
            webSocket: settings.webSocket
        )
    }
}

public func createElevenLabs(settings: ElevenLabsProviderSettings = .init()) -> ElevenLabsProvider {
    ElevenLabsProvider(settings: settings)
}

public let elevenLabs = createElevenLabs()
