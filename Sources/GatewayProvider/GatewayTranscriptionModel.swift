import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class GatewayTranscriptionModel: TranscriptionModelV4 {
    public let modelId: String
    private let config: GatewayModelConfig
    private let webSocket: WebSocketConstructor?
    public var provider: String { config.provider }

    init(modelId: String, config: GatewayModelConfig, webSocket: WebSocketConstructor?) {
        self.modelId = modelId
        self.config = config
        self.webSocket = webSocket
    }

    public func doGenerate(options: TranscriptionModelV4CallOptions) async throws -> TranscriptionModelV4Result {
        let audio: String
        switch options.audio {
        case .binary(let data): audio = data.base64EncodedString()
        case .base64(let value): audio = value
        }
        var body: [String: JSONValue] = ["audio": .string(audio), "mediaType": .string(options.mediaType)]
        if let value = options.providerOptions { body["providerOptions"] = try gatewayJSON(value) }
        let result = try await config.post(
            "transcription", modelId: modelId, body: .object(body), headers: options.headers,
            abortSignal: options.abortSignal, response: GatewayTranscriptionResponse.self
        )
        var warnings = result.value.warnings ?? []
        if (modelId.hasPrefix("xai/") || modelId.hasPrefix("spacexai/")),
           options.providerOptions?["xai"]?["diarize"] == .bool(true) || options.providerOptions?["spacexai"]?["diarize"] == .bool(true),
           !containsSpeaker(result.rawValue) {
            warnings.append(.unsupported(feature: "providerOptions.xai.diarize", details: "AI Gateway does not currently expose xAI speaker diarization metadata."))
        }
        return .init(
            text: result.value.text, segments: result.value.segments ?? [], language: result.value.language,
            durationInSeconds: result.value.durationInSeconds, warnings: warnings, usage: result.value.usage,
            response: .init(timestamp: Date(), modelId: modelId, headers: result.responseHeaders, body: result.rawValue),
            providerMetadata: result.value.providerMetadata
        )
    }

    public func doStream(options: TranscriptionModelV4StreamOptions) async throws -> TranscriptionModelV4StreamResult {
        let timestamp = config.currentDate()
        let headers = combineHeaders(
            try await config.headers(), options.headers?.mapValues { Optional($0) },
            ["ai-transcription-model-specification-version": "4", "ai-model-id": modelId],
            try await config.o11yHeaders()
        )
        let normalized = Dictionary(uniqueKeysWithValues: headers.compactMap { key, value in value.map { (key.lowercased(), $0) } })
        let protocols: [String]
        if let auth = normalized["authorization"], auth.hasPrefix("Bearer ") {
            protocols = getGatewayTranscriptionProtocols(String(auth.dropFirst(7)), teamIdOrSlug: normalized["x-vercel-ai-gateway-team"])
        } else { protocols = [GATEWAY_TRANSCRIPTION_SUBPROTOCOL] }
        let frame = TranscriptionStreamStartFrame(
            inputAudioFormat: options.inputAudioFormat, providerOptions: options.providerOptions, includeRawChunks: options.includeRawChunks
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = try encoder.encode(frame)
        let text = String(decoding: data, as: UTF8.self)
        let url = try toGatewayTranscriptionUrl(config.baseURL, modelId: modelId)
        let stream = AsyncThrowingStream<TranscriptionModelV4StreamPart, Error> { continuation in
            let session = GatewayTranscriptionSession(audio: options.audio, authMethod: parseAuthMethod(from: normalized), continuation: continuation)
            let startup = Task {
                await session.start(url: url, protocols: protocols, headers: headers, webSocket: webSocket, abortSignal: options.abortSignal, startFrame: text)
            }
            continuation.onTermination = { _ in
                startup.cancel()
                Task { await session.cancel() }
            }
        }
        return .init(stream: stream, request: .init(body: try JSONSerialization.jsonObject(with: data)), response: .init(timestamp: timestamp, modelId: modelId))
    }
}

public struct GatewayTranscriptionFactoryGetTokenOptions: Sendable {
    public let model: String
    public let expiresAfterSeconds: Int?

    public init(model: String, expiresAfterSeconds: Int? = nil) {
        self.model = model
        self.expiresAfterSeconds = expiresAfterSeconds
    }
}

public struct GatewayTranscriptionFactoryGetTokenResult: Sendable, Equatable {
    public let token: String
    public let url: String
    public let expiresAt: Double?

    public init(token: String, url: String, expiresAt: Double? = nil) {
        self.token = token
        self.url = url
        self.expiresAt = expiresAt
    }
}

public struct GatewayTranscriptionFactory: Sendable {
    let config: @Sendable () -> GatewayModelConfig
    let metadataConfig: GatewayConfig
    let webSocket: WebSocketConstructor?

    public func callAsFunction(_ modelId: String) -> GatewayTranscriptionModel {
        GatewayTranscriptionModel(modelId: modelId, config: config(), webSocket: webSocket)
    }

    public func callAsFunction(_ modelId: GatewayTranscriptionModelId) -> GatewayTranscriptionModel { self(modelId.rawValue) }

    public func getToken(options: GatewayTranscriptionFactoryGetTokenOptions) async throws -> GatewayTranscriptionFactoryGetTokenResult {
        let result = try await GatewayClientSecrets(config: metadataConfig).mint(model: options.model, expiresAfterSeconds: options.expiresAfterSeconds, routeKind: "transcription")
        return .init(token: result.token, url: try toGatewayTranscriptionUrl(metadataConfig.baseURL, modelId: options.model), expiresAt: result.expiresAt)
    }
}

private struct GatewayTranscriptionResponse: Decodable, Sendable {
    let text: String
    let segments: [TranscriptionModelV4Result.Segment]?
    let language: String?
    let durationInSeconds: Double?
    let warnings: [SharedV4Warning]?
    let usage: JSONObject?
    let providerMetadata: SharedV4ProviderMetadata?
}

private func containsSpeaker(_ value: Any?) -> Bool {
    if let array = value as? [Any] { return array.contains { containsSpeaker($0) } }
    guard let object = value as? [String: Any] else { return false }
    return object.contains { key, value in (key == "speaker" && !(value is NSNull)) || containsSpeaker(value) }
}

private actor GatewayTranscriptionSession {
    private let audio: AsyncThrowingStream<TranscriptionModelV4StreamAudio, Error>
    private let authMethod: GatewayAuthMethod?
    private let continuation: AsyncThrowingStream<TranscriptionModelV4StreamPart, Error>.Continuation
    private var connection: WebSocketConnection?
    private var sender: Task<Void, Never>?
    private var audioRead: Task<TranscriptionModelV4StreamAudio?, Error>?
    private var receiver: Task<Void, Never>?
    private var abortSignal: (@Sendable () -> Bool)?
    private var finished = false
    private var audioStopped = false
    private var serverError: JSONValue?

    init(audio: AsyncThrowingStream<TranscriptionModelV4StreamAudio, Error>, authMethod: GatewayAuthMethod?, continuation: AsyncThrowingStream<TranscriptionModelV4StreamPart, Error>.Continuation) {
        self.audio = audio
        self.authMethod = authMethod
        self.continuation = continuation
    }

    func start(url: String, protocols: [String], headers: [String: String?], webSocket: WebSocketConstructor?, abortSignal: (@Sendable () -> Bool)?, startFrame: String) async {
        guard !finished, !Task.isCancelled else { await cancel(); return }
        self.abortSignal = abortSignal
        do {
            let connection = try connectToWebSocket(url: url, protocols: protocols, headers: headers, webSocket: webSocket, abortSignal: abortSignal)
            self.connection = connection
            try await connection.send(.text(startFrame))
            guard !finished else { return }
            receiver = Task { await self.receive(connection) }
            sender = Task { await self.sendAudio(connection) }
        } catch {
            fail(error)
        }
    }

    private func sendAudio(_ connection: WebSocketConnection) async {
        let source = GatewayAudioSource(audio)
        do {
            while !finished, !audioStopped, !Task.isCancelled {
                let read = Task { try await source.next() }
                audioRead = read
                let chunk = try await read.value
                audioRead = nil
                guard !finished, !audioStopped, !Task.isCancelled else { return }
                guard let chunk else { break }
                let bytes: Data
                switch chunk {
                case .binary(let value): bytes = value
                case .base64(let value): bytes = try convertBase64ToData(value)
                }
                var offset = 0
                while offset < bytes.count {
                    guard !finished, !audioStopped, !Task.isCancelled else { return }
                    let end = min(offset + 64 * 1024, bytes.count)
                    try await connection.send(.binary(bytes.subdata(in: offset..<end)))
                    offset = end
                }
            }
            guard !finished, !audioStopped, !Task.isCancelled else { return }
            try await connection.send(.text(#"{"type":"transcription-stream.audio-done"}"#))
        } catch {
            audioRead = nil
            if !Task.isCancelled, !audioStopped { fail(error) }
        }
    }

    private func receive(_ connection: WebSocketConnection) async {
        do {
            for try await text in connection.messages {
                guard !finished else { return }
                guard let part = parseTranscriptionStreamPart(text) else { continue }
                switch part {
                case .finish:
                    finished = true
                    continuation.yield(part)
                    continuation.finish()
                    stopAudio()
                    sender?.cancel()
                    connection.close(code: 1000)
                    return
                case .error(let error):
                    serverError = error
                    stopAudio()
                default: break
                }
                continuation.yield(part)
            }
            if let serverError { fail(errorFromServerPart(serverError)) }
            else { fail(GatewayStreamFailure(message: "AI Gateway transcription stream closed before a finish part was received")) }
        } catch {
            if isAbortError(error), Task.isCancelled || abortSignal?() == true { fail(error) }
            else if let serverError { fail(errorFromServerPart(serverError)) }
            else { fail(error) }
        }
    }

    func cancel() async {
        guard !finished else { return }
        finished = true
        stopAudio()
        sender?.cancel()
        receiver?.cancel()
        connection?.close(code: nil)
    }

    private func stopAudio() {
        guard !audioStopped else { return }
        audioStopped = true
        audioRead?.cancel()
        Task { await cancelStream(audio) }
    }

    private func fail(_ error: Error) {
        guard !finished else { return }
        finished = true
        stopAudio()
        sender?.cancel()
        receiver?.cancel()
        connection?.close(code: nil)
        continuation.finish(throwing: isAbortError(error) ? error : asGatewayError(error, authMethod: authMethod))
    }

    private func errorFromServerPart(_ error: JSONValue) -> Error {
        let codes = ["authentication_error": 401, "failed_dependency": 424, "forbidden": 403, "internal_server_error": 500, "invalid_request_error": 400, "model_not_found": 404, "rate_limit_exceeded": 429]
        if case .object(let value) = error, case .string(let message)? = value["message"], case .string(let type)? = value["type"], let code = codes[type] {
            return createGatewayErrorFromResponse(response: ["error": ["message": message, "type": type]], statusCode: code, authMethod: authMethod)
        }
        let message: String
        if case .object(let value) = error, case .string(let value)? = value["message"] { message = value }
        else { message = AISDKProvider.getErrorMessage(jsonValueToFoundation(error)) }
        return GatewayStreamFailure(message: "AI Gateway transcription stream failed: \(message)")
    }
}

private final class GatewayAudioSource: @unchecked Sendable {
    private var iterator: AsyncThrowingStream<TranscriptionModelV4StreamAudio, Error>.Iterator

    init(_ stream: AsyncThrowingStream<TranscriptionModelV4StreamAudio, Error>) {
        iterator = stream.makeAsyncIterator()
    }

    // The session owns a single pending read and cancels it before stopping audio.
    func next() async throws -> TranscriptionModelV4StreamAudio? { try await iterator.next() }
}

private struct GatewayStreamFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
