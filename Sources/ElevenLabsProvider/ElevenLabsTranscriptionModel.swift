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

    public func doStream(options: TranscriptionModelV4StreamOptions) async throws -> TranscriptionModelV4StreamResult {
        guard modelIdentifier == .scribeV2Realtime else {
            throw UnsupportedFunctionalityError(functionality: "streaming transcription with \(modelId)")
        }
        let timestamp = config.currentDate()
        let parsed = try await parseProviderOptions(
            provider: "elevenlabs", providerOptions: options.providerOptions, schema: elevenLabsTranscriptionModelOptionsSchema
        )
        let streaming = parsed?.streaming
        var warnings: [SharedV4Warning] = []
        for name in ["diarize", "fileFormat", "numSpeakers", "tagAudioEvents", "timestampsGranularity"] {
            if let value = options.providerOptions?["elevenlabs"]?[name], value != .null {
                warnings.append(.unsupported(feature: "providerOptions.elevenlabs.\(name)", details: "ElevenLabs realtime transcription does not support \(name)."))
            }
        }
        if streaming?.filterBackgroundAudio == true,
           streaming?.includeTimestamps == true || streaming?.includeLanguageDetection == true {
            throw InvalidArgumentError(
                argument: "providerOptions",
                message: "providerOptions.elevenlabs.streaming.filterBackgroundAudio cannot be combined with includeTimestamps or includeLanguageDetection"
            )
        }
        let input = try RealtimeInput(options.inputAudioFormat)
        let url = try streamURL(input: input, language: parsed?.languageCode, streaming: streaming)
        let headers = combineHeaders(try config.headers(), options.headers?.mapValues(Optional.some))
        let webSocket = config.webSocket
        let stream = AsyncThrowingStream<TranscriptionModelV4StreamPart, Error> { continuation in
            let session = RealtimeSession(
                options: options, streaming: streaming, sampleRate: input.sampleRate,
                language: parsed?.languageCode, warnings: warnings, continuation: continuation
            )
            let startup = Task { await session.start(url: url, headers: headers, webSocket: webSocket) }
            continuation.onTermination = { _ in
                startup.cancel()
                Task { await session.cancel() }
            }
        }
        return .init(stream: stream, request: .init(body: url), response: .init(timestamp: timestamp, modelId: modelId))
    }

    private func streamURL(input: RealtimeInput, language: String?, streaming: ElevenLabsTranscriptionModelOptions.Streaming?) throws -> String {
        let base = try toWebSocketURL(config.url(.init(modelId: modelId, path: "/v1/speech-to-text/realtime")))
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { throw WebSocketError.invalidURL(base.absoluteString) }
        var items = components.queryItems ?? []
        func set(_ name: String, _ value: String?) {
            guard let value else { return }
            items.removeAll { $0.name == name }
            items.append(.init(name: name, value: value))
        }
        set("model_id", modelId)
        set("audio_format", input.audioFormat)
        set("commit_strategy", streaming?.commitStrategy?.rawValue)
        set("enable_logging", streaming?.enableLogging.map(String.init))
        set("filter_background_audio", streaming?.filterBackgroundAudio.map(String.init))
        set("include_language_detection", streaming?.includeLanguageDetection.map(String.init))
        let requiresDetails = streaming?.includeTimestamps == true || streaming?.includeLanguageDetection == true
        set("include_timestamps", requiresDetails ? "true" : streaming?.includeTimestamps.map(String.init))
        set("language_code", language)
        set("min_silence_duration_ms", streaming?.minSilenceDurationMs.map(String.init))
        set("min_speech_duration_ms", streaming?.minSpeechDurationMs.map(String.init))
        set("no_verbatim", streaming?.noVerbatim.map(String.init))
        set("vad_silence_threshold_secs", streaming?.vadSilenceThresholdSecs.map { String($0) })
        set("vad_threshold", streaming?.vadThreshold.map { String($0) })
        items += (streaming?.keyterms ?? []).map { .init(name: "keyterms", value: $0) }
        items += (streaming?.secondaryLanguages ?? []).map { .init(name: "secondary_languages", value: $0) }
        components.queryItems = items
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else { throw WebSocketError.invalidURL(base.absoluteString) }
        return url.absoluteString
    }

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

private struct RealtimeInput {
    let audioFormat: String
    let sampleRate: Int

    init(_ format: SharedV4AudioFormat) throws {
        if format.type.lowercased() == "audio/pcmu" {
            guard format.rate == nil || format.rate == 8000 else {
                throw InvalidArgumentError(argument: "inputAudioFormat", message: "ElevenLabs only supports audio/pcmu at 8000 Hz")
            }
            audioFormat = "ulaw_8000"
            sampleRate = 8000
        } else {
            let rate = format.rate ?? 16000
            guard format.type.lowercased() == "audio/pcm", [8000, 16000, 22050, 24000, 44100, 48000].contains(rate) else {
                throw InvalidArgumentError(argument: "inputAudioFormat", message: "ElevenLabs realtime transcription supports audio/pcm at 8000, 16000, 22050, 24000, 44100, or 48000 Hz, and audio/pcmu at 8000 Hz")
            }
            audioFormat = "pcm_\(rate)"
            sampleRate = rate
        }
    }
}

private actor RealtimeSession {
    private let options: TranscriptionModelV4StreamOptions
    private let streaming: ElevenLabsTranscriptionModelOptions.Streaming?
    private let sampleRate: Int
    private let warnings: [SharedV4Warning]
    private let continuation: AsyncThrowingStream<TranscriptionModelV4StreamPart, Error>.Continuation
    private var connection: WebSocketConnection?
    private var sender: Task<Void, Never>?
    private var receiver: Task<Void, Never>?
    private var finalization: Task<Void, Never>?
    private var finished = false
    private var endOfInput = false
    private var receivedFinalCommit = false
    private var sessionId: String?
    private var segmentIndex = 0
    private var commitCount = 0
    private var commitsAtEnd = 0
    private var finalCommitCount: Int?
    private var timestampedCount = 0
    private var language: String?
    private var texts: [String] = []
    private var segments: [TranscriptionModelV4Result.Segment] = []

    init(options: TranscriptionModelV4StreamOptions, streaming: ElevenLabsTranscriptionModelOptions.Streaming?, sampleRate: Int,
         language: String?, warnings: [SharedV4Warning], continuation: AsyncThrowingStream<TranscriptionModelV4StreamPart, Error>.Continuation) {
        self.options = options
        self.streaming = streaming
        self.sampleRate = sampleRate
        self.language = language
        self.warnings = warnings
        self.continuation = continuation
    }

    func start(url: String, headers: [String: String?], webSocket: WebSocketConstructor?) async {
        guard !finished, !Task.isCancelled else { cancel(); return }
        do {
            let connection = try connectToWebSocket(url: url, headers: headers, webSocket: webSocket, abortSignal: options.abortSignal)
            self.connection = connection
            try await connection.waitUntilOpen()
            guard !finished else { return }
            receiver = Task { await self.receive(connection) }
        } catch { fail(error) }
    }

    private func sendAudio(_ connection: WebSocketConnection) async {
        var firstChunk = true
        do {
            for try await chunk in options.audio {
                guard !finished, !Task.isCancelled else { return }
                let base64: String
                switch chunk {
                case .binary(let bytes): base64 = bytes.base64EncodedString()
                case .base64(let value): base64 = value
                }
                var frame: JSONObject = ["message_type": "input_audio_chunk", "audio_base_64": .string(base64), "commit": false, "sample_rate": .number(Double(sampleRate))]
                if firstChunk, let previousText = streaming?.previousText { frame["previous_text"] = .string(previousText) }
                try await send(frame, connection: connection)
                firstChunk = false
                try await connection.waitForBufferDrain()
            }
            guard !finished, !Task.isCancelled else { return }
            commitsAtEnd = commitCount
            endOfInput = true
            try await send(["message_type": "input_audio_chunk", "audio_base_64": "", "commit": true, "sample_rate": .number(Double(sampleRate))], connection: connection)
        } catch WebSocketError.closed { closed() }
        catch { fail(error) }
    }

    private func send(_ frame: JSONObject, connection: WebSocketConnection) async throws {
        let data = try JSONEncoder().encode(JSONValue.object(frame))
        try await connection.send(.text(String(decoding: data, as: UTF8.self)))
    }

    private func receive(_ connection: WebSocketConnection) async {
        do {
            for try await text in connection.messages {
                guard !finished else { return }
                let data = Data(text.utf8)
                guard let raw = try? JSONDecoder().decode(JSONValue.self, from: data) else { continue }
                if options.includeRawChunks == true { continuation.yield(.raw(rawValue: raw)) }
                guard let event = try? JSONDecoder().decode(RealtimeEvent.self, from: data) else { continue }
                accept(event, connection: connection)
            }
            closed()
        } catch WebSocketError.closed {
            if options.abortSignal?() == true || Task.isCancelled { fail(CancellationError()) }
            else { closed() }
        } catch { fail(error) }
    }

    private func accept(_ event: RealtimeEvent, connection: WebSocketConnection) {
        if let type = event.messageType, RealtimeEvent.errorTypes.contains(type) {
            if endOfInput, commitCount > 0 || timestampedCount > 0, RealtimeEvent.finalizationErrors.contains(type) {
                receivedFinalCommit = true
                finish()
            } else { fail(RealtimeFailure(message: event.error ?? "ElevenLabs realtime transcription error")) }
            return
        }
        let id = "\(sessionId ?? "session"):\(segmentIndex)"
        switch event.messageType {
        case "session_started":
            sessionId = event.sessionId
            continuation.yield(.streamStart(warnings: warnings))
            sender = Task { await self.sendAudio(connection) }
        case "partial_transcript":
            continuation.yield(.transcriptPartial(id: id, text: event.text ?? "", startSecond: nil, durationInSeconds: nil, channelIndex: nil, providerMetadata: nil))
        case "final_transcript", "committed_transcript":
            commitCount += 1
            let text = (event.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                texts.append(text)
                segmentIndex += 1
                continuation.yield(.transcriptFinal(id: id, text: text, startSecond: nil, endSecond: nil, channelIndex: nil, providerMetadata: nil))
            }
            if endOfInput, commitCount > commitsAtEnd {
                receivedFinalCommit = true
                finalCommitCount = commitCount
                if streaming?.includeTimestamps != true && streaming?.includeLanguageDetection != true || event.messageType == "final_transcript" {
                    scheduleFinish()
                }
            }
        case "final_transcript_with_timestamps", "committed_transcript_with_timestamps":
            let text = (event.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let timed = (event.words ?? []).compactMap { word -> TranscriptionModelV4Result.Segment? in
                guard let start = word.start, let end = word.end else { return nil }
                return .init(text: word.text ?? "", startSecond: start, endSecond: end)
            }
            language = event.languageCode ?? language
            // Plain and timestamped events describe the same commit.
            if texts.count <= timestampedCount, !text.isEmpty {
                texts.append(text)
                segmentIndex += 1
                continuation.yield(.transcriptFinal(
                    id: id, text: text, startSecond: streaming?.includeTimestamps == true ? timed.first?.startSecond : nil,
                    endSecond: streaming?.includeTimestamps == true ? timed.last?.endSecond : nil, channelIndex: nil, providerMetadata: nil
                ))
            }
            timestampedCount += 1
            if streaming?.includeTimestamps == true { segments += timed }
            if endOfInput, timestampedCount > commitsAtEnd, timestampedCount >= (finalCommitCount ?? 0) {
                receivedFinalCommit = true
                scheduleFinish()
            }
        default: break
        }
    }

    private func scheduleFinish() {
        finalization?.cancel()
        // Drain the paired detailed event and nearby VAD commits before closing.
        finalization = Task {
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            finish()
        }
    }

    private func closed() {
        guard !finished else { return }
        if endOfInput, receivedFinalCommit { finish() }
        else { fail(RealtimeFailure(message: "ElevenLabs realtime transcription stream closed before completion.")) }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        cleanup(code: 1000)
        continuation.yield(.finish(text: texts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines), segments: segments,
                                   language: language, durationInSeconds: segments.last?.endSecond, providerMetadata: nil))
        continuation.finish()
    }

    private func fail(_ error: Error) {
        guard !finished else { return }
        finished = true
        cleanup(code: nil)
        continuation.finish(throwing: error)
    }

    func cancel() {
        guard !finished else { return }
        finished = true
        cleanup(code: nil)
    }

    private func cleanup(code: Int?) {
        connection?.close(code: code)
        finalization?.cancel()
        sender?.cancel()
        receiver?.cancel()
        let audio = options.audio
        Task { await cancelStream(audio) }
    }
}

private struct RealtimeEvent: Decodable {
    struct Word: Decodable { let text: String?; let start: Double?; let end: Double? }
    let messageType: String?
    let sessionId: String?
    let text: String?
    let languageCode: String?
    let words: [Word]?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case messageType = "message_type", sessionId = "session_id", languageCode = "language_code"
        case text, words, error
    }

    static let errorTypes: Set<String> = [
        "auth_error", "chunk_size_exceeded", "commit_throttled", "error", "input_error", "insufficient_audio_activity",
        "queue_overflow", "quota_exceeded", "rate_limited", "resource_exhausted", "session_time_limit_exceeded", "transcriber_error", "unaccepted_terms"
    ]
    static let finalizationErrors: Set<String> = ["commit_throttled", "input_error", "insufficient_audio_activity"]
}

private struct RealtimeFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
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
