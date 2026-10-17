import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import RevAIProvider

private func response(_ request: URLRequest, _ body: String, status: Int = 200) -> FetchResponse {
    FetchResponse(
        body: .data(Data(body.utf8)),
        urlResponse: HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil,
            headerFields: ["Content-Type": "application/json", "x-request-id": "transcript-request"]
        )!
    )
}

private func configPayload(_ request: URLRequest) throws -> JSONObject {
    let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
    let marker = "name=\"config\"\r\n\r\n"
    let start = try #require(body.range(of: marker)).upperBound
    let end = try #require(body.range(of: "\r\n--", range: start..<body.endIndex)).lowerBound
    return try JSONDecoder().decode(JSONObject.self, from: Data(body[start..<end].utf8))
}

@Suite("RevAI file transcription")
struct RevAITranscriptionModelTests {
    @Test("Uploads audio, polls the job and returns timed text with raw metadata", arguments: [false, true])
    func transcribesFile(base64: Bool) async throws {
        let audio = Data("AUDIO".utf8)
        let fetch: FetchFunction = { request in
            #expect(request.url?.host == "api.rev.ai")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer request")
            #expect(request.value(forHTTPHeaderField: "X-Trace") == "request")
            #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("ai-sdk-revai/") == true)
            switch request.url?.path {
            case "/speechtotext/v1/jobs":
                #expect(request.httpMethod == "POST")
                #expect(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
                let config = try configPayload(request)
                #expect(config == ["transcriber": "low_cost"])
                let body = try #require(request.httpBody)
                #expect(body.range(of: audio) != nil)
                #expect(String(decoding: body, as: UTF8.self).contains("filename=\"audio.wav\""))
                return response(request, #"{"id":"job","status":"in_progress","language":"en"}"#)
            case "/speechtotext/v1/jobs/job":
                #expect(request.httpMethod == "GET")
                return response(request, #"{"id":"job","status":"transcribed","language":"fr"}"#)
            case "/speechtotext/v1/jobs/job/transcript":
                #expect(request.httpMethod == "GET")
                return response(request, #"{"extra":1e100,"monologues":[{"elements":[{"type":"text","value":"Hello","ts":0.5,"end_ts":1.5},{"type":"punct","value":" "},{"type":"text","value":"World","ts":1.75,"end_ts":2.85},{"type":"punct","value":"."}]},{"elements":[{"type":"text","value":"Tail","ts":3}]}]}"#)
            default:
                throw URLError(.badURL)
            }
        }
        let provider: any ProviderV4 = createRevAI(settings: .init(
            apiKey: "key", headers: ["Authorization": "Bearer provider", "X-Trace": "provider"], fetch: fetch
        ))
        let resolved = try provider.transcriptionModel(modelId: "low_cost")
        let model = try #require(resolved)
        let start = Date()
        let result = try await model.doGenerate(options: .init(
            audio: base64 ? .base64(audio.base64EncodedString()) : .binary(audio), mediaType: "audio/wav",
            headers: ["authorization": "Bearer request", "x-trace": "request"]
        ))
        #expect(result.text == "Hello World. Tail")
        #expect(result.segments == [
            .init(text: "Hello", startSecond: 0.5, endSecond: 1.5),
            .init(text: "World", startSecond: 1.75, endSecond: 2.85),
            .init(text: "Tail", startSecond: 3, endSecond: 4)
        ])
        #expect(result.language == "en")
        #expect(result.durationInSeconds == 2.85)
        #expect(result.warnings.isEmpty)
        #expect(result.usage == nil)
        #expect(result.request == nil)
        #expect(result.providerMetadata == nil)
        #expect(result.response.modelId == "low_cost")
        #expect(result.response.timestamp >= start && result.response.timestamp <= Date())
        #expect(result.response.headers?["x-request-id"] == "transcript-request")
        let raw = try #require(result.response.body as? [String: Any])
        #expect(raw["extra"] as? Double == 1e100)
        #expect((raw["monologues"] as? [Any])?.count == 2)
    }

    enum Defaults: Sendable { case empty, nullish }

    @Test("Distinguishes absent fields from explicit null and applies nested defaults", arguments: [Defaults.empty, .nullish])
    func optionDefaults(mode: Defaults) async throws {
        let nullish = mode == .nullish
        let providerOptions: JSONObject = nullish ? [
            "rush": .null, "language": .null, "skip_diarization": .null,
            "summarization_config": ["model": .null, "prompt": .null],
            "notification_config": ["url": "https://callback.example", "auth_headers": .null]
        ] : [:]
        let fetch: FetchFunction = { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer key")
            if request.httpMethod == "POST" {
                let config = try configPayload(request)
                #expect(config["transcriber"] == "fusion")
                #expect(config["rush"] == (nullish ? nil : .bool(false)))
                #expect(config["language"] == (nullish ? nil : .string("en")))
                #expect(config["skip_diarization"] == (nullish ? nil : .bool(false)))
                #expect(config["test_mode"] == false)
                #expect(config["skip_postprocessing"] == false)
                #expect(config["skip_punctuation"] == false)
                #expect(config["remove_disfluencies"] == false)
                #expect(config["remove_atmospherics"] == false)
                #expect(config["filter_profanity"] == false)
                #expect(config["forced_alignment"] == false)
                #expect(config["diarization_type"] == "standard")
                if nullish {
                    #expect(config["summarization_config"] == ["model": .null, "type": "paragraph", "prompt": .null])
                    #expect(config["notification_config"] == ["url": "https://callback.example", "auth_headers": .null])
                }
                return response(request, #"{"id":"job","status":"transcribed"}"#)
            }
            return response(request, #"{"monologues":null}"#)
        }
        let result = try await createRevAI(settings: .init(apiKey: "key", fetch: fetch))(.fusion).transcription.doGenerate(options: .init(
            audio: .binary(Data()), mediaType: "audio/wav", providerOptions: ["revai": providerOptions]
        ))
        #expect(result.text == "")
        #expect(result.segments.isEmpty)
        #expect(result.language == nil)
        #expect(result.durationInSeconds == 0)
    }

    @Test("Serializes all file transcription options without narrowing source numbers")
    func transcriptionOptions() async throws {
        var options = RevAITranscriptionModelOptions()
        options.metadata = "recording"
        options.notificationConfig = .init(url: "https://callback.example", authHeaders: .init(authorization: "Bearer callback"))
        options.deleteAfterSeconds = 1e100
        options.verbatim = false
        options.rush = true
        options.testMode = true
        options.segmentsToTranscribe = [.init(start: 0.25, end: 60.75)]
        options.speakerNames = [.init(displayName: "Speaker")]
        options.skipDiarization = true
        options.skipPostprocessing = true
        options.skipPunctuation = true
        options.removeDisfluencies = true
        options.removeAtmospherics = true
        options.filterProfanity = true
        options.speakerChannelsCount = 2.5
        options.speakersCount = 1e100
        options.diarizationType = .premium
        options.customVocabularyId = "vocabulary"
        options.customVocabularies = [["phrases": ["word"]]]
        options.strictCustomVocabulary = true
        options.summarizationConfig = .init(prompt: "Summarize")
        options.translationConfig = .init(targetLanguages: [.init(language: .fr)])
        options.language = "fr"
        options.forcedAlignment = true
        let supplied = try JSONDecoder().decode(JSONObject.self, from: JSONEncoder().encode(options))
        let expectedConfig: JSONObject = [
            "transcriber": "machine", "metadata": "recording",
            "notification_config": ["url": "https://callback.example", "auth_headers": ["Authorization": "Bearer callback"]],
            "delete_after_seconds": 1e100, "verbatim": false, "rush": true, "test_mode": true,
            "segments_to_transcribe": [["start": 0.25, "end": 60.75]],
            "speaker_names": [["display_name": "Speaker"]],
            "skip_diarization": true, "skip_postprocessing": true, "skip_punctuation": true,
            "remove_disfluencies": true, "remove_atmospherics": true, "filter_profanity": true,
            "speaker_channels_count": 2.5, "speakers_count": 1e100, "diarization_type": "premium",
            "custom_vocabulary_id": "vocabulary", "custom_vocabularies": [.object([:])],
            "strict_custom_vocabulary": true,
            "summarization_config": ["model": "standard", "type": "paragraph", "prompt": "Summarize"],
            "translation_config": ["target_languages": [["language": "fr"]], "model": "standard"],
            "language": "fr", "forced_alignment": true
        ]
        let fetch: FetchFunction = { request in
            if request.httpMethod == "POST" {
                let config = try configPayload(request)
                #expect(config == expectedConfig)
                return response(request, #"{"id":"job","status":"transcribed"}"#)
            }
            return response(request, #"{"monologues":[{"elements":[{"type":"text","ts":0.25,"end_ts":1e100},{"type":"text","value":null,"ts":2,"end_ts":2.5},{"type":"text","value":"\ufeff Trim \ufeff","ts":5,"end_ts":6},{"type":"text","value":"\u0085","ts":6,"end_ts":7}]}],"native":2.5}"#)
        }
        let result = try await createRevAI(settings: .init(apiKey: "key", fetch: fetch)).transcription(modelId: .machine).doGenerate(options: .init(
            audio: .binary(Data()), mediaType: "audio/mp3", providerOptions: ["revai": supplied]
        ))
        #expect(result.text == "\u{FEFF} Trim \u{FEFF}\u{0085}")
        #expect(result.segments == [
            .init(text: "undefined", startSecond: 0.25, endSecond: 1e100),
            .init(text: "null", startSecond: 2, endSecond: 2.5),
            .init(text: "Trim", startSecond: 5, endSecond: 6),
            .init(text: "\u{0085}", startSecond: 6, endSecond: 7)
        ])
        #expect(result.durationInSeconds == 1e100)
        #expect((result.response.body as? [String: Any])?["native"] as? Double == 2.5)
    }

    enum InvalidData: Sendable {
        case verbatimNull, languageNumber, diarizationNumber, infiniteNumber, response
        var options: JSONObject? {
            switch self {
            case .verbatimNull: ["verbatim": .null]
            case .languageNumber: ["language": 1]
            case .diarizationNumber: ["diarization_type": 1]
            case .infiniteNumber: ["speakers_count": .number(.infinity)]
            case .response: nil
            }
        }
    }

    @Test("Rejects malformed options and successful responses through the public operation", arguments: [InvalidData.verbatimNull, .languageNumber, .diarizationNumber, .infiniteNumber, .response])
    func rejectsMalformedData(data: InvalidData) async throws {
        let fetch: FetchFunction = { request in
            if request.httpMethod == "POST" { return response(request, #"{"id":"job","status":"transcribed"}"#) }
            return response(request, #"{"monologues":[{"elements":[{"ts":"invalid"}]}]}"#)
        }
        let model = createRevAI(settings: .init(apiKey: "key", fetch: fetch)).transcription(modelId: .machine)
        do {
            _ = try await model.doGenerate(options: .init(
                audio: .binary(Data()), mediaType: "audio/wav",
                providerOptions: data.options.map { ["revai": $0] }
            ))
            Issue.record("Expected boundary validation failure")
        } catch let error as InvalidArgumentError {
            #expect(data.options != nil)
            #expect(error.argument == "providerOptions")
        } catch let error as APICallError {
            #expect(data.options == nil)
            #expect(error.statusCode == 200)
            #expect(error.cause is TypeValidationError)
        }
    }

    @Test("Returns job submission and polling failures as AISDK errors", arguments: [false, true])
    func jobFailure(submissionFailed: Bool) async throws {
        let fetch: FetchFunction = { request in
            if request.httpMethod == "POST", !submissionFailed {
                return response(request, #"{"id":"job","status":"in_progress"}"#)
            }
            return response(request, #"{"id":"job","status":"failed","reason":"invalid_media"}"#)
        }
        let model = createRevAI(settings: .init(apiKey: "key", fetch: fetch)).transcription(modelId: .machine)
        do {
            _ = try await model.doGenerate(options: .init(audio: .binary(Data()), mediaType: "audio/wav"))
            Issue.record("Expected job failure")
        } catch let error as any AISDKError {
            #expect(error.name == (submissionFailed ? "TranscriptionJobSubmissionFailed" : "TranscriptionJobFailed"))
            #expect(error.cause != nil)
            #expect(hasMarker(error, marker: "vercel.ai.error"))
        }
    }

    @Test("Cancellation stops an unfinished job before the polling delay")
    func cancelsPolling() async throws {
        final class Abort: @unchecked Sendable {
            private let lock = NSLock()
            private var value = false
            func set() { lock.withLock { value = true } }
            func get() -> Bool { lock.withLock { value } }
        }
        let abort = Abort()
        let fetch: FetchFunction = { request in
            if request.httpMethod == "POST" { return response(request, #"{"id":"job","status":"in_progress"}"#) }
            abort.set()
            return response(request, #"{"id":"job","status":"in_progress"}"#)
        }
        let model = createRevAI(settings: .init(apiKey: "key", fetch: fetch)).transcription(modelId: .machine)
        await #expect(throws: CancellationError.self) {
            try await model.doGenerate(options: .init(audio: .binary(Data()), mediaType: "audio/wav", abortSignal: { abort.get() }))
        }
    }
}
