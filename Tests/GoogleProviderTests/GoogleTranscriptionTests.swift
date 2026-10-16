import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import GoogleProvider

@Suite("Google transcription V4")
struct GoogleTranscriptionTests {
    @Test func unaryInteractionsWireAndAnnotations() async throws {
        let capture = GoogleTranscriptionCapture()
        let model = GoogleTranscriptionModel(modelId: "gemini-3.5-transcribe", config: .init(provider: "google.transcription", baseURL: "https://google.example/v1beta", fetch: { request in
            await capture.append(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json", "request-id": "transcript"])!
            return .init(body: .data(Data(#"{"steps":[{"content":[{"type":"audio","text":"ignored"},{"type":"text","text":"Hello ","annotations":[{"type":"word_info","text":"Hello","start_offset":"0s","end_offset":"0.5s"},{"type":"word_info","text":"invalid","start_offset":"bad","end_offset":"1s"}]}]},{"content":[{"type":"text","text":"world"}]}],"usage":{"total_tokens":12}}"#.utf8)), urlResponse: response)
        }))
        let result = try await model.doGenerate(options: .init(audio: .binary(Data([1, 2, 3])), mediaType: "audio/wav", providerOptions: ["google": [
            "languageCodes": .array([.string("en-US")]), "customVocabulary": .array([.string("Vertex")]), "diarization": .bool(true), "wordTimestamp": .bool(true), "mode": .string("SMART")
        ]]))
        #expect(result.text == "Hello world")
        #expect(result.segments == [.init(text: "Hello", startSecond: 0, endSecond: 0.5)])
        #expect(result.usage?["total_tokens"] == .number(12))
        #expect(result.providerMetadata?["google"]?["usage"] == result.usage.map(JSONValue.object))
        #expect(result.response.headers?["request-id"] == "transcript")
        let request = try #require(await capture.last)
        #expect(request.url?.absoluteString == "https://google.example/v1beta/interactions")
        let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
        #expect(body == .object([
            "model": .string("gemini-3.5-transcribe"), "input": .array([.object(["type": .string("audio"), "data": .string("AQID"), "mime_type": .string("audio/wav")])]),
            "generation_config": .object(["transcription_config": .object([
                "language_codes": .array([.string("en-US")]), "custom_vocabulary": .array([.string("Vertex")]),
                "mode": .object(["type": .string("smart"), "diarization_mode": .string("speaker"), "timestamp_granularities": .array([.string("word")])])
            ])])
        ]))
    }

    @Test func liveSession() async throws {
        let socket = GoogleTranscriptionSocket()
        let handshake = GoogleHandshakeCapture()
        let server = Task {
            for await body in socket.sent {
                guard case .object(let object) = body else { continue }
                if let setup = object["setup"] {
                    #expect(setup == .object(["model": .string("models/gemini-3.5-transcribe-live"), "inputAudioTranscription": .object(["wordTimestamp": .bool(true)])]))
                    socket.emit(#"{"setupComplete":{}}"#)
                }
                if case .object(let realtime) = object["realtimeInput"] {
                    if let audio = realtime["audio"] {
                        #expect(audio == .object(["data": .string("AQID"), "mimeType": .string("audio/pcm;rate=16000")]))
                    }
                    if realtime["audioStreamEnd"] == .bool(true) {
                        socket.emit("invalid json")
                        socket.emit("[1]")
                        socket.emit(#"{"serverContent":{"interimInputTranscription":{"text":"draft"}}}"#)
                        socket.emit(#"{"serverContent":{"inputTranscription":{"text":"Hello ","languageCode":"en"}}}"#)
                        socket.emit(#"{"serverContent":{"inputTranscription":{"text":"world","finished":true}},"usageMetadata":{"totalTokenCount":7}}"#)
                        socket.emit(#"{"serverContent":{"turnComplete":true}}"#)
                        return
                    }
                }
            }
        }
        defer { server.cancel() }
        let model = GoogleTranscriptionModel(modelId: "gemini-3.5-transcribe-live", config: .init(
            provider: "google.transcription", baseURL: "https://proxy.example/custom/v1beta", headers: { ["X-Goog-Api-Key": "provider"] },
            webSocket: { request in handshake.store(request); return socket }
        ))
        let audio = AsyncThrowingStream<TranscriptionModelV4StreamAudio, Error> { $0.yield(.binary(Data([1, 2, 3]))); $0.finish() }
        let result = try await model.doStream(options: .init(audio: audio, inputAudioFormat: .init(type: "audio/pcm"), providerOptions: ["google": ["wordTimestamp": .bool(true)]], headers: ["x-goog-api-key": "request", "x-client": "client"], includeRawChunks: true))
        let parts = try await collectGoogleTranscription(result.stream)
        #expect(parts.first == .streamStart(warnings: []))
        #expect(parts.contains(.raw(rawValue: .array([.number(1)]))))
        #expect(parts.contains(.transcriptPartial(id: "google-segment-0", text: "draft", startSecond: nil, durationInSeconds: nil, channelIndex: nil, providerMetadata: nil)))
        #expect(parts.contains(.transcriptDelta(id: "google-segment-0", delta: "Hello ", providerMetadata: nil)))
        #expect(parts.contains(.transcriptFinal(id: "google-segment-0", text: "Hello world", startSecond: nil, endSecond: nil, channelIndex: nil, providerMetadata: nil)))
        #expect(parts.last == .finish(text: "Hello world", segments: [], language: "en", durationInSeconds: nil, usage: ["totalTokenCount": .number(7)], providerMetadata: ["google": ["usageMetadata": .object(["totalTokenCount": .number(7)])]]))
        let request = try #require(handshake.value)
        #expect(request.url.absoluteString == "wss://proxy.example/custom/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent?key=request")
        #expect(request.headers["x-client"] == "client")
        #expect(request.headers.keys.contains(where: { $0.lowercased() == "x-goog-api-key" }) == false)
    }

    @Test func serverErrorCancelsInputBeforeSetupAcknowledgement() async throws {
        let socket = GoogleTranscriptionSocket()
        let audio = AsyncThrowingStream<TranscriptionModelV4StreamAudio, Error>.makeStream()
        let ended = AsyncStream<Void>.makeStream()
        audio.continuation.onTermination = { _ in ended.continuation.yield(()); ended.continuation.finish() }
        let server = Task {
            for await _ in socket.sent { socket.emit(#"{"error":{"message":"permission denied"}}"#); return }
        }
        defer { server.cancel() }
        let model = GoogleTranscriptionModel(modelId: "gemini-3.5-transcribe-live", config: .init(provider: "google.transcription", baseURL: "https://google.example", headers: { ["x-goog-api-key": "key"] }, webSocket: { _ in socket }))
        let result = try await model.doStream(options: .init(audio: audio.stream, inputAudioFormat: .init(type: "audio/pcm")))
        do {
            _ = try await collectGoogleTranscription(result.stream)
            Issue.record("Expected server error")
        } catch { #expect(error.localizedDescription == "permission denied") }
        try await googleTranscriptionWithin { var iterator = ended.stream.makeAsyncIterator(); _ = await iterator.next() }
    }

    @Test func consumerCancellationClosesAudioAndSocket() async throws {
        let socket = GoogleTranscriptionSocket()
        let audio = AsyncThrowingStream<TranscriptionModelV4StreamAudio, Error>.makeStream()
        let ended = AsyncStream<Void>.makeStream()
        let ready = AsyncStream<Void>.makeStream()
        audio.continuation.onTermination = { _ in ended.continuation.yield(()); ended.continuation.finish() }
        audio.continuation.yield(.base64("AQID"))
        let server = Task {
            for await event in socket.sent {
                guard case .object(let object) = event else { continue }
                if object["setup"] != nil { socket.emit(#"{"setupComplete":{}}"#) }
                if object["realtimeInput"] != nil { ready.continuation.yield(()); ready.continuation.finish() }
            }
        }
        defer { server.cancel() }
        let model = GoogleTranscriptionModel(modelId: "gemini-3.5-transcribe-live", config: .init(provider: "google.transcription", baseURL: "https://google.example", headers: { ["x-goog-api-key": "key"] }, webSocket: { _ in socket }))
        let result = try await model.doStream(options: .init(audio: audio.stream, inputAudioFormat: .init(type: "audio/pcm")))
        let consumer = Task { for try await _ in result.stream {} }
        try await googleTranscriptionWithin { var iterator = ready.stream.makeAsyncIterator(); _ = await iterator.next() }
        consumer.cancel()
        _ = try? await consumer.value
        try await googleTranscriptionWithin { var iterator = ended.stream.makeAsyncIterator(); _ = await iterator.next() }
        await server.value
    }

    @Test func abortWhileWaitingForSetupCancelsAudio() async throws {
        let socket = GoogleTranscriptionSocket()
        let flag = GoogleTranscriptionAbort()
        let audio = AsyncThrowingStream<TranscriptionModelV4StreamAudio, Error>.makeStream()
        let ended = AsyncStream<Void>.makeStream()
        audio.continuation.onTermination = { _ in ended.continuation.yield(()); ended.continuation.finish() }
        let server = Task { for await _ in socket.sent { flag.abort(); return } }
        defer { server.cancel() }
        let model = GoogleTranscriptionModel(modelId: "gemini-3.5-transcribe-live", config: .init(provider: "google.transcription", baseURL: "https://google.example", headers: { ["x-goog-api-key": "key"] }, webSocket: { _ in socket }))
        let result = try await model.doStream(options: .init(audio: audio.stream, inputAudioFormat: .init(type: "audio/pcm"), abortSignal: { flag.value }))
        await #expect(throws: CancellationError.self) { _ = try await collectGoogleTranscription(result.stream) }
        try await googleTranscriptionWithin { var iterator = ended.stream.makeAsyncIterator(); _ = await iterator.next() }
    }

    @Test func methodAndFormatRefusals() async throws {
        let unary = GoogleTranscriptionModel(modelId: "gemini-3.5-transcribe", config: .init(provider: "google.transcription", baseURL: "https://google.example"))
        let live = GoogleTranscriptionModel(modelId: "gemini-3.5-transcribe-live", config: .init(provider: "google.transcription", baseURL: "https://google.example"))
        let audio = AsyncThrowingStream<TranscriptionModelV4StreamAudio, Error> { $0.finish() }
        await #expect(throws: InvalidArgumentError.self) { _ = try await unary.doStream(options: .init(audio: audio, inputAudioFormat: .init(type: "audio/pcm"))) }
        await #expect(throws: InvalidArgumentError.self) { _ = try await live.doGenerate(options: .init(audio: .base64("AQID"), mediaType: "audio/wav")) }
        await #expect(throws: InvalidArgumentError.self) { _ = try await live.doStream(options: .init(audio: audio, inputAudioFormat: .init(type: "audio/pcm", rate: 24000))) }
        await #expect(throws: LoadAPIKeyError.self) { _ = try await live.doStream(options: .init(audio: audio, inputAudioFormat: .init(type: "audio/pcm"))) }
    }
}

private actor GoogleTranscriptionCapture {
    private(set) var last: URLRequest?
    func append(_ request: URLRequest) { last = request }
}

private final class GoogleHandshakeCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: GoogleWebSocketRequest?
    func store(_ value: GoogleWebSocketRequest) { lock.lock(); defer { lock.unlock() }; stored = value }
    var value: GoogleWebSocketRequest? { lock.lock(); defer { lock.unlock() }; return stored }
}

private final class GoogleTranscriptionSocket: GoogleWebSocketConnection, Sendable {
    let messages: AsyncThrowingStream<String, Error>
    let sent: AsyncStream<JSONValue>
    private let incoming: AsyncThrowingStream<String, Error>.Continuation
    private let outgoing: AsyncStream<JSONValue>.Continuation
    init() {
        let received = AsyncThrowingStream<String, Error>.makeStream()
        messages = received.stream; incoming = received.continuation
        let sending = AsyncStream<JSONValue>.makeStream()
        sent = sending.stream; outgoing = sending.continuation
    }
    func send(_ text: String) async throws { outgoing.yield(try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))) }
    func emit(_ text: String) { incoming.yield(text) }
    func close(code: Int?) { incoming.finish(); outgoing.finish() }
}

private final class GoogleTranscriptionAbort: @unchecked Sendable {
    private let lock = NSLock()
    private var aborted = false
    func abort() { lock.lock(); defer { lock.unlock() }; aborted = true }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return aborted }
}

private enum GoogleTranscriptionTimeout: Error { case timedOut }
private func googleTranscriptionWithin<Value: Sendable>(_ operation: @escaping @Sendable () async throws -> Value) async throws -> Value {
    try await withThrowingTaskGroup(of: Value.self) { group in
        group.addTask(operation: operation)
        group.addTask { try await Task.sleep(nanoseconds: 2_000_000_000); throw GoogleTranscriptionTimeout.timedOut }
        defer { group.cancelAll() }
        guard let value = try await group.next() else { throw GoogleTranscriptionTimeout.timedOut }
        return value
    }
}
private func collectGoogleTranscription(_ stream: AsyncThrowingStream<TranscriptionModelV4StreamPart, Error>) async throws -> [TranscriptionModelV4StreamPart] {
    try await googleTranscriptionWithin {
        var parts: [TranscriptionModelV4StreamPart] = []
        for try await part in stream { parts.append(part) }
        return parts
    }
}
