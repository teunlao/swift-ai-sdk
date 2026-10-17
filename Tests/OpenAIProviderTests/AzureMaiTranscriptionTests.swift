import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import AzureProvider

private final class MaiAbort: @unchecked Sendable {
    private let lock = NSLock()
    private var aborted = false
    func set() { lock.withLock { aborted = true } }
    var value: Bool { lock.withLock { aborted } }
}

private func maiFrame(_ socket: TranscriptionSocket, type: String) async throws -> JSONValue {
    try await transcriptionDeadline {
        for await frame in socket.sent {
            if case .object(let value) = frame, value["type"] == .string(type) { return frame }
        }
        throw SocketFailure.deadline
    }
}
private func maiParts(_ stream: AsyncThrowingStream<TranscriptionModelV4StreamPart, Error>) async throws -> [TranscriptionModelV4StreamPart] {
    try await transcriptionDeadline {
        var parts: [TranscriptionModelV4StreamPart] = []
        for try await part in stream { parts.append(part) }
        return parts
    }
}
private func maiStream(_ socket: TranscriptionSocket, options: TranscriptionModelV4StreamOptions) async throws -> TranscriptionModelV4StreamResult {
    try await createAzure(settings: .init(resourceName: "stream-resource", apiKey: "stream-key", webSocket: socket.make))
        .transcription("mai-transcribe-2-streaming").doStream(options: options)
}
private func configureMai(_ socket: TranscriptionSocket) async throws {
    socket.message(#"{"type":"session.created"}"#)
    _ = try await maiFrame(socket, type: "session.update")
    socket.message(#"{"type":"session.updated"}"#)
}

@Suite("Azure MAI streaming transcription")
struct AzureMaiTranscriptionTests {
    @Test("Session acknowledgement gates audio, ordered transcript events retain raw data and duration")
    func protocolFlow() async throws {
        let socket = TranscriptionSocket()
        let audio = TranscriptionAudioSource(chunks: [.binary(Data()), .base64(""), .binary(Data([1, 2, 3])), .base64("BA==")], finished: true)
        let provider = try createAzure(settings: .init(maiBaseURL: "https://gateway.example.com/mai/v1/",
            tokenProvider: { "resolved-token" }, headers: ["X-Stream": "configured", "Authorization": "Bearer configured"], webSocket: socket.make))
        let result = try await provider.transcriptionModel("custom-deployment").doStream(options: .init(
            audio: audio.stream, inputAudioFormat: .init(type: "audio/pcm", rate: 16000),
            providerOptions: ["azure": ["api": "mai", "language": "en", "timestamps": "word"]],
            headers: ["AUTHORIZATION": "Bearer caller", "X-Stream": "caller"], includeRawChunks: true))
        #expect(socket.request?.url?.absoluteString == "wss://gateway.example.com/mai/v1/realtime?intent=transcription")
        #expect(socket.request?.value(forHTTPHeaderField: "Authorization") == "Bearer caller")
        #expect(socket.request?.value(forHTTPHeaderField: "X-Stream") == "caller")
        socket.message("invalid json")
        socket.message(#"{"type":"session.created","session":{"id":"session-1"}}"#)
        let update = try await maiFrame(socket, type: "session.update")
        #expect(update == ["type": "session.update", "session": ["type": "transcription", "audio": ["input": [
            "format": ["type": "audio/pcm", "rate": 16000], "transcription": ["model": "custom-deployment", "language": "en"],
            "turn_detection": .null, "noise_reduction": .null
        ]]]])
        #expect(result.request?.body as? JSONValue == update)
        #expect(socket.frames == [update])
        socket.message(#"{"type":"session.updated"}"#)
        socket.message(#"{"type":"session.updated"}"#)
        _ = try await maiFrame(socket, type: "input_audio_buffer.commit")
        #expect(socket.frames.dropFirst() == [
            ["type": "input_audio_buffer.append", "audio": "AQID"], ["type": "input_audio_buffer.append", "audio": "BA=="],
            ["type": "input_audio_buffer.commit"]
        ])
        socket.message(#"{"type":"future.event","extra":false}"#)
        socket.message(#"{"type":"conversation.item.input_audio_transcription.delta","item_id":"opaque:i","delta":"Hel"}"#)
        socket.message(#"{"type":"conversation.item.input_audio_transcription.intermediate","item_id":"opaque:i","intermediate":"partial"}"#)
        socket.message(#"{"type":"conversation.item.input_audio_transcription.delta","item_id":"opaque:i","delta":"lo"}"#)
        socket.message(#"{"type":"conversation.item.input_audio_transcription.completed","item_id":"opaque:i"}"#)
        let parts = try await maiParts(result.stream)
        let raw = parts.compactMap { part -> JSONValue? in if case .raw(let value) = part { return value }; return nil }
        #expect(raw.contains(["type": "future.event", "extra": false]))
        #expect(raw.last == ["type": "conversation.item.input_audio_transcription.completed", "item_id": "opaque:i"])
        let transcript = parts.filter { if case .raw = $0 { return false }; return true }
        #expect(transcript == [
            .streamStart(warnings: [.unsupported(feature: "providerOptions.azure.timestamps", details: "This option requires the Azure Speech API.")]),
            .transcriptDelta(id: "opaque:i", delta: "Hel", providerMetadata: nil),
            .transcriptPartial(id: "opaque:i", text: "partial", startSecond: nil, durationInSeconds: nil, channelIndex: nil, providerMetadata: nil),
            .transcriptDelta(id: "opaque:i", delta: "lo", providerMetadata: nil),
            .transcriptFinal(id: "opaque:i", text: "Hello", startSecond: nil, endSecond: nil, channelIndex: nil, providerMetadata: nil),
            .finish(text: "Hello", segments: [], language: "en", durationInSeconds: 0.000125, providerMetadata: nil)
        ])
        #expect(socket.closeCodes == [1000])
    }

    @Test("Empty audio finishes without append or commit")
    func noAudio() async throws {
        let socket = TranscriptionSocket()
        let source = TranscriptionAudioSource(finished: true)
        let result = try await maiStream(socket, options: .init(audio: source.stream, inputAudioFormat: .init(type: "audio/pcm")))
        try await configureMai(socket)
        let parts = try await maiParts(result.stream)
        #expect(parts == [.streamStart(warnings: []), .finish(text: "", segments: [], language: nil, durationInSeconds: nil, providerMetadata: nil)])
        #expect(socket.frames.count == 1)
        #expect(socket.closeCodes == [1000])
    }

    @Test("Buffer drain precedes the next audio chunk and commit")
    func bufferDrain() async throws {
        let socket = TranscriptionSocket(blockDrain: true)
        let source = TranscriptionAudioSource(chunks: [.binary(Data([1])), .binary(Data([2]))], finished: true)
        let result = try await maiStream(socket, options: .init(audio: source.stream, inputAudioFormat: .init(type: "audio/pcm")))
        try await configureMai(socket)
        try await transcriptionDeadline { for await _ in socket.draining { return } }
        #expect(socket.frames.count == 2)
        socket.releaseDrain()
        _ = try await maiFrame(socket, type: "input_audio_buffer.commit")
        socket.message(#"{"type":"conversation.item.input_audio_transcription.delta","delta":"ignored"}"#)
        socket.message(#"{"type":"conversation.item.input_audio_transcription.completed","transcript":""}"#)
        let parts = try await maiParts(result.stream)
        #expect(parts.last == .finish(text: "", segments: [], language: nil, durationInSeconds: 2.0 / 48000, providerMetadata: nil))
    }

    @Test("A provisional completed event does not finish before input is committed")
    func completedBeforeCommit() async throws {
        let socket = TranscriptionSocket()
        let source = TranscriptionAudioSource(chunks: [.binary(Data([1]))])
        let result = try await maiStream(socket, options: .init(audio: source.stream, inputAudioFormat: .init(type: "audio/pcm")))
        let early = AsyncStream<Void>.makeStream()
        let consumer = Task {
            var parts: [TranscriptionModelV4StreamPart] = []
            for try await part in result.stream {
                parts.append(part)
                if case .transcriptFinal(_, "early", _, _, _, _) = part { early.continuation.yield(()) }
            }
            return parts
        }
        defer { consumer.cancel(); early.continuation.finish() }
        try await configureMai(socket)
        _ = try await maiFrame(socket, type: "input_audio_buffer.append")
        socket.message(#"{"type":"conversation.item.input_audio_transcription.completed","transcript":"early"}"#)
        try await transcriptionDeadline { for await _ in early.stream { return } }
        #expect(!source.isCancelled)
        source.continuation.finish()
        _ = try await maiFrame(socket, type: "input_audio_buffer.commit")
        socket.message(#"{"type":"conversation.item.input_audio_transcription.completed","transcript":"final"}"#)
        let parts = try await transcriptionDeadline {
            try await withTaskCancellationHandler { try await consumer.value } onCancel: { consumer.cancel() }
        }
        #expect(parts.last == .finish(text: "final", segments: [], language: nil, durationInSeconds: 1.0 / 48000, providerMetadata: nil))
        #expect(parts.filter { if case .transcriptFinal = $0 { return true }; return false }.count == 2)
    }

    @Test("Terminal failures release the retained audio source and socket", arguments: ["constructor", "socket", "server", "send", "audio", "close", "null"])
    func failures(_ mode: String) async throws {
        let socket = TranscriptionSocket(failSend: mode == "send")
        let source = TranscriptionAudioSource(chunks: [.binary(Data([1])), .binary(Data([2]))])
        let provider = try createAzure(settings: .init(resourceName: "stream-resource", apiKey: "key", webSocket: { request in
            if mode == "constructor" { throw SocketFailure.creation }
            return socket.make(request)
        }))
        let result = try await provider.transcription("mai-transcribe-2-streaming").doStream(options: .init(
            audio: source.stream, inputAudioFormat: .init(type: "audio/pcm")))
        switch mode {
        case "socket": socket.fail()
        case "server": socket.message(#"{"type":"conversation.item.input_audio_transcription.failed","error":{"code":"DeploymentNotFound","message":"failed"}}"#)
        case "send": try await configureMai(socket)
        case "audio": source.continuation.finish(throwing: SocketFailure.audio); try await configureMai(socket)
        case "close": socket.remoteClose(code: 1011, reason: "server error")
        case "null": socket.message("null")
        default: break
        }
        do { _ = try await maiParts(result.stream); Issue.record("Expected terminal stream failure") }
        catch {
            if mode == "server" { #expect(error.localizedDescription == "Azure MAI transcription error (DeploymentNotFound): failed") }
            if mode == "close" { #expect(error.localizedDescription == "Azure MAI transcription connection closed before the transcript completed (code 1011: server error)") }
            if mode == "socket" { #expect(error.localizedDescription == "Azure MAI transcription WebSocket error") }
            if mode == "constructor" { #expect(error as? SocketFailure == .creation) }
            if mode == "audio" { #expect(error as? SocketFailure == .audio) }
            if mode == "null" { #expect(error is TypeValidationError) }
        }
        if mode != "audio" { #expect(source.isCancelled) }
        if mode != "constructor" { #expect(!socket.closeCodes.isEmpty) }
    }

    @Test("Consumer cancellation releases audio before and after the opening gate", arguments: [true, false])
    func consumerCancellation(_ beforeOpen: Bool) async throws {
        let socket = TranscriptionSocket(open: !beforeOpen)
        let source = TranscriptionAudioSource(chunks: [.binary(Data([1]))])
        let result = try await maiStream(socket, options: .init(audio: source.stream, inputAudioFormat: .init(type: "audio/pcm")))
        let consumer = Task { for try await _ in result.stream {} }
        if !beforeOpen { try await configureMai(socket); _ = try await maiFrame(socket, type: "input_audio_buffer.append") }
        consumer.cancel()
        _ = try? await consumer.value
        try await transcriptionDeadline { for await _ in source.termination { return } }
        #expect(source.isCancelled)
        #expect(!socket.closeCodes.isEmpty)
    }

    @Test("Dropping an unread MAI stream releases its audio source and opening socket")
    func dropStream() async throws {
        let socket = TranscriptionSocket(open: false)
        defer { socket.remoteClose() }
        let source = TranscriptionAudioSource()
        var result: TranscriptionModelV4StreamResult? = try await maiStream(socket,
            options: .init(audio: source.stream, inputAudioFormat: .init(type: "audio/pcm")))
        withExtendedLifetime(result) {}
        result = nil
        try await transcriptionDeadline { for await _ in source.termination { return } }
        #expect(source.isCancelled)
        #expect(!socket.closeCodes.isEmpty)
    }

    @Test("The shared abort owner closes an idle MAI connection and audio source")
    func abort() async throws {
        let socket = TranscriptionSocket()
        let source = TranscriptionAudioSource()
        let signal = MaiAbort()
        let result = try await maiStream(socket, options: .init(audio: source.stream, inputAudioFormat: .init(type: "audio/pcm"), abortSignal: { signal.value }))
        signal.set()
        _ = await #expect(throws: CancellationError.self) { try await maiParts(result.stream) }
        #expect(source.isCancelled)
        #expect(!socket.closeCodes.isEmpty)
    }

    @Test("Only Source PCM sample rates are accepted", arguments: [("audio/pcm", 8000), ("audio/pcmu", nil)] as [(String, Int?)])
    func formats(_ type: String, _ rate: Int?) async throws {
        let socket = TranscriptionSocket()
        let source = TranscriptionAudioSource(finished: true)
        let error = await #expect(throws: InvalidArgumentError.self) {
            try await maiStream(socket, options: .init(audio: source.stream, inputAudioFormat: .init(type: type, rate: rate)))
        }
        #expect(error?.argument == "inputAudioFormat")
    }
}
