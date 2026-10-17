import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class GroqTranscriptionModel: TranscriptionModelV4 {
    struct Config: Sendable {
        struct RequestOptions: Sendable {
            let modelId: GroqTranscriptionModelId
            let path: String
        }

        let provider: String
        let url: @Sendable (RequestOptions) -> String
        let headers: @Sendable () throws -> [String: String?]
        let fetch: FetchFunction?
        let currentDate: @Sendable () -> Date
    }

    private let modelIdentifier: GroqTranscriptionModelId
    private let config: Config

    init(modelId: GroqTranscriptionModelId, config: Config) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    public func doGenerate(options: TranscriptionModelV4CallOptions) async throws -> TranscriptionModelV4Result {
        let timestamp = config.currentDate()
        let groq = try await parseProviderOptions(provider: "groq", providerOptions: options.providerOptions, schema: groqTranscriptionModelOptions)
        let audio: Data
        switch options.audio {
        case .binary(let data): audio = data
        case .base64(let value): audio = try convertBase64ToData(value)
        }
        var formData = MultipartFormDataBuilder()
        var values: [String: Any] = ["model": modelId, "file": audio]
        formData.appendField(name: "model", value: modelId)
        formData.appendFile(name: "file", filename: "audio.\(mediaTypeToExtension(options.mediaType))", contentType: options.mediaType, data: audio)
        func append(_ name: String, _ value: String) {
            formData.appendField(name: name, value: value)
            values[name] = value
        }
        if let value = groq?.language { append("language", value) }
        if let value = groq?.prompt { append("prompt", value) }
        if let value = groq?.responseFormat { append("response_format", value) }
        if let value = groq?.temperature {
            append("temperature", value == 0 ? "0" : String(decoding: try JSONEncoder().encode(value), as: UTF8.self))
        }
        for value in groq?.timestampGranularities ?? [] { append("timestamp_granularities[]", value) }

        let handler: ResponseHandler<Transcription>
        if groq?.responseFormat == "text" {
            handler = { input in
                let response = try await createBinaryResponseHandler()(input)
                var bytes = response.value
                // Match TextDecoder's default handling of a leading UTF-8 BOM.
                if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes.removeFirst(3) }
                let text = String(decoding: bytes, as: UTF8.self)
                return .init(value: .init(text: text, segments: [], language: nil, duration: nil), rawValue: text, responseHeaders: response.responseHeaders)
            }
        } else {
            handler = { input in
                let response = try await createJsonResponseHandler(responseSchema: groqTranscriptionResponseSchema)(input)
                return .init(value: response.value.transcription, rawValue: response.rawValue, responseHeaders: response.responseHeaders)
            }
        }
        let response = try await postToAPI(
            url: config.url(.init(modelId: modelIdentifier, path: "/audio/transcriptions")),
            headers: combineHeaders(try config.headers(), options.headers?.mapValues(Optional.some)).compactMapValues { $0 },
            body: PostBody(content: .multipartFormData(formData), values: values),
            failedResponseHandler: groqFailedResponseHandler,
            successfulResponseHandler: handler,
            isAborted: options.abortSignal,
            fetch: config.fetch
        )
        return .init(
            text: response.value.text,
            segments: response.value.segments,
            language: response.value.language,
            durationInSeconds: response.value.duration,
            response: .init(timestamp: timestamp, modelId: modelId, headers: response.responseHeaders, body: response.rawValue)
        )
    }
}

private struct Transcription: Sendable {
    let text: String
    let segments: [TranscriptionModelV4Result.Segment]
    let language: String?
    let duration: Double?
}

private struct GroqTranscriptionResponse: Decodable, Sendable {
    struct Metadata: Decodable, Sendable {
        let id: String
    }

    struct Segment: Decodable, Sendable {
        let id: Double
        let seek: Double
        let start: Double
        let end: Double
        let text: String
        let tokens: [Double]
        let temperature: Double
        let averageLogProbability: Double
        let compressionRatio: Double
        let noSpeechProbability: Double

        private enum CodingKeys: String, CodingKey {
            case id, seek, start, end, text, tokens, temperature
            case averageLogProbability = "avg_logprob"
            case compressionRatio = "compression_ratio"
            case noSpeechProbability = "no_speech_prob"
        }
    }

    struct Word: Decodable, Sendable {
        let word: String
        let start: Double
        let end: Double
    }

    let text: String
    let xGroq: Metadata
    let task: String?
    let language: String?
    let duration: Double?
    let segments: [Segment]?
    let words: [Word]?

    private enum CodingKeys: String, CodingKey {
        case text, task, language, duration, segments, words
        case xGroq = "x_groq"
    }

    var transcription: Transcription {
        .init(
            text: text,
            segments: segments?.map { .init(text: $0.text, startSecond: $0.start, endSecond: $0.end) }
                ?? words?.map { .init(text: $0.word, startSecond: $0.start, endSecond: $0.end) } ?? [],
            language: language,
            duration: duration
        )
    }
}

private let groqTranscriptionResponseSchema = FlexibleSchema(
    Schema<GroqTranscriptionResponse>.codable(GroqTranscriptionResponse.self, jsonSchema: ["type": "object"])
)
