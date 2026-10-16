import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct GoogleSpeechModelOptions: Sendable, Codable, Equatable {
    public struct Metadata: Sendable, Codable, Equatable {
        public var speaker: String?
        public var style: String?
        public init(speaker: String? = nil, style: String? = nil) { self.speaker = speaker; self.style = style }
    }
    public struct Turn: Sendable, Codable, Equatable {
        public var text: String
        public var speechMetadata: Metadata?
        public init(text: String, speechMetadata: Metadata? = nil) { self.text = text; self.speechMetadata = speechMetadata }
    }
    public struct MultiSpeakerVoiceConfig: Sendable, Codable, Equatable {
        public struct Speaker: Sendable, Codable, Equatable {
            public struct VoiceConfig: Sendable, Codable, Equatable {
                public struct Prebuilt: Sendable, Codable, Equatable {
                    public var voiceName: String
                    public init(voiceName: String) { self.voiceName = voiceName }
                }
                public var prebuiltVoiceConfig: Prebuilt
                public init(prebuiltVoiceConfig: Prebuilt) { self.prebuiltVoiceConfig = prebuiltVoiceConfig }
            }
            public var speaker: String
            public var voiceConfig: VoiceConfig
            public init(speaker: String, voiceName: String) { self.speaker = speaker; self.voiceConfig = .init(prebuiltVoiceConfig: .init(voiceName: voiceName)) }
        }
        public var speakerVoiceConfigs: [Speaker]
        public init(speakerVoiceConfigs: [Speaker]) { self.speakerVoiceConfigs = speakerVoiceConfigs }
    }
    public var speechMetadata: Metadata?
    public var turns: [Turn]?
    public var multiSpeakerVoiceConfig: MultiSpeakerVoiceConfig?
    public init(speechMetadata: Metadata? = nil, turns: [Turn]? = nil, multiSpeakerVoiceConfig: MultiSpeakerVoiceConfig? = nil) {
        self.speechMetadata = speechMetadata; self.turns = turns; self.multiSpeakerVoiceConfig = multiSpeakerVoiceConfig
    }
}

private let googleSpeechOptionsSchema = FlexibleSchema(Schema<GoogleSpeechModelOptions>(
    jsonSchemaResolver: { .object(["type": .string("object")]) },
    validator: { value in
        do {
            let json = try jsonValue(from: value)
            guard case .object(let object) = json else { throw SchemaValidationIssuesError(vendor: "google", issues: "speech options must be an object") }
            func metadata(_ value: JSONValue?) throws {
                guard let value else { return }
                guard case .object(let object) = value else { throw SchemaValidationIssuesError(vendor: "google", issues: "speechMetadata must be an object") }
                for key in ["speaker", "style"] where object[key] == .null { throw SchemaValidationIssuesError(vendor: "google", issues: "invalid speechMetadata.\(key)") }
                if object["speaker"] == .string("") { throw SchemaValidationIssuesError(vendor: "google", issues: "speaker must not be empty") }
            }
            for key in ["speechMetadata", "turns", "multiSpeakerVoiceConfig"] where object[key] == .null { throw SchemaValidationIssuesError(vendor: "google", issues: "invalid speech option \(key)") }
            try metadata(object["speechMetadata"])
            if case .array(let turns) = object["turns"] {
                for turn in turns { if case .object(let object) = turn { try metadata(object["speechMetadata"]) } }
            }
            if case .object(let multi) = object["multiSpeakerVoiceConfig"], case .array(let speakers) = multi["speakerVoiceConfigs"] {
                for speaker in speakers {
                    if case .object(let speaker) = speaker, case .object(let voice) = speaker["voiceConfig"], voice["voice"] != nil { throw SchemaValidationIssuesError(vendor: "google", issues: "custom voice is not supported") }
                }
            }
            let options = try JSONDecoder().decode(GoogleSpeechModelOptions.self, from: JSONEncoder().encode(json))
            if options.turns?.isEmpty == true { throw SchemaValidationIssuesError(vendor: "google", issues: "turns must not be empty") }
            return .success(value: options)
        } catch { return .failure(error: TypeValidationError.wrap(value: value, cause: error)) }
    }
))

private struct GoogleSpeechResponse: Decodable, Sendable {
    struct Candidate: Decodable, Sendable {
        struct Content: Decodable, Sendable {
            struct Part: Decodable, Sendable {
                struct Inline: Decodable, Sendable { let data: String?; let mimeType: String? }
                let inlineData: Inline?
            }
            let parts: [Part]?
        }
        let content: Content?
    }
    let candidates: [Candidate]?
    let usageMetadata: JSONObject?
}
private let googleSpeechResponseSchema = FlexibleSchema(Schema<GoogleSpeechResponse>.codable(GoogleSpeechResponse.self, jsonSchema: .object(["type": .string("object")])))

public final class GoogleSpeechModel: SpeechModelV4 {
    public struct Config: Sendable {
        public let provider: String
        public let baseURL: String
        public let headers: @Sendable () throws -> [String: String?]
        public let fetch: FetchFunction?
        public let currentDate: @Sendable () -> Date
        public let resolveBaseURL: (@Sendable () throws -> String)?
        public init(provider: String, baseURL: String, headers: @escaping @Sendable () throws -> [String: String?] = { [:] }, fetch: FetchFunction? = nil, currentDate: @escaping @Sendable () -> Date = { Date() }, resolveBaseURL: (@Sendable () throws -> String)? = nil) {
            self.provider = provider; self.baseURL = baseURL; self.headers = headers; self.fetch = fetch; self.currentDate = currentDate; self.resolveBaseURL = resolveBaseURL
        }
    }
    public let modelId: String
    public var provider: String { config.provider }
    private let config: Config
    public init(modelId: String, config: Config) { self.modelId = modelId; self.config = config }

    public func doGenerate(options: SpeechModelV4CallOptions) async throws -> SpeechModelV4Result {
        let date = config.currentDate()
        var google: GoogleSpeechModelOptions?
        var rawOptions: JSONObject?
        let names = googleProviderOptionsNames(provider)
        for name in names + (names.contains("google") ? [] : ["google"]) {
            google = try await parseProviderOptions(provider: name, providerOptions: options.providerOptions, schema: googleSpeechOptionsSchema)
            if google != nil { rawOptions = options.providerOptions?[name]; break }
        }
        let voice = options.voice ?? "Kore"
        let input = getGoogleSpeechInput(text: options.text, voice: voice, providerOptions: rawOptions.map { ["google": $0] })
        if input.usesCustomVoice { throw InvalidArgumentError(argument: "voice", message: "Custom voices are not supported. Use a prebuilt voice instead.") }
        let structured = !modelId.hasPrefix("gemini-2.5-") && !modelId.hasPrefix("gemini-3.1-")
        var warnings: [SharedV4Warning] = []
        var parts: [JSONValue] = []
        let multi = google?.multiSpeakerVoiceConfig
        if structured {
            if google?.turns != nil && google?.speechMetadata != nil { throw InvalidArgumentError(argument: "providerOptions", message: "Set speechMetadata on each turn when using turns.") }
            if google?.turns != nil && !options.text.isEmpty { warnings.append(.unsupported(feature: "text", details: "Google TTS turns replace the top-level text.")) }
            for turn in google?.turns ?? [.init(text: options.text, speechMetadata: google?.speechMetadata)] {
                let speaker = turn.speechMetadata?.speaker
                if let multi, !multi.speakerVoiceConfigs.contains(where: { $0.speaker == speaker }) { throw InvalidArgumentError(argument: "speechMetadata.speaker", message: "Every multi-speaker turn must specify a speechMetadata.speaker matching a configured speaker.") }
                var part: [String: JSONValue] = ["text": .string(turn.text)]
                var metadata: [String: JSONValue] = [:]
                if let style = turn.speechMetadata?.style ?? options.instructions { metadata["style"] = .string(style) }
                if let speaker { metadata["speaker"] = .string(speaker) }
                if !metadata.isEmpty { part["speechMetadata"] = .object(metadata) }
                parts.append(.object(part))
            }
        } else {
            if google?.turns != nil || google?.speechMetadata != nil { throw InvalidArgumentError(argument: "providerOptions", message: "Structured speech metadata and turns require Gemini 3.8 TTS.") }
            var text = options.text
            if let instructions = options.instructions {
                if multi != nil { warnings.append(.unsupported(feature: "instructions", details: "Google Gemini TTS ignores `instructions` when `multiSpeakerVoiceConfig` is set, because prepending them would break multi-speaker transcript parsing.")) }
                else { text = "\(instructions): \(text)" }
            }
            parts = [.object(["text": .string(text)])]
        }
        if input.text.isEmpty { throw InvalidArgumentError(argument: "text", message: "Speech input must contain a non-empty transcript.") }
        if options.speed != nil { warnings.append(.unsupported(feature: "speed", details: "Google Gemini TTS models do not support the `speed` option. It was ignored.")) }
        if options.language != nil { warnings.append(.unsupported(feature: "language", details: "Google Gemini TTS models do not support the `language` option. Language is detected automatically from the input text.")) }
        let formats = structured ? ["wav": "AUDIO_WAV", "audio/wav": "AUDIO_WAV", "pcm": "AUDIO_L16", "audio/l16": "AUDIO_L16", "mulaw": "AUDIO_MULAW", "audio/mulaw": "AUDIO_MULAW", "alaw": "AUDIO_ALAW", "audio/alaw": "AUDIO_ALAW"] : ["wav": "AUDIO_WAV", "pcm": "AUDIO_L16"]
        let format = options.outputFormat.flatMap { formats[$0] } ?? "AUDIO_WAV"
        if let output = options.outputFormat, formats[output] == nil { warnings.append(.unsupported(feature: "outputFormat", details: "Unsupported output format: \(output). Using wav instead.")) }
        let speech: JSONValue
        if let multi { speech = .object(["multiSpeakerVoiceConfig": try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(multi))]) }
        else { speech = .object(["voiceConfig": .object(["prebuiltVoiceConfig": .object(["voiceName": .string(voice)])])]) }
        var generation: [String: JSONValue] = ["responseModalities": .array([.string("AUDIO")]), "speechConfig": speech]
        if structured && options.outputFormat != nil { generation["responseFormat"] = .object(["audio": .object(["mimeType": .string(format)])]) }
        let body: JSONValue = .object(["contents": .array([.object(["role": .string("user"), "parts": .array(parts)])]), "generationConfig": .object(generation)])
        let response = try await postJsonToAPI(url: "\(try config.resolveBaseURL?() ?? config.baseURL)/models/\(modelId):generateContent", headers: combineHeaders(try config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 }, body: body, failedResponseHandler: googleFailedResponseHandler, successfulResponseHandler: createJsonResponseHandler(responseSchema: googleSpeechResponseSchema), isAborted: options.abortSignal, fetch: config.fetch)
        let inline = (response.value.candidates ?? []).flatMap { $0.content?.parts ?? [] }.compactMap(\.inlineData).first { $0.data?.isEmpty == false }
        let mimeType = inline?.mimeType
        let regex = try! NSRegularExpression(pattern: "rate=(\\d+)")
        let rate: Int
        if let mimeType, let match = regex.firstMatch(in: mimeType, range: NSRange(mimeType.startIndex..., in: mimeType)), let range = Range(match.range(at: 1), in: mimeType), let value = Int(mimeType[range]) { rate = value } else { rate = 24000 }
        var audio = try inline?.data.map(convertBase64ToData) ?? Data()
        let pcm = mimeType.map { googleModelMatches($0, "^audio/(?:l16|pcm)(?:;|$)") } ?? !structured
        if format == "AUDIO_WAV" && pcm && !audio.isEmpty { audio = googleWav(audio, sampleRate: rate) }
        if format == "AUDIO_L16" && !audio.isEmpty && !structured {
            warnings.append(.unsupported(feature: "outputFormat", details: "Returning raw PCM audio (signed 16-bit little-endian, mono, \(rate) Hz). These bytes have no container header and are not directly playable; see providerMetadata.google for the sample rate and mime type."))
        }
        return .init(audio: .binary(audio), warnings: warnings, usage: response.value.usageMetadata, request: .init(body: try googleJSONString(body)), response: .init(timestamp: date, modelId: modelId, headers: response.responseHeaders, body: response.rawValue), providerMetadata: ["google": ["sampleRate": .number(Double(rate)), "mimeType": mimeType.map(JSONValue.string) ?? .null]])
    }
}

private func googleWav(_ pcm: Data, sampleRate: Int) -> Data {
    var output = Data()
    func ascii(_ value: String) { output.append(contentsOf: value.utf8) }
    func u16(_ value: UInt16) { var little = value.littleEndian; withUnsafeBytes(of: &little) { output.append(contentsOf: $0) } }
    func u32(_ value: UInt32) { var little = value.littleEndian; withUnsafeBytes(of: &little) { output.append(contentsOf: $0) } }
    ascii("RIFF"); u32(UInt32(truncatingIfNeeded: 36 + pcm.count)); ascii("WAVE"); ascii("fmt "); u32(16); u16(1); u16(1)
    u32(UInt32(truncatingIfNeeded: sampleRate)); u32(UInt32(truncatingIfNeeded: sampleRate &* 2)); u16(2); u16(16); ascii("data"); u32(UInt32(truncatingIfNeeded: pcm.count)); output.append(pcm)
    return output
}
