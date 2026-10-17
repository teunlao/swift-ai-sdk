import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class OpenAITranscriptionModel: TranscriptionModelV4 {
    public let modelId: String
    private let config: OpenAIConfig
    public var provider: String { config.provider }

    public init(modelId: OpenAITranscriptionModelId, config: OpenAIConfig) {
        self.modelId = modelId.rawValue
        self.config = config
    }

    public func doGenerate(options: TranscriptionModelV4CallOptions) async throws -> TranscriptionModelV4Result {
        if isRealtime {
            throw UnsupportedFunctionalityError(functionality: "non-streaming transcription with \(modelId)")
        }
        let timestamp = config._internal?.currentDate?() ?? Date()
        let settings = try await parseProviderOptions(provider: "openai", providerOptions: options.providerOptions, schema: openAITranscriptionModelOptionsSchema)
        var form = MultipartFormDataBuilder()
        form.appendField(name: "model", value: modelId)
        let data: Data
        switch options.audio {
        case .binary(let value): data = value
        case .base64(let value): data = try convertBase64ToData(value)
        }
        form.appendFile(name: "file", filename: "audio.\(mediaTypeToExtension(options.mediaType))", contentType: options.mediaType, data: data)
        if modelId == "whisper-1" { form.appendField(name: "response_format", value: "verbose_json") }
        let diarized = modelId == "gpt-4o-transcribe-diarize"
        if let settings {
            for value in settings.include ?? [] { form.appendField(name: "include[]", value: value) }
            if let value = settings.language { form.appendField(name: "language", value: value) }
            if let value = settings.prompt { form.appendField(name: "prompt", value: value) }
            if modelId != "whisper-1" {
                let format = settings.responseFormat ?? (diarized ? "diarized_json" : ["gpt-4o-transcribe", "gpt-4o-mini-transcribe"].contains(modelId) ? "json" : "verbose_json")
                form.appendField(name: "response_format", value: format)
            }
            if let value = settings.temperature { form.appendField(name: "temperature", value: jsNumberString(value)) }
            for value in settings.timestampGranularities ?? [] { form.appendField(name: "timestamp_granularities[]", value: value) }
        } else if diarized {
            form.appendField(name: "response_format", value: "diarized_json")
        }
        if let chunking = settings?.chunkingStrategy ?? (diarized ? .auto : nil) {
            let value: String
            switch chunking {
            case .auto: value = "auto"
            case let .serverVAD(threshold, prefixPaddingMs, silenceDurationMs):
                var vad: JSONObject = ["type": "server_vad"]
                if let threshold { vad["threshold"] = .number(threshold) }
                if let prefixPaddingMs { vad["prefix_padding_ms"] = .number(Double(prefixPaddingMs)) }
                if let silenceDurationMs { vad["silence_duration_ms"] = .number(Double(silenceDurationMs)) }
                value = try openAIJSONStringify(.object(vad))
            }
            form.appendField(name: "chunking_strategy", value: value)
        }
        let result = try await postToAPI(
            url: config.url(.init(modelId: modelId, path: "/audio/transcriptions")),
            headers: combineHeaders(try config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 },
            body: PostBody(content: .multipartFormData(form), values: form.values),
            failedResponseHandler: openAIFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: openAITranscriptionResponseSchema),
            isAborted: options.abortSignal, fetch: config.fetch
        )
        let response = result.value
        let segments = response.segments?.map { TranscriptionModelV4Result.Segment(text: $0.text, startSecond: $0.start, endSecond: $0.end) }
            ?? response.words?.map { .init(text: $0.word, startSecond: $0.start, endSecond: $0.end) } ?? []
        let speakers: [JSONValue] = response.segments?.compactMap {
            guard case .diarized(let segment) = $0 else { return nil }
            return ["text": .string(segment.text), "startSecond": .number(segment.start), "endSecond": .number(segment.end), "speaker": .string(segment.speaker)]
        } ?? []
        return TranscriptionModelV4Result(
            text: response.text, segments: segments, language: response.language.flatMap { transcriptionLanguages[$0] },
            durationInSeconds: response.duration, warnings: [], usage: response.usage,
            response: .init(timestamp: timestamp, modelId: modelId, headers: result.responseHeaders, body: result.rawValue),
            providerMetadata: speakers.isEmpty ? nil : ["openai": ["segments": .array(speakers)]]
        )
    }

    public func doStream(options: TranscriptionModelV4StreamOptions) async throws -> TranscriptionModelV4StreamResult {
        if !isRealtime {
            throw UnsupportedFunctionalityError(functionality: "streaming transcription with \(modelId)")
        }
        let timestamp = config._internal?.currentDate?() ?? Date()
        let settings = try await parseProviderOptions(provider: "openai", providerOptions: options.providerOptions, schema: openAITranscriptionModelOptionsSchema)
        let rawOptions = options.providerOptions?["openai"] ?? [:]
        let warnings: [SharedV4Warning] = ["include", "prompt", "temperature", "timestampGranularities"].compactMap {
            guard let value = rawOptions[$0], value != .null else { return nil }
            return .unsupported(feature: "providerOptions.openai.\($0)", details: "OpenAI streaming transcription does not support \($0).")
        }
        let headers = combineHeaders(try config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 }
        let handshake = transcriptionHandshake(headers)
        var request = URLRequest(url: try toWebSocketURL(config.url(.init(modelId: modelId, path: "/realtime?intent=transcription"))))
        for (key, value) in handshake.headers { request.setValue(value, forHTTPHeaderField: key) }
        if !handshake.protocols.isEmpty {
            request.setValue(handshake.protocols.joined(separator: ", "), forHTTPHeaderField: "Sec-WebSocket-Protocol")
        }
        var format: JSONObject = ["type": .string(options.inputAudioFormat.type)]
        if let rate = options.inputAudioFormat.rate { format["rate"] = .number(Double(rate)) }
        var transcription: JSONObject = ["model": .string(modelId)]
        if let language = settings?.language { transcription["language"] = .string(language) }
        if let delay = settings?.streaming?.delay { transcription["delay"] = .string(delay) }
        var session: JSONObject = ["type": "transcription", "audio": ["input": [
            "format": .object(format), "transcription": .object(transcription), "turn_detection": .null
        ]]]
        if let include = settings?.streaming?.include { session["include"] = .array(include.map(JSONValue.string)) }
        let update: JSONValue = ["type": "session.update", "session": .object(session)]
        let pair = AsyncThrowingStream<TranscriptionModelV4StreamPart, Error>.makeStream()
        let owner = TranscriptionSession(config: config, options: options, request: request, update: update, language: settings?.language, warnings: warnings, continuation: pair.continuation)
        pair.continuation.onTermination = { @Sendable _ in Task { await owner.terminate(.cancelled) } }
        await owner.start()
        return TranscriptionModelV4StreamResult(
            stream: pair.stream, request: .init(body: update), response: .init(timestamp: timestamp, modelId: modelId)
        )
    }

    private var isRealtime: Bool { modelId == "gpt-realtime-whisper" || modelId.hasPrefix("gpt-realtime-whisper-") }
}

private actor TranscriptionSession {
    enum Completion {
        case transcript(text: String, id: String?)
        case closed
        case failed(any Error)
        case cancelled
    }

    private let config: OpenAIConfig
    private let options: TranscriptionModelV4StreamOptions
    private let request: URLRequest
    private let update: JSONValue
    private let language: String?
    private let warnings: [SharedV4Warning]
    private let continuation: AsyncThrowingStream<TranscriptionModelV4StreamPart, Error>.Continuation
    private var connection: (any WebSocketLike)?
    private var sender: Task<Void, Never>?
    private var receiver: Task<Void, Never>?
    private var abortObserver: Task<Void, Never>?
    private var finished = false

    init(config: OpenAIConfig, options: TranscriptionModelV4StreamOptions, request: URLRequest, update: JSONValue, language: String?, warnings: [SharedV4Warning], continuation: AsyncThrowingStream<TranscriptionModelV4StreamPart, Error>.Continuation) {
        self.config = config; self.options = options; self.request = request; self.update = update
        self.language = language; self.warnings = warnings; self.continuation = continuation
    }

    func start() async {
        guard !finished else { return }
        if Task.isCancelled || options.abortSignal?() == true {
            await terminate(.failed(CancellationError()))
            return
        }
        do {
            let socket = try (config.webSocket ?? defaultWebSocketConstructor())(request)
            connection = socket
            sender = Task { await sendAudio(socket) }
            receiver = Task { await receive(socket) }
            if let signal = options.abortSignal {
                // A closure-only signal has no notification channel.
                abortObserver = Task {
                    while !Task.isCancelled {
                        if signal() { await terminate(.failed(CancellationError())); return }
                        do { try await Task.sleep(for: .milliseconds(20)) } catch { return }
                    }
                }
            }
        } catch { await terminate(.failed(error)) }
    }

    private func sendAudio(_ socket: any WebSocketLike) async {
        do {
            do { try await socket.waitUntilOpen() }
            catch is CancellationError { throw CancellationError() }
            catch { throw TranscriptionStreamError(message: "OpenAI realtime transcription error") }
            guard !finished else { return }
            continuation.yield(.streamStart(warnings: warnings))
            try await socket.send(.text(openAIJSONStringify(update)))
            for try await audio in options.audio {
                try Task.checkCancellation()
                guard !finished else { return }
                let encoded: String
                switch audio {
                case .binary(let value): encoded = convertToBase64(.data(value))
                case .base64(let value): encoded = convertToBase64(.string(value))
                }
                try await socket.send(.text(openAIJSONStringify(["type": "input_audio_buffer.append", "audio": .string(encoded)])))
                try await socket.waitForBufferDrain()
            }
            if !finished {
                try Task.checkCancellation()
                try await socket.send(.text(openAIJSONStringify(["type": "input_audio_buffer.commit"])))
            }
        } catch { await terminate(.failed(error)) }
    }

    private func receive(_ socket: any WebSocketLike) async {
        do {
            for try await message in socket.messages {
                guard !finished else { return }
                let text = readWebSocketMessageText(message)
                let parsed = await safeParseJSON(ParseJSONOptions(text: text))
                guard case .success(let raw, _) = parsed else { continue }
                guard !finished else { return }
                if options.includeRawChunks == true { continuation.yield(.raw(rawValue: raw)) }
                if raw == .null {
                    let error = TypeValidationError.wrap(value: raw, cause: TranscriptionStreamError(message: "Expected a realtime transcription event"))
                    await terminate(.failed(error))
                    return
                }
                guard case .object(let event) = raw, case .string(let type) = event["type"] else { continue }
                switch type {
                case "conversation.item.input_audio_transcription.delta":
                    continuation.yield(.transcriptDelta(id: event["item_id"]?.stringValue, delta: event["delta"]?.stringValue ?? "", providerMetadata: nil))
                case "conversation.item.input_audio_transcription.completed":
                    await terminate(.transcript(text: event["transcript"]?.stringValue ?? "", id: event["item_id"]?.stringValue))
                    return
                case "error":
                    let message = event["error"]?.objectValue?["message"]?.stringValue ?? "OpenAI realtime error"
                    await terminate(.failed(TranscriptionStreamError(message: message)))
                    return
                default: break
                }
            }
            await terminate(.closed)
        } catch WebSocketError.closed {
            await terminate(.closed)
        } catch {
            await terminate(.failed(TranscriptionStreamError(message: "OpenAI realtime transcription error")))
        }
    }

    func terminate(_ completion: Completion) async {
        guard !finished else { return }
        finished = true
        sender?.cancel(); sender = nil
        receiver?.cancel(); receiver = nil
        abortObserver?.cancel(); abortObserver = nil
        let code: Int? = if case .transcript = completion { 1000 } else { nil }
        connection?.close(code: code)
        connection = nil
        await cancelStream(options.audio)
        switch completion {
        case .transcript(let text, let id):
            if let id {
                continuation.yield(.transcriptFinal(id: id, text: text, startSecond: nil, endSecond: nil, channelIndex: nil, providerMetadata: nil))
            }
            continuation.yield(.finish(text: text, segments: [], language: language, durationInSeconds: nil, providerMetadata: nil))
            continuation.finish()
        case .failed(let error): continuation.finish(throwing: error)
        case .closed, .cancelled: continuation.finish()
        }
    }
}

private struct TranscriptionStreamError: Error, LocalizedError, CustomStringConvertible {
    let message: String
    var errorDescription: String? { message }
    var description: String { message }
}

private func transcriptionHandshake(_ headers: [String: String]) -> (protocols: [String], headers: [String: String]) {
    let authorization = headers.first { $0.key.lowercased() == "authorization" }?.value
    let expression = try! NSRegularExpression(pattern: "^bearer\\s+(.+)$", options: .caseInsensitive)
    guard let authorization, let match = expression.firstMatch(in: authorization, range: NSRange(authorization.startIndex..., in: authorization)),
          let range = Range(match.range(at: 1), in: authorization) else { return (["realtime"], headers) }
    return (["realtime", "openai-insecure-api-key.\(authorization[range])"], headers.filter { $0.key.lowercased() != "authorization" })
}

private extension JSONValue {
    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }
    var objectValue: JSONObject? {
        guard case .object(let value) = self else { return nil }
        return value
    }
}

private let transcriptionLanguages: [String: String] = [
    "afrikaans": "af", "arabic": "ar", "armenian": "hy", "azerbaijani": "az", "belarusian": "be",
    "bosnian": "bs", "bulgarian": "bg", "catalan": "ca", "chinese": "zh", "croatian": "hr",
    "czech": "cs", "danish": "da", "dutch": "nl", "english": "en", "estonian": "et", "finnish": "fi",
    "french": "fr", "galician": "gl", "german": "de", "greek": "el", "hebrew": "he", "hindi": "hi",
    "hungarian": "hu", "icelandic": "is", "indonesian": "id", "italian": "it", "japanese": "ja",
    "kannada": "kn", "kazakh": "kk", "korean": "ko", "latvian": "lv", "lithuanian": "lt",
    "macedonian": "mk", "malay": "ms", "marathi": "mr", "maori": "mi", "nepali": "ne",
    "norwegian": "no", "persian": "fa", "polish": "pl", "portuguese": "pt", "romanian": "ro",
    "russian": "ru", "serbian": "sr", "slovak": "sk", "slovenian": "sl", "spanish": "es",
    "swahili": "sw", "swedish": "sv", "tagalog": "tl", "tamil": "ta", "thai": "th", "turkish": "tr",
    "ukrainian": "uk", "urdu": "ur", "vietnamese": "vi", "welsh": "cy"
]
