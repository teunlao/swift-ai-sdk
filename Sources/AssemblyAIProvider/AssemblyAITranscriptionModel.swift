import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/assemblyai/src/assemblyai-transcription-model.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public final class AssemblyAITranscriptionModel: TranscriptionModelV3 {
    public struct Config: Sendable {
        public struct RequestOptions: Sendable {
            public let modelId: AssemblyAITranscriptionModelId
            public let path: String

            public init(modelId: AssemblyAITranscriptionModelId, path: String) {
                self.modelId = modelId
                self.path = path
            }
        }

        public let provider: String
        public let url: @Sendable (RequestOptions) -> String
        public let headers: @Sendable () -> [String: String?]
        public let fetch: FetchFunction?
        public let currentDate: @Sendable () -> Date

        public init(
            provider: String,
            url: @escaping @Sendable (RequestOptions) -> String,
            headers: @escaping @Sendable () -> [String: String?],
            fetch: FetchFunction?,
            currentDate: @escaping @Sendable () -> Date
        ) {
            self.provider = provider
            self.url = url
            self.headers = headers
            self.fetch = fetch
            self.currentDate = currentDate
        }
    }

    private struct PreparedRequest {
        let body: [String: JSONValue]
        let warnings: [TranscriptionModelV3CallWarning]
    }

    private let modelIdentifier: AssemblyAITranscriptionModelId
    private let config: Config

    public init(modelId: AssemblyAITranscriptionModelId, config: Config) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    public func doGenerate(options: TranscriptionModelV3CallOptions) async throws -> TranscriptionModelV3Result {
        let timestamp = config.currentDate()

        let audioData: Data
        switch options.audio {
        case .binary(let data):
            audioData = data
        case .base64(let base64):
            audioData = try convertBase64ToData(base64)
        }

        // Upload audio first
        var uploadHeaders = combineHeaders(
            config.headers(),
            options.headers?.mapValues { Optional($0) }
        )
        uploadHeaders["Content-Type"] = "application/octet-stream"

        let uploadResponse = try await postToAPI(
            url: config.url(.init(modelId: modelIdentifier, path: "/v2/upload")),
            headers: uploadHeaders.compactMapValues { $0 },
            body: PostBody(content: .data(audioData), values: nil),
            failedResponseHandler: assemblyaiFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: assemblyaiUploadResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let prepared = try await prepareRequest(options: options)
        var payload = prepared.body
        payload["audio_url"] = .string(uploadResponse.value.upload_url)

        let transcriptResponse = try await postJsonToAPI(
            url: config.url(.init(modelId: modelIdentifier, path: "/v2/transcript")),
            headers: combineHeaders(config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 },
            body: JSONValue.object(payload),
            failedResponseHandler: assemblyaiFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: assemblyaiTranscriptionResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let result = transcriptResponse.value
        let segments = (result.words ?? []).map {
            TranscriptionModelV3Result.Segment(text: $0.text, startSecond: $0.start, endSecond: $0.end)
        }

        let duration = result.audio_duration ?? result.words?.last?.end

        return TranscriptionModelV3Result(
            text: result.text ?? "",
            segments: segments,
            language: result.language_code,
            durationInSeconds: duration,
            warnings: prepared.warnings,
            request: nil,
            response: TranscriptionModelV3Result.ResponseInfo(
                timestamp: timestamp,
                modelId: modelIdentifier.rawValue,
                headers: transcriptResponse.responseHeaders,
                body: transcriptResponse.rawValue
            ),
            providerMetadata: nil
        )
    }

    private func prepareRequest(options: TranscriptionModelV3CallOptions) async throws -> PreparedRequest {
        let parsedOptions: AssemblyAITranscriptionOptions? = try await parseProviderOptions(
            provider: "assemblyai",
            providerOptions: options.providerOptions,
            schema: assemblyaiTranscriptionOptionsSchema
        )

        var body: [String: JSONValue] = [
            "speech_model": .string(modelIdentifier.rawValue)
        ]

        if let opts = parsedOptions {
            if let value = opts.audioEndAt {
                body["audio_end_at"] = .number(Double(value))
            }
            if let value = opts.audioStartFrom {
                body["audio_start_from"] = .number(Double(value))
            }
            if let value = opts.autoChapters {
                body["auto_chapters"] = .bool(value)
            }
            if let value = opts.autoHighlights {
                body["auto_highlights"] = .bool(value)
            }
            if let value = opts.boostParam {
                body["boost_param"] = .string(value)
            }
            if let value = opts.contentSafety {
                body["content_safety"] = .bool(value)
            }
            if let value = opts.contentSafetyConfidence {
                body["content_safety_confidence"] = .number(Double(value))
            }
            if let value = opts.customSpelling {
                let entries = value.map { entry -> JSONValue in
                    .object([
                        "from": .array(entry.from.map(JSONValue.string)),
                        "to": .string(entry.to)
                    ])
                }
                body["custom_spelling"] = .array(entries)
            }
            if let value = opts.disfluencies {
                body["disfluencies"] = .bool(value)
            }
            if let value = opts.entityDetection {
                body["entity_detection"] = .bool(value)
            }
            if let value = opts.filterProfanity {
                body["filter_profanity"] = .bool(value)
            }
            if let value = opts.formatText {
                body["format_text"] = .bool(value)
            }
            if let value = opts.iabCategories {
                body["iab_categories"] = .bool(value)
            }
            if let value = opts.languageCode {
                body["language_code"] = .string(value)
            }
            if let value = opts.languageConfidenceThreshold {
                body["language_confidence_threshold"] = .number(value)
            }
            if let value = opts.languageDetection {
                body["language_detection"] = .bool(value)
            }
            if let value = opts.multichannel {
                body["multichannel"] = .bool(value)
            }
            if let value = opts.punctuate {
                body["punctuate"] = .bool(value)
            }
            if let value = opts.redactPii {
                body["redact_pii"] = .bool(value)
            }
            if let value = opts.redactPiiAudio {
                body["redact_pii_audio"] = .bool(value)
            }
            if let value = opts.redactPiiAudioQuality {
                body["redact_pii_audio_quality"] = .string(value)
            }
            if let value = opts.redactPiiPolicies {
                body["redact_pii_policies"] = .array(value.map(JSONValue.string))
            }
            if let value = opts.redactPiiSub {
                body["redact_pii_sub"] = .string(value)
            }
            if let value = opts.sentimentAnalysis {
                body["sentiment_analysis"] = .bool(value)
            }
            if let value = opts.speakerLabels {
                body["speaker_labels"] = .bool(value)
            }
            if let value = opts.speakersExpected {
                body["speakers_expected"] = .number(Double(value))
            }
            if let value = opts.speechThreshold {
                body["speech_threshold"] = .number(value)
            }
            if let value = opts.summarization {
                body["summarization"] = .bool(value)
            }
            if let value = opts.summaryModel {
                body["summary_model"] = .string(value)
            }
            if let value = opts.summaryType {
                body["summary_type"] = .string(value)
            }
            if let value = opts.webhookAuthHeaderName {
                body["webhook_auth_header_name"] = .string(value)
            }
            if let value = opts.webhookAuthHeaderValue {
                body["webhook_auth_header_value"] = .string(value)
            }
            if let value = opts.webhookUrl {
                body["webhook_url"] = .string(value)
            }
            if let value = opts.wordBoost {
                body["word_boost"] = .array(value.map(JSONValue.string))
            }
        }

        return PreparedRequest(body: body, warnings: [])
    }
}

// MARK: - Response Schemas

private struct AssemblyAIUploadResponse: Codable, Sendable {
    let upload_url: String
}

private let assemblyaiUploadResponseSchema = FlexibleSchema(
    Schema<AssemblyAIUploadResponse>.codable(
        AssemblyAIUploadResponse.self,
        jsonSchema: .object([
            "type": .string("object")
        ])
    )
)

private struct AssemblyAITranscriptionWord: Codable, Sendable {
    let start: Double
    let end: Double
    let text: String
}

private struct AssemblyAITranscriptionResponse: Codable, Sendable {
    let text: String?
    let language_code: String?
    let words: [AssemblyAITranscriptionWord]?
    let audio_duration: Double?
}

private let assemblyaiTranscriptionResponseSchema = FlexibleSchema(
    Schema<AssemblyAITranscriptionResponse>.codable(
        AssemblyAITranscriptionResponse.self,
        jsonSchema: .object([
            "type": .string("object")
        ])
    )
)
