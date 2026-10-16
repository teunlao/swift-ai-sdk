import Foundation
import AISDKProvider
import AISDKProviderUtils

public typealias GoogleTranscriptionModelId = String

public struct GoogleTranscriptionModelOptions: Sendable, Equatable, Codable {
    public enum Mode: String, Sendable, Codable { case smart = "SMART", verbatim = "VERBATIM" }
    public var languageCodes: [String]?
    public var customVocabulary: [String]?
    public var wordTimestamp: Bool?
    public var diarization: Bool?
    public var mode: Mode?
    public init(languageCodes: [String]? = nil, customVocabulary: [String]? = nil, wordTimestamp: Bool? = nil, diarization: Bool? = nil, mode: Mode? = nil) {
        self.languageCodes = languageCodes; self.customVocabulary = customVocabulary
        self.wordTimestamp = wordTimestamp; self.diarization = diarization; self.mode = mode
    }
    var audioConfig: JSONObject {
        var result: JSONObject = [:]
        if let languageCodes { result["languageCodes"] = .array(languageCodes.map(JSONValue.string)) }
        if let customVocabulary { result["customVocabulary"] = .array(customVocabulary.map(JSONValue.string)) }
        if let wordTimestamp { result["wordTimestamp"] = .bool(wordTimestamp) }
        if let diarization { result["diarization"] = .bool(diarization) }
        if let mode { result["mode"] = .string(mode.rawValue) }
        return result
    }
    var interactionsConfig: JSONObject {
        var result: JSONObject = [:]
        if let languageCodes { result["language_codes"] = .array(languageCodes.map(JSONValue.string)) }
        if let customVocabulary { result["custom_vocabulary"] = .array(customVocabulary.map(JSONValue.string)) }
        if mode != nil || diarization == true || wordTimestamp == true {
            var modeConfig: JSONObject = ["type": .string((mode?.rawValue ?? "VERBATIM").lowercased())]
            if diarization == true { modeConfig["diarization_mode"] = .string("speaker") }
            if wordTimestamp == true { modeConfig["timestamp_granularities"] = .array([.string("word")]) }
            result["mode"] = .object(modeConfig)
        }
        return result
    }
}

private let googleTranscriptionOptionsSchema = FlexibleSchema(Schema<GoogleTranscriptionModelOptions>(
    jsonSchemaResolver: { .object(["type": .string("object")]) }, validator: { value in
        do {
            let json = try jsonValue(from: value)
            guard case .object(let object) = json else {
                throw SchemaValidationIssuesError(vendor: "google", issues: "Provider options must be an object")
            }
            for key in ["languageCodes", "customVocabulary", "wordTimestamp", "diarization", "mode"] where object[key] == .null {
                throw SchemaValidationIssuesError(vendor: "google", issues: "\(key) must not be null")
            }
            return .success(value: try JSONDecoder().decode(GoogleTranscriptionModelOptions.self, from: JSONEncoder().encode(json)))
        } catch { return .failure(error: TypeValidationError.wrap(value: value, cause: error)) }
    }
))

public final class GoogleTranscriptionModel: TranscriptionModelV4 {
    public struct LiveRequest: Sendable {
        public let url: URL
        public let model: String
        public let headers: [String: String]
        public init(url: URL, model: String, headers: [String: String]) {
            self.url = url; self.model = model; self.headers = headers
        }
    }
    public struct Config: Sendable {
        public let provider: String
        public let baseURL: String
        public let headers: @Sendable () throws -> [String: String?]
        public let fetch: FetchFunction?
        public let webSocket: GoogleWebSocketFactory?
        public let resolveBaseURL: (@Sendable () throws -> String)?
        public let liveRequest: (@Sendable (String, [String: String]) async throws -> LiveRequest)?
        public init(provider: String, baseURL: String, headers: @escaping @Sendable () throws -> [String: String?] = { [:] }, fetch: FetchFunction? = nil, webSocket: GoogleWebSocketFactory? = nil, resolveBaseURL: (@Sendable () throws -> String)? = nil, liveRequest: (@Sendable (String, [String: String]) async throws -> LiveRequest)? = nil) {
            self.provider = provider; self.baseURL = baseURL; self.headers = headers; self.fetch = fetch
            self.webSocket = webSocket; self.resolveBaseURL = resolveBaseURL; self.liveRequest = liveRequest
        }
    }
    private struct Response: Decodable, Sendable {
        struct Step: Decodable, Sendable {
            struct Content: Decodable, Sendable {
                struct Annotation: Decodable, Sendable {
                    let type: String?
                    let text: String?
                    let start_offset: String?
                    let end_offset: String?
                }
                let type: String?
                let text: String?
                let annotations: [Annotation]?
            }
            let content: [Content]?
        }
        let steps: [Step]?
        let usage: JSONObject?
    }
    public let modelId: String
    public var provider: String { config.provider }
    private let config: Config
    public init(modelId: String, config: Config) { self.modelId = modelId; self.config = config }

    private func parseOptions(_ options: SharedV4ProviderOptions?) async throws -> GoogleTranscriptionModelOptions? {
        let namespaces = provider.hasPrefix("google.vertex.") ? ["googleVertex", "vertex", "google"] : ["google"]
        for namespace in namespaces {
            if let parsed = try await parseProviderOptions(provider: namespace, providerOptions: options, schema: googleTranscriptionOptionsSchema) { return parsed }
        }
        return nil
    }

    public func doGenerate(options: TranscriptionModelV4CallOptions) async throws -> TranscriptionModelV4Result {
        guard !modelId.contains("-live") else {
            throw InvalidArgumentError(argument: "modelId", message: "Model '\(modelId)' only supports streaming transcription. Use a unary model such as 'gemini-3.5-transcribe'.")
        }
        let timestamp = Date()
        let parsed = try await parseOptions(options.providerOptions)
        let data: String
        switch options.audio { case .base64(let value): data = value; case .binary(let value): data = value.base64EncodedString() }
        var body: JSONObject = ["model": .string(modelId), "input": .array([.object([
            "type": .string("audio"), "data": .string(data), "mime_type": .string(options.mediaType)
        ])])]
        if let config = parsed?.interactionsConfig, !config.isEmpty {
            body["generation_config"] = .object(["transcription_config": .object(config)])
        }
        let result = try await postJsonToAPI(
            url: "\(try config.resolveBaseURL?() ?? config.baseURL)/interactions",
            headers: combineHeaders(try config.headers(), options.headers).compactMapValues { $0 }, body: JSONValue.object(body),
            failedResponseHandler: googleFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: FlexibleSchema(Schema<Response>.codable(
                Response.self, jsonSchema: .object(["type": .string("object")])
            ))), isAborted: options.abortSignal, fetch: config.fetch
        )
        var text = ""
        var segments: [TranscriptionModelV4Result.Segment] = []
        for step in result.value.steps ?? [] {
            for part in step.content ?? [] where part.type == "text" {
                guard let value = part.text else { continue }
                text += value
                for annotation in part.annotations ?? [] where annotation.type == "word_info" {
                    guard let word = annotation.text, let start = googleTranscriptionOffset(annotation.start_offset), let end = googleTranscriptionOffset(annotation.end_offset) else { continue }
                    segments.append(.init(text: word, startSecond: start, endSecond: end))
                }
            }
        }
        return .init(text: text, segments: segments, usage: result.value.usage,
                     response: .init(timestamp: timestamp, modelId: modelId, headers: result.responseHeaders, body: result.rawValue),
                     providerMetadata: result.value.usage.map { ["google": ["usage": .object($0)]] })
    }

    public func doStream(options: TranscriptionModelV4StreamOptions) async throws -> TranscriptionModelV4StreamResult {
        guard modelId.contains("-live") else {
            throw InvalidArgumentError(argument: "modelId", message: "Model '\(modelId)' does not support streaming transcription. Use a live model such as 'gemini-3.5-transcribe-live'.")
        }
        guard options.inputAudioFormat.type == "audio/pcm", options.inputAudioFormat.rate == nil || options.inputAudioFormat.rate == 16000 else {
            throw InvalidArgumentError(argument: "inputAudioFormat", message: "The Gemini Live transcription API only supports 16kHz 16-bit PCM input audio.")
        }
        let timestamp = Date()
        let parsed = try await parseOptions(options.providerOptions)
        let headers = combineHeaders(try config.headers(), options.headers).compactMapValues { $0 }
        let request: LiveRequest
        if let live = config.liveRequest { request = try await live(modelId, headers) }
        else {
            guard let key = headers.first(where: { $0.key.lowercased() == "x-goog-api-key" })?.value else {
                throw LoadAPIKeyError(message: "Google Generative AI API key is required for streaming transcription.")
            }
            guard var url = URLComponents(string: try config.resolveBaseURL?() ?? config.baseURL) else {
                throw InvalidArgumentError(argument: "baseURL", message: "Invalid transcription base URL")
            }
            var path = url.path
            if path.hasSuffix("/v1beta") { path.removeLast("/v1beta".count) }
            else if path.hasSuffix("/v1alpha") { path.removeLast("/v1alpha".count) }
            if path.hasSuffix("/") { path.removeLast() }
            url.scheme = url.scheme == "https" ? "wss" : "ws"
            url.path = path + "/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"
            url.queryItems = (url.queryItems ?? []).filter { $0.name != "key" } + [.init(name: "key", value: key)]
            guard let address = url.url else { throw InvalidArgumentError(argument: "baseURL", message: "Invalid transcription base URL") }
            request = .init(url: address, model: getGoogleModelPath(modelId), headers: headers.filter { $0.key.lowercased() != "x-goog-api-key" })
        }
        let setup: JSONValue = .object(["model": .string(request.model), "inputAudioTranscription": .object(parsed?.audioConfig ?? [:])])
        let pair = AsyncThrowingStream<TranscriptionModelV4StreamPart, Error>.makeStream()
        let session = GoogleLiveTranscriptionSession(
            factory: config.webSocket ?? defaultGoogleWebSocket, request: request,
            setup: setup, options: options, continuation: pair.continuation
        )
        pair.continuation.onTermination = { _ in Task { await session.cancel() } }
        Task { await session.start() }
        return .init(stream: pair.stream, request: .init(body: setup), response: .init(timestamp: timestamp, modelId: modelId))
    }
}

private func googleTranscriptionOffset(_ value: String?) -> Double? {
    guard let value else { return nil }
    guard let range = value.range(of: "^\\s*[+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][+-]?[0-9]+)?", options: .regularExpression),
          let number = Double(value[range].trimmingCharacters(in: .whitespacesAndNewlines)), number.isFinite else { return nil }
    return number
}

private struct GoogleLiveTranscriptionFailure: Error, LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}

private actor GoogleLiveTranscriptionSession {
    private let factory: GoogleWebSocketFactory
    private let request: GoogleTranscriptionModel.LiveRequest
    private let setup: JSONValue
    private let options: TranscriptionModelV4StreamOptions
    private let continuation: AsyncThrowingStream<TranscriptionModelV4StreamPart, Error>.Continuation
    private var socket: (any GoogleWebSocketConnection)?
    private var sender: Task<Void, Never>?
    private var receiver: Task<Void, Never>?
    private var abortObserver: Task<Void, Never>?
    private var finishTimer: Task<Void, Never>?
    private var setupWaiter: CheckedContinuation<Void, Error>?
    private var acknowledged = false
    private var closed = false
    private var audioStarted = false
    private var audioEnded = false
    private var segment = 0
    private var buffer = ""
    private var interim = ""
    private var text = ""
    private var language: String?
    private var usage: JSONObject?

    init(factory: @escaping GoogleWebSocketFactory, request: GoogleTranscriptionModel.LiveRequest, setup: JSONValue, options: TranscriptionModelV4StreamOptions, continuation: AsyncThrowingStream<TranscriptionModelV4StreamPart, Error>.Continuation) {
        self.factory = factory; self.request = request; self.setup = setup; self.options = options; self.continuation = continuation
    }
    func start() {
        guard !closed else { return }
        do {
            if options.abortSignal?() == true { throw CancellationError() }
            let socket = try factory(.init(url: request.url, headers: request.headers))
            self.socket = socket
            receiver = Task {
                do {
                    for try await message in socket.messages {
                        if Task.isCancelled { return }
                        await self.receive(message)
                    }
                    self.socketClosed()
                } catch { self.socketClosed(error) }
            }
            sender = Task { await self.sendAudio(socket) }
            if let isAborted = options.abortSignal {
                abortObserver = Task {
                    do {
                        while !Task.isCancelled {
                            if isAborted() { self.fail(CancellationError()); return }
                            try await Task.sleep(nanoseconds: 50_000_000)
                        }
                    } catch {}
                }
            }
        } catch { fail(error) }
    }
    private func waitForSetup() async throws {
        if closed { throw CancellationError() }
        if acknowledged { return }
        try await withCheckedThrowingContinuation { setupWaiter = $0 }
    }
    private func sendAudio(_ socket: any GoogleWebSocketConnection) async {
        do {
            try await socket.waitUntilOpen()
            guard !closed else { return }
            continuation.yield(.streamStart(warnings: []))
            try await socket.send(encode(.object(["setup": setup])))
            try await waitForSetup()
            guard !closed else { return }
            audioStarted = true
            for try await chunk in options.audio {
                try Task.checkCancellation()
                guard !closed else { return }
                if options.abortSignal?() == true { throw CancellationError() }
                let data: String
                switch chunk { case .binary(let value): data = value.base64EncodedString(); case .base64(let value): data = value }
                try await socket.send(encode(.object(["realtimeInput": .object(["audio": .object([
                    "data": .string(data), "mimeType": .string("audio/pcm;rate=\(options.inputAudioFormat.rate ?? 16000)")
                ])])])) )
            }
            guard !closed else { return }
            audioEnded = true
            try await socket.send(encode(.object(["realtimeInput": .object(["audioStreamEnd": .bool(true)])])))
            scheduleFinish()
        } catch { if !closed { fail(error) } }
    }
    private func receive(_ message: String) async {
        guard !closed, let data = message.data(using: .utf8),
              let raw = try? JSONDecoder().decode(JSONValue.self, from: data) else { return }
        if options.includeRawChunks == true { continuation.yield(.raw(rawValue: raw)) }
        guard case .object(let event) = raw else { return }
        if let complete = event["setupComplete"], complete != .null {
            acknowledged = true
            setupWaiter?.resume()
            setupWaiter = nil
        }
        if case .object(let metadata) = event["usageMetadata"] { usage = metadata }
        if case .object(let error) = event["error"] {
            fail(GoogleLiveTranscriptionFailure(message: string(error["message"]) ?? "Google Live API error")); return
        }
        let content: JSONObject
        if case .object(let object) = event["serverContent"] { content = object } else { content = [:] }
        if case .object(let partial) = content["interimInputTranscription"], let value = string(partial["text"]), !value.isEmpty {
            scheduleFinish(); interim = value
            continuation.yield(.transcriptPartial(id: segmentId, text: value, startSecond: nil, durationInSeconds: nil, channelIndex: nil, providerMetadata: nil))
        }
        let transcription = content["inputTranscription"] ?? event["inputTranscription"]
        if case .object(let transcript) = transcription {
            if let value = string(transcript["languageCode"]) { language = value }
            if let delta = string(transcript["text"]), !delta.isEmpty {
                scheduleFinish(); interim = ""; buffer += delta
                continuation.yield(.transcriptDelta(id: segmentId, delta: delta, providerMetadata: nil))
            }
            if transcript["finished"] == .bool(true) { completeSegment() }
        }
        if content["turnComplete"] == .bool(true) { completeSegment() }
        let status = string(content["interactionStatus"])
        if audioEnded && (status == "IDLE" || status == "REQUIRES_ACTION" || (content["turnComplete"] == .bool(true) && status == nil)) { finish() }
    }
    private var segmentId: String { "google-segment-\(segment)" }
    private func completeSegment() {
        if buffer.isEmpty { buffer = interim }
        guard !buffer.isEmpty else { return }
        interim = ""
        continuation.yield(.transcriptFinal(id: segmentId, text: buffer, startSecond: nil, endSecond: nil, channelIndex: nil, providerMetadata: nil))
        text += text.isEmpty ? buffer : " \(buffer)"
        buffer = ""; segment += 1
    }
    private func scheduleFinish() {
        guard !closed, audioEnded else { return }
        finishTimer?.cancel()
        finishTimer = Task {
            do { try await Task.sleep(nanoseconds: 3_000_000_000); self.finish() } catch {}
        }
    }
    private func socketClosed(_ error: (any Error)? = nil) {
        guard !closed else { return }
        if audioEnded { finish() }
        else { fail(error ?? GoogleLiveTranscriptionFailure(message: "Google Live transcription WebSocket closed unexpectedly before finishing")) }
    }
    private func finish() {
        guard !closed else { return }
        completeSegment(); closed = true
        continuation.yield(.finish(text: text, segments: [], language: language, durationInSeconds: nil, usage: usage,
                                   providerMetadata: usage.map { ["google": ["usageMetadata": .object($0)]] }))
        continuation.finish(); cleanup(code: 1000)
    }
    private func fail(_ error: any Error) {
        guard !closed else { return }
        closed = true; continuation.finish(throwing: error); cleanup(code: nil)
    }
    func cancel() { if !closed { closed = true; cleanup(code: nil) } }
    private func cleanup(code: Int?) {
        finishTimer?.cancel(); sender?.cancel(); receiver?.cancel(); abortObserver?.cancel()
        setupWaiter?.resume(throwing: CancellationError()); setupWaiter = nil
        socket?.close(code: code)
        if !audioStarted {
            let audio = options.audio
            let task = Task { var iterator = audio.makeAsyncIterator(); _ = try? await iterator.next() }
            task.cancel()
        }
    }
    private func encode(_ value: JSONValue) throws -> String { String(decoding: try JSONEncoder().encode(value), as: UTF8.self) }
    private func string(_ value: JSONValue?) -> String? { if case .string(let text) = value { return text }; return nil }
}
