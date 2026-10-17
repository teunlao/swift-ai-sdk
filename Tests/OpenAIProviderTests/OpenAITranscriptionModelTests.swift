import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import OpenAIProvider

enum SocketFailure: Error, Equatable { case creation, send, audio, deadline }

final class TranscriptionAudioSource: @unchecked Sendable {
    let stream: AsyncThrowingStream<TranscriptionModelV4StreamAudio, Error>
    let continuation: AsyncThrowingStream<TranscriptionModelV4StreamAudio, Error>.Continuation
    private let lock = NSLock()
    private var cancelled = false
    let termination: AsyncStream<Void>

    init(chunks: [TranscriptionModelV4StreamAudio] = [], finished: Bool = false) {
        let pair = AsyncThrowingStream<TranscriptionModelV4StreamAudio, Error>.makeStream()
        stream = pair.stream
        continuation = pair.continuation
        let notice = AsyncStream<Void>.makeStream()
        termination = notice.stream
        continuation.onTermination = { [weak self] termination in
            if case .cancelled = termination { self?.lock.withLock { self?.cancelled = true } }
            notice.continuation.yield(())
            notice.continuation.finish()
        }
        for chunk in chunks { continuation.yield(chunk) }
        if finished { continuation.finish() }
    }

    var isCancelled: Bool { lock.withLock { cancelled } }
}

final class TranscriptionSocket: WebSocketLike, @unchecked Sendable {
    let messages: AsyncThrowingStream<WebSocketMessage, Error>
    let sent: AsyncStream<JSONValue>
    let draining: AsyncStream<Void>
    private let incoming: AsyncThrowingStream<WebSocketMessage, Error>.Continuation
    private let outgoing: AsyncStream<JSONValue>.Continuation
    private let drainNotice: AsyncStream<Void>.Continuation
    private let opened: AsyncThrowingStream<Void, Error>
    private let openGate: AsyncThrowingStream<Void, Error>.Continuation
    private let drained: AsyncThrowingStream<Void, Error>
    private let drainGate: AsyncThrowingStream<Void, Error>.Continuation
    private let lock = NSLock()
    private var requests: [URLRequest] = []
    private var values: [JSONValue] = []
    private var closes: [Int?] = []
    private let initiallyOpen: Bool
    private let blockDrain: Bool
    private let failSend: Bool

    init(open: Bool = true, blockDrain: Bool = false, failSend: Bool = false) {
        let input = AsyncThrowingStream<WebSocketMessage, Error>.makeStream()
        messages = input.stream; incoming = input.continuation
        let output = AsyncStream<JSONValue>.makeStream()
        sent = output.stream; outgoing = output.continuation
        let notice = AsyncStream<Void>.makeStream()
        draining = notice.stream; drainNotice = notice.continuation
        let opening = AsyncThrowingStream<Void, Error>.makeStream()
        opened = opening.stream; openGate = opening.continuation
        let drain = AsyncThrowingStream<Void, Error>.makeStream()
        drained = drain.stream; drainGate = drain.continuation
        initiallyOpen = open; self.blockDrain = blockDrain; self.failSend = failSend
    }

    func make(_ request: URLRequest) -> any WebSocketLike {
        lock.withLock { requests.append(request) }
        return self
    }

    func waitUntilOpen() async throws {
        if initiallyOpen { return }
        var iterator = opened.makeAsyncIterator()
        _ = try await iterator.next()
    }

    func waitForBufferDrain() async throws {
        drainNotice.yield(())
        if blockDrain {
            var iterator = drained.makeAsyncIterator()
            _ = try await iterator.next()
        }
    }

    func send(_ message: WebSocketMessage) async throws {
        let text = readWebSocketMessageText(message)
        if failSend && lock.withLock({ values.count >= 2 }) { throw SocketFailure.send }
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
        lock.withLock { values.append(value) }
        outgoing.yield(value)
    }

    func close(code: Int?) {
        lock.withLock { closes.append(code) }
        incoming.finish(); outgoing.finish(); drainNotice.finish()
        openGate.finish(throwing: CancellationError())
        drainGate.finish(throwing: CancellationError())
    }

    func message(_ text: String) { incoming.yield(.text(text)) }
    func fail() { incoming.finish(throwing: SocketFailure.send) }
    func remoteClose(code: Int? = nil, reason: String? = nil) {
        if code != nil || reason != nil { incoming.finish(throwing: WebSocketError.closed(code: code, reason: reason)) }
        else { incoming.finish() }
    }
    func open() { openGate.yield(()); openGate.finish() }
    func releaseDrain() { drainGate.yield(()); drainGate.finish() }
    var frames: [JSONValue] { lock.withLock { values } }
    var request: URLRequest? { lock.withLock { requests.first } }
    var closeCodes: [Int?] { lock.withLock { closes } }
}

private final class AbortFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func abort() { lock.withLock { value = true } }
    func read() -> Bool { lock.withLock { value } }
}

func transcriptionDeadline<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask { try await Task.sleep(for: .seconds(1)); throw SocketFailure.deadline }
        defer { group.cancelAll() }
        return try await group.next()!
    }
}

private func collect(_ stream: AsyncThrowingStream<TranscriptionModelV4StreamPart, Error>) async throws -> [TranscriptionModelV4StreamPart] {
    try await transcriptionDeadline {
        var parts: [TranscriptionModelV4StreamPart] = []
        for try await part in stream { parts.append(part) }
        return parts
    }
}

private func waitForCommit(_ socket: TranscriptionSocket) async throws {
    try await transcriptionDeadline {
        for await frame in socket.sent {
            if frame == .object(["type": .string("input_audio_buffer.commit")]) { return }
        }
        throw SocketFailure.deadline
    }
}

private func field(_ body: String, _ name: String) -> [String] {
    body.components(separatedBy: "\r\n--").compactMap { part in
        guard part.contains("name=\"\(name)\""), let separator = part.range(of: "\r\n\r\n") else { return nil }
        return String(part[separator.upperBound...].components(separatedBy: "\r\n").first ?? "")
    }
}

private func response(_ request: URLRequest, _ body: String, status: Int = 200) -> FetchResponse {
    FetchResponse(body: .data(Data(body.utf8)), urlResponse: HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: nil,
        headerFields: ["Content-Type": "application/json", "X-Request-ID": "request-1"]
    )!)
}

private func streamModel(_ socket: TranscriptionSocket) -> OpenAITranscriptionModel {
    OpenAITranscriptionModel(modelId: "gpt-realtime-whisper-2026-01-01", config: .init(
        provider: "openai.transcription", url: { "https://api.openai.com/v1\($0.path)" },
        headers: { ["aUtHoRiZaTiOn": "Bearer configured"] }, webSocket: socket.make,
        _internal: .init(currentDate: { Date(timeIntervalSince1970: 12) })
    ))
}

@Suite("OpenAITranscriptionModel")
struct OpenAITranscriptionModelTests {
    @Test func whisperMultipartWordsAndMetadata() async throws {
        let model = OpenAITranscriptionModel(modelId: "whisper-1", config: .init(
            provider: "openai.transcription", url: { "https://api.openai.com/v1\($0.path)" },
            headers: { ["Authorization": "Bearer configured"] }, fetch: { request in
                #expect(request.httpMethod == "POST")
                #expect(request.url?.path == "/v1/audio/transcriptions")
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer caller")
                #expect(request.value(forHTTPHeaderField: "X-Custom") == "yes")
                let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
                #expect(body.contains("filename=\"audio.wav\""))
                #expect(request.httpBody?.range(of: Data([13, 10, 251, 255, 13, 10])) != nil)
                #expect(field(body, "model") == ["whisper-1"])
                #expect(field(body, "response_format") == ["verbose_json"])
                #expect(field(body, "temperature") == ["0.25"])
                #expect(field(body, "timestamp_granularities[]") == ["word"])
                #expect(field(body, "include[]") == ["logprobs"])
                #expect(field(body, "prompt") == ["context"])
                #expect(field(body, "language") == ["en"])
                return response(request, #"{"text":"Hello","language":"english","duration":0.75,"words":[{"word":"Hello","start":0.125,"end":0.75}],"usage":{"type":"duration","seconds":0.75}}"#)
            }, _internal: .init(currentDate: { Date(timeIntervalSince1970: 12) })
        ))
        let result = try await model.doGenerate(options: .init(audio: .base64("\t- _ 8\r\n"), mediaType: "audio/x-wav", providerOptions: ["openai": [
            "language": "en", "prompt": "context", "temperature": 0.25,
            "timestampGranularities": ["word"], "include": ["logprobs"], "responseFormat": "json"
        ]], headers: ["authorization": "Bearer caller", "X-Custom": "yes"]))
        #expect(result.text == "Hello")
        #expect(result.segments == [.init(text: "Hello", startSecond: 0.125, endSecond: 0.75)])
        #expect(result.language == "en")
        #expect(result.durationInSeconds == 0.75)
        #expect(result.usage == ["type": "duration", "seconds": 0.75])
        #expect(result.response.timestamp == Date(timeIntervalSince1970: 12))
        #expect(result.response.modelId == "whisper-1")
        #expect(result.response.headers?["x-request-id"] == "request-1")
        let raw = try jsonValue(from: #require(result.response.body))
        if case .object(let body) = raw { #expect(body["text"] == "Hello") }
        else { Issue.record("Missing raw response object") }
    }

    @Test func diarizationDefaultsAndSpeakerMetadata() async throws {
        let model = OpenAITranscriptionModel(modelId: "gpt-4o-transcribe-diarize", config: .init(
            provider: "openai.transcription", url: { "https://api.openai.com/v1\($0.path)" }, fetch: { request in
                let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
                #expect(field(body, "response_format") == ["diarized_json"])
                #expect(field(body, "chunking_strategy") == ["auto"])
                #expect(body.contains("filename=\"audio.\""))
                return response(request, #"{"text":"lead Hello","segments":[{"id":0,"seek":0,"start":0,"end":0.125,"text":"lead ","tokens":[1],"temperature":0,"avg_logprob":-0.5,"compression_ratio":1.2,"no_speech_prob":0.1},{"type":"transcript.text.segment","id":"s1","start":0.125,"end":1.5,"text":"Hello","speaker":"A"}],"words":[{"word":"ignored","start":2,"end":3}],"usage":{"input_tokens":2,"details":{"audio":1.25}},"language":"unknown"}"#)
            }
        ))
        let result = try await model.doGenerate(options: .init(audio: .binary(Data([0, 255])), mediaType: "unknown"))
        #expect(result.segments == [.init(text: "lead ", startSecond: 0, endSecond: 0.125), .init(text: "Hello", startSecond: 0.125, endSecond: 1.5)])
        #expect(result.language == nil)
        #expect(result.usage == ["input_tokens": 2, "details": ["audio": 1.25]])
        #expect(result.providerMetadata?["openai"]?["segments"] == [[
            "text": "Hello", "startSecond": 0.125, "endSecond": 1.5, "speaker": "A"
        ]])
    }

    @Test(arguments: [false, true]) func optionsPresenceControlsDefaults(present: Bool) async throws {
        let model = OpenAITranscriptionModel(modelId: "gpt-4o-mini-transcribe", config: .init(
            provider: "openai.transcription", url: { _ in "https://api.openai.com/v1/audio/transcriptions" }, fetch: { request in
                let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
                #expect(field(body, "response_format") == (present ? ["json"] : []))
                #expect(field(body, "temperature") == (present ? ["0"] : []))
                #expect(field(body, "timestamp_granularities[]") == (present ? ["segment"] : []))
                return response(request, #"{"text":"ok","segments":[],"words":[{"word":"ignored","start":0,"end":1}]}"#)
            }
        ))
        let result = try await model.doGenerate(options: .init(audio: .binary(Data()), mediaType: "audio/pcm", providerOptions: present ? ["openai": [:]] : nil))
        #expect(result.segments == [])
    }

    @Test func serverVadAndResponseOverride() async throws {
        let model = OpenAITranscriptionModel(modelId: "gpt-4o-transcribe-diarize", config: .init(
            provider: "openai.transcription", url: { _ in "https://api.openai.com/v1/audio/transcriptions" }, fetch: { request in
                let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
                #expect(field(body, "response_format") == ["json"])
                let chunking = try JSONDecoder().decode(JSONValue.self, from: Data(try #require(field(body, "chunking_strategy").first).utf8))
                #expect(chunking == ["type": "server_vad", "threshold": 0.5, "prefix_padding_ms": 0, "silence_duration_ms": 250])
                return response(request, #"{"text":"ok"}"#)
            }
        ))
        _ = try await model.doGenerate(options: .init(audio: .binary(Data()), mediaType: "audio/wav", providerOptions: ["openai": [
            "responseFormat": "json", "chunkingStrategy": ["type": "server_vad", "threshold": 0.5, "prefixPaddingMs": 0, "silenceDurationMs": 250]
        ]]))
    }

    @Test(arguments: [["responseFormat": .string("text")], ["temperature": .number(.nan)], ["language": .null], ["chunkingStrategy": ["type": "server_vad", "prefixPaddingMs": 0.5]], ["chunkingStrategy": ["type": "server_vad", "silenceDurationMs": 9_007_199_254_740_992]]] as [JSONObject])
    func invalidOptionsFailBeforeHTTP(options: JSONObject) async throws {
        let model = OpenAITranscriptionModel(modelId: "whisper-1", config: .init(
            provider: "openai.transcription", url: { _ in "https://api.openai.com/v1/audio/transcriptions" }, fetch: { request in
                Issue.record("Invalid options reached HTTP")
                return response(request, #"{"text":"invalid"}"#)
            }
        ))
        await #expect(throws: InvalidArgumentError.self) {
            _ = try await model.doGenerate(options: .init(audio: .binary(Data()), mediaType: "audio/wav", providerOptions: ["openai": options]))
        }
    }

    @Test func httpFailurePreservesWireDiagnostics() async throws {
        let model = OpenAITranscriptionModel(modelId: "whisper-1", config: .init(
            provider: "openai.transcription", url: { _ in "https://api.openai.com/v1/audio/transcriptions" }, fetch: { request in
                response(request, #"{"error":{"message":"bad audio","type":"invalid_request_error","code":"bad_audio"}}"#, status: 400)
            }
        ))
        do {
            _ = try await model.doGenerate(options: .init(audio: .binary(Data()), mediaType: "audio/wav"))
            Issue.record("Expected API failure")
        } catch let error as APICallError {
            #expect(error.statusCode == 400)
            #expect(error.message == "bad audio")
            #expect(error.responseBody?.contains("bad_audio") == true)
            #expect(error.responseHeaders?["x-request-id"] == "request-1")
            #expect((error.requestBodyValues as? [String: FormDataValue])?["model"] == .string("whisper-1"))
        }
    }

    @Test func websocketProtocolOrderingAndRawEvents() async throws {
        let socket = TranscriptionSocket()
        let audio = TranscriptionAudioSource(chunks: [.binary(Data([1, 2, 3])), .base64("BA==")], finished: true)
        let result = try await streamModel(socket).doStream(options: .init(
            audio: audio.stream, inputAudioFormat: .init(type: "audio/pcm", rate: 24_000),
            providerOptions: ["openai": ["language": "en", "prompt": "context", "temperature": 0.5, "streaming": ["delay": "low", "include": ["logprobs"]]]],
            headers: ["AUTHORIZATION": "bEaReR caller", "X-Custom": "yes"], includeRawChunks: true
        ))
        try await waitForCommit(socket)
        #expect(socket.request?.url?.absoluteString == "wss://api.openai.com/v1/realtime?intent=transcription")
        #expect(socket.request?.value(forHTTPHeaderField: "Sec-WebSocket-Protocol") == "realtime, openai-insecure-api-key.caller")
        #expect(socket.request?.value(forHTTPHeaderField: "X-Custom") == "yes")
        #expect(socket.request?.value(forHTTPHeaderField: "Authorization") == nil)
        let frames = socket.frames
        #expect(frames.count == 4)
        #expect(frames.first == result.request?.body as? JSONValue)
        if case .object(let update) = frames.first, case .object(let session) = update["session"], case .object(let audio) = session["audio"], case .object(let input) = audio["input"] {
            #expect(input["format"] == ["type": "audio/pcm", "rate": 24_000])
            #expect(input["transcription"] == ["model": "gpt-realtime-whisper-2026-01-01", "language": "en", "delay": "low"])
            #expect(input["turn_detection"] == .null)
            #expect(session["include"] == ["logprobs"])
        } else { Issue.record("Invalid session update") }
        #expect(frames.dropFirst().prefix(2) == [["type": "input_audio_buffer.append", "audio": "AQID"], ["type": "input_audio_buffer.append", "audio": "BA=="]])
        socket.message("invalid json")
        socket.message(#"{"type":"conversation.item.input_audio_transcription.delta","item_id":"i1","delta":"Hel"}"#)
        socket.message(#"{"type":"conversation.item.input_audio_transcription.completed","item_id":"i1","transcript":"Hello"}"#)
        let parts = try await collect(result.stream)
        #expect(parts.count == 6)
        if case .streamStart(let warnings) = parts.first {
            #expect(warnings.map { if case .unsupported(let feature, _) = $0 { return feature }; return "" } == ["providerOptions.openai.prompt", "providerOptions.openai.temperature"])
        } else { Issue.record("Missing stream start") }
        #expect(parts.dropFirst(2).first == .transcriptDelta(id: "i1", delta: "Hel", providerMetadata: nil))
        #expect(parts.suffix(2) == [
            .transcriptFinal(id: "i1", text: "Hello", startSecond: nil, endSecond: nil, channelIndex: nil, providerMetadata: nil),
            .finish(text: "Hello", segments: [], language: "en", durationInSeconds: nil, providerMetadata: nil)
        ])
        #expect(result.response?.timestamp == Date(timeIntervalSince1970: 12))
        #expect(socket.closeCodes == [1000])
    }

    @Test(arguments: [nil, "Basic token", " Bearer token"] as [String?])
    func nonBearerHandshakePreservesHeaders(authorization: String?) async throws {
        let socket = TranscriptionSocket()
        let source = TranscriptionAudioSource(finished: true)
        let model = OpenAITranscriptionModel(modelId: "gpt-realtime-whisper", config: .init(
            provider: "openai.transcription", url: { "https://api.openai.com/v1\($0.path)" },
            headers: { ["Authorization": authorization, "X-Custom": "yes"] }, webSocket: socket.make
        ))
        let result = try await model.doStream(options: .init(audio: source.stream, inputAudioFormat: .init(type: "audio/pcma")))
        try await waitForCommit(socket)
        #expect(socket.request?.value(forHTTPHeaderField: "Sec-WebSocket-Protocol") == "realtime")
        #expect(socket.request?.value(forHTTPHeaderField: "X-Custom") == "yes")
        #expect(socket.request?.value(forHTTPHeaderField: "Authorization") == authorization)
        socket.message(#"{"type":"conversation.item.input_audio_transcription.completed","transcript":""}"#)
        let parts = try await collect(result.stream)
        #expect(parts.last == .finish(text: "", segments: [], language: nil, durationInSeconds: nil, providerMetadata: nil))
    }

    @Test func bufferDrainPrecedesNextAudioAndCommit() async throws {
        let socket = TranscriptionSocket(blockDrain: true)
        let source = TranscriptionAudioSource(chunks: [.binary(Data([1])), .binary(Data([2]))], finished: true)
        let result = try await streamModel(socket).doStream(options: .init(audio: source.stream, inputAudioFormat: .init(type: "audio/pcmu")))
        try await transcriptionDeadline {
            for await _ in socket.draining { return }
            throw SocketFailure.deadline
        }
        #expect(socket.frames.count == 2)
        socket.releaseDrain()
        try await waitForCommit(socket)
        socket.message(#"{"type":"conversation.item.input_audio_transcription.completed","transcript":""}"#)
        let parts = try await collect(result.stream)
        #expect(parts.last == .finish(text: "", segments: [], language: nil, durationInSeconds: nil, providerMetadata: nil))
    }

    @Test(arguments: ["creation", "send", "socket", "server", "audio", "close", "null"])
    func terminalPathsCancelRetainedAudio(mode: String) async throws {
        let socket = TranscriptionSocket(failSend: mode == "send")
        let source = TranscriptionAudioSource(chunks: mode == "send" ? [.binary(Data([1])), .binary(Data([2]))] : [])
        let model = OpenAITranscriptionModel(modelId: "gpt-realtime-whisper", config: .init(
            provider: "openai.transcription", url: { "https://api.openai.com/v1\($0.path)" }, webSocket: { request in
                if mode == "creation" { throw SocketFailure.creation }
                return socket.make(request)
            }
        ))
        let result = try await model.doStream(options: .init(audio: source.stream, inputAudioFormat: .init(type: "audio/pcm", rate: 24_000)))
        if mode == "socket" { socket.fail() }
        if mode == "server" { socket.message(#"{"type":"error","error":{"message":"invalid session"}}"#) }
        if mode == "audio" { source.continuation.finish(throwing: SocketFailure.audio) }
        if mode == "close" { socket.remoteClose() }
        if mode == "null" { socket.message("null") }
        do {
            let parts = try await collect(result.stream)
            #expect(mode == "close")
            #expect(parts.allSatisfy { if case .streamStart = $0 { return true }; return false })
        } catch {
            #expect(mode != "close")
            if mode == "creation" { #expect(error as? SocketFailure == .creation) }
            if mode == "send" { #expect(error as? SocketFailure == .send) }
            if mode == "audio" { #expect(error as? SocketFailure == .audio) }
            if mode == "socket" { #expect(error.localizedDescription == "OpenAI realtime transcription error") }
            if mode == "server" { #expect(error.localizedDescription == "invalid session") }
            if mode == "null" { #expect(error is TypeValidationError) }
        }
        if mode != "audio" { #expect(source.isCancelled) }
        if mode != "creation" { #expect(!socket.closeCodes.isEmpty) }
    }

    @Test(arguments: [false, true]) func abortCancelsIdleAudioAndSocket(beforeOpen: Bool) async throws {
        let socket = TranscriptionSocket(open: !beforeOpen)
        let source = TranscriptionAudioSource()
        let flag = AbortFlag()
        let result = try await streamModel(socket).doStream(options: .init(audio: source.stream, inputAudioFormat: .init(type: "audio/pcma"), abortSignal: flag.read))
        flag.abort()
        await #expect(throws: CancellationError.self) { _ = try await collect(result.stream) }
        #expect(source.isCancelled)
        #expect(!socket.closeCodes.isEmpty)
    }

    @Test(arguments: [false, true]) func consumerCancelReleasesAudio(beforeOpen: Bool) async throws {
        let socket = TranscriptionSocket(open: !beforeOpen)
        let source = TranscriptionAudioSource()
        let result = try await streamModel(socket).doStream(options: .init(audio: source.stream, inputAudioFormat: .init(type: "audio/pcm", rate: 24_000)))
        let task = Task { try await collect(result.stream) }
        task.cancel()
        _ = try? await task.value
        try await transcriptionDeadline {
            for await _ in source.termination { return }
            throw SocketFailure.deadline
        }
        #expect(source.isCancelled)
        #expect(!socket.closeCodes.isEmpty)
    }

    @Test func completedWhileDrainingCancelsAudio() async throws {
        let socket = TranscriptionSocket(blockDrain: true)
        let source = TranscriptionAudioSource(chunks: [.binary(Data([1]))])
        let result = try await streamModel(socket).doStream(options: .init(audio: source.stream, inputAudioFormat: .init(type: "audio/pcm", rate: 24_000)))
        try await transcriptionDeadline {
            for await _ in socket.draining { return }
            throw SocketFailure.deadline
        }
        socket.message(#"{"type":"conversation.item.input_audio_transcription.completed","item_id":"i","transcript":"done"}"#)
        let parts = try await collect(result.stream)
        #expect(parts.last == .finish(text: "done", segments: [], language: nil, durationInSeconds: nil, providerMetadata: nil))
        #expect(source.isCancelled)
        #expect(socket.frames.count == 2)
    }

    @Test func unsupportedModesFailBeforeTransport() async throws {
        let socket = TranscriptionSocket()
        let model = streamModel(socket)
        await #expect(throws: UnsupportedFunctionalityError.self) {
            _ = try await model.doGenerate(options: .init(audio: .binary(Data()), mediaType: "audio/wav"))
        }
        let rest = OpenAITranscriptionModel(modelId: "whisper-1", config: .init(provider: "openai.transcription", url: { _ in "unused" }))
        let source = TranscriptionAudioSource(finished: true)
        await #expect(throws: UnsupportedFunctionalityError.self) {
            _ = try await rest.doStream(options: .init(audio: source.stream, inputAudioFormat: .init(type: "audio/pcm", rate: 24_000)))
        }
    }
}
