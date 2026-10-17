import AISDKProvider
import AISDKProviderUtils
import OpenAIProvider

public final class AzureTranscriptionModel: TranscriptionModelV4 {
    public let modelId: String
    public let provider = "azure.transcription"
    private let openai: OpenAITranscriptionModel
    private let speech: AzureSpeechTranscriptionModel
    private let mai: AzureMaiTranscriptionModel

    public init(modelId: String, openai: OpenAITranscriptionModel, speech: AzureSpeechTranscriptionModel, mai: AzureMaiTranscriptionModel) {
        self.modelId = modelId; self.openai = openai; self.speech = speech; self.mai = mai
    }

    public func doGenerate(options: TranscriptionModelV4CallOptions) async throws -> TranscriptionModelV4Result {
        let settings = try await settings(options.providerOptions)
        let result: TranscriptionModelV4Result
        var warnings: [SharedV4Warning]
        switch api(settings) {
        case .mai: return try await mai.doGenerate(options: options)
        case .speech:
            result = try await speech.doGenerate(options: options, speechOptions: settings.speech)
            warnings = result.warnings
        case .openai:
            result = try await openai.doGenerate(options: options)
            warnings = result.warnings + speechWarnings(settings.speech)
        }
        if settings.language != nil {
            warnings.append(.unsupported(feature: "providerOptions.azure.language", details: "This option requires MAI streaming transcription."))
        }
        return .init(text: result.text, segments: result.segments, language: result.language, durationInSeconds: result.durationInSeconds,
            warnings: warnings, usage: result.usage, request: result.request, response: result.response, providerMetadata: result.providerMetadata)
    }

    public func doStream(options: TranscriptionModelV4StreamOptions) async throws -> TranscriptionModelV4StreamResult {
        let settings = try await settings(options.providerOptions)
        switch api(settings) {
        case .speech: throw UnsupportedFunctionalityError(functionality: "streaming transcription with the Azure Speech API")
        case .mai: return try await mai.doStream(options: options, maiOptions: settings.mai, warnings: speechWarnings(settings.speech))
        case .openai: return try await openai.doStream(options: options)
        }
    }

    private func settings(_ options: SharedV4ProviderOptions?) async throws -> AzureTranscriptionModelOptions {
        try await parseProviderOptions(provider: "azure", providerOptions: options, schema: azureTranscriptionModelOptions) ?? .init()
    }
    private func api(_ settings: AzureTranscriptionModelOptions) -> AzureTranscriptionModelOptions.API {
        settings.api ?? (isMaiTranscribeStreaming(modelId) ? .mai : maiTranscribeModel(modelId) != nil ? .speech : .openai)
    }
    private func speechWarnings(_ options: AzureTranscriptionModelSpeechOptions) -> [SharedV4Warning] {
        var keys: [String] = []
        if options.timestamps != nil { keys.append("timestamps") }
        if options.transcribeStyle != nil { keys.append("transcribeStyle") }
        if options.locales != nil { keys.append("locales") }
        if options.diarization != nil { keys.append("diarization") }
        if options.phraseList != nil { keys.append("phraseList") }
        return keys.map { .unsupported(feature: "providerOptions.azure.\($0)", details: "This option requires the Azure Speech API.") }
    }
}
