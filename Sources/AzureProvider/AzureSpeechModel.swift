import AISDKProvider
import AISDKProviderUtils
import OpenAIProvider

public final class AzureSpeechModel: SpeechModelV4 {
    public let modelId: String
    public let provider = "azure.speech"
    private let openai: OpenAISpeechModel
    private let speech: AzureSpeechSpeechModel

    public init(modelId: String, openai: OpenAISpeechModel, speech: AzureSpeechSpeechModel) {
        self.modelId = modelId
        self.openai = openai
        self.speech = speech
    }

    public func doGenerate(options: SpeechModelV4CallOptions) async throws -> SpeechModelV4Result {
        let settings = try await parseProviderOptions(provider: "azure", providerOptions: options.providerOptions,
            schema: azureSpeechModelOptions) ?? .init()
        if (settings.api ?? (maiVoiceModel(modelId) == nil ? .openai : .speech)) == .speech {
            return try await speech.doGenerate(options: options,
                speechOptions: .init(style: settings.style, styleDegree: settings.styleDegree))
        }
        let result = try await openai.doGenerate(options: options)
        var warnings = result.warnings
        if settings.style != nil {
            warnings.append(.unsupported(feature: "providerOptions.azure.style", details: "This option requires the Azure Speech API."))
        }
        if settings.styleDegree != nil {
            warnings.append(.unsupported(feature: "providerOptions.azure.styleDegree", details: "This option requires the Azure Speech API."))
        }
        return .init(audio: result.audio, warnings: warnings, usage: result.usage, request: result.request,
            response: result.response, providerMetadata: result.providerMetadata)
    }
}
