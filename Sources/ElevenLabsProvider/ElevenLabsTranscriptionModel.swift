import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/elevenlabs/src/elevenlabs-transcription-model.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public final class ElevenLabsTranscriptionModel: TranscriptionModelV3 {
    private let modelIdentifier: ElevenLabsTranscriptionModelId
    private let config: ElevenLabsConfig

    public init(modelId: ElevenLabsTranscriptionModelId, config: ElevenLabsConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    public func doGenerate(options: TranscriptionModelV3CallOptions) async throws -> TranscriptionModelV3Result {
        let prepared = try await prepareRequest(options: options)

        var headers = combineHeaders(config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 }
        headers["Content-Type"] = prepared.contentType

        let response = try await postToAPI(
            url: config.url(.init(modelId: modelIdentifier.rawValue, path: "/v1/speech-to-text")),
            headers: headers,
            body: PostBody(content: .data(prepared.body), values: nil),
            failedResponseHandler: elevenLabsFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: elevenLabsTranscriptionResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let currentDate = config.currentDate()
        let mappedSegments = response.value.words?.map { word -> TranscriptionModelV3Result.Segment in
            TranscriptionModelV3Result.Segment(
                text: word.text,
                startSecond: word.start ?? 0,
                endSecond: word.end ?? 0
            )
        } ?? []

        let duration = response.value.words?.last?.end

        return TranscriptionModelV3Result(
            text: response.value.text,
            segments: mappedSegments,
            language: response.value.languageCode,
            durationInSeconds: duration,
            warnings: prepared.warnings,
            request: nil,
            response: TranscriptionModelV3Result.ResponseInfo(
                timestamp: currentDate,
                modelId: modelIdentifier.rawValue,
                headers: response.responseHeaders,
                body: response.rawValue
            )
        )
    }

    // MARK: - Preparation

    private struct PreparedRequest {
        let body: Data
        let contentType: String
        let warnings: [TranscriptionModelV3CallWarning]
    }

    private func prepareRequest(options: TranscriptionModelV3CallOptions) async throws -> PreparedRequest {
        let warnings: [TranscriptionModelV3CallWarning] = []

        let providerOptions = try await parseProviderOptions(
            provider: "elevenlabs",
            providerOptions: options.providerOptions,
            schema: elevenLabsTranscriptionOptionsSchema
        )

        let audioData = try data(from: options.audio)
        let fileExtension = mediaTypeToExtension(options.mediaType)
        let filename = fileExtension.isEmpty ? "audio" : "audio.\(fileExtension)"

        var builder = MultipartFormDataBuilder()
        builder.appendField(name: "model_id", value: modelIdentifier.rawValue)

        let diarizeEnabled = providerOptions?.diarize ?? true
        builder.appendField(name: "diarize", value: diarizeEnabled ? "true" : "false")

        builder.appendFile(name: "file", filename: filename, contentType: options.mediaType, data: audioData)

        if let providerOptions {
            if let language = providerOptions.languageCode {
                builder.appendField(name: "language_code", value: language)
            }
            if let tagAudioEvents = providerOptions.tagAudioEvents {
                builder.appendField(name: "tag_audio_events", value: String(tagAudioEvents))
            }
            if let speakers = providerOptions.numSpeakers {
                builder.appendField(name: "num_speakers", value: String(speakers))
            }
            if let granularity = providerOptions.timestampsGranularity {
                builder.appendField(name: "timestamps_granularity", value: granularity.rawValue)
            }
            if let fileFormat = providerOptions.fileFormat {
                builder.appendField(name: "file_format", value: fileFormat.rawValue)
            }
        }

        let (body, contentType) = builder.build()
        return PreparedRequest(body: body, contentType: contentType, warnings: warnings)
    }

    private func data(from audio: TranscriptionModelV3Audio) throws -> Data {
        switch audio {
        case .binary(let data):
            return data
        case .base64(let base64):
            return try convertBase64ToData(base64)
        }
    }
}

// MARK: - Response Schema

private struct ElevenLabsTranscriptionResponse: Codable, Sendable {
    struct Word: Codable, Sendable {
        let text: String
        let type: String
        let start: Double?
        let end: Double?
        let speakerId: String?
        let characters: [CharacterTiming]?

        struct CharacterTiming: Codable, Sendable {
            let text: String
            let start: Double?
            let end: Double?

            enum CodingKeys: String, CodingKey {
                case text
                case start
                case end
            }
        }

        enum CodingKeys: String, CodingKey {
            case text
            case type
            case start
            case end
            case speakerId = "speaker_id"
            case characters
        }
    }

    let languageCode: String
    let languageProbability: Double
    let text: String
    let words: [Word]?

    enum CodingKeys: String, CodingKey {
        case languageCode = "language_code"
        case languageProbability = "language_probability"
        case text
        case words
    }
}

private let elevenLabsTranscriptionResponseSchema = FlexibleSchema(
    Schema<ElevenLabsTranscriptionResponse>.codable(
        ElevenLabsTranscriptionResponse.self,
        jsonSchema: .object(["type": .string("object")])
    )
)
