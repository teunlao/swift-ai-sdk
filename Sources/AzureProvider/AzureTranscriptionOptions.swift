import AISDKProvider
import AISDKProviderUtils

public struct AzureTranscriptionModelSpeechOptions: Sendable, Encodable, Equatable {
    public enum Timestamps: String, Sendable, Encodable { case word, segment, none }
    public enum Style: String, Sendable, Encodable { case verbatim, clean }
    public struct Diarization: Sendable, Encodable, Equatable {
        public var enabled: Bool
        public init(enabled: Bool) { self.enabled = enabled }
    }
    public struct PhraseList: Sendable, Encodable, Equatable {
        public var phrases: [String]
        public init(phrases: [String]) { self.phrases = phrases }
    }
    public var timestamps: Timestamps?
    public var transcribeStyle: Style?
    public var locales: [String]?
    public var diarization: Diarization?
    public var phraseList: PhraseList?
    public init(timestamps: Timestamps? = nil, transcribeStyle: Style? = nil, locales: [String]? = nil,
                diarization: Diarization? = nil, phraseList: PhraseList? = nil) {
        self.timestamps = timestamps; self.transcribeStyle = transcribeStyle; self.locales = locales
        self.diarization = diarization; self.phraseList = phraseList
    }
}

public struct AzureTranscriptionModelMaiOptions: Sendable, Encodable, Equatable {
    public var language: String?
    public init(language: String? = nil) { self.language = language }
}

public struct AzureTranscriptionModelOptions: Sendable, Encodable, Equatable {
    public enum API: String, Sendable, Encodable { case openai, speech, mai }
    public var api: API?
    public var timestamps: AzureTranscriptionModelSpeechOptions.Timestamps?
    public var transcribeStyle: AzureTranscriptionModelSpeechOptions.Style?
    public var locales: [String]?
    public var diarization: AzureTranscriptionModelSpeechOptions.Diarization?
    public var phraseList: AzureTranscriptionModelSpeechOptions.PhraseList?
    public var language: String?
    public init(api: API? = nil, timestamps: AzureTranscriptionModelSpeechOptions.Timestamps? = nil,
                transcribeStyle: AzureTranscriptionModelSpeechOptions.Style? = nil, locales: [String]? = nil,
                diarization: AzureTranscriptionModelSpeechOptions.Diarization? = nil,
                phraseList: AzureTranscriptionModelSpeechOptions.PhraseList? = nil, language: String? = nil) {
        self.api = api; self.timestamps = timestamps; self.transcribeStyle = transcribeStyle; self.locales = locales
        self.diarization = diarization; self.phraseList = phraseList; self.language = language
    }
    var speech: AzureTranscriptionModelSpeechOptions {
        .init(timestamps: timestamps, transcribeStyle: transcribeStyle, locales: locales, diarization: diarization, phraseList: phraseList)
    }
    var mai: AzureTranscriptionModelMaiOptions { .init(language: language) }
}

private let speechProperties: JSONObject = [
    "timestamps": ["type": "string", "enum": ["word", "segment", "none"]],
    "transcribeStyle": ["type": "string", "enum": ["verbatim", "clean"]],
    "locales": ["type": "array", "items": ["type": "string"], "minItems": 1, "maxItems": 1],
    "diarization": ["type": "object", "required": ["enabled"], "additionalProperties": false, "properties": ["enabled": ["type": "boolean"]]],
    "phraseList": ["type": "object", "required": ["phrases"], "additionalProperties": false, "properties": ["phrases": ["type": "array", "items": ["type": "string"]]]]
]
private let maiProperties: JSONObject = ["language": ["type": "string", "minLength": 1]]
private let allProperties = speechProperties.merging(maiProperties) { _, rhs in rhs }.merging([
    "api": ["type": "string", "enum": ["openai", "speech", "mai"]]
]) { _, rhs in rhs }

private func optionIssue(_ key: String) -> SchemaValidationIssuesError {
    .init(vendor: "azure", issues: "Invalid transcription option: \(key)")
}

private func parseTranscriptionOptions(_ value: Any, properties: JSONObject) throws -> AzureTranscriptionModelOptions {
    let json = try jsonValue(from: value)
    guard case .object(let fields) = json, Set(fields.keys).isSubset(of: Set(properties.keys)) else { throw optionIssue("object") }
    func string(_ key: String) throws -> String? {
        guard let value = fields[key] else { return nil }
        guard case .string(let value) = value else { throw optionIssue(key) }
        return value
    }
    func strings(_ value: JSONValue, key: String) throws -> [String] {
        guard case .array(let entries) = value else { throw optionIssue(key) }
        return try entries.map {
            guard case .string(let value) = $0 else { throw optionIssue(key) }
            return value
        }
    }
    var result = AzureTranscriptionModelOptions()
    if let name = try string("api") {
        guard let api = AzureTranscriptionModelOptions.API(rawValue: name) else { throw optionIssue("api") }
        result.api = api
    }
    if let name = try string("timestamps") {
        guard let timestamps = AzureTranscriptionModelSpeechOptions.Timestamps(rawValue: name) else { throw optionIssue("timestamps") }
        result.timestamps = timestamps
    }
    if let name = try string("transcribeStyle") {
        guard let style = AzureTranscriptionModelSpeechOptions.Style(rawValue: name) else { throw optionIssue("transcribeStyle") }
        result.transcribeStyle = style
    }
    if let value = fields["locales"] {
        let values = try strings(value, key: "locales")
        guard values.count == 1 else { throw optionIssue("locales") }
        result.locales = values
    }
    if let value = fields["diarization"] {
        guard case .object(let values) = value, Set(values.keys) == ["enabled"], case .bool(let enabled) = values["enabled"] else { throw optionIssue("diarization") }
        result.diarization = .init(enabled: enabled)
    }
    if let value = fields["phraseList"] {
        guard case .object(let values) = value, Set(values.keys) == ["phrases"], let phrases = values["phrases"] else { throw optionIssue("phraseList") }
        result.phraseList = .init(phrases: try strings(phrases, key: "phraseList.phrases"))
    }
    if let language = try string("language") {
        guard !language.isEmpty else { throw optionIssue("language") }
        result.language = language
    }
    return result
}

private func transcriptionSchema<T>(properties: JSONObject, project: @escaping @Sendable (AzureTranscriptionModelOptions) -> T) -> FlexibleSchema<T> {
    FlexibleSchema(Schema(jsonSchemaResolver: { ["type": "object", "additionalProperties": false, "properties": .object(properties)] }, validator: { value in
        do { return .success(value: project(try parseTranscriptionOptions(value, properties: properties))) }
        catch { return .failure(error: TypeValidationError.wrap(value: value, cause: error)) }
    }))
}

public let azureTranscriptionModelOptions = transcriptionSchema(properties: allProperties) { $0 }
public let azureSpeechTranscriptionModelOptions = transcriptionSchema(properties: speechProperties) { $0.speech }
public let azureMaiTranscriptionModelOptions = transcriptionSchema(properties: maiProperties) { $0.mai }

struct MaiTranscribeModel {
    let name: String
    let supportsTimestamps: Bool
}
func maiTranscribeModel(_ id: String) -> MaiTranscribeModel? {
    switch id.lowercased() {
    case "mai-transcribe-2": .init(name: "MAI-Transcribe-2", supportsTimestamps: true)
    case "mai-transcribe-1.5": .init(name: "MAI-Transcribe-1.5", supportsTimestamps: false)
    default: nil
    }
}
func isMaiTranscribeStreaming(_ id: String) -> Bool { id.lowercased() == "mai-transcribe-2-streaming" }
