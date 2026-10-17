import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class ElevenLabsSpeechModel: SpeechModelV4 {
    private let modelIdentifier: ElevenLabsSpeechModelId
    private let config: ElevenLabsConfig

    public init(modelId: ElevenLabsSpeechModelId, config: ElevenLabsConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    public func doGenerate(options: SpeechModelV4CallOptions) async throws -> SpeechModelV4Result {
        let timestamp = config.currentDate()
        let parsed = try await parseProviderOptions(
            provider: "elevenlabs", providerOptions: options.providerOptions, schema: elevenLabsSpeechModelOptionsSchema
        )
        var body: JSONObject = ["text": .string(options.text), "model_id": .string(modelId)]
        if let language = options.language, !language.isEmpty {
            body["language_code"] = .string(language)
        } else if let language = parsed?.languageCode, !language.isEmpty {
            body["language_code"] = .string(language)
        }
        var voiceSettings: JSONObject = [:]
        if let speed = options.speed { voiceSettings["speed"] = .number(speed) }
        if let settings = parsed?.voiceSettings {
            if let value = settings.stability { voiceSettings["stability"] = .number(value) }
            if let value = settings.similarityBoost { voiceSettings["similarity_boost"] = .number(value) }
            if let value = settings.style { voiceSettings["style"] = .number(value) }
            if let value = settings.useSpeakerBoost { voiceSettings["use_speaker_boost"] = .bool(value) }
        }
        if !voiceSettings.isEmpty { body["voice_settings"] = .object(voiceSettings) }
        if let locators = parsed?.pronunciationDictionaryLocators {
            body["pronunciation_dictionary_locators"] = .array(locators.map {
                var value: JSONObject = ["pronunciation_dictionary_id": .string($0.pronunciationDictionaryId)]
                if let version = $0.versionId, !version.isEmpty { value["version_id"] = .string(version) }
                return .object(value)
            })
        }
        if let seed = parsed?.seed { body["seed"] = .number(seed) }
        if let text = parsed?.previousText, !text.isEmpty { body["previous_text"] = .string(text) }
        if let text = parsed?.nextText, !text.isEmpty { body["next_text"] = .string(text) }
        if let ids = parsed?.previousRequestIds { body["previous_request_ids"] = .array(ids.map(JSONValue.string)) }
        if let ids = parsed?.nextRequestIds { body["next_request_ids"] = .array(ids.map(JSONValue.string)) }
        if let value = parsed?.applyTextNormalization { body["apply_text_normalization"] = .string(value.rawValue) }
        if let value = parsed?.applyLanguageTextNormalization { body["apply_language_text_normalization"] = .bool(value) }

        let format = options.outputFormat ?? "mp3_44100_128"
        let formats = [
            "mp3": "mp3_44100_128", "mp3_32": "mp3_44100_32", "mp3_64": "mp3_44100_64",
            "mp3_96": "mp3_44100_96", "mp3_128": "mp3_44100_128", "mp3_192": "mp3_44100_192",
            "pcm": "pcm_44100", "ulaw": "ulaw_8000"
        ]
        let voice = options.voice ?? "21m00Tcm4TlvDq8ikWAM"
        let endpoint = config.url(.init(modelId: modelId, path: "/v1/text-to-speech/\(voice)"))
        guard var url = URLComponents(string: endpoint) else {
            throw InvalidArgumentError(argument: "url", message: "Invalid speech URL: \(endpoint)")
        }
        var query: [URLQueryItem] = []
        if !format.isEmpty { query.append(.init(name: "output_format", value: formats[format] ?? format)) }
        if let logging = parsed?.enableLogging { query.append(.init(name: "enable_logging", value: String(logging))) }
        url.queryItems = query.isEmpty ? nil : query
        url.percentEncodedQuery = url.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").replacingOccurrences(of: "%20", with: "+")
        var warnings: [SharedV4Warning] = []
        if let instructions = options.instructions, !instructions.isEmpty {
            warnings.append(.unsupported(feature: "instructions", details: "ElevenLabs speech models do not support instructions. Instructions parameter was ignored."))
        }
        let response = try await postJsonToAPI(
            url: url.string ?? endpoint,
            headers: combineHeaders(try config.headers(), options.headers).compactMapValues { $0 },
            body: JSONValue.object(body),
            failedResponseHandler: elevenLabsFailedResponseHandler,
            successfulResponseHandler: createBinaryResponseHandler(),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let request = String(decoding: try encoder.encode(JSONValue.object(body)), as: UTF8.self)
        return .init(
            audio: .binary(response.value), warnings: warnings, request: .init(body: request),
            response: .init(timestamp: timestamp, modelId: modelId, headers: response.responseHeaders, body: response.rawValue)
        )
    }
}
