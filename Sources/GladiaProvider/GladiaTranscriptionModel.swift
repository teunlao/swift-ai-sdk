import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/gladia/src/gladia-transcription-model.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public final class GladiaTranscriptionModel: TranscriptionModelV3 {
    private let modelIdentifier: String
    private let config: GladiaConfig

    init(modelId: String, config: GladiaConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier }

    public func doGenerate(options: TranscriptionModelV3CallOptions) async throws -> TranscriptionModelV3Result {
        let audioData = try data(from: options.audio)
        let fileExtension = mediaTypeToExtension(options.mediaType)
        let filename = fileExtension.isEmpty ? "audio" : "audio.\(fileExtension)"
        let currentDate = config.currentDate()

        var builder = MultipartFormDataBuilder()
        builder.appendFile(name: "audio", filename: filename, contentType: options.mediaType, data: audioData)
        let (formBody, contentType) = builder.build()

        let baseHeaders = config.headers()
        let optionHeaders = options.headers?.mapValues { Optional($0) }

        var uploadHeaders = combineHeaders(baseHeaders, optionHeaders).compactMapValues { $0 }
        uploadHeaders["Content-Type"] = contentType

        let uploadResponse = try await postToAPI(
            url: config.url(.init(modelId: modelIdentifier, path: "/v2/upload")),
            headers: uploadHeaders,
            body: PostBody(content: .data(formBody), values: nil),
            failedResponseHandler: gladiaFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: gladiaUploadResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let (body, warnings) = try await prepareRequestBody(options: options)

        var transcriptionBody = body
        transcriptionBody["audio_url"] = .string(uploadResponse.value.audioURL)

        let jsonHeaders = combineHeaders(baseHeaders, optionHeaders).compactMapValues { $0 }

        let transcriptionInitResponse = try await postJsonToAPI(
            url: config.url(.init(modelId: modelIdentifier, path: "/v2/pre-recorded")),
            headers: jsonHeaders,
            body: JSONValue.object(transcriptionBody),
            failedResponseHandler: gladiaFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: gladiaTranscriptionInitializeResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let pollingHeaders = combineHeaders(baseHeaders, optionHeaders).compactMapValues { $0 }
        let resultURL = transcriptionInitResponse.value.resultURL
        let timeoutMs = 60_000
        let pollingIntervalMs = 1_000
        let startTime = Date()

        while true {
            if Date().timeIntervalSince(startTime) * 1000.0 > Double(timeoutMs) {
                throw APICallError(
                    message: "Transcription job polling timed out",
                    url: resultURL,
                    requestBodyValues: nil
                )
            }

            let pollResponse = try await getFromAPI(
                url: resultURL,
                headers: pollingHeaders,
                failedResponseHandler: gladiaFailedResponseHandler,
                successfulResponseHandler: createJsonResponseHandler(responseSchema: gladiaTranscriptionResultResponseSchema),
                isAborted: options.abortSignal,
                fetch: config.fetch
            )

            let result = pollResponse.value

            switch result.status {
            case .done:
                guard let payload = result.result else {
                    throw APICallError(
                        message: "Transcription result is empty",
                        url: resultURL,
                        requestBodyValues: nil,
                        data: result
                    )
                }

                return try buildResult(
                    payload: payload,
                    fullResult: result,
                    headers: pollResponse.responseHeaders,
                    body: pollResponse.rawValue,
                    warnings: warnings,
                    timestamp: currentDate
                )
            case .error:
                throw APICallError(
                    message: "Transcription job failed",
                    url: resultURL,
                    requestBodyValues: nil,
                    data: result
                )
            case .queued, .processing:
                try await delay(pollingIntervalMs)
            }
        }
    }

    private func prepareRequestBody(options: TranscriptionModelV3CallOptions) async throws -> ([String: JSONValue], [SharedV3Warning]) {
        let gladiaOptions = try await parseProviderOptions(
            provider: "gladia",
            providerOptions: options.providerOptions,
            schema: gladiaTranscriptionOptionsSchema
        )

        var body: [String: JSONValue] = [:]
        let warnings: [SharedV3Warning] = []

        guard let gladiaOptions else {
            return (body, warnings)
        }

        if let contextPrompt = gladiaOptions.contextPrompt {
            body["context_prompt"] = .string(contextPrompt)
        }

        if let customVocabulary = gladiaOptions.customVocabulary {
            switch customVocabulary {
            case .bool(let flag):
                body["custom_vocabulary"] = .bool(flag)
            case .entries(let entries):
                body["custom_vocabulary"] = .array(entries.map(makeVocabularyEntryJSON))
            }
        }

        if let config = gladiaOptions.customVocabularyConfig {
            var object: [String: JSONValue] = [
                "vocabulary": .array(config.vocabulary.map(makeVocabularyEntryJSON))
            ]
            if let intensity = config.defaultIntensity {
                object["default_intensity"] = .number(intensity)
            }
            body["custom_vocabulary_config"] = .object(object)
        }

        if let detectLanguage = gladiaOptions.detectLanguage {
            body["detect_language"] = .bool(detectLanguage)
        }

        if let enableCodeSwitching = gladiaOptions.enableCodeSwitching {
            body["enable_code_switching"] = .bool(enableCodeSwitching)
        }

        if let codeSwitchingConfig = gladiaOptions.codeSwitchingConfig, let languages = codeSwitchingConfig.languages {
            body["code_switching_config"] = .object([
                "languages": .array(languages.map(JSONValue.string))
            ])
        }

        if let language = gladiaOptions.language {
            body["language"] = .string(language)
        }

        if let callback = gladiaOptions.callback {
            body["callback"] = .bool(callback)
        }

        if let callbackConfig = gladiaOptions.callbackConfig {
            var object: [String: JSONValue] = ["url": .string(callbackConfig.url)]
            if let method = callbackConfig.method {
                object["method"] = .string(method.rawValue)
            }
            body["callback_config"] = .object(object)
        }

        if let subtitles = gladiaOptions.subtitles {
            body["subtitles"] = .bool(subtitles)
        }

        if let subtitlesConfig = gladiaOptions.subtitlesConfig {
            var object: [String: JSONValue] = [:]
            if let formats = subtitlesConfig.formats {
                object["formats"] = .array(formats.map { .string($0.rawValue) })
            }
            if let min = subtitlesConfig.minimumDuration {
                object["minimum_duration"] = .number(min)
            }
            if let max = subtitlesConfig.maximumDuration {
                object["maximum_duration"] = .number(max)
            }
            if let maxCharacters = subtitlesConfig.maximumCharactersPerRow {
                object["maximum_characters_per_row"] = .number(Double(maxCharacters))
            }
            if let maxRows = subtitlesConfig.maximumRowsPerCaption {
                object["maximum_rows_per_caption"] = .number(Double(maxRows))
            }
            if let style = subtitlesConfig.style {
                object["style"] = .string(style.rawValue)
            }
            if !object.isEmpty {
                body["subtitles_config"] = .object(object)
            }
        }

        if let diarization = gladiaOptions.diarization {
            body["diarization"] = .bool(diarization)
        }

        if let diarizationConfig = gladiaOptions.diarizationConfig {
            var object: [String: JSONValue] = [:]
            if let count = diarizationConfig.numberOfSpeakers {
                object["number_of_speakers"] = .number(Double(count))
            }
            if let min = diarizationConfig.minSpeakers {
                object["min_speakers"] = .number(Double(min))
            }
            if let max = diarizationConfig.maxSpeakers {
                object["max_speakers"] = .number(Double(max))
            }
            if let enhanced = diarizationConfig.enhanced {
                object["enhanced"] = .bool(enhanced)
            }
            if !object.isEmpty {
                body["diarization_config"] = .object(object)
            }
        }

        if let translation = gladiaOptions.translation {
            body["translation"] = .bool(translation)
        }

        if let translationConfig = gladiaOptions.translationConfig {
            var object: [String: JSONValue] = [
                "target_languages": .array(translationConfig.targetLanguages.map(JSONValue.string))
            ]
            if let model = translationConfig.model {
                object["model"] = .string(model.rawValue)
            }
            if let match = translationConfig.matchOriginalUtterances {
                object["match_original_utterances"] = .bool(match)
            }
            body["translation_config"] = .object(object)
        }

        if let summarization = gladiaOptions.summarization {
            body["summarization"] = .bool(summarization)
        }

        if let summarizationConfig = gladiaOptions.summarizationConfig, let type = summarizationConfig.type {
            body["summarization_config"] = .object(["type": .string(type.rawValue)])
        }

        if let moderation = gladiaOptions.moderation {
            body["moderation"] = .bool(moderation)
        }

        if let ner = gladiaOptions.namedEntityRecognition {
            body["named_entity_recognition"] = .bool(ner)
        }

        if let chapterization = gladiaOptions.chapterization {
            body["chapterization"] = .bool(chapterization)
        }

        if let nameConsistency = gladiaOptions.nameConsistency {
            body["name_consistency"] = .bool(nameConsistency)
        }

        if let customSpelling = gladiaOptions.customSpelling {
            body["custom_spelling"] = .bool(customSpelling)
        }

        if let customSpellingConfig = gladiaOptions.customSpellingConfig {
            let entries = customSpellingConfig.spellingDictionary.mapValues { values in
                JSONValue.array(values.map(JSONValue.string))
            }
            body["custom_spelling_config"] = .object(entries)
        }

        if let structured = gladiaOptions.structuredDataExtraction {
            body["structured_data_extraction"] = .bool(structured)
        }

        if let structuredConfig = gladiaOptions.structuredDataExtractionConfig {
            body["structured_data_extraction_config"] = .object([
                "classes": .array(structuredConfig.classes.map(JSONValue.string))
            ])
        }

        if let sentiment = gladiaOptions.sentimentAnalysis {
            body["sentiment_analysis"] = .bool(sentiment)
        }

        if let audioToLLM = gladiaOptions.audioToLlm {
            body["audio_to_llm"] = .bool(audioToLLM)
        }

        if let audioToLLMConfig = gladiaOptions.audioToLlmConfig {
            body["audio_to_llm_config"] = .object([
                "prompts": .array(audioToLLMConfig.prompts.map(JSONValue.string))
            ])
        }

        if let customMetadata = gladiaOptions.customMetadata {
            body["custom_metadata"] = .object(customMetadata)
        }

        if let sentences = gladiaOptions.sentences {
            body["sentences"] = .bool(sentences)
        }

        if let displayMode = gladiaOptions.displayMode {
            body["display_mode"] = .bool(displayMode)
        }

        if let punctuation = gladiaOptions.punctuationEnhanced {
            body["punctuation_enhanced"] = .bool(punctuation)
        }

        return (body, warnings)
    }

    private func data(from audio: TranscriptionModelV3Audio) throws -> Data {
        switch audio {
        case .binary(let data):
            return data
        case .base64(let base64):
            return try convertBase64ToData(base64)
        }
    }

    private func makeVocabularyEntryJSON(_ entry: GladiaTranscriptionOptions.CustomVocabularyEntry) -> JSONValue {
        switch entry {
        case .string(let value):
            return .string(value)
        case .details(let term):
            var object: [String: JSONValue] = ["value": .string(term.value)]
            if let intensity = term.intensity {
                object["intensity"] = .number(intensity)
            }
            if let pronunciations = term.pronunciations {
                object["pronunciations"] = .array(pronunciations.map(JSONValue.string))
            }
            if let language = term.language {
                object["language"] = .string(language)
            }
            return .object(object)
        }
    }

    private func buildResult(
        payload: GladiaTranscriptionResultResponse.Result,
        fullResult: GladiaTranscriptionResultResponse,
        headers: [String: String],
        body: Any?,
        warnings: [SharedV3Warning],
        timestamp: Date
    ) throws -> TranscriptionModelV3Result {
        let language = payload.transcription.languages.first
        let segments = payload.transcription.utterances.map {
            TranscriptionModelV3Result.Segment(
                text: $0.text,
                startSecond: $0.start,
                endSecond: $0.end
            )
        }

        var providerMetadata: [String: [String: JSONValue]]? = nil
        if let data = try? JSONEncoder().encode(fullResult),
           let json = try? JSONDecoder().decode(JSONValue.self, from: data),
           case .object(let object) = json {
            providerMetadata = ["gladia": object]
        }

        return TranscriptionModelV3Result(
            text: payload.transcription.fullTranscript,
            segments: segments,
            language: language,
            durationInSeconds: payload.metadata.audioDuration,
            warnings: warnings,
            request: nil,
            response: TranscriptionModelV3Result.ResponseInfo(
                timestamp: timestamp,
                modelId: modelIdentifier,
                headers: headers,
                body: body
            ),
            providerMetadata: providerMetadata
        )
    }
}

private struct GladiaUploadResponse: Codable, Sendable {
    let audioURL: String

    private enum CodingKeys: String, CodingKey {
        case audioURL = "audio_url"
    }
}

private struct GladiaTranscriptionInitializeResponse: Codable, Sendable {
    let resultURL: String

    private enum CodingKeys: String, CodingKey {
        case resultURL = "result_url"
    }
}

private struct GladiaTranscriptionResultResponse: Codable, Sendable {
    enum Status: String, Codable, Sendable {
        case queued
        case processing
        case done
        case error
    }

    struct Result: Codable, Sendable {
        struct Metadata: Codable, Sendable {
            let audioDuration: Double

            private enum CodingKeys: String, CodingKey {
                case audioDuration = "audio_duration"
            }
        }

        struct Transcription: Codable, Sendable {
            struct Utterance: Codable, Sendable {
                let start: Double
                let end: Double
                let text: String
            }

            let fullTranscript: String
            let languages: [String]
            let utterances: [Utterance]

            private enum CodingKeys: String, CodingKey {
                case fullTranscript = "full_transcript"
                case languages
                case utterances
            }
        }

        let metadata: Metadata
        let transcription: Transcription
    }

    let status: Status
    let result: Result?
}

private let gladiaUploadResponseSchema = FlexibleSchema(
    Schema<GladiaUploadResponse>.codable(
        GladiaUploadResponse.self,
        jsonSchema: .object([
            "type": .string("object"),
            "required": .array([.string("audio_url")])
        ])
    )
)

private let gladiaTranscriptionInitializeResponseSchema = FlexibleSchema(
    Schema<GladiaTranscriptionInitializeResponse>.codable(
        GladiaTranscriptionInitializeResponse.self,
        jsonSchema: .object([
            "type": .string("object"),
            "required": .array([.string("result_url")])
        ])
    )
)

private let gladiaTranscriptionResultResponseSchema = FlexibleSchema(
    Schema<GladiaTranscriptionResultResponse>.codable(
        GladiaTranscriptionResultResponse.self,
        jsonSchema: .object([
            "type": .string("object"),
            "required": .array([.string("status")])
        ])
    )
)
