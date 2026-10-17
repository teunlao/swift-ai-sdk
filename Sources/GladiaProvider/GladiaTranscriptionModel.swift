import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class GladiaTranscriptionModel: TranscriptionModelV4 {
    private let config: GladiaConfig
    init(config: GladiaConfig) { self.config = config }
    public var provider: String { config.provider }
    public var modelId: String { "default" }

    public func doGenerate(options: TranscriptionModelV4CallOptions) async throws -> TranscriptionModelV4Result {
        let now = config.currentDate()
        let audio: Data
        switch options.audio {
        case .binary(let value): audio = value
        case .base64(let value): audio = try convertBase64ToData(value)
        }
        var form = MultipartFormDataBuilder()
        form.appendFile(name: "audio", filename: "audio.\(mediaTypeToExtension(options.mediaType))", contentType: options.mediaType, data: audio)
        let upload = try await postToAPI(
            url: "https://api.gladia.io/v2/upload", headers: combineHeaders(try config.headers(), options.headers?.mapValues(Optional.some)).compactMapValues { $0 },
            body: .init(content: .multipartFormData(form), values: nil), failedResponseHandler: gladiaFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: uploadSchema), isAborted: options.abortSignal, fetch: config.fetch
        )
        let settings = try await parseProviderOptions(provider: "gladia", providerOptions: options.providerOptions, schema: gladiaTranscriptionModelOptionsSchema)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        var body = try settings.map { try JSONDecoder().decode(JSONObject.self, from: encoder.encode($0)) } ?? [:]
        body["audio_url"] = .string(upload.value.audioURL)
        let initialized = try await postJsonToAPI(
            url: "https://api.gladia.io/v2/pre-recorded", headers: combineHeaders(try config.headers(), options.headers?.mapValues(Optional.some)).compactMapValues { $0 },
            body: JSONValue.object(body), failedResponseHandler: gladiaFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: initializeSchema), isAborted: options.abortSignal, fetch: config.fetch
        )
        let start = Date()
        var cause: (any Error)?
        while true {
            if Date().timeIntervalSince(start) > 60 {
                throw JobError(name: "TranscriptionJobPollingTimedOut", message: "Transcription job polling timed out", cause: cause)
            }
            let polled = try await getFromAPI(
                url: initialized.value.resultURL, headers: combineHeaders(try config.headers(), options.headers?.mapValues(Optional.some)).compactMapValues { $0 },
                failedResponseHandler: gladiaFailedResponseHandler,
                successfulResponseHandler: createJsonResponseHandler(responseSchema: resultSchema), isAborted: options.abortSignal, fetch: config.fetch,
                validateUrl: true, credentialedOrigin: "https://api.gladia.io", trustedOrigin: "https://api.gladia.io"
            )
            let value = polled.value
            cause = InvalidResponseDataError(data: value.fields, message: "Gladia transcription job response")
            if value.status == .error { throw JobError(name: "TranscriptionJobFailed", message: "Transcription job failed", cause: cause) }
            if value.status == .done {
                guard let result = value.result else { throw JobError(name: "TranscriptionResultEmpty", message: "Transcription result is empty", cause: cause) }
                return .init(text: result.transcription.fullTranscript,
                             segments: result.transcription.utterances.map { .init(text: $0.text, startSecond: $0.start, endSecond: $0.end) },
                             language: result.transcription.languages.first, durationInSeconds: result.metadata.audioDuration,
                             response: .init(timestamp: now, modelId: modelId, headers: polled.responseHeaders), providerMetadata: ["gladia": value.fields])
            }
            try await delay(1000)
        }
    }
}

private struct UploadResponse: Decodable {
    let audioURL: String
    enum CodingKeys: String, CodingKey { case audioURL = "audio_url" }
}
private struct InitializeResponse: Decodable {
    let resultURL: String
    enum CodingKeys: String, CodingKey { case resultURL = "result_url" }
}
private func decodeFields<Key: CodingKey & CaseIterable>(_ container: KeyedDecodingContainer<Key>) throws -> JSONObject {
    var result: JSONObject = [:]
    for key in Key.allCases where container.contains(key) { result[key.stringValue] = try container.decode(JSONValue.self, forKey: key) }
    return result
}
private struct TaskResponse: Decodable {
    enum Status: String, Decodable { case queued, processing, done, error }
    struct Result: Decodable {
        struct Metadata: Decodable {
            let audioDuration: Double
            enum CodingKeys: String, CodingKey { case audioDuration = "audio_duration" }
        }
        struct Transcription: Decodable {
            struct Utterance: Decodable {
                struct Word: Decodable {
                    let fields: JSONObject
                    enum Keys: String, CodingKey, CaseIterable { case word, start, end, confidence }
                    init(from decoder: Decoder) throws {
                        let value = try decoder.container(keyedBy: Keys.self)
                        _ = try value.decode(String.self, forKey: .word)
                        _ = try value.decode(Double.self, forKey: .start)
                        _ = try value.decode(Double.self, forKey: .end)
                        _ = try value.decodeIfPresent(Double.self, forKey: .confidence)
                        fields = try decodeFields(value)
                    }
                }
                let start: Double
                let end: Double
                let text: String
                let fields: JSONObject
                enum Keys: String, CodingKey, CaseIterable { case start, end, text, speaker, confidence, language, words }
                init(from decoder: Decoder) throws {
                    let value = try decoder.container(keyedBy: Keys.self)
                    start = try value.decode(Double.self, forKey: .start)
                    end = try value.decode(Double.self, forKey: .end)
                    text = try value.decode(String.self, forKey: .text)
                    if let speaker = try value.decodeIfPresent(JSONValue.self, forKey: .speaker) {
                        switch speaker {
                        case .string, .number: break
                        default: throw DecodingError.dataCorruptedError(forKey: .speaker, in: value, debugDescription: "Expected a string or number")
                        }
                    }
                    _ = try value.decodeIfPresent(Double.self, forKey: .confidence)
                    _ = try value.decodeIfPresent(String.self, forKey: .language)
                    let words = try value.decodeIfPresent([Word].self, forKey: .words)
                    var parsed = try decodeFields(value)
                    if let words { parsed["words"] = .array(words.map { .object($0.fields) }) }
                    fields = parsed
                }
            }
            let fullTranscript: String
            let languages: [String]
            let utterances: [Utterance]
            enum CodingKeys: String, CodingKey { case fullTranscript = "full_transcript", languages, utterances }
            var fields: JSONObject { ["full_transcript": .string(fullTranscript), "languages": .array(languages.map(JSONValue.string)), "utterances": .array(utterances.map { .object($0.fields) })] }
        }
        let metadata: Metadata
        let transcription: Transcription
        var fields: JSONObject { ["metadata": ["audio_duration": .number(metadata.audioDuration)], "transcription": .object(transcription.fields)] }
    }
    let status: Status
    let result: Result?
    let fields: JSONObject
    enum Keys: String, CodingKey, CaseIterable { case status, result }
    init(from decoder: Decoder) throws {
        let value = try decoder.container(keyedBy: Keys.self)
        status = try value.decode(Status.self, forKey: .status)
        result = try value.decodeIfPresent(Result.self, forKey: .result)
        var parsed = try decodeFields(value)
        if let result { parsed["result"] = .object(result.fields) }
        fields = parsed
    }
}
private let uploadSchema = FlexibleSchema(Schema<UploadResponse>.codable(UploadResponse.self, jsonSchema: ["type": "object"]))
private let initializeSchema = FlexibleSchema(Schema<InitializeResponse>.codable(InitializeResponse.self, jsonSchema: ["type": "object"]))
private let resultSchema = FlexibleSchema(Schema<TaskResponse>.codable(TaskResponse.self, jsonSchema: ["type": "object"]))
private struct JobError: AISDKError {
    static let errorDomain = "vercel.ai.error"
    let name: String
    let message: String
    let cause: (any Error)?
}
