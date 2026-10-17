import Foundation
import Network
import CryptoKit
import Testing
import AISDKProvider
import OpenAIProvider

@Suite("OpenAI native transcription WebSocket")
struct OpenAITranscriptionNativeTests {
    @Test(arguments: [false, true])
    func handshakeOutcome(refused: Bool) async throws {
        let server = try await TranscriptionSocketServer(mode: refused ? .refuse : .accept)
        defer { server.stop() }
        let source = TranscriptionAudioSource(chunks: [.binary(Data([1]))])
        let model = OpenAITranscriptionModel(modelId: "gpt-realtime-whisper", config: .init(
            provider: "openai.transcription", url: { "\(server.origin)\($0.path)" },
            headers: { ["Authorization": "Bearer loopback-key"] }
        ))
        let result = try await model.doStream(options: .init(audio: source.stream, inputAudioFormat: .init(type: "audio/pcm", rate: 24_000)))
        try await transcriptionDeadline {
            var iterator = result.stream.makeAsyncIterator()
            if refused {
                do {
                    let part = try await iterator.next()
                    Issue.record("Handshake refusal produced \(String(describing: part)) before an error")
                    while try await iterator.next() != nil {}
                } catch {
                    #expect(error.localizedDescription == "OpenAI realtime transcription error")
                }
            } else {
                let start = try await iterator.next()
                let transcript = try await iterator.next()
                let finish = try await iterator.next()
                let end = try await iterator.next()
                #expect(start == .streamStart(warnings: []))
                #expect(transcript == .transcriptFinal(id: "native", text: "done", startSecond: nil, endSecond: nil, channelIndex: nil, providerMetadata: nil))
                #expect(finish == .finish(text: "done", segments: [], language: nil, durationInSeconds: nil, providerMetadata: nil))
                #expect(end == nil)
            }
        }
        #expect(source.isCancelled)
        try await transcriptionDeadline { for await _ in server.closed { return } }
    }

    @Test func cancelDuringHandshakeReleasesPeerAndAudio() async throws {
        let server = try await TranscriptionSocketServer(mode: .pending)
        defer { server.stop() }
        let source = TranscriptionAudioSource()
        let model = OpenAITranscriptionModel(modelId: "gpt-realtime-whisper", config: .init(
            provider: "openai.transcription", url: { "\(server.origin)\($0.path)" }
        ))
        let result = try await model.doStream(options: .init(audio: source.stream, inputAudioFormat: .init(type: "audio/pcm", rate: 24_000)))
        let consumer = Task {
            var iterator = result.stream.makeAsyncIterator()
            return try await iterator.next()
        }
        try await transcriptionDeadline { for await _ in server.requested { return } }
        consumer.cancel()
        _ = try? await consumer.value
        try await transcriptionDeadline { for await _ in source.termination { return } }
        #expect(source.isCancelled)
        try await transcriptionDeadline { for await _ in server.closed { return } }
    }
}

private final class TranscriptionSocketServer: @unchecked Sendable {
    enum Mode: Sendable { case accept, refuse, pending }
    private var port: UInt16 = 0
    var origin: String { "http://127.0.0.1:\(port)" }
    let requested: AsyncStream<Void>
    let closed: AsyncStream<Void>
    private let listener: NWListener
    private let lock = NSLock()
    private var peers: [NWConnection] = []

    init(mode: Mode) async throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        let requestNotice = AsyncStream<Void>.makeStream()
        requested = requestNotice.stream
        let closeNotice = AsyncStream<Void>.makeStream()
        closed = closeNotice.stream
        let queue = DispatchQueue(label: "transcription-ws-test")
        listener.newConnectionHandler = { [weak self] connection in
            self?.lock.withLock { self?.peers.append(connection) }
            connection.start(queue: queue)
            Task {
                defer { connection.cancel(); closeNotice.continuation.yield(()); closeNotice.continuation.finish() }
                let peer = SocketPeer(connection)
                do {
                    let head = try await peer.readHead()
                    requestNotice.continuation.yield(())
                    requestNotice.continuation.finish()
                    if mode == .pending {
                        await peer.waitForClose()
                        return
                    }
                    if mode == .refuse {
                        try await peer.send(Data("HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8))
                        await peer.waitForClose()
                        return
                    }
                    #expect(head.first?.hasPrefix("GET /realtime?intent=transcription ") == true)
                    let headers = Dictionary(uniqueKeysWithValues: head.dropFirst().compactMap { line -> (String, String)? in
                        guard let colon = line.firstIndex(of: ":") else { return nil }
                        return (line[..<colon].lowercased(), line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces))
                    })
                    #expect(headers["authorization"] == nil)
                    #expect(headers["sec-websocket-protocol"] == "realtime, openai-insecure-api-key.loopback-key")
                    let key = try #require(headers["sec-websocket-key"])
                    let digest = Insecure.SHA1.hash(data: Data((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8))
                    try await peer.send(Data(("HTTP/1.1 101 Switching Protocols\r\nConnection: Upgrade\r\nUpgrade: websocket\r\nSec-WebSocket-Accept: \(Data(digest).base64EncodedString())\r\nSec-WebSocket-Protocol: realtime\r\n\r\n").utf8))
                    let update = try await peer.readFrame()
                    #expect(update["type"] as? String == "session.update")
                    let append = try await peer.readFrame()
                    #expect(append["type"] as? String == "input_audio_buffer.append")
                    #expect(append["audio"] as? String == "AQ==")
                    let text = Data(#"{"type":"conversation.item.input_audio_transcription.completed","item_id":"native","transcript":"done"}"#.utf8)
                    try await peer.send(Data([0x81, UInt8(text.count)]) + text)
                    try await peer.readClose()
                    try await peer.send(Data([0x88, 2, 3, 232]))
                    await peer.waitForClose()
                } catch { Issue.record(error) }
            }
        }
        port = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            let gate = StartupGate()
            listener.stateUpdateHandler = { [listener] state in
                switch state {
                case .ready: if gate.take() { continuation.resume(returning: listener.port!.rawValue) }
                case .failed(let error): if gate.take() { continuation.resume(throwing: error) }
                default: break
                }
            }
            listener.start(queue: queue)
        }
        listener.stateUpdateHandler = nil
    }

    func stop() {
        listener.cancel()
        for peer in lock.withLock({ peers }) { peer.cancel() }
    }
}

private final class StartupGate: @unchecked Sendable {
    private let lock = NSLock()
    private var taken = false
    func take() -> Bool { lock.withLock { defer { taken = true }; return !taken } }
}

private final class SocketPeer: @unchecked Sendable {
    private let connection: NWConnection
    private var buffer = Data()
    init(_ connection: NWConnection) { self.connection = connection }

    func readHead() async throws -> [String] {
        let separator = Data("\r\n\r\n".utf8)
        while buffer.range(of: separator) == nil { try await receive() }
        let range = buffer.range(of: separator)!
        let head = String(decoding: buffer[..<range.lowerBound], as: UTF8.self)
        buffer.removeSubrange(..<range.upperBound)
        return head.components(separatedBy: "\r\n")
    }

    func readFrame() async throws -> [String: Any] {
        let frame = try await readPayload()
        #expect(frame.opcode == 0x81)
        return try #require(try JSONSerialization.jsonObject(with: frame.data) as? [String: Any])
    }

    func readClose() async throws {
        let frame = try await readPayload()
        #expect(frame.opcode == 0x88)
        #expect(frame.data == Data([3, 232]))
    }

    private func readPayload() async throws -> (opcode: UInt8, data: Data) {
        let head = try await read(2)
        #expect(head[1] & 0x80 != 0)
        var length = Int(head[1] & 0x7f)
        if length == 126 {
            let bytes = try await read(2)
            length = Int(bytes[0]) << 8 | Int(bytes[1])
        }
        let mask = try await read(4)
        let payload = try await read(length)
        return (head[0], Data(payload.enumerated().map { $0.element ^ mask[$0.offset % 4] }))
    }

    func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }

    func waitForClose() async { while (try? await receive()) != nil { buffer.removeAll() } }

    private func read(_ length: Int) async throws -> [UInt8] {
        while buffer.count < length { try await receive() }
        let bytes = Array(buffer.prefix(length))
        buffer.removeFirst(length)
        return bytes
    }

    private func receive() async throws {
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, done, error in
                if let data, !data.isEmpty { continuation.resume(returning: data) }
                else { continuation.resume(throwing: error ?? URLError(done ? .networkConnectionLost : .unknown)) }
            }
        }
        buffer.append(data)
    }
}
