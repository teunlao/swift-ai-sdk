import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class AssemblyAITranscriptionModel: TranscriptionModelV4 {
    struct Config: Sendable {
        let provider: String
        let headers: @Sendable () throws -> [String: String?]
        let fetch: FetchFunction?
        var currentDate: @Sendable () -> Date = { Date() }
        var pollingInterval: Duration = .seconds(3)
    }
    private let identifier: AssemblyAITranscriptionModelId
    private let config: Config
    init(modelId: AssemblyAITranscriptionModelId, config: Config) { identifier = modelId; self.config = config }
    public var provider: String { config.provider }
    public var modelId: String { identifier.rawValue }

    public func doGenerate(options: TranscriptionModelV4CallOptions) async throws -> TranscriptionModelV4Result {
        let now = config.currentDate()
        let audio: Data
        switch options.audio {
        case .binary(let value): audio = value
        case .base64(let value): audio = try convertBase64ToData(value)
        }
        let upload = try await postToAPI(
            url: "https://api.assemblyai.com/v2/upload",
            headers: combineHeaders(["Content-Type": "application/octet-stream"], try config.headers(), options.headers?.mapValues(Optional.some)).compactMapValues { $0 },
            body: .init(content: .data(audio), values: audio), failedResponseHandler: assemblyaiFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: assemblyaiUploadResponseSchema), isAborted: options.abortSignal, fetch: config.fetch
        )
        let settings = try await parseProviderOptions(provider: "assemblyai", providerOptions: options.providerOptions, schema: assemblyaiTranscriptionModelOptionsSchema)
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        var body = try settings.map { try JSONDecoder().decode(JSONObject.self, from: encoder.encode($0)) } ?? [:]
        var warnings: [SharedV4Warning] = []
        let docs = "https://www.assemblyai.com/docs/pre-recorded-audio/select-the-speech-model"
        if modelId == "best" {
            body["speech_model"] = .string(modelId)
            warnings.append(.deprecated(setting: "model '\(modelId)'", message: "The 'best' model is a legacy AssemblyAI model. Use 'universal-3-5-pro' instead. See documentation: \(docs)"))
        } else {
            body["speech_models"] = [.string(modelId)]
            if modelId == "universal-3-pro" {
                warnings.append(.other(message: "'universal-3-5-pro' is AssemblyAI's latest flagship model and is set to replace 'universal-3-pro'. See \(docs)"))
            } else if modelId == "universal-2" {
                warnings.append(.other(message: "'universal-3-5-pro' is AssemblyAI's latest flagship model. See \(docs)"))
            }
        }
        if let settings {
            var boost: [String] = []
            if settings.wordBoost != nil { boost.append("wordBoost") }
            if settings.boostParam != nil { boost.append("boostParam") }
            if !boost.isEmpty {
                warnings.append(.deprecated(setting: boost.joined(separator: ", "), message: "'wordBoost' and 'boostParam' are deprecated and are rejected by 'universal-3-pro' / 'universal-3-5-pro' and 'slam-1'. Use 'keytermsPrompt' instead."))
            }
            if (settings.redactPiiReturnUnredacted != nil || settings.redactStaticEntities != nil), settings.redactPii != true {
                warnings.append(.other(message: "'redactPiiReturnUnredacted' and 'redactStaticEntities' require 'redactPii' to be enabled; AssemblyAI rejects the request otherwise."))
            }
            if settings.redactPiiAudioOptions != nil, settings.redactPiiAudio != true {
                warnings.append(.other(message: "'redactPiiAudioOptions' only applies when 'redactPiiAudio' is enabled; it is otherwise ignored."))
            }
            if settings.languageCode != nil, settings.languageDetection == true {
                warnings.append(.other(message: "'languageDetection' cannot be combined with an explicit 'languageCode'; AssemblyAI rejects requests that set both."))
            }
        }
        body["audio_url"] = .string(upload.value.uploadURL)
        let submitted = try await postJsonToAPI(
            url: "https://api.assemblyai.com/v2/transcript", headers: combineHeaders(try config.headers(), options.headers?.mapValues(Optional.some)).compactMapValues { $0 },
            body: JSONValue.object(body), failedResponseHandler: assemblyaiFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: assemblyaiSubmitResponseSchema), isAborted: options.abortSignal, fetch: config.fetch
        )
        while true {
            try Task.checkCancellation()
            if options.abortSignal?() == true { throw CancellationError() }
            let completed = try await getFromAPI(
                url: "https://api.assemblyai.com/v2/transcript/\(submitted.value.id)",
                headers: combineHeaders(try config.headers(), options.headers?.mapValues(Optional.some)).compactMapValues { $0 },
                failedResponseHandler: assemblyaiFailedResponseHandler,
                successfulResponseHandler: createJsonResponseHandler(responseSchema: assemblyaiTranscriptionResponseSchema), isAborted: options.abortSignal, fetch: config.fetch
            )
            let result = completed.value
            if result.status == .error { throw TranscriptionFailure(message: "Transcription failed: \(result.error ?? "Unknown error")") }
            if result.status == .completed {
                guard let rawValue = completed.rawValue, case .object(let raw) = try jsonValue(from: rawValue) else {
                    throw InvalidResponseDataError(data: completed.rawValue, message: "Expected a transcript object")
                }
                var metadata: JSONObject = [:]
                for (wire, field) in [("utterances", "utterances"), ("sentiment_analysis_results", "sentimentAnalysisResults"), ("entities", "entities"), ("content_safety_labels", "contentSafetyLabels"), ("iab_categories_result", "iabCategoriesResult"), ("auto_highlights_result", "autoHighlightsResult")] {
                    if let value = raw[wire], value != .null { metadata[field] = value }
                }
                return .init(text: result.text ?? "", segments: result.words?.map { .init(text: $0.text, startSecond: $0.start / 1000, endSecond: $0.end / 1000) } ?? [],
                             language: result.languageCode, durationInSeconds: result.audioDuration ?? result.words?.last.map { $0.end / 1000 }, warnings: warnings,
                             response: .init(timestamp: now, modelId: modelId, headers: completed.responseHeaders, body: completed.rawValue), providerMetadata: metadata.isEmpty ? nil : ["assemblyai": metadata])
            }
            try await Task.sleep(for: config.pollingInterval)
        }
    }
}

private enum TranscriptStatus: String, Decodable { case queued, processing, completed, error }
private struct UploadResponse: Decodable {
    let uploadURL: String
    enum CodingKeys: String, CodingKey { case uploadURL = "upload_url" }
}
private struct SubmitResponse: Decodable { let id: String; let status: TranscriptStatus }
private struct Word: Decodable {
    let start: Double
    let end: Double
    let text: String
    let confidence: Double?
    let speaker: String?
    let channel: String?
}
private struct TranscriptResponse: Decodable {
    struct Utterance: Decodable {
        let start: Double
        let end: Double
        let text: String
        let confidence: Double?
        let speaker: String?
        let channel: String?
        let words: [Word]?
    }
    struct Sentiment: Decodable {
        let text: String
        let start: Double?
        let end: Double?
        let sentiment: String
        let confidence: Double?
        let speaker: String?
    }
    struct Entity: Decodable {
        let entityType: String
        let text: String
        let start: Double?
        let end: Double?
        enum CodingKeys: String, CodingKey { case text, start, end; case entityType = "entity_type" }
    }
    let id: String
    let status: TranscriptStatus
    let text: String?
    let languageCode: String?
    let speechModelUsed: String?
    let words: [Word]?
    let utterances: [Utterance]?
    let sentimentAnalysisResults: [Sentiment]?
    let entities: [Entity]?
    let contentSafetyLabels: JSONObject?
    let iabCategoriesResult: JSONObject?
    let autoHighlightsResult: JSONObject?
    let audioDuration: Double?
    let error: String?
    enum CodingKeys: String, CodingKey {
        case id, status, text, words, utterances, entities, error
        case languageCode = "language_code", speechModelUsed = "speech_model_used", sentimentAnalysisResults = "sentiment_analysis_results"
        case contentSafetyLabels = "content_safety_labels", iabCategoriesResult = "iab_categories_result", autoHighlightsResult = "auto_highlights_result", audioDuration = "audio_duration"
    }
}
private let assemblyaiUploadResponseSchema = FlexibleSchema(Schema<UploadResponse>.codable(UploadResponse.self, jsonSchema: ["type": "object"]))
private let assemblyaiSubmitResponseSchema = FlexibleSchema(Schema<SubmitResponse>.codable(SubmitResponse.self, jsonSchema: ["type": "object"]))
private let assemblyaiTranscriptionResponseSchema = FlexibleSchema(Schema<TranscriptResponse>.codable(TranscriptResponse.self, jsonSchema: ["type": "object"]))
private struct TranscriptionFailure: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
