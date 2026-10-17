import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
@testable import GatewayProvider

@Suite("Gateway transcription")
struct GatewayTranscriptionModelTests {
    @Test("transcription sends base64 audio and preserves usage, segments, and diarization warnings")
    func generate() async throws {
        let provider = createGateway(settings: .init(apiKey: "key", fetch: { request in
            #expect(request.url?.path == "/v4/ai/transcription-model")
            #expect(request.value(forHTTPHeaderField: "ai-transcription-model-specification-version") == "4")
            let data = try #require(request.httpBody)
            let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(body["audio"] as? String == "AQID")
            #expect(body["mediaType"] as? String == "audio/wav")
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"]))
            return FetchResponse(body: .data(Data(#"{"text":"Hello","segments":[{"text":"Hello","startSecond":0,"endSecond":1}],"language":"en","durationInSeconds":1,"usage":{"seconds":1},"providerMetadata":{"gateway":{"cost":"0.01"}}}"#.utf8)), urlResponse: response)
        }))
        let result = try await provider.transcription(modelId: "xai/stt").doGenerate(options: .init(
            audio: .binary(Data([1, 2, 3])), mediaType: "audio/wav", providerOptions: ["xai": ["diarize": true]]
        ))
        #expect(result.text == "Hello")
        #expect(result.segments == [.init(text: "Hello", startSecond: 0, endSecond: 1)])
        #expect(result.language == "en")
        #expect(result.durationInSeconds == 1)
        #expect(result.usage?["seconds"] == .number(1))
        #expect(result.providerMetadata?["gateway"]?["cost"] == .string("0.01"))
        #expect(result.warnings.contains { if case .unsupported(feature: "providerOptions.xai.diarize", _) = $0 { return true }; return false })
    }

    @Test("streaming transcription sends its envelope and bounded binary frames, then parses ordered results")
    func stream() async throws {
        let socket = Socket()
        let provider = createGateway(settings: .init(apiKey: "key", teamIdOrSlug: "team", webSocket: { request in
            #expect(request.url?.absoluteString == "wss://ai-gateway.vercel.sh/v4/ai/transcription-model?ai-model-id=openai%2Fgpt-realtime-whisper")
            let protocols = request.value(forHTTPHeaderField: "Sec-WebSocket-Protocol")
            #expect(getGatewayRealtimeAuthToken(protocols) == "key")
            #expect(getGatewayRealtimeTeamIdOrSlug(protocols) == "team")
            #expect(protocols?.hasPrefix(GATEWAY_TRANSCRIPTION_SUBPROTOCOL) == true)
            return socket
        }))
        let audio = AsyncThrowingStream<TranscriptionModelV4StreamAudio, Error> { continuation in
            continuation.yield(.base64(Data(repeating: 1, count: 64 * 1024 + 1).base64EncodedString()))
            continuation.finish()
        }
        let result = try await provider.experimental_transcription("openai/gpt-realtime-whisper").doStream(options: .init(
            audio: audio, inputAudioFormat: .init(type: "audio/pcm", rate: 16000),
            providerOptions: ["openai": ["language": "en"]], includeRawChunks: true
        ))
        var parts: [TranscriptionModelV4StreamPart] = []
        for try await part in result.stream { parts.append(part) }
        try #require(parts.count == 3)
        #expect(parts[1] == .transcriptDelta(id: "segment", delta: "Hello", providerMetadata: nil))
        guard case .responseMetadata(let timestamp, _, _, _) = parts[0] else { Issue.record("Missing metadata"); return }
        #expect(timestamp == Date(timeIntervalSince1970: 1700000000))
        guard case .finish(let text, _, _, _, let usage, _) = parts[2] else { Issue.record("Missing finish"); return }
        #expect(text == "Hello")
        #expect(usage?["seconds"] == .number(1))
        let sent = socket.sent()
        guard case .text(let start)? = sent.first else { Issue.record("Missing start frame"); return }
        let frame = try #require(JSONSerialization.jsonObject(with: Data(start.utf8)) as? [String: Any])
        #expect(frame["type"] as? String == "transcription-stream.start")
        let format = try #require(frame["inputAudioFormat"] as? [String: Any])
        #expect(format["type"] as? String == "audio/pcm")
        #expect(format["rate"] as? Int == 16000)
        #expect(frame["includeRawChunks"] as? Bool == true)
        let sizes = sent.compactMap { message -> Int? in if case .binary(let data) = message { return data.count }; return nil }
        #expect(sizes == [64 * 1024, 1])
        #expect(sent.last == .text(#"{"type":"transcription-stream.audio-done"}"#))
    }

    @Test("a server error part is forwarded and maps its closing failure to a typed Gateway error")
    func streamError() async throws {
        let socket = Socket(failure: true)
        let model = createGateway(settings: .init(apiKey: "key", webSocket: { _ in socket })).transcription(modelId: "openai/gpt-realtime-whisper")
        let result = try await model.doStream(options: .init(audio: AsyncThrowingStream { $0.finish() }, inputAudioFormat: .init(type: "audio/pcm", rate: 16000)))
        var errors: [JSONValue] = []
        do {
            for try await part in result.stream { if case .error(let error) = part { errors.append(error) } }
            Issue.record("Expected terminal server error")
        } catch let error as GatewayRateLimitError {
            #expect(error.isRetryable)
            #expect(error.statusCode == 429)
        }
        #expect(errors == [["message": "Slow down", "type": "rate_limit_exceeded"]])
    }

    @Test("a server error cancels the audio producer while leaving the socket open for the terminal close")
    func serverErrorStopsAudio() async throws {
        let stopped = Signal()
        let audio = AsyncThrowingStream<TranscriptionModelV4StreamAudio, Error> { continuation in
            continuation.onTermination = { _ in Task { await stopped.resolve() } }
            continuation.yield(.binary(Data([1])))
        }
        let socket = Socket(holdAudio: true)
        let model = createGateway(settings: .init(apiKey: "key", webSocket: { _ in socket })).transcription(modelId: "openai/gpt-realtime-whisper")
        let result = try await model.doStream(options: .init(audio: audio, inputAudioFormat: .init(type: "audio/pcm", rate: 16000)))
        var iterator = result.stream.makeAsyncIterator()
        guard case .error? = try await iterator.next() else { Issue.record("Expected server error part"); return }
        await stopped.wait()
        #expect(socket.isClosed() == false)
        socket.serverClose()
        do {
            _ = try await iterator.next()
            Issue.record("Expected terminal server error")
        } catch let error as GatewayRateLimitError {
            #expect(error.statusCode == 429)
        }
    }

    @Test("a server finish cancels an audio producer whose input remains open")
    func serverFinishStopsAudio() async throws {
        let stopped = Signal()
        let audio = AsyncThrowingStream<TranscriptionModelV4StreamAudio, Error> { continuation in
            continuation.onTermination = { _ in Task { await stopped.resolve() } }
            continuation.yield(.binary(Data([1])))
        }
        let socket = Socket(holdAudio: true, finishEarly: true)
        let model = createGateway(settings: .init(apiKey: "key", webSocket: { _ in socket })).transcription(modelId: "openai/gpt-realtime-whisper")
        let result = try await model.doStream(options: .init(audio: audio, inputAudioFormat: .init(type: "audio/pcm", rate: 16000)))
        var parts: [TranscriptionModelV4StreamPart] = []
        for try await part in result.stream { parts.append(part) }
        guard case .finish(let text, _, _, _, _, _)? = parts.last else { Issue.record("Expected finish part"); return }
        #expect(text == "Hello")
        await stopped.wait()
        #expect(socket.isClosed())
    }

    @Test("an aborted stream cancels audio even before a socket is opened")
    func abortedBeforeOpen() async throws {
        let stopped = Signal()
        let audio = AsyncThrowingStream<TranscriptionModelV4StreamAudio, Error> { continuation in
            continuation.onTermination = { _ in Task { await stopped.resolve() } }
        }
        let model = createGateway(settings: .init(apiKey: "key", webSocket: { _ in Socket() })).transcription(modelId: "openai/gpt-realtime-whisper")
        let result = try await model.doStream(options: .init(audio: audio, inputAudioFormat: .init(type: "audio/pcm", rate: 16000), abortSignal: { true }))
        await #expect(throws: CancellationError.self) { for try await _ in result.stream {} }
        await stopped.wait()
    }

    @Test("transcription client secrets bind the mint to the transcription route")
    func clientSecret() async throws {
        let provider = createGateway(settings: .init(baseURL: "https://proxy.test/v4/ai", apiKey: "server-key", fetch: { request in
            #expect(request.url?.absoluteString == "https://proxy.test/v1/realtime/client-secrets")
            let data = try #require(request.httpBody)
            let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(body["routeKind"] as? String == "transcription")
            #expect(body["model"] as? String == "openai/gpt-realtime-whisper")
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"]))
            return FetchResponse(body: .data(Data(#"{"token":"vcst_transcription","expiresAt":1234}"#.utf8)), urlResponse: response)
        }))
        let secret = try await provider.experimental_transcription.getToken(options: .init(model: "openai/gpt-realtime-whisper"))
        #expect(secret.token == "vcst_transcription")
        #expect(secret.expiresAt == 1234)
        #expect(secret.url == "wss://proxy.test/v4/ai/transcription-model?ai-model-id=openai%2Fgpt-realtime-whisper")
    }

    private final class Socket: WebSocketLike, @unchecked Sendable {
        let messages: AsyncThrowingStream<WebSocketMessage, Error>
        private let continuation: AsyncThrowingStream<WebSocketMessage, Error>.Continuation
        private let lock = NSLock()
        private var outgoing: [WebSocketMessage] = []
        private let failure: Bool
        private let holdAudio: Bool
        private let finishEarly: Bool
        private var closed = false
        private var audioSend: CheckedContinuation<Void, Error>?

        init(failure: Bool = false, holdAudio: Bool = false, finishEarly: Bool = false) {
            self.failure = failure
            self.holdAudio = holdAudio
            self.finishEarly = finishEarly
            let pair = AsyncThrowingStream<WebSocketMessage, Error>.makeStream()
            messages = pair.stream
            continuation = pair.continuation
        }

        func send(_ message: WebSocketMessage) async throws {
            lock.withLock { outgoing.append(message) }
            if holdAudio, case .binary = message {
                continuation.yield(.text(finishEarly
                    ? #"{"type":"finish","text":"Hello","segments":[]}"#
                    : #"{"type":"error","error":{"message":"Slow down","type":"rate_limit_exceeded"}}"#))
                try await withCheckedThrowingContinuation { (waiting: CheckedContinuation<Void, Error>) in
                    let alreadyClosed = lock.withLock {
                        if closed { return true }
                        audioSend = waiting
                        return false
                    }
                    if alreadyClosed { waiting.resume(throwing: CancellationError()) }
                }
                return
            }
            guard case .text(let text) = message, text.contains("transcription-stream.audio-done") else { return }
            if failure {
                continuation.yield(.text(#"{"type":"error","error":{"message":"Slow down","type":"rate_limit_exceeded"}}"#))
            } else {
                continuation.yield(.text(#"{"type":"response-metadata","timestamp":"2023-11-14T22:13:20.000Z"}"#))
                continuation.yield(.text(#"{"type":"future-part","data":1}"#))
                continuation.yield(.text(#"{"type":"transcript-delta","id":"segment","delta":"Hello"}"#))
                continuation.yield(.text(#"{"type":"finish","text":"Hello","segments":[],"usage":{"seconds":1}}"#))
            }
            continuation.finish()
        }

        func close(code: Int?) {
            let waiting = lock.withLock {
                closed = true
                let waiting = audioSend
                audioSend = nil
                return waiting
            }
            waiting?.resume(throwing: CancellationError())
            continuation.finish()
        }
        func serverClose() { continuation.finish() }
        func isClosed() -> Bool { lock.withLock { closed } }
        func sent() -> [WebSocketMessage] { lock.withLock { outgoing } }
    }

    private actor Signal {
        private var resolved = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        func resolve() {
            resolved = true
            let pending = waiters
            waiters.removeAll()
            for waiter in pending { waiter.resume() }
        }
        func wait() async {
            if resolved { return }
            await withCheckedContinuation { waiters.append($0) }
        }
    }
}
