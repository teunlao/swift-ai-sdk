import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class DeepgramSpeechModel: SpeechModelV4 {
    private let identifier: DeepgramSpeechModelId
    private let config: DeepgramConfig
    init(modelId: DeepgramSpeechModelId, config: DeepgramConfig) { identifier = modelId; self.config = config }
    public var provider: String { config.provider }
    public var modelId: String { identifier.rawValue }

    public func doGenerate(options: SpeechModelV4CallOptions) async throws -> SpeechModelV4Result {
        let now = config.currentDate()
        let settings = try await parseProviderOptions(provider: "deepgram", providerOptions: options.providerOptions, schema: deepgramSpeechModelOptionsSchema)
        var warnings: [SharedV4Warning] = []
        var upstreamModelId = modelId
        if ["aura", "aura-2"].contains(modelId) {
            guard let voice = options.voice?.trimmingCharacters(in: ecmaWhitespace), !voice.isEmpty else {
                throw RequiredVoiceError(message: "Deepgram speech model \"\(modelId)\" requires a `voice` to be set (e.g. voice: 'thalia').")
            }
            if options.language == "auto" {
                warnings.append(.compatibility(feature: "language", details: "Deepgram TTS models do not support automatic language detection. Language \"en\" was used instead."))
            }
            let language = options.language.flatMap { $0.isEmpty || $0 == "auto" ? nil : $0 } ?? "en"
            upstreamModelId = "\(modelId)-\(voice)-\(language)"
        }
        var query = QueryParameters()
        query["model"] = upstreamModelId
        let format = (options.outputFormat ?? "mp3").lowercased()
        let formats: [String: AudioFormat] = [
            "mp3": .init(encoding: "mp3"), "wav": .init(encoding: "linear16", container: "wav"), "linear16": .init(encoding: "linear16", container: "wav"),
            "mulaw": .init(encoding: "mulaw", container: "wav"), "alaw": .init(encoding: "alaw", container: "wav"), "opus": .init(encoding: "opus", container: "ogg"),
            "ogg": .init(encoding: "opus", container: "ogg"), "flac": .init(encoding: "flac"), "aac": .init(encoding: "aac"), "pcm": .init(encoding: "linear16", container: "none")
        ]
        if let mapped = formats[format] {
            query["encoding"] = mapped.encoding
            query["container"] = mapped.container
        } else {
            let parts = format.split(separator: "_", omittingEmptySubsequences: false)
            if parts.count >= 2 {
                let first = String(parts[0])
                let numeric = parts[1].trimmingCharacters(in: ecmaWhitespace)
                let prefix = numeric.range(of: "^[+-]?[0-9]+", options: .regularExpression).map { String(numeric[$0]) }
                let sampleRate = prefix.map(numberFromString)
                if ["linear16", "mulaw", "alaw", "mp3", "opus", "flac", "aac"].contains(first) {
                    query["encoding"] = first
                    if ["linear16", "mulaw", "alaw"].contains(first) { query["container"] = "wav" }
                    else if first == "opus" { query["container"] = "ogg" }
                    if let sampleRate, validSampleRates(first)?.contains(sampleRate) == true { query["sample_rate"] = numberString(sampleRate) }
                } else if first == "wav" || first == "ogg" {
                    query["container"] = first
                    query["encoding"] = first == "wav" ? "linear16" : "opus"
                    if let sampleRate { query["sample_rate"] = numberString(sampleRate) }
                }
            }
        }
        func warn(_ details: String) { warnings.append(.unsupported(feature: "providerOptions", details: details)) }
        if let settings {
            if let encoding = settings.encoding, !encoding.isEmpty {
                let encoding = encoding.lowercased()
                query["encoding"] = encoding
                if let container = settings.container, !container.isEmpty {
                    if ["linear16", "mulaw", "alaw"].contains(encoding) {
                        if ["wav", "none"].contains(container.lowercased()) { query["container"] = container.lowercased() }
                        else { warn("Encoding \"\(encoding)\" only supports containers \"wav\" or \"none\". Container \"\(container)\" was ignored.") }
                    } else if encoding == "opus" { query["container"] = "ogg" }
                    else if ["mp3", "flac", "aac"].contains(encoding) {
                        warn("Encoding \"\(encoding)\" does not support container parameter. Container \"\(container)\" was ignored.")
                        query["container"] = nil
                    }
                } else if ["mp3", "flac", "aac"].contains(encoding) { query["container"] = nil }
                else if ["linear16", "mulaw", "alaw"].contains(encoding), query["container"] == nil { query["container"] = "wav" }
                else if encoding == "opus" { query["container"] = "ogg" }
                if ["mp3", "opus", "aac"].contains(encoding) { query["sample_rate"] = nil }
                if ["linear16", "mulaw", "alaw", "flac"].contains(encoding) { query["bit_rate"] = nil }
            } else if let container = settings.container, !container.isEmpty {
                let container = container.lowercased()
                let encoding = container == "wav" || container == "none" ? "linear16" : container == "ogg" ? "opus" : nil
                if let encoding {
                    query["container"] = container
                    if encoding != query["encoding"]?.lowercased() {
                        query["encoding"] = encoding
                        if ["mp3", "opus", "aac"].contains(encoding) { query["sample_rate"] = nil }
                        if ["linear16", "mulaw", "alaw", "flac"].contains(encoding) { query["bit_rate"] = nil }
                    }
                }
            }
            let encoding = query["encoding"]?.lowercased() ?? ""
            if let rate = settings.sampleRate {
                let value = numberString(rate)
                if let allowed = validSampleRates(encoding) {
                    if allowed.contains(rate) { query["sample_rate"] = value }
                    else { warn("Encoding \"\(encoding)\" only supports sample rates: \(allowed.map(numberString).joined(separator: ", ")). Sample rate \(value) was ignored.") }
                } else if ["mp3", "opus", "aac"].contains(encoding) {
                    warn("Encoding \"\(encoding)\" has a fixed sample rate and does not support sample_rate parameter. Sample rate \(value) was ignored.")
                } else { query["sample_rate"] = value }
            }
            if let bitRate = settings.bitRate {
                let string: String
                let number: Double
                switch bitRate {
                case .number(let value): string = numberString(value); number = value
                case .string(let value): string = value; number = numberFromString(value)
                }
                if encoding == "mp3", ![32000, 48000].contains(number) {
                    warn("Encoding \"mp3\" only supports bit rates: 32000, 48000. Bit rate \(string) was ignored.")
                } else if encoding == "opus", number < 4000 || number > 650000 {
                    warn("Encoding \"opus\" supports bit rates between 4000 and 650000. Bit rate \(string) was ignored.")
                } else if encoding == "aac", number < 4000 || number > 192000 {
                    warn("Encoding \"aac\" supports bit rates between 4000 and 192000. Bit rate \(string) was ignored.")
                } else if ["linear16", "mulaw", "alaw", "flac"].contains(encoding) {
                    warn("Encoding \"\(encoding)\" does not support bit_rate parameter. Bit rate \(string) was ignored.")
                } else { query["bit_rate"] = string }
            }
            if let callback = settings.callback, !callback.isEmpty { query["callback"] = callback }
            query["callback_method"] = settings.callbackMethod?.rawValue
            query["mip_opt_out"] = settings.mipOptOut.map(String.init)
            if let tag = settings.tag {
                switch tag {
                case .single(let string): if !string.isEmpty { query["tag"] = string }
                case .multiple(let strings): query["tag"] = strings.joined(separator: ",")
                }
            }
        }
        if upstreamModelId == modelId, let voice = options.voice, !voice.isEmpty, voice != modelId {
            warnings.append(.unsupported(feature: "voice", details: "Deepgram TTS models embed the voice in the model ID. The voice parameter \"\(voice)\" was ignored. Use the model ID to select a voice (e.g., \"aura-2-helena-en\")."))
        }
        query["speed"] = options.speed.map(numberString)
        if upstreamModelId == modelId, let language = options.language, !language.isEmpty {
            warnings.append(.unsupported(feature: "language", details: "Deepgram TTS models are language-specific via the model ID. Language parameter \"\(language)\" was ignored. Select a model with the appropriate language suffix (e.g., \"-en\" for English)."))
        }
        if let instructions = options.instructions, !instructions.isEmpty {
            warnings.append(.unsupported(feature: "instructions", details: "Deepgram TTS REST API does not support instructions. Instructions parameter was ignored."))
        }
        let body: JSONValue = ["text": .string(options.text)]
        let response = try await postJsonToAPI(
            url: query.url("https://api.deepgram.com/v1/speak"), headers: combineHeaders(try config.headers(), options.headers?.mapValues(Optional.some)).compactMapValues { $0 },
            body: body, failedResponseHandler: deepgramFailedResponseHandler, successfulResponseHandler: createBinaryResponseHandler(), isAborted: options.abortSignal, fetch: config.fetch
        )
        let headers = response.responseHeaders
        func headerNumber(_ name: String) -> Double? {
            guard let value = headers[name] else { return nil }
            let number = numberFromString(value)
            return number.isNaN ? nil : number
        }
        let count = headerNumber("dg-char-count")
        var metadata: JSONObject = [:]
        for (header, field) in [("dg-model-name", "modelName"), ("dg-model-uuid", "modelUuid"), ("dg-pronunciation-warnings", "pronunciationWarnings"), ("dg-request-id", "requestId")] {
            if let value = headers[header], !value.isEmpty { metadata[field] = .string(value) }
        }
        for (header, field) in [("dg-char-count", "charCount"), ("dg-breaks-applied", "breaksApplied"), ("dg-pronunciations-applied", "pronunciationsApplied")] {
            if let value = headerNumber(header) { metadata[field] = .number(value) }
        }
        if let value = headers["dg-additional-model-uuids"] { metadata["additionalModelUuids"] = .array(value.components(separatedBy: ",").map(JSONValue.string)) }
        return .init(audio: .binary(response.value), warnings: warnings, usage: count.map { ["characters": .number($0)] },
                     request: .init(body: String(decoding: try JSONEncoder().encode(body), as: UTF8.self)),
                     response: .init(timestamp: now, modelId: modelId, headers: headers, body: response.rawValue), providerMetadata: ["deepgram": metadata])
    }
}

private struct AudioFormat {
    let encoding: String
    var container: String? = nil
}

private func validSampleRates(_ encoding: String) -> [Double]? {
    switch encoding {
    case "linear16": [8000, 16000, 24000, 32000, 48000]
    case "mulaw", "alaw": [8000, 16000]
    case "flac": [8000, 16000, 22050, 32000, 48000]
    default: nil
    }
}
private struct RequiredVoiceError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
