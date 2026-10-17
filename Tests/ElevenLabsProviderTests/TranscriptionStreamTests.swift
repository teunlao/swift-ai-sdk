import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import ElevenLabsProvider

@Suite("ElevenLabs realtime transcription")
struct TranscriptionStreamTests {
    @Test("doStream sends authenticated audio and maps ordered transcripts without duplicating detailed commits")
    func requestAndTranscripts() async throws {
        let socket = Socket(events: [
            #"not json"#,
            #"{"message_type":"partial_transcript","text":"Hello"}"#,
            #"{"message_type":"committed_transcript","text":" Hello "}"#,
            #"{"message_type":"committed_transcript_with_timestamps","text":"Hello","language_code":"en","words":[{"text":"Hello","start":0,"end":0.4},{"text":"ignored","start":0.4}]}"#,
            #"{"message_type":"partial_transcript","text":"world"}"#,
            #"{"message_type":"committed_transcript","text":" world "}"#,
            #"{"message_type":"committed_transcript_with_timestamps","text":"world","words":[{"text":"world","start":0.5,"end":0.9}]}"#
        ])
        let model = createElevenLabs(settings: .init(
            apiKey: "key", headers: ["Custom-Provider": "provider", "User-Agent": "client"],
            webSocket: { request in
                let url = try #require(request.url)
                #expect(url.scheme == "wss")
                #expect(url.host == "api.elevenlabs.io")
                #expect(url.path == "/v1/speech-to-text/realtime")
                let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
                func value(_ name: String) -> String? { query.first { $0.name == name }?.value }
                #expect(value("model_id") == "scribe_v2_realtime")
                #expect(value("audio_format") == "pcm_16000")
                #expect(value("language_code") == "en")
                #expect(value("commit_strategy") == "manual")
                #expect(value("enable_logging") == "false")
                #expect(value("filter_background_audio") == "false")
                #expect(value("include_language_detection") == "true")
                #expect(value("include_timestamps") == "true")
                #expect(value("min_silence_duration_ms") == "200")
                #expect(value("min_speech_duration_ms") == "150")
                #expect(value("no_verbatim") == "true")
                #expect(value("vad_silence_threshold_secs") == "1.2")
                #expect(value("vad_threshold") == "0.5")
                #expect(query.filter { $0.name == "keyterms" }.compactMap(\.value) == ["C++", "AI SDK"])
                #expect(query.filter { $0.name == "secondary_languages" }.compactMap(\.value) == ["es", "fr"])
                #expect(url.absoluteString.contains("C%2B%2B"))
                #expect(request.value(forHTTPHeaderField: "xi-api-key") == "request-key")
                #expect(request.value(forHTTPHeaderField: "Custom-Provider") == "provider")
                #expect(request.value(forHTTPHeaderField: "Custom-Request") == "request")
                #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("client ai-sdk-elevenlabs/") == true)
                return socket
            }
        )).transcription(modelId: .scribeV2Realtime)
        let audio = AsyncThrowingStream<TranscriptionModelV4StreamAudio, Error> {
            $0.yield(.binary(Data([1, 2, 3])))
            $0.yield(.base64("BAUG"))
            $0.finish()
        }
        let result = try await model.doStream(options: .init(
            audio: audio, inputAudioFormat: .init(type: "audio/pcm"), providerOptions: ["elevenlabs": [
                "languageCode": "en", "diarize": true, "streaming": [
                    "commitStrategy": "manual", "enableLogging": false, "filterBackgroundAudio": false,
                    "includeLanguageDetection": true, "includeTimestamps": true,
                    "keyterms": ["C++", "AI SDK"], "minSilenceDurationMs": 200, "minSpeechDurationMs": 150,
                    "noVerbatim": true, "previousText": "Earlier context", "secondaryLanguages": ["es", "fr"],
                    "vadSilenceThresholdSecs": 1.2, "vadThreshold": 0.5
                ]
            ]], headers: ["xi-api-key": "request-key", "Custom-Request": "request"], includeRawChunks: true
        ))
        let parts = try await collect(result.stream)
        #expect(result.response?.modelId == "scribe_v2_realtime")
        #expect((result.request?.body as? String)?.hasPrefix("wss://api.elevenlabs.io/v1/speech-to-text/realtime?") == true)
        let raw = parts.compactMap { if case .raw(let value) = $0 { return value }; return nil }
        #expect(raw.count == 7)
        #expect(raw.first == ["message_type": "session_started", "session_id": "session-1"])
        let normalized = parts.filter { if case .raw = $0 { return false }; return true }
        guard case .streamStart(let warnings)? = normalized.first else { Issue.record("Missing stream start"); return }
        #expect(warnings.contains { if case .unsupported(feature: "providerOptions.elevenlabs.diarize", _) = $0 { return true }; return false })
        #expect(Array(normalized.dropFirst()) == [
            .transcriptPartial(id: "session-1:0", text: "Hello", startSecond: nil, durationInSeconds: nil, channelIndex: nil, providerMetadata: nil),
            .transcriptFinal(id: "session-1:0", text: "Hello", startSecond: nil, endSecond: nil, channelIndex: nil, providerMetadata: nil),
            .transcriptPartial(id: "session-1:1", text: "world", startSecond: nil, durationInSeconds: nil, channelIndex: nil, providerMetadata: nil),
            .transcriptFinal(id: "session-1:1", text: "world", startSecond: nil, endSecond: nil, channelIndex: nil, providerMetadata: nil),
            .finish(text: "Hello world", segments: [
                .init(text: "Hello", startSecond: 0, endSecond: 0.4),
                .init(text: "world", startSecond: 0.5, endSecond: 0.9)
            ], language: "en", durationInSeconds: 0.9, providerMetadata: nil)
        ])
        let sent = try socket.sent().map { try JSONDecoder().decode(JSONValue.self, from: Data(readWebSocketMessageText($0).utf8)) }
        #expect(sent == [
            ["message_type": "input_audio_chunk", "audio_base_64": "AQID", "commit": false, "sample_rate": 16000, "previous_text": "Earlier context"],
            ["message_type": "input_audio_chunk", "audio_base_64": "BAUG", "commit": false, "sample_rate": 16000],
            ["message_type": "input_audio_chunk", "audio_base_64": "", "commit": true, "sample_rate": 16000]
        ])
        #expect(socket.closeCode() == 1000)
    }

    @Test("language detection requests detailed events but does not expose unrequested timestamps")
    func languageWithoutTimestamps() async throws {
        let socket = Socket(events: [
            #"{"message_type":"committed_transcript_with_timestamps","text":"Hola","language_code":"es","words":[{"text":"Hola","start":0,"end":0.4}]}"#
        ])
        let model = createElevenLabs(settings: .init(apiKey: "key", webSocket: { request in
            let items = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems
            #expect(items?.first { $0.name == "include_timestamps" }?.value == "true")
            #expect(items?.first { $0.name == "audio_format" }?.value == "ulaw_8000")
            return socket
        })).transcription(modelId: .scribeV2Realtime)
        let result = try await model.doStream(options: .init(
            audio: AsyncThrowingStream { $0.finish() }, inputAudioFormat: .init(type: "AUDIO/PCMU"),
            providerOptions: ["elevenlabs": ["streaming": ["includeLanguageDetection": true, "includeTimestamps": false]]]
        ))
        let parts = try await collect(result.stream)
        #expect(parts == [
            .streamStart(warnings: []),
            .transcriptFinal(id: "session-1:0", text: "Hola", startSecond: nil, endSecond: nil, channelIndex: nil, providerMetadata: nil),
            .finish(text: "Hola", segments: [], language: "es", durationInSeconds: nil, providerMetadata: nil)
        ])
    }

    @Test("timestamp-only final events carry timing and can complete without a remote close")
    func timestampOnly() async throws {
        let socket = Socket(events: [
            #"{"message_type":"final_transcript_with_timestamps","text":"Hi","words":[{"text":"Hi","start":0.1,"end":0.6}]}"#
        ])
        let result = try await model(socket).doStream(options: .init(
            audio: AsyncThrowingStream { $0.finish() }, inputAudioFormat: .init(type: "audio/pcm", rate: 24000),
            providerOptions: ["elevenlabs": ["streaming": ["includeTimestamps": true]]]
        ))
        let parts = try await collect(result.stream)
        #expect(parts.last == .finish(text: "Hi", segments: [.init(text: "Hi", startSecond: 0.1, endSecond: 0.6)], language: nil, durationInSeconds: 0.6, providerMetadata: nil))
        #expect(parts.dropFirst().first == .transcriptFinal(id: "session-1:0", text: "Hi", startSecond: 0.1, endSecond: 0.6, channelIndex: nil, providerMetadata: nil))
    }

    @Test("a close after committed text succeeds even when requested timestamps have not arrived")
    func closeAfterCommit() async throws {
        let socket = Socket(events: [#"{"message_type":"committed_transcript","text":"Done"}"#], closes: true)
        let result = try await model(socket).doStream(options: .init(
            audio: AsyncThrowingStream { $0.finish() }, inputAudioFormat: .init(type: "audio/pcm"),
            providerOptions: ["elevenlabs": ["streaming": ["includeTimestamps": true]]]
        ))
        #expect(try await collect(result.stream).last == .finish(text: "Done", segments: [], language: nil, durationInSeconds: nil, providerMetadata: nil))
    }

    @Test("an empty final commit rejection preserves text committed while input was open")
    func rejectedFinalCommit() async throws {
        let socket = Socket(events: [#"{"message_type":"insufficient_audio_activity","error":"not enough audio"}"#])
        let audio = AsyncThrowingStream<TranscriptionModelV4StreamAudio, Error>.makeStream()
        let result = try await model(socket).doStream(options: .init(audio: audio.stream, inputAudioFormat: .init(type: "audio/pcm")))
        var iterator = result.stream.makeAsyncIterator()
        #expect(try await iterator.next() == .streamStart(warnings: []))
        socket.emit(#"{"message_type":"committed_transcript","text":"Already done"}"#)
        #expect(try await iterator.next() == .transcriptFinal(id: "session-1:0", text: "Already done", startSecond: nil, endSecond: nil, channelIndex: nil, providerMetadata: nil))
        audio.continuation.finish()
        #expect(try await iterator.next() == .finish(text: "Already done", segments: [], language: nil, durationInSeconds: nil, providerMetadata: nil))
        #expect(try await iterator.next() == nil)
    }

    @Test("provider failures and premature close fail the stream", arguments: [false, true])
    func streamFailures(_ prematureClose: Bool) async throws {
        let socket = Socket(events: prematureClose ? [] : [#"{"message_type":"quota_exceeded","error":"quota exhausted"}"#], closes: prematureClose)
        let result = try await model(socket).doStream(options: .init(audio: AsyncThrowingStream { $0.finish() }, inputAudioFormat: .init(type: "audio/pcm")))
        do {
            _ = try await collect(result.stream)
            Issue.record("Expected terminal stream failure")
        } catch {
            #expect(error.localizedDescription == (prematureClose ? "ElevenLabs realtime transcription stream closed before completion." : "quota exhausted"))
        }
    }

    @Test("connection setup failure cancels the caller's audio producer")
    func failedConnection() async throws {
        let stopped = Signal()
        let audio = AsyncThrowingStream<TranscriptionModelV4StreamAudio, Error> {
            $0.onTermination = { _ in Task { await stopped.resolve() } }
        }
        let model = createElevenLabs(settings: .init(apiKey: "key", webSocket: { _ in throw ConnectionFailure() })).transcription(modelId: .scribeV2Realtime)
        let result = try await model.doStream(options: .init(audio: audio, inputAudioFormat: .init(type: "audio/pcm")))
        await #expect(throws: ConnectionFailure.self) { try await collect(result.stream) }
        await stopped.wait()
    }

    @Test("cancelling the consumer closes the socket and cancels pending audio")
    func cancellation() async throws {
        let stopped = Signal()
        let started = Signal()
        let socket = Socket()
        let audio = AsyncThrowingStream<TranscriptionModelV4StreamAudio, Error> {
            $0.onTermination = { _ in Task { await stopped.resolve() } }
        }
        let result = try await model(socket).doStream(options: .init(audio: audio, inputAudioFormat: .init(type: "audio/pcm")))
        let consumer = Task {
            for try await part in result.stream {
                if case .streamStart = part { await started.resolve() }
            }
        }
        await started.wait()
        consumer.cancel()
        _ = await consumer.result
        await stopped.wait()
        #expect(socket.isClosed())
    }

    @Test("invalid models, audio formats, and incompatible options fail before connecting")
    func invalidArguments() async throws {
        await #expect(throws: UnsupportedFunctionalityError.self) {
            try await createElevenLabs().transcription(modelId: .scribeV2).doStream(options: .init(audio: AsyncThrowingStream { $0.finish() }, inputAudioFormat: .init(type: "audio/pcm")))
        }
        let model = createElevenLabs().transcription(modelId: .scribeV2Realtime)
        for format in [SharedV4AudioFormat(type: "audio/wav"), .init(type: "audio/pcm", rate: 12000), .init(type: "audio/pcmu", rate: 16000)] {
            await #expect(throws: InvalidArgumentError.self) {
                try await model.doStream(options: .init(audio: AsyncThrowingStream { $0.finish() }, inputAudioFormat: format))
            }
        }
        for option in ["includeTimestamps", "includeLanguageDetection"] {
            await #expect(throws: InvalidArgumentError.self) {
                try await model.doStream(options: .init(
                    audio: AsyncThrowingStream { $0.finish() }, inputAudioFormat: .init(type: "audio/pcm"),
                    providerOptions: ["elevenlabs": ["streaming": .object(["filterBackgroundAudio": true, option: true])]]
                ))
            }
        }
    }

    private func model(_ socket: Socket) -> ElevenLabsTranscriptionModel {
        createElevenLabs(settings: .init(apiKey: "key", webSocket: { _ in socket })).transcription(modelId: .scribeV2Realtime)
    }

    private func collect(_ stream: AsyncThrowingStream<TranscriptionModelV4StreamPart, Error>) async throws -> [TranscriptionModelV4StreamPart] {
        var parts: [TranscriptionModelV4StreamPart] = []
        for try await part in stream { parts.append(part) }
        return parts
    }

    private struct ConnectionFailure: Error {}

    private final class Socket: WebSocketLike, @unchecked Sendable {
        let messages: AsyncThrowingStream<WebSocketMessage, Error>
        private let continuation: AsyncThrowingStream<WebSocketMessage, Error>.Continuation
        private let events: [String]
        private let closes: Bool
        private let lock = NSLock()
        private var outgoing: [WebSocketMessage] = []
        private var closed = false
        private var code: Int?
        private var pendingSend: CheckedContinuation<Void, Error>?

        init(events: [String] = [], closes: Bool = false) {
            self.events = events
            self.closes = closes
            let pair = AsyncThrowingStream<WebSocketMessage, Error>.makeStream()
            messages = pair.stream
            continuation = pair.continuation
            emit(#"{"message_type":"session_started","session_id":"session-1"}"#)
        }

        func send(_ message: WebSocketMessage) async throws {
            lock.withLock { outgoing.append(message) }
            let value = try JSONDecoder().decode(JSONValue.self, from: Data(readWebSocketMessageText(message).utf8))
            guard case .object(let frame) = value, frame["commit"] == true else { return }
            events.forEach(emit)
            if closes {
                continuation.finish(throwing: WebSocketError.closed(code: 1000, reason: nil))
                try await withCheckedThrowingContinuation { (waiting: CheckedContinuation<Void, Error>) in
                    let alreadyClosed = lock.withLock {
                        if closed { return true }
                        pendingSend = waiting
                        return false
                    }
                    if alreadyClosed { waiting.resume(throwing: WebSocketError.closed(code: 1000, reason: nil)) }
                }
            }
        }

        func emit(_ text: String) { continuation.yield(.text(text)) }
        func close(code: Int?) {
            let waiting = lock.withLock {
                closed = true
                self.code = code
                let waiting = pendingSend
                pendingSend = nil
                return waiting
            }
            waiting?.resume(throwing: WebSocketError.closed(code: code, reason: nil))
            continuation.finish()
        }
        func sent() -> [WebSocketMessage] { lock.withLock { outgoing } }
        func closeCode() -> Int? { lock.withLock { code } }
        func isClosed() -> Bool { lock.withLock { closed } }
    }

    private actor Signal {
        private var resolved = false
        private var waiter: CheckedContinuation<Void, Never>?
        func resolve() { resolved = true; waiter?.resume(); waiter = nil }
        func wait() async { if !resolved { await withCheckedContinuation { waiter = $0 } } }
    }
}
