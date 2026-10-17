import Foundation
import AISDKProvider
import AISDKProviderUtils

// Port of packages/revai/src/revai-transcription-model.ts and its options schema.

private let revaiProviderOptionsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(true),
])

private let revaiTranslationLanguageCodes: Set<String> = [
    "en",
    "en-us",
    "en-gb",
    "ar",
    "pt",
    "pt-br",
    "pt-pt",
    "fr",
    "fr-ca",
    "es",
    "es-es",
    "es-la",
    "it",
    "ja",
    "ko",
    "de",
    "ru",
]

private let revaiProviderOptionsSchema = FlexibleSchema(
    Schema<[String: JSONValue]>(
        jsonSchemaResolver: { revaiProviderOptionsJSONSchema },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(
                        vendor: "revai",
                        issues: "provider options must be an object"
                    )
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                func fail(_ issues: String) -> SchemaValidationResult<[String: JSONValue]> {
                    let error = SchemaValidationIssuesError(vendor: "revai", issues: issues)
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                func hasKey(_ key: String) -> Bool {
                    dict.keys.contains(key)
                }

                func readString(_ key: String) -> String? {
                    guard let raw = dict[key], raw != .null else { return nil }
                    guard case .string(let s) = raw else { return nil }
                    return s
                }

                func readNumber(_ key: String) -> Double? {
                    guard let raw = dict[key], raw != .null else { return nil }
                    guard case .number(let n) = raw, n.isFinite else { return nil }
                    return n
                }

                func readBool(_ key: String) -> Bool? {
                    guard let raw = dict[key], raw != .null else { return nil }
                    guard case .bool(let b) = raw else { return nil }
                    return b
                }

                func readNullishDefaultBool(_ key: String, defaultValue: Bool) -> Bool? {
                    if !hasKey(key) { return defaultValue }
                    guard let raw = dict[key] else { return defaultValue }
                    if raw == .null { return nil }
                    guard case .bool(let b) = raw else { return nil }
                    return b
                }

                func readNullishDefaultString(_ key: String, defaultValue: String) -> String? {
                    if !hasKey(key) { return defaultValue }
                    guard let raw = dict[key] else { return defaultValue }
                    if raw == .null { return nil }
                    guard case .string(let s) = raw else { return nil }
                    return s
                }

                var out: [String: JSONValue] = [:]

                if let metadata = dict["metadata"] {
                    if metadata != .null {
                        guard case .string = metadata else { return fail("metadata must be a string") }
                        out["metadata"] = metadata
                    }
                }

                if let notification = dict["notification_config"] {
                    if notification != .null {
                        guard case .object(let obj) = notification else {
                            return fail("notification_config must be an object")
                        }

                        guard case .string(let url) = (obj["url"] ?? .null) else {
                            return fail("notification_config.url must be a string")
                        }

                        var notifOut: [String: JSONValue] = ["url": .string(url)]

                        if let authHeaders = obj["auth_headers"] {
                            if authHeaders == .null {
                                notifOut["auth_headers"] = .null
                            } else {
                                guard case .object(let authObj) = authHeaders else {
                                    return fail("notification_config.auth_headers must be an object")
                                }
                                guard case .string(let auth) = (authObj["Authorization"] ?? .null) else {
                                    return fail("notification_config.auth_headers.Authorization must be a string")
                                }
                                notifOut["auth_headers"] = .object(["Authorization": .string(auth)])
                            }
                        }

                        out["notification_config"] = .object(notifOut)
                    }
                }

                if let deleteAfter = dict["delete_after_seconds"] {
                    if deleteAfter != .null {
                        guard case .number = deleteAfter else { return fail("delete_after_seconds must be a number") }
                        out["delete_after_seconds"] = deleteAfter
                    }
                }

                if hasKey("verbatim") {
                    guard let raw = dict["verbatim"] else { return fail("verbatim must be a boolean") }
                    if raw == .null { return fail("verbatim must be a boolean") }
                    guard case .bool = raw else { return fail("verbatim must be a boolean") }
                    out["verbatim"] = raw
                }

                if let rush = readNullishDefaultBool("rush", defaultValue: false) {
                    out["rush"] = .bool(rush)
                }
                if let testMode = readNullishDefaultBool("test_mode", defaultValue: false) {
                    out["test_mode"] = .bool(testMode)
                }

                if let segments = dict["segments_to_transcribe"] {
                    if segments != .null {
                        guard case .array(let arr) = segments else {
                            return fail("segments_to_transcribe must be an array")
                        }
                        var outSegments: [JSONValue] = []
                        outSegments.reserveCapacity(arr.count)
                        for entry in arr {
                            guard case .object(let seg) = entry else {
                                return fail("segments_to_transcribe entries must be objects")
                            }
                            guard case .number(let start) = (seg["start"] ?? .null), start.isFinite,
                                  case .number(let end) = (seg["end"] ?? .null), end.isFinite else {
                                return fail("segments_to_transcribe entries must include start/end numbers")
                            }
                            outSegments.append(.object(["start": .number(start), "end": .number(end)]))
                        }
                        out["segments_to_transcribe"] = .array(outSegments)
                    }
                }

                if let speakerNames = dict["speaker_names"] {
                    if speakerNames != .null {
                        guard case .array(let arr) = speakerNames else {
                            return fail("speaker_names must be an array")
                        }
                        var outNames: [JSONValue] = []
                        outNames.reserveCapacity(arr.count)
                        for entry in arr {
                            guard case .object(let speaker) = entry else {
                                return fail("speaker_names entries must be objects")
                            }
                            guard case .string(let display) = (speaker["display_name"] ?? .null) else {
                                return fail("speaker_names entries must include display_name string")
                            }
                            outNames.append(.object(["display_name": .string(display)]))
                        }
                        out["speaker_names"] = .array(outNames)
                    }
                }

                if let skipDiarization = readNullishDefaultBool("skip_diarization", defaultValue: false) {
                    out["skip_diarization"] = .bool(skipDiarization)
                }
                if let skipPostprocessing = readNullishDefaultBool("skip_postprocessing", defaultValue: false) {
                    out["skip_postprocessing"] = .bool(skipPostprocessing)
                }
                if let skipPunctuation = readNullishDefaultBool("skip_punctuation", defaultValue: false) {
                    out["skip_punctuation"] = .bool(skipPunctuation)
                }
                if let removeDisfluencies = readNullishDefaultBool("remove_disfluencies", defaultValue: false) {
                    out["remove_disfluencies"] = .bool(removeDisfluencies)
                }
                if let removeAtmospherics = readNullishDefaultBool("remove_atmospherics", defaultValue: false) {
                    out["remove_atmospherics"] = .bool(removeAtmospherics)
                }
                if let filterProfanity = readNullishDefaultBool("filter_profanity", defaultValue: false) {
                    out["filter_profanity"] = .bool(filterProfanity)
                }

                if let speakerChannels = dict["speaker_channels_count"] {
                    if speakerChannels != .null {
                        guard case .number = speakerChannels else { return fail("speaker_channels_count must be a number") }
                        out["speaker_channels_count"] = speakerChannels
                    }
                }

                if let speakersCount = dict["speakers_count"] {
                    if speakersCount != .null {
                        guard case .number = speakersCount else { return fail("speakers_count must be a number") }
                        out["speakers_count"] = speakersCount
                    }
                }

                if let diarizationType = readNullishDefaultString("diarization_type", defaultValue: "standard") {
                    guard diarizationType == "standard" || diarizationType == "premium" else {
                        return fail("diarization_type must be 'standard' or 'premium'")
                    }
                    out["diarization_type"] = .string(diarizationType)
                }

                if let customVocabId = dict["custom_vocabulary_id"] {
                    if customVocabId != .null {
                        guard case .string = customVocabId else { return fail("custom_vocabulary_id must be a string") }
                        out["custom_vocabulary_id"] = customVocabId
                    }
                }

                if hasKey("custom_vocabularies") {
                    guard let raw = dict["custom_vocabularies"] else { return fail("custom_vocabularies must be an array") }
                    guard case .array(let arr) = raw else { return fail("custom_vocabularies must be an array") }
                    var outArr: [JSONValue] = []
                    outArr.reserveCapacity(arr.count)
                    for item in arr {
                        guard case .object = item else { return fail("custom_vocabularies entries must be objects") }
                        // zod's `z.object({})` strips unknown keys, so values become `{}`.
                        outArr.append(.object([:]))
                    }
                    out["custom_vocabularies"] = .array(outArr)
                }

                if hasKey("strict_custom_vocabulary") {
                    guard let raw = dict["strict_custom_vocabulary"] else { return fail("strict_custom_vocabulary must be a boolean") }
                    if raw == .null { return fail("strict_custom_vocabulary must be a boolean") }
                    guard case .bool = raw else { return fail("strict_custom_vocabulary must be a boolean") }
                    out["strict_custom_vocabulary"] = raw
                }

                if let summarization = dict["summarization_config"] {
                    if summarization != .null {
                        guard case .object(let obj) = summarization else {
                            return fail("summarization_config must be an object")
                        }

                        var summaryOut: [String: JSONValue] = [:]

                        if let modelRaw = obj["model"] {
                            if modelRaw == .null {
                                summaryOut["model"] = .null
                            } else if case .string(let m) = modelRaw {
                                guard m == "standard" || m == "premium" else { return fail("summarization_config.model must be 'standard' or 'premium'") }
                                summaryOut["model"] = .string(m)
                            } else {
                                return fail("summarization_config.model must be a string")
                            }
                        } else {
                            summaryOut["model"] = .string("standard")
                        }

                        if let typeRaw = obj["type"] {
                            if typeRaw == .null {
                                summaryOut["type"] = .null
                            } else if case .string(let t) = typeRaw {
                                guard t == "paragraph" || t == "bullets" else { return fail("summarization_config.type must be 'paragraph' or 'bullets'") }
                                summaryOut["type"] = .string(t)
                            } else {
                                return fail("summarization_config.type must be a string")
                            }
                        } else {
                            summaryOut["type"] = .string("paragraph")
                        }

                        if let promptRaw = obj["prompt"] {
                            if promptRaw == .null {
                                summaryOut["prompt"] = .null
                            } else {
                                guard case .string = promptRaw else { return fail("summarization_config.prompt must be a string") }
                                summaryOut["prompt"] = promptRaw
                            }
                        }

                        out["summarization_config"] = .object(summaryOut)
                    }
                }

                if let translation = dict["translation_config"] {
                    if translation != .null {
                        guard case .object(let obj) = translation else {
                            return fail("translation_config must be an object")
                        }

                        guard case .array(let targets) = (obj["target_languages"] ?? .null) else {
                            return fail("translation_config.target_languages must be an array")
                        }

                        var outTargets: [JSONValue] = []
                        outTargets.reserveCapacity(targets.count)
                        for entry in targets {
                            guard case .object(let targetObj) = entry else {
                                return fail("translation_config.target_languages entries must be objects")
                            }
                            guard case .string(let language) = (targetObj["language"] ?? .null) else {
                                return fail("translation_config.target_languages.language must be a string")
                            }
                            guard revaiTranslationLanguageCodes.contains(language) else {
                                return fail("translation_config.target_languages.language must be a supported code")
                            }
                            outTargets.append(.object(["language": .string(language)]))
                        }

                        var translationOut: [String: JSONValue] = [
                            "target_languages": .array(outTargets)
                        ]

                        if let modelRaw = obj["model"] {
                            if modelRaw == .null {
                                translationOut["model"] = .null
                            } else if case .string(let m) = modelRaw {
                                guard m == "standard" || m == "premium" else { return fail("translation_config.model must be 'standard' or 'premium'") }
                                translationOut["model"] = .string(m)
                            } else {
                                return fail("translation_config.model must be a string")
                            }
                        } else {
                            translationOut["model"] = .string("standard")
                        }

                        out["translation_config"] = .object(translationOut)
                    }
                }

                if let language = readNullishDefaultString("language", defaultValue: "en") {
                    out["language"] = .string(language)
                }

                if let forcedAlignment = readNullishDefaultBool("forced_alignment", defaultValue: false) {
                    out["forced_alignment"] = .bool(forcedAlignment)
                }

                // Ensure any present keys were type-checked (so we don't silently accept wrong types).
                // This mirrors zod's behavior in the upstream implementation.
                if hasKey("metadata"), readString("metadata") == nil, dict["metadata"] != .null { return fail("metadata must be a string") }
                if hasKey("language"), readString("language") == nil, dict["language"] != .null { return fail("language must be a string") }
                if hasKey("diarization_type"), readString("diarization_type") == nil, dict["diarization_type"] != .null { return fail("diarization_type must be a string") }
                if hasKey("delete_after_seconds"), readNumber("delete_after_seconds") == nil, dict["delete_after_seconds"] != .null { return fail("delete_after_seconds must be a number") }
                if hasKey("speaker_channels_count"), readNumber("speaker_channels_count") == nil, dict["speaker_channels_count"] != .null { return fail("speaker_channels_count must be a number") }
                if hasKey("speakers_count"), readNumber("speakers_count") == nil, dict["speakers_count"] != .null { return fail("speakers_count must be a number") }

                if hasKey("rush"), dict["rush"] != .null, readBool("rush") == nil { return fail("rush must be a boolean") }
                if hasKey("test_mode"), dict["test_mode"] != .null, readBool("test_mode") == nil { return fail("test_mode must be a boolean") }
                if hasKey("skip_diarization"), dict["skip_diarization"] != .null, readBool("skip_diarization") == nil { return fail("skip_diarization must be a boolean") }
                if hasKey("skip_postprocessing"), dict["skip_postprocessing"] != .null, readBool("skip_postprocessing") == nil { return fail("skip_postprocessing must be a boolean") }
                if hasKey("skip_punctuation"), dict["skip_punctuation"] != .null, readBool("skip_punctuation") == nil { return fail("skip_punctuation must be a boolean") }
                if hasKey("remove_disfluencies"), dict["remove_disfluencies"] != .null, readBool("remove_disfluencies") == nil { return fail("remove_disfluencies must be a boolean") }
                if hasKey("remove_atmospherics"), dict["remove_atmospherics"] != .null, readBool("remove_atmospherics") == nil { return fail("remove_atmospherics must be a boolean") }
                if hasKey("filter_profanity"), dict["filter_profanity"] != .null, readBool("filter_profanity") == nil { return fail("filter_profanity must be a boolean") }
                if hasKey("forced_alignment"), dict["forced_alignment"] != .null, readBool("forced_alignment") == nil { return fail("forced_alignment must be a boolean") }

                return .success(value: out)
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)

private struct RevAIJobResponse: Codable, Sendable, Error {
    let id: String?
    let status: String?
    let language: String?
    let pathId: String

    enum CodingKeys: String, CodingKey { case id, status, language }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(String.self, forKey: .id)
        status = try values.decodeIfPresent(String.self, forKey: .status)
        language = try values.decodeIfPresent(String.self, forKey: .language)
        pathId = id ?? (values.contains(.id) ? "null" : "undefined")
    }
}

private let revaiTranscriptionJobResponseSchema = FlexibleSchema(
    Schema.codable(
        RevAIJobResponse.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

private struct RevAITranscriptResponse: Codable, Sendable {
    struct Monologue: Codable, Sendable {
        struct Element: Codable, Sendable {
            let type: String?
            let value: String?
            let segmentValue: String
            let ts: Double?
            let endTs: Double?

            enum CodingKeys: String, CodingKey {
                case type
                case value
                case ts
                case endTs = "end_ts"
            }

            init(from decoder: Decoder) throws {
                let fields = try decoder.container(keyedBy: CodingKeys.self)
                type = try fields.decodeIfPresent(String.self, forKey: .type)
                value = try fields.decodeIfPresent(String.self, forKey: .value)
                ts = try fields.decodeIfPresent(Double.self, forKey: .ts)
                endTs = try fields.decodeIfPresent(Double.self, forKey: .endTs)
                // Concatenation and array joining coerce nullish values differently in JavaScript.
                segmentValue = value ?? (fields.contains(.value) ? "null" : "undefined")
            }
        }

        let elements: [Element]?
    }

    let monologues: [Monologue]?
}

private let revaiTranscriptionResponseSchema = FlexibleSchema(
    Schema.codable(
        RevAITranscriptResponse.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

private struct RevAITranscriptionJobError: AISDKError, Sendable {
    static let errorDomain = "vercel.ai.error"

    let name: String
    let message: String
    let cause: (any Error)?
    init(name: String, message: String, cause: RevAIJobResponse) {
        self.name = name
        self.message = message
        self.cause = cause
    }
}

public final class RevAITranscriptionModel: TranscriptionModelV4 {
    private let modelIdentifier: RevAITranscriptionModelId
    private let config: RevAIConfig

    init(modelId: RevAITranscriptionModelId, config: RevAIConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    public func doGenerate(options: TranscriptionModelV4CallOptions) async throws -> TranscriptionModelV4Result {
        let currentDate = config.currentDate()

        let prepared = try await prepareRequest(options: options)

        let headers = combineHeaders(
            try config.headers(),
            options.headers?.mapValues(Optional.some),
            ["content-type": prepared.contentType]
        ).compactMapValues { $0 }

        let submission = try await postToAPI(
            url: config.url(.init(modelId: modelIdentifier.rawValue, path: "/speechtotext/v1/jobs")),
            headers: headers,
            body: PostBody(content: .data(prepared.body), values: nil),
            failedResponseHandler: revaiFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: revaiTranscriptionJobResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let submissionResponse = submission.value

        if submissionResponse.status == "failed" {
            throw RevAITranscriptionJobError(
                name: "TranscriptionJobSubmissionFailed",
                message: "Failed to submit transcription job to Rev.ai",
                cause: submissionResponse
            )
        }

        let jobId = submissionResponse.pathId
        let timeoutMs = 60_000.0
        let pollingIntervalMs = 1_000
        let start = Date()
        var jobResponse = submissionResponse

        while jobResponse.status != "transcribed" {
            if options.abortSignal?() == true {
                throw CancellationError()
            }

            let elapsedMs = Date().timeIntervalSince(start) * 1000
            if elapsedMs > timeoutMs {
                throw RevAITranscriptionJobError(
                    name: "TranscriptionJobPollingTimedOut",
                    message: "Transcription job polling timed out",
                    cause: submissionResponse
                )
            }

            let polling = try await getFromAPI(
                url: config.url(.init(modelId: modelIdentifier.rawValue, path: "/speechtotext/v1/jobs/\(jobId)")),
                headers: combineHeaders(try config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 },
                failedResponseHandler: revaiFailedResponseHandler,
                successfulResponseHandler: createJsonResponseHandler(responseSchema: revaiTranscriptionJobResponseSchema),
                isAborted: options.abortSignal,
                fetch: config.fetch
            )

            jobResponse = polling.value

            if jobResponse.status == "failed" {
                throw RevAITranscriptionJobError(
                    name: "TranscriptionJobFailed",
                    message: "Transcription job failed",
                    cause: jobResponse
                )
            }

            if jobResponse.status != "transcribed" {
                try await delay(pollingIntervalMs, abortSignal: options.abortSignal)
            }
        }

        let transcript = try await getFromAPI(
            url: config.url(.init(modelId: modelIdentifier.rawValue, path: "/speechtotext/v1/jobs/\(jobId)/transcript")),
            headers: combineHeaders(try config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 },
            failedResponseHandler: revaiFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: revaiTranscriptionResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let mapped = mapTranscript(transcript.value, submissionLanguage: submissionResponse.language)

        return TranscriptionModelV4Result(
            text: mapped.text,
            segments: mapped.segments,
            language: mapped.language,
            durationInSeconds: mapped.durationInSeconds,
            warnings: prepared.warnings,
            request: nil,
            response: TranscriptionModelV4Result.ResponseInfo(
                timestamp: currentDate,
                modelId: modelIdentifier.rawValue,
                headers: transcript.responseHeaders,
                body: transcript.rawValue
            ),
            providerMetadata: nil
        )
    }

    // MARK: - Preparation

    private struct PreparedRequest: Sendable {
        let body: Data
        let contentType: String
        let warnings: [SharedV4Warning]
    }

    private func prepareRequest(options: TranscriptionModelV4CallOptions) async throws -> PreparedRequest {
        let warnings: [SharedV4Warning] = []

        let revaiOptions = try await parseProviderOptions(
            provider: "revai",
            providerOptions: options.providerOptions,
            schema: revaiProviderOptionsSchema
        )

        let audioData = try data(from: options.audio)
        let fileExtension = mediaTypeToExtension(options.mediaType)
        let filename = "audio.\(fileExtension)"

        var builder = MultipartFormDataBuilder()
        builder.appendFile(name: "media", filename: filename, contentType: options.mediaType, data: audioData)

        var transcriptionOptions: [String: JSONValue] = [
            "transcriber": .string(modelIdentifier.rawValue),
        ]

        if let revaiOptions {
            for (key, value) in revaiOptions {
                transcriptionOptions[key] = value
            }
        }

        let configString = try jsonStringify(.object(transcriptionOptions))
        builder.appendField(name: "config", value: configString)

        let (body, contentType) = builder.build()
        return PreparedRequest(body: body, contentType: contentType, warnings: warnings)
    }

    private func data(from audio: TranscriptionModelV4Audio) throws -> Data {
        switch audio {
        case .binary(let data):
            return data
        case .base64(let base64):
            return try convertBase64ToData(base64)
        }
    }

    private func jsonStringify(_ value: JSONValue) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(codingPath: [], debugDescription: "Failed to encode JSON string")
            )
        }
        return string
    }

    // MARK: - Response Mapping

    private static let segmentWhitespace = CharacterSet(charactersIn: "\u{0009}\u{000A}\u{000B}\u{000C}\u{000D}\u{0020}\u{00A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{FEFF}")

    private struct MappedTranscript: Sendable {
        let text: String
        let segments: [TranscriptionModelV4Result.Segment]
        let language: String?
        let durationInSeconds: Double?
    }

    private func mapTranscript(_ transcript: RevAITranscriptResponse, submissionLanguage: String?) -> MappedTranscript {
        var durationInSeconds: Double = 0
        var segments: [TranscriptionModelV4Result.Segment] = []

        for monologue in transcript.monologues ?? [] {
            var currentSegmentText = ""
            var segmentStartSecond: Double = 0
            var hasStartedSegment = false

            for element in monologue.elements ?? [] {
                currentSegmentText += element.segmentValue

                if element.type == "text" {
                    if let end = element.endTs, end > durationInSeconds {
                        durationInSeconds = end
                    }

                    if !hasStartedSegment, let ts = element.ts {
                        segmentStartSecond = ts
                        hasStartedSegment = true
                    }

                    if let end = element.endTs, hasStartedSegment {
                        let trimmed = currentSegmentText.trimmingCharacters(in: Self.segmentWhitespace)
                        if !trimmed.isEmpty {
                            segments.append(
                                TranscriptionModelV4Result.Segment(
                                    text: trimmed,
                                    startSecond: segmentStartSecond,
                                    endSecond: end
                                )
                            )
                        }

                        currentSegmentText = ""
                        hasStartedSegment = false
                    }
                }
            }

            if hasStartedSegment {
                let trimmed = currentSegmentText.trimmingCharacters(in: Self.segmentWhitespace)
                if !trimmed.isEmpty {
                    let endSecond: Double = durationInSeconds > segmentStartSecond ? durationInSeconds : (segmentStartSecond + 1)
                    segments.append(
                        TranscriptionModelV4Result.Segment(
                            text: trimmed,
                            startSecond: segmentStartSecond,
                            endSecond: endSecond
                        )
                    )
                }
            }
        }

        let text = (transcript.monologues ?? []).map { monologue in
            (monologue.elements ?? []).map { $0.value ?? "" }.joined()
        }.joined(separator: " ")

        return MappedTranscript(
            text: text,
            segments: segments,
            language: submissionLanguage,
            durationInSeconds: durationInSeconds
        )
    }
}
