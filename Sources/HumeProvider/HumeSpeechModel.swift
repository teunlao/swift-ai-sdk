import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class HumeSpeechModel: SpeechModelV4 {
    private let config: HumeConfig
    init(config: HumeConfig) { self.config = config }
    public var provider: String { config.provider }
    public var modelId: String { "" }

    public func doGenerate(options: SpeechModelV4CallOptions) async throws -> SpeechModelV4Result {
        let now = config.currentDate()
        let settings = try await parseProviderOptions(provider: "hume", providerOptions: options.providerOptions, schema: humeSpeechModelOptionsSchema)
        var warnings: [SharedV4Warning] = []
        var body = HumeSpeechAPITypes(utterances: [
            .init(text: options.text, description: options.instructions, speed: options.speed, trailingSilence: nil,
                  voice: .init(id: options.voice ?? "d8ab67c6-953d-4bd8-9370-8fa53a0f1453", name: nil, provider: "HUME_AI"))
        ], context: nil, format: .init(type: "mp3"))
        if let format = options.outputFormat, !format.isEmpty {
            if ["mp3", "pcm", "wav"].contains(format) { body.format.type = format }
            else { warnings.append(.unsupported(feature: "outputFormat", details: "Unsupported output format: \(format). Using mp3 instead.")) }
        }
        if let context = settings?.context {
            switch context {
            case .generationId(let id): body.context = .init(generationID: id, utterances: nil)
            case .utterances(let utterances):
                body.context = .init(generationID: nil, utterances: utterances.map { utterance in
                    let voice: HumeSpeechAPIVoice?
                    switch utterance.voice {
                    case .id(let id, let provider)?: voice = .init(id: id, name: nil, provider: provider?.rawValue)
                    case .name(let name, let provider)?: voice = .init(id: nil, name: name, provider: provider?.rawValue)
                    case nil: voice = nil
                    }
                    return .init(text: utterance.text, description: utterance.description, speed: utterance.speed, trailingSilence: utterance.trailingSilence, voice: voice)
                })
            }
        }
        if let language = options.language, !language.isEmpty {
            warnings.append(.unsupported(feature: "language", details: "Hume speech models do not support language selection. Language parameter \"\(language)\" was ignored."))
        }
        let response = try await postJsonToAPI(
            url: "https://api.hume.ai/v0/tts/file", headers: combineHeaders(try config.headers(), options.headers?.mapValues(Optional.some)).compactMapValues { $0 },
            body: body, failedResponseHandler: humeFailedResponseHandler, successfulResponseHandler: createBinaryResponseHandler(), isAborted: options.abortSignal, fetch: config.fetch
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return .init(audio: .binary(response.value), warnings: warnings, request: .init(body: String(decoding: try encoder.encode(body), as: UTF8.self)),
                     response: .init(timestamp: now, modelId: modelId, headers: response.responseHeaders, body: response.rawValue))
    }
}
