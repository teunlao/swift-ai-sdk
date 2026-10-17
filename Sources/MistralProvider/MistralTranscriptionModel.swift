import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class MistralTranscriptionModel: TranscriptionModelV4 {
    struct Config: Sendable {
        let provider: String
        let baseURL: String
        let headers: @Sendable () throws -> [String: String?]
        let fetch: FetchFunction?
        let currentDate: (@Sendable () -> Date)?

        init(
            provider: String,
            baseURL: String,
            headers: @escaping @Sendable () throws -> [String: String?] = { [:] },
            fetch: FetchFunction? = nil,
            currentDate: (@Sendable () -> Date)? = nil
        ) {
            self.provider = provider
            self.baseURL = baseURL
            self.headers = headers
            self.fetch = fetch
            self.currentDate = currentDate
        }
    }

    private let modelIdentifier: MistralTranscriptionModelId
    private let config: Config

    init(modelId: MistralTranscriptionModelId, config: Config) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    public func doGenerate(options: TranscriptionModelV4CallOptions) async throws -> TranscriptionModelV4Result {
        let timestamp = config.currentDate?() ?? Date()
        let mistralOptions = try await parseProviderOptions(
            provider: "mistral",
            providerOptions: options.providerOptions,
            schema: mistralTranscriptionModelOptionsSchema
        )
        if mistralOptions?.language != nil, mistralOptions?.timestampGranularities != nil {
            throw InvalidArgumentError(
                argument: "providerOptions",
                message: "providerOptions.mistral.language cannot be combined with providerOptions.mistral.timestampGranularities"
            )
        }

        var formData = MultipartFormDataBuilder()
        var requestBodyValues: [String: Any] = [:]
        func appendField(_ name: String, _ value: String) {
            formData.appendField(name: name, value: value)
            requestBodyValues[name] = value
        }
        appendField("model", modelId)
        let audio: Data
        switch options.audio {
        case .binary(let data): audio = data
        case .base64(let value): audio = try convertBase64ToData(value)
        }
        formData.appendFile(
            name: "file",
            filename: "audio.\(mediaTypeToExtension(options.mediaType))",
            contentType: options.mediaType,
            data: audio
        )
        requestBodyValues["file"] = audio
        if let language = mistralOptions?.language {
            appendField("language", language)
        }
        if let temperature = mistralOptions?.temperature {
            appendField("temperature", temperature == 0 ? "0" : String(decoding: try JSONEncoder().encode(temperature), as: UTF8.self))
        }
        for granularity in mistralOptions?.timestampGranularities ?? [] {
            appendField("timestamp_granularities", granularity.rawValue)
        }
        if let diarize = mistralOptions?.diarize {
            appendField("diarize", String(diarize))
        }
        for bias in mistralOptions?.contextBias ?? [] {
            appendField("context_bias", bias)
        }

        let response = try await postToAPI(
            url: "\(config.baseURL)/audio/transcriptions",
            headers: combineHeaders(try config.headers(), options.headers?.mapValues(Optional.some)).compactMapValues { $0 },
            body: PostBody(content: .multipartFormData(formData), values: requestBodyValues),
            failedResponseHandler: mistralFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: mistralTranscriptionResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )
        let value = response.value
        let segments = (value.segments ?? []).map {
            TranscriptionModelV4Result.Segment(text: $0.text, startSecond: $0.start, endSecond: $0.end)
        }
        var metadata: JSONObject = [:]
        if let usage = value.usage {
            metadata["usage"] = .object(usage.metadata)
        }
        let providerSegments = (value.segments ?? []).compactMap { segment -> JSONValue? in
            guard segment.type != nil || segment.score != nil || segment.speakerId != nil else { return nil }
            var result: JSONObject = [
                "text": .string(segment.text),
                "startSecond": .number(segment.start),
                "endSecond": .number(segment.end)
            ]
            if let type = segment.type { result["type"] = .string(type.rawValue) }
            if let score = segment.score { result["score"] = .number(score) }
            if let speakerId = segment.speakerId { result["speakerId"] = .string(speakerId) }
            return .object(result)
        }
        if !providerSegments.isEmpty {
            metadata["segments"] = .array(providerSegments)
        }
        return TranscriptionModelV4Result(
            text: value.text,
            segments: segments,
            language: value.language,
            durationInSeconds: value.usage?.promptAudioSeconds ?? segments.last?.endSecond,
            usage: value.usage?.values,
            response: .init(timestamp: timestamp, modelId: value.model, headers: response.responseHeaders, body: response.rawValue),
            providerMetadata: metadata.isEmpty ? nil : ["mistral": metadata]
        )
    }
}

private struct MistralTranscriptionResponse: Decodable, Sendable {
    struct Segment: Decodable, Sendable {
        enum SegmentType: String, Decodable, Sendable {
            case transcriptionSegment = "transcription_segment"
        }

        let type: SegmentType?
        let text: String
        let start: Double
        let end: Double
        let score: Double?
        let speakerId: String?

        enum CodingKeys: String, CodingKey {
            case type, text, start, end, score
            case speakerId = "speaker_id"
        }
    }

    struct Usage: Decodable, Sendable {
        let values: JSONObject
        let metadata: JSONObject
        let promptAudioSeconds: Double?

        enum CodingKeys: String, CodingKey, CaseIterable {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
            case promptAudioSeconds = "prompt_audio_seconds"
            case requestCount = "request_count"

            var metadataKey: String {
                switch self {
                case .promptTokens: return "promptTokens"
                case .completionTokens: return "completionTokens"
                case .totalTokens: return "totalTokens"
                case .promptAudioSeconds: return "promptAudioSeconds"
                case .requestCount: return "requestCount"
                }
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            var values: JSONObject = [:]
            var metadata: JSONObject = [:]
            for key in CodingKeys.allCases where container.contains(key) {
                if let value = try container.decodeIfPresent(Double.self, forKey: key) {
                    values[key.rawValue] = .number(value)
                    metadata[key.metadataKey] = .number(value)
                } else {
                    values[key.rawValue] = .null
                }
            }
            self.values = values
            self.metadata = metadata
            self.promptAudioSeconds = try container.decodeIfPresent(Double.self, forKey: .promptAudioSeconds)
        }
    }

    let model: String
    let text: String
    let language: String?
    let segments: [Segment]?
    let usage: Usage?
}

private let mistralTranscriptionResponseSchema = FlexibleSchema(
    Schema<MistralTranscriptionResponse>.codable(
        MistralTranscriptionResponse.self,
        jsonSchema: .object(["type": .string("object")])
    )
)
