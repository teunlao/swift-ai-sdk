import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct AzureMaiTranscriptionConfig: Sendable {
    public let url: @Sendable () throws -> String
    public let headers: @Sendable () async throws -> [String: String?]
    public let webSocket: WebSocketConstructor?
    public let _internal: Internal?
    public struct Internal: Sendable {
        public let currentDate: (@Sendable () -> Date)?
        public init(currentDate: (@Sendable () -> Date)? = nil) { self.currentDate = currentDate }
    }
    public init(url: @escaping @Sendable () throws -> String, headers: @escaping @Sendable () async throws -> [String: String?],
                webSocket: WebSocketConstructor? = nil, _internal: Internal? = nil) {
        self.url = url; self.headers = headers; self.webSocket = webSocket; self._internal = _internal
    }
}

public final class AzureMaiTranscriptionModel: TranscriptionModelV4 {
    public let modelId: String
    public let provider = "azure.transcription"
    private let config: AzureMaiTranscriptionConfig
    public init(modelId: String, config: AzureMaiTranscriptionConfig) { self.modelId = modelId; self.config = config }

    public func doGenerate(options: TranscriptionModelV4CallOptions) async throws -> TranscriptionModelV4Result {
        throw UnsupportedFunctionalityError(functionality: "file transcription with \(modelId) (use streaming transcription)")
    }

    public func doStream(options: TranscriptionModelV4StreamOptions) async throws -> TranscriptionModelV4StreamResult {
        try await doStream(options: options, maiOptions: .init(), warnings: [])
    }

    public func doStream(options: TranscriptionModelV4StreamOptions, maiOptions: AzureTranscriptionModelMaiOptions,
                         warnings: [SharedV4Warning]) async throws -> TranscriptionModelV4StreamResult {
        let timestamp = config._internal?.currentDate?() ?? Date()
        let format = options.inputAudioFormat
        let rate = format.rate ?? 24000
        guard format.type == "audio/pcm", [16000, 24000].contains(rate) else {
            throw InvalidArgumentError(argument: "inputAudioFormat", message: "MAI streaming transcription requires 16-bit mono PCM (audio/pcm) at 16000 or 24000 Hz, got \(format.type)\(format.rate != nil ? " at \(rate) Hz" : "").")
        }
        var transcription: JSONObject = ["model": .string(modelId)]
        if let language = maiOptions.language { transcription["language"] = .string(language) }
        let update: JSONValue = ["type": "session.update", "session": ["type": "transcription", "audio": ["input": [
            "format": ["type": "audio/pcm", "rate": .number(Double(rate))], "transcription": .object(transcription),
            "turn_detection": .null, "noise_reduction": .null
        ]]]]
        let headers = combineHeaders(try await config.headers(), options.headers?.mapValues(Optional.some))
        let url = try toWebSocketURL(config.url())
        let pair = AsyncThrowingStream<TranscriptionModelV4StreamPart, Error>.makeStream()
        let session = MaiTranscriptionSession(options: options, update: update, language: maiOptions.language,
            bytesPerSecond: rate * 2, warnings: warnings, continuation: pair.continuation)
        pair.continuation.onTermination = { @Sendable _ in Task { await session.terminate(.cancelled) } }
        await session.start(url: url, headers: headers, webSocket: config.webSocket)
        return .init(stream: pair.stream, request: .init(body: update), response: .init(timestamp: timestamp, modelId: modelId))
    }
}

private actor MaiTranscriptionSession {
    enum Completion { case transcript(String), failed(any Error), cancelled }
    private let options: TranscriptionModelV4StreamOptions
    private let update: JSONValue
    private let language: String?
    private let bytesPerSecond: Int
    private let warnings: [SharedV4Warning]
    private let continuation: AsyncThrowingStream<TranscriptionModelV4StreamPart, Error>.Continuation
    private var connection: WebSocketConnection?
    private var receiver: Task<Void, Never>?
    private var sender: Task<Void, Never>?
    private var finished = false
    private var audioStarted = false
    private var committed = false
    private var audioBytes = 0
    private var deltas = ""

    init(options: TranscriptionModelV4StreamOptions, update: JSONValue, language: String?, bytesPerSecond: Int,
         warnings: [SharedV4Warning], continuation: AsyncThrowingStream<TranscriptionModelV4StreamPart, Error>.Continuation) {
        self.options = options; self.update = update; self.language = language; self.bytesPerSecond = bytesPerSecond
        self.warnings = warnings; self.continuation = continuation
    }

    func start(url: URL, headers: [String: String?], webSocket: WebSocketConstructor?) async {
        do {
            let connection = try connectToWebSocket(url: url.absoluteString, headers: headers, webSocket: webSocket, abortSignal: options.abortSignal)
            self.connection = connection
            receiver = Task { await receive(connection) }
        } catch { await terminate(.failed(error)) }
    }

    private func receive(_ connection: WebSocketConnection) async {
        do { try await connection.waitUntilOpen() }
        catch is CancellationError { await terminate(.failed(CancellationError())); return }
        catch { await terminate(.failed(MaiTranscriptionError("Azure MAI transcription WebSocket error"))); return }
        guard !finished else { return }
        continuation.yield(.streamStart(warnings: warnings))
        var iterator = connection.messages.makeAsyncIterator()
        while !finished {
            let text: String?
            do { text = try await iterator.next() }
            catch is CancellationError { await terminate(.failed(CancellationError())); return }
            catch WebSocketError.closed(let code, let reason) { await terminate(.failed(Self.closed(code: code, reason: reason))); return }
            catch { await terminate(.failed(MaiTranscriptionError("Azure MAI transcription WebSocket error"))); return }
            guard let text else { await terminate(.failed(Self.closed(code: nil, reason: nil))); return }
            do { try await event(text, connection: connection) }
            catch { await terminate(.failed(error)); return }
        }
    }

    private func event(_ text: String, connection: WebSocketConnection) async throws {
        let parsed = await safeParseJSON(ParseJSONOptions(text: text))
        guard case .success(let raw, _) = parsed, !finished else { return }
        if options.includeRawChunks == true { continuation.yield(.raw(rawValue: raw)) }
        if raw == .null { throw TypeValidationError.wrap(value: raw, cause: MaiTranscriptionError("Expected a MAI transcription event")) }
        guard case .object(let event) = raw, case .string(let type) = event["type"] else { return }
        switch type {
        case "session.created":
            try await connection.send(.text(String(decoding: JSONEncoder().encode(update), as: UTF8.self)))
        case "session.updated":
            if !audioStarted {
                audioStarted = true
                sender = Task { await sendAudio(connection) }
            }
        case "conversation.item.input_audio_transcription.delta":
            let delta = try Self.string(event, "delta") ?? ""
            deltas += delta
            continuation.yield(.transcriptDelta(id: try Self.string(event, "item_id"), delta: delta, providerMetadata: nil))
        case "conversation.item.input_audio_transcription.intermediate":
            continuation.yield(.transcriptPartial(id: try Self.string(event, "item_id"), text: try Self.string(event, "intermediate") ?? "",
                startSecond: nil, durationInSeconds: nil, channelIndex: nil, providerMetadata: nil))
        case "conversation.item.input_audio_transcription.completed":
            let transcript = try Self.string(event, "transcript") ?? deltas
            continuation.yield(.transcriptFinal(id: try Self.string(event, "item_id"), text: transcript,
                startSecond: nil, endSecond: nil, channelIndex: nil, providerMetadata: nil))
            if committed { await terminate(.transcript(transcript)) }
        case "conversation.item.input_audio_transcription.failed", "error":
            let error: JSONObject
            if case .object(let object) = event["error"] { error = object } else { error = [:] }
            let code = try Self.string(error, "code").map { " (\($0))" } ?? ""
            throw MaiTranscriptionError("Azure MAI transcription error\(code): \(try Self.string(error, "message") ?? "unknown error")")
        default: break
        }
    }

    private func sendAudio(_ connection: WebSocketConnection) async {
        do {
            for try await chunk in options.audio {
                try Task.checkCancellation()
                guard !finished else { return }
                let base64: String
                let count: Int
                switch chunk {
                case .binary(let bytes): base64 = bytes.base64EncodedString(); count = bytes.count
                case .base64(let value):
                    base64 = value
                    let length = value.utf16.count
                    let padding = value.hasSuffix("==") ? 2 : value.hasSuffix("=") ? 1 : 0
                    count = (length / 4) * 3 + ((length % 4) * 3) / 4 - padding
                }
                if base64.isEmpty { continue }
                let sum = audioBytes.addingReportingOverflow(count)
                guard !sum.overflow else { throw InvalidArgumentError(argument: "audio", message: "Audio byte count exceeds the integer range.") }
                audioBytes = sum.partialValue
                try await connection.send(.text(String(decoding: JSONEncoder().encode(JSONValue.object([
                    "type": "input_audio_buffer.append", "audio": .string(base64)
                ])), as: UTF8.self)))
                try await connection.waitForBufferDrain()
            }
            guard !finished else { return }
            try Task.checkCancellation()
            if audioBytes == 0 { await terminate(.transcript("")); return }
            committed = true
            try await connection.send(.text(#"{"type":"input_audio_buffer.commit"}"#))
        } catch { await terminate(.failed(error)) }
    }

    func terminate(_ completion: Completion) async {
        guard !finished else { return }
        finished = true
        let code: Int? = if case .transcript = completion { 1000 } else { nil }
        connection?.close(code: code)
        connection = nil
        sender?.cancel(); sender = nil
        receiver?.cancel(); receiver = nil
        await cancelStream(options.audio)
        switch completion {
        case .transcript(let text):
            continuation.yield(.finish(text: text, segments: [], language: language,
                durationInSeconds: audioBytes > 0 ? Double(audioBytes) / Double(bytesPerSecond) : nil, providerMetadata: nil))
            continuation.finish()
        case .failed(let error): continuation.finish(throwing: error)
        case .cancelled: continuation.finish()
        }
    }

    private static func string(_ fields: JSONObject, _ key: String) throws -> String? {
        guard let value = fields[key], value != .null else { return nil }
        guard case .string(let text) = value else {
            throw TypeValidationError.wrap(value: value, cause: MaiTranscriptionError("Expected string field \(key)"))
        }
        return text
    }
    private static func closed(code: Int?, reason: String?) -> MaiTranscriptionError {
        let details = code.map { " (code \($0)\(reason.flatMap { $0.isEmpty ? nil : ": \($0)" } ?? ""))" } ?? ""
        return MaiTranscriptionError("Azure MAI transcription connection closed before the transcript completed\(details)")
    }
}

private struct MaiTranscriptionError: Error, LocalizedError, Sendable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
