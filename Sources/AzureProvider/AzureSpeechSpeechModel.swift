import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct AzureSpeechSpeechConfig: Sendable {
    public let url: @Sendable () throws -> String
    public let headers: @Sendable () throws -> [String: String?]
    public let fetch: FetchFunction?
    public let _internal: Internal?

    public struct Internal: Sendable {
        public let currentDate: (@Sendable () -> Date)?
        public init(currentDate: (@Sendable () -> Date)? = nil) { self.currentDate = currentDate }
    }

    public init(url: @escaping @Sendable () throws -> String,
                headers: @escaping @Sendable () throws -> [String: String?],
                fetch: FetchFunction? = nil, _internal: Internal? = nil) {
        self.url = url
        self.headers = headers
        self.fetch = fetch
        self._internal = _internal
    }
}

public final class AzureSpeechSpeechModel: SpeechModelV4 {
    public let modelId: String
    public let provider = "azure.speech"
    private let config: AzureSpeechSpeechConfig

    public init(modelId: String, config: AzureSpeechSpeechConfig) {
        self.modelId = modelId
        self.config = config
    }

    public func doGenerate(options: SpeechModelV4CallOptions) async throws -> SpeechModelV4Result {
        try await doGenerate(options: options, speechOptions: .init())
    }

    public func doGenerate(options: SpeechModelV4CallOptions, speechOptions: AzureSpeechModelSpeechOptions) async throws -> SpeechModelV4Result {
        let timestamp = config._internal?.currentDate?() ?? Date()
        var warnings: [SharedV4Warning] = []
        if options.instructions != nil {
            warnings.append(.unsupported(feature: "instructions", details: "Use providerOptions.azure.style to control speaking style."))
        }
        let resolved = Self.voice(options.voice, language: options.language)
        if let warning = resolved.warning { warnings.append(.unsupported(feature: "language", details: warning)) }
        if speechOptions.styleDegree != nil && speechOptions.style == nil {
            warnings.append(.unsupported(feature: "providerOptions.azure.styleDegree", details: "styleDegree requires style."))
        }
        var outputFormat = Self.defaultOutputFormat
        if let requested = options.outputFormat {
            let format = requested.lowercased()
            if let shorthand = Self.outputFormats[format] { outputFormat = shorthand }
            else if Self.nativeFormat(format) { outputFormat = format }
            else {
                warnings.append(.unsupported(feature: "outputFormat", details: "Unsupported output format: \(requested). Using mp3 instead."))
            }
        }
        let voice = resolved.name
        let voiceName = voice.contains(":") ? voice : "\(voice):\(maiVoiceModel(modelId) ?? modelId)"
        var content = Self.escape(options.text)
        if let speed = options.speed { content = "<prosody rate=\"\(jsNumberString(speed))\">\(content)</prosody>" }
        if let style = speechOptions.style {
            let degree = speechOptions.styleDegree.map { " styledegree=\"\(jsNumberString($0))\"" } ?? ""
            content = "<mstts:express-as style=\"\(Self.escape(style))\"\(degree)>\(content)</mstts:express-as>"
        }
        let locale = Self.locale(voice) ?? "en-US"
        let ssml = "<speak version=\"1.0\" xmlns=\"http://www.w3.org/2001/10/synthesis\" xmlns:mstts=\"http://www.w3.org/2001/mstts\" xml:lang=\"\(Self.escape(locale))\"><voice name=\"\(Self.escape(voiceName))\">\(content)</voice></speak>"
        let url = try config.url()
        let headers = combineHeaders(try config.headers(),
            ["Content-Type": "application/ssml+xml", "X-Microsoft-OutputFormat": outputFormat],
            options.headers?.mapValues(Optional.some)).compactMapValues { $0 }
        let response = try await postToAPI(url: url, headers: headers,
            body: .init(content: .data(Data(ssml.utf8)), values: ssml), failedResponseHandler: speechFailedResponseHandler,
            successfulResponseHandler: createBinaryResponseHandler(), isAborted: options.abortSignal, fetch: config.fetch)
        return .init(audio: .binary(response.value), warnings: warnings, request: .init(body: ssml),
            response: .init(timestamp: timestamp, modelId: modelId, headers: response.responseHeaders, body: response.rawValue))
    }

    private static let defaultVoice = "en-US-Harper"
    private static let defaultVoices = [
        "de": "de-DE-Mia", "en": defaultVoice, "es": "es-MX-Valeria", "fr": "fr-FR-Soleil",
        "hi": "hi-IN-Kavya", "hu": "hu-HU-Lilla", "it": "it-IT-Rosa", "ko": "ko-KR-Haena",
        "nl": "nl-NL-Fleur", "pt": "pt-BR-Luana", "ro": "ro-RO-Elena", "ru": "ru-RU-Masha",
        "th": "th-TH-Krit", "tr": "tr-TR-Elif", "zh": "zh-CN-Mei"
    ]
    private static let defaultOutputFormat = "audio-24khz-160kbitrate-mono-mp3"
    private static let outputFormats = [
        "mp3": defaultOutputFormat, "opus": "ogg-24khz-16bit-mono-opus",
        "pcm": "raw-24khz-16bit-mono-pcm", "wav": "riff-24khz-16bit-mono-pcm"
    ]
    private static let localePattern = try! NSRegularExpression(pattern: "^([A-Za-z]{2,3}-[A-Za-z]{2,4})-")

    private struct Voice {
        let name: String
        let warning: String?
        init(_ name: String, warning: String? = nil) { self.name = name; self.warning = warning }
    }

    private static func voice(_ voice: String?, language: String?) -> Voice {
        let code = language.flatMap { $0.isEmpty ? nil : $0.components(separatedBy: "-").first?.lowercased() }
        guard let voice else {
            guard let code else { return Voice(defaultVoice) }
            if code == "auto" {
                return Voice(defaultVoice, warning: "Automatic language detection is not supported. \(defaultVoice) was used.")
            }
            if let name = defaultVoices[code] { return Voice(name) }
            return Voice(defaultVoice, warning: "No default MAI voice for language \"\(language ?? "")\". \(defaultVoice) was used.")
        }
        let voiceLanguage = locale(voice)?.components(separatedBy: "-").first?.lowercased()
        if let code, code != "auto", let voiceLanguage, code != voiceLanguage {
            return Voice(voice, warning: "The voice \(voice) selects the language. Language \"\(language ?? "")\" was ignored.")
        }
        return Voice(voice)
    }

    private static func locale(_ voice: String) -> String? {
        guard let match = localePattern.firstMatch(in: voice, range: NSRange(voice.startIndex..., in: voice)),
              let range = Range(match.range(at: 1), in: voice) else { return nil }
        return String(voice[range])
    }

    private static func nativeFormat(_ value: String) -> Bool {
        guard let prefix = ["amr-", "audio-", "g722-", "ogg-", "raw-", "riff-", "webm-"].first(where: value.hasPrefix) else { return false }
        let suffix = value.dropFirst(prefix.count)
        return !suffix.isEmpty && suffix.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
    }

    private static func escape(_ value: String) -> String {
        value.unicodeScalars.reduce(into: "") { result, scalar in
            switch scalar.value {
            case 38: result += "&amp;"
            case 60: result += "&lt;"
            case 62: result += "&gt;"
            case 34: result += "&quot;"
            case 39: result += "&apos;"
            default: result.unicodeScalars.append(scalar)
            }
        }
    }

}

private struct SpeechError: Decodable, Sendable {
    struct Detail: Decodable, Sendable { let message: String }
    let error: Detail
}

private let speechErrorSchema = FlexibleSchema(Schema.codable(SpeechError.self, jsonSchema: [
    "type": "object", "required": ["error"], "properties": [
        "error": ["type": "object", "required": ["message"], "properties": ["message": ["type": "string"]]]
    ]
]))

private let speechFailedResponseHandler: ResponseHandler<APICallError> = { input in
    let response = input.response
    let headers = extractResponseHeaders(from: response.httpResponse)
    let body = try await response.body.collectText()
    let parsed = await safeParseJSON(ParseJSONWithSchemaOptions(text: body, schema: speechErrorSchema))
    let reset = response.statusCode == 502 && body.contains("reset reason: protocol error")
    let message: String
    if case .success(let error, _) = parsed { message = error.error.message }
    else if reset {
        message = "Azure Speech could not synthesize the request. Check that the voice is available for this model and that the style is supported by the voice."
    } else if response.statusCode == 400 {
        message = "Azure Speech request failed with status 400. Check the voice name, style, and output format."
    } else { message = "Azure Speech request failed with status \(response.statusCode)." }
    return .init(value: APICallError(message: message, url: input.url, requestBodyValues: input.requestBodyValues,
        statusCode: reset ? 400 : response.statusCode, responseHeaders: headers, responseBody: body,
        isRetryable: reset ? false : nil), responseHeaders: headers)
}
