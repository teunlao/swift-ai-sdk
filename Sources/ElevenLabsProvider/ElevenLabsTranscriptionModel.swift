import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class ElevenLabsTranscriptionModel: TranscriptionModelV4 {
    private let modelIdentifier: ElevenLabsTranscriptionModelId
    private let config: ElevenLabsConfig

    public init(modelId: ElevenLabsTranscriptionModelId, config: ElevenLabsConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    public func doGenerate(options: TranscriptionModelV4CallOptions) async throws -> TranscriptionModelV4Result {
        guard modelIdentifier != .scribeV2Realtime else {
            throw UnsupportedFunctionalityError(functionality: "non-streaming transcription with \(modelId)")
        }
        let timestamp = config.currentDate()
        let parsed = try await parseProviderOptions(
            provider: "elevenlabs", providerOptions: options.providerOptions, schema: elevenLabsTranscriptionModelOptionsSchema
        )
        var warnings: [SharedV4Warning] = []
        if parsed?.streaming != nil {
            warnings.append(.unsupported(feature: "providerOptions.elevenlabs.streaming", details: "ElevenLabs batch transcription does not support streaming options."))
        }
        let data: Data
        switch options.audio {
        case .binary(let value): data = value
        case .base64(let value): data = try convertBase64ToData(value)
        }
        var form = MultipartFormDataBuilder()
        var requestBodyValues: [String: Any] = [:]
        func appendField(_ name: String, _ value: String) {
            form.appendField(name: name, value: value)
            requestBodyValues[name] = value
        }
        appendField("model_id", modelId)
        form.appendFile(name: "file", filename: "audio.\(mediaTypeToExtension(options.mediaType))", contentType: options.mediaType, data: data)
        requestBodyValues["file"] = data
        appendField("diarize", String(parsed?.diarize ?? true))
        if let value = parsed?.languageCode { appendField("language_code", value) }
        if let value = parsed?.tagAudioEvents { appendField("tag_audio_events", String(value)) }
        if let value = parsed?.numSpeakers { appendField("num_speakers", String(value)) }
        if let value = parsed?.timestampsGranularity { appendField("timestamps_granularity", value.rawValue) }
        if let value = parsed?.fileFormat { appendField("file_format", value.rawValue) }
        let response = try await postToAPI(
            url: config.url(.init(modelId: modelId, path: "/v1/speech-to-text")),
            headers: combineHeaders(try config.headers(), options.headers).compactMapValues { $0 },
            body: PostBody(content: .multipartFormData(form), values: requestBodyValues),
            failedResponseHandler: elevenLabsFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: transcriptionResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )
        let value = response.value
        return .init(
            text: value.text,
            segments: value.words?.map { .init(text: $0.text, startSecond: $0.start ?? 0, endSecond: $0.end ?? 0) } ?? [],
            language: value.languageCode,
            durationInSeconds: value.words?.last?.end,
            warnings: warnings,
            response: .init(timestamp: timestamp, modelId: modelId, headers: response.responseHeaders, body: response.rawValue),
            providerMetadata: value.words.map { ["elevenlabs": ["words": .array($0.map { .object($0.metadata) })]] }
        )
    }
}

private struct TranscriptionResponse: Decodable, Sendable {
    struct Word: Decodable, Sendable {
        enum Kind: String, Decodable { case word, spacing, audio_event }

        struct CharacterTiming: Decodable, Sendable {
            let metadata: JSONObject
            enum CodingKeys: String, CodingKey, CaseIterable { case text, start, end }
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                _ = try container.decode(String.self, forKey: .text)
                _ = try container.decodeIfPresent(Double.self, forKey: .start)
                _ = try container.decodeIfPresent(Double.self, forKey: .end)
                var result: JSONObject = [:]
                for key in CodingKeys.allCases where container.contains(key) {
                    result[key.rawValue] = try container.decode(JSONValue.self, forKey: key)
                }
                metadata = result
            }
        }

        let text: String
        let start: Double?
        let end: Double?
        let metadata: JSONObject

        enum CodingKeys: String, CodingKey, CaseIterable {
            case text, type, start, end, speaker_id, characters
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            text = try container.decode(String.self, forKey: .text)
            _ = try container.decode(Kind.self, forKey: .type)
            start = try container.decodeIfPresent(Double.self, forKey: .start)
            end = try container.decodeIfPresent(Double.self, forKey: .end)
            _ = try container.decodeIfPresent(String.self, forKey: .speaker_id)
            let characters = try container.decodeIfPresent([CharacterTiming].self, forKey: .characters)
            var result: JSONObject = [:]
            for key in CodingKeys.allCases where container.contains(key) {
                result[key.rawValue] = try container.decode(JSONValue.self, forKey: key)
            }
            if let characters { result["characters"] = .array(characters.map { .object($0.metadata) }) }
            metadata = result
        }
    }

    let languageCode: String
    let languageProbability: Double
    let text: String
    let words: [Word]?

    enum CodingKeys: String, CodingKey {
        case languageCode = "language_code"
        case languageProbability = "language_probability"
        case text, words
    }
}

private let transcriptionResponseSchema = FlexibleSchema(
    Schema<TranscriptionResponse>.codable(TranscriptionResponse.self, jsonSchema: .object(["type": .string("object")]))
)
