import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct AzureSpeechTranscriptionConfig: Sendable {
    public let url: @Sendable () throws -> String
    public let headers: @Sendable () throws -> [String: String?]
    public let fetch: FetchFunction?
    public init(url: @escaping @Sendable () throws -> String, headers: @escaping @Sendable () throws -> [String: String?], fetch: FetchFunction? = nil) {
        self.url = url; self.headers = headers; self.fetch = fetch
    }
}

public final class AzureSpeechTranscriptionModel: TranscriptionModelV4 {
    public let modelId: String
    public let provider = "azure.transcription"
    private let config: AzureSpeechTranscriptionConfig
    public init(modelId: String, config: AzureSpeechTranscriptionConfig) { self.modelId = modelId; self.config = config }

    public func doGenerate(options: TranscriptionModelV4CallOptions) async throws -> TranscriptionModelV4Result {
        try await doGenerate(options: options, speechOptions: .init())
    }

    public func doGenerate(options: TranscriptionModelV4CallOptions, speechOptions: AzureTranscriptionModelSpeechOptions) async throws -> TranscriptionModelV4Result {
        let timestamp = Date()
        let model = maiTranscribeModel(modelId)
        var modelOptions: JSONObject = [:]
        if let timestamps = speechOptions.timestamps ?? (model?.supportsTimestamps == false ? nil : .segment) {
            modelOptions["timestamps"] = .string(timestamps.rawValue)
        }
        if let style = speechOptions.transcribeStyle { modelOptions["transcribeStyle"] = .string(style.rawValue) }
        var definition: JSONObject = ["enhancedMode": ["enabled": true, "model": .string(model?.name ?? modelId), "modelOptions": .object(modelOptions)]]
        if let locales = speechOptions.locales { definition["locales"] = .array(locales.map(JSONValue.string)) }
        if let diarization = speechOptions.diarization { definition["diarization"] = ["enabled": .bool(diarization.enabled)] }
        if let phrases = speechOptions.phraseList { definition["phraseList"] = ["phrases": .array(phrases.phrases.map(JSONValue.string))] }
        let audio: Data
        switch options.audio {
        case .binary(let bytes): audio = bytes
        case .base64(let base64): audio = try convertBase64ToData(base64)
        }
        var form = MultipartFormDataBuilder()
        form.appendFile(name: "audio", filename: "audio.\(mediaTypeToExtension(options.mediaType))", contentType: options.mediaType, data: audio)
        form.appendField(name: "definition", value: String(decoding: try JSONEncoder().encode(JSONValue.object(definition)), as: UTF8.self))
        let response = try await postToAPI(url: config.url(),
            headers: combineHeaders(try config.headers(), options.headers?.mapValues(Optional.some)).compactMapValues { $0 },
            body: .init(content: .multipartFormData(form), values: form.values), failedResponseHandler: batchFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: batchResponseSchema),
            isAborted: options.abortSignal, fetch: config.fetch)
        let phrases = response.value.phrases ?? []
        let languages = Set(phrases.compactMap { phrase -> String? in
            guard let locale = phrase.locale?.unwrapped, !locale.isEmpty else { return nil }
            return locale.components(separatedBy: "-")[0].lowercased()
        })
        let language = languages.count == 1 ? languages.first : nil
        let reportedLanguage = language.flatMap { value in
            value.utf8.count == 2 && value.utf8.allSatisfy { (97...122).contains($0) } ? value : nil
        }
        let segments = phrases.compactMap { phrase -> TranscriptionModelV4Result.Segment? in
            guard let offset = phrase.offsetMilliseconds?.unwrapped, let duration = phrase.durationMilliseconds?.unwrapped else { return nil }
            return .init(text: phrase.text, startSecond: offset / 1000, endSecond: (offset + duration) / 1000)
        }
        let metadata = AzureTranscriptionProviderMetadata(azure: .init(phrases: phrases))
        let providerMetadata = try JSONDecoder().decode(SharedV4ProviderMetadata.self, from: JSONEncoder().encode(metadata))
        return .init(text: response.value.combinedPhrases.map(\.text).joined(separator: " "), segments: segments,
            language: reportedLanguage, durationInSeconds: response.value.durationMilliseconds.map { $0 / 1000 },
            response: .init(timestamp: timestamp, modelId: modelId, headers: response.responseHeaders, body: response.rawValue),
            providerMetadata: providerMetadata)
    }
}

private struct BatchResponse: Decodable, Sendable {
    struct Text: Decodable, Sendable { let text: String }
    let combinedPhrases: [Text]
    let durationMilliseconds: Double?
    let phrases: [AzureTranscriptionProviderMetadata.Phrase]?
}

private let wordSchema: JSONValue = ["type": "object", "required": ["text"], "properties": [
    "text": ["type": "string"], "offsetMilliseconds": ["type": ["number", "null"]], "durationMilliseconds": ["type": ["number", "null"]]
]]
private let phraseSchema: JSONValue = ["type": "object", "required": ["text"], "properties": [
    "text": ["type": "string"], "offsetMilliseconds": ["type": ["number", "null"]], "durationMilliseconds": ["type": ["number", "null"]],
    "locale": ["type": ["string", "null"]], "speaker": ["type": ["number", "null"]], "confidence": ["type": ["number", "null"]],
    "words": ["type": ["array", "null"], "items": wordSchema]
]]
private let batchResponseSchema = FlexibleSchema(Schema.codable(BatchResponse.self, jsonSchema: [
    "type": "object", "required": ["combinedPhrases"], "properties": [
        "combinedPhrases": ["type": "array", "items": ["type": "object", "required": ["text"], "properties": ["text": ["type": "string"]]]],
        "durationMilliseconds": ["type": ["number", "null"]], "phrases": ["type": ["array", "null"], "items": phraseSchema]
    ]
]))

private enum BatchError: Decodable, Sendable {
    struct Detail: Decodable, Sendable { let message: String }
    case nested(Detail)
    case topLevel(String)
    private enum Keys: String, CodingKey { case error, message }
    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: Keys.self)
        if let detail = try? fields.decode(Detail.self, forKey: .error) { self = .nested(detail) }
        else { self = .topLevel(try fields.decode(String.self, forKey: .message)) }
    }
    var message: String {
        switch self { case .nested(let detail): detail.message; case .topLevel(let message): message }
    }
}
private let batchFailedResponseHandler = createJsonErrorResponseHandler(errorSchema: FlexibleSchema(Schema.codable(BatchError.self, jsonSchema: [
    "anyOf": [
        ["type": "object", "required": ["error"], "properties": ["error": ["type": "object", "required": ["message"], "properties": ["message": ["type": "string"]]]]],
        ["type": "object", "required": ["message"], "properties": ["message": ["type": "string"]]]
    ]
])), errorToMessage: { $0.message })
