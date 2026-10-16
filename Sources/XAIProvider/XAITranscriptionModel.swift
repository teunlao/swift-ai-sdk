import Foundation
import AISDKProvider
import AISDKProviderUtils

struct XAITranscriptionModelConfig: Sendable {
    let provider: String
    let baseURL: String
    let headers: @Sendable () throws -> [String: String?]
    let fetch: FetchFunction?
    let webSocket: XAIWebSocketFactory?
}

private struct TranscriptionResponse: Codable, Sendable {
    struct Word: Codable, Sendable {
        let text: String
        let start: Double
        let end: Double
        let speaker: Double?
        let speakerIsNull: Bool
        enum CodingKeys: String, CodingKey { case text, start, end, speaker }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            text = try container.decode(String.self, forKey: .text)
            start = try container.decode(Double.self, forKey: .start)
            end = try container.decode(Double.self, forKey: .end)
            speaker = try container.decodeIfPresent(Double.self, forKey: .speaker)
            speakerIsNull = try container.contains(.speaker) && container.decodeNil(forKey: .speaker)
        }
    }
    let text: String
    let language: String?
    let duration: Double?
    let words: [Word]?
}
private let transcriptionResponseSchema = FlexibleSchema(Schema<TranscriptionResponse>.codable(TranscriptionResponse.self, jsonSchema: .object(["type": .string("object")])))

private struct StreamingEvent: Decodable {
    let type: String?
    let text: String?
    let isFinal: Bool?
    let speechFinal: Bool?
    let start: Double?
    let duration: Double?
    let channelIndex: Int?
    let message: String?
    enum CodingKeys: String, CodingKey { case type, text, isFinal = "is_final", speechFinal = "speech_final", start, duration, channelIndex = "channel_index", message }
}

public final class XAITranscriptionModel: TranscriptionModelV4 {
    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }
    private let modelIdentifier: XAITranscriptionModelId
    private let config: XAITranscriptionModelConfig
    init(modelId: XAITranscriptionModelId, config: XAITranscriptionModelConfig) { self.modelIdentifier = modelId; self.config = config }

    public func doGenerate(options: TranscriptionModelV4CallOptions) async throws -> TranscriptionModelV4Result {
        let timestamp = Date()
        let xai = try await parseProviderOptions(provider: "xai", providerOptions: options.providerOptions, schema: xaiTranscriptionOptionsSchema) ?? .init()
        var multipart = MultipartFormDataBuilder()
        var params = sttParams(xai)
        if let value = xai.audioFormat { params.append(("audio_format", value.rawValue)) }
        if let value = xai.format { params.append(("format", String(value))) }
        for (name, value) in params { multipart.appendField(name: name, value: value) }
        let audio: Data
        switch options.audio { case .binary(let bytes): audio = bytes; case .base64(let value): audio = try convertBase64ToData(value) }
        multipart.appendFile(name: "file", filename: "audio.\(mediaTypeToExtension(options.mediaType))", contentType: options.mediaType, data: audio)
        let body = multipart.build()
        let response = try await postToAPI(url: "\(config.baseURL)/stt", headers: combineHeaders(try config.headers(), options.headers?.mapValues(Optional.some), ["Content-Type": body.contentType]).compactMapValues { $0 }, body: PostBody(content: .data(body.data), values: nil), failedResponseHandler: xaiFailedResponseHandler, successfulResponseHandler: createJsonResponseHandler(responseSchema: transcriptionResponseSchema), isAborted: options.abortSignal, fetch: config.fetch)
        var metadata: SharedV4ProviderMetadata?
        if let words = response.value.words, words.contains(where: { $0.speaker != nil }) {
            metadata = ["xai": ["words": .array(words.map { word in
                var data: [String: JSONValue] = ["text": .string(word.text), "start": .number(word.start), "end": .number(word.end)]
                if let speaker = word.speaker { data["speaker"] = .number(speaker) }
                else if word.speakerIsNull { data["speaker"] = .null }
                return .object(data)
            })]]
        }
        return .init(text: response.value.text, segments: (response.value.words ?? []).map { .init(text: $0.text, startSecond: $0.start, endSecond: $0.end) }, language: response.value.language?.isEmpty == false ? response.value.language : nil, durationInSeconds: response.value.duration, response: .init(timestamp: timestamp, modelId: modelId, headers: response.responseHeaders, body: response.rawValue), providerMetadata: metadata)
    }

    public func doStream(options: TranscriptionModelV4StreamOptions) async throws -> TranscriptionModelV4StreamResult {
        let timestamp = Date()
        let xai = try await parseProviderOptions(provider: "xai", providerOptions: options.providerOptions, schema: xaiTranscriptionOptionsSchema) ?? .init()
        if xai.multichannel == true && xai.channels == nil { throw InvalidArgumentError(argument: "providerOptions", message: "providerOptions.xai.channels is required when providerOptions.xai.multichannel is true") }
        var warnings: [SharedV4Warning] = []
        if xai.format != nil { warnings.append(.unsupported(feature: "providerOptions.xai.format", details: "xAI streaming transcription does not support format.")) }
        let encodings = ["audio/pcm": "pcm", "audio/pcmu": "mulaw", "audio/pcma": "alaw", "audio/opus": "opus"]
        if xai.audioFormat == nil && encodings[options.inputAudioFormat.type] == nil {
            warnings.append(.other(message: "Unrecognized inputAudioFormat.type \"\(options.inputAudioFormat.type)\"; falling back to raw PCM encoding. Use audio/pcm, audio/pcmu, audio/pcma, audio/opus, or set providerOptions.xai.audioFormat explicitly."))
        }
        var components = URLComponents(string: "\(config.baseURL)/stt")!
        components.scheme = components.scheme == "http" ? "ws" : "wss"
        var params = sttParams(xai).filter { $0.0 != "sample_rate" }
        if let rate = xai.sampleRate ?? options.inputAudioFormat.rate { params.append(("sample_rate", String(rate))) }
        params.append(("encoding", xai.audioFormat?.rawValue ?? encodings[options.inputAudioFormat.type] ?? "pcm"))
        if let value = xai.streaming?.interimResults { params.append(("interim_results", String(value))) }
        if let value = xai.streaming?.endpointing { params.append(("endpointing", String(value))) }
        if let value = xai.streaming?.smartTurn { params.append(("smart_turn", String(value))) }
        if let value = xai.streaming?.smartTurnTimeout { params.append(("smart_turn_timeout", String(value))) }
        components.queryItems = (components.queryItems ?? []) + params.map { URLQueryItem(name: $0.0, value: $0.1) }
        let url = components.url!
        var request = URLRequest(url: url)
        for (key, value) in combineHeaders(try config.headers(), options.headers?.mapValues(Optional.some)).compactMapValues({ $0 }) { request.setValue(value, forHTTPHeaderField: key) }
        let requestValue = request
        let factory = config.webSocket ?? defaultXAIWebSocket
        let expected = xai.multichannel == true ? xai.channels! : 1
        let streamWarnings = warnings
        let stream = AsyncThrowingStream<TranscriptionModelV4StreamPart, Error> { continuation in
            let producer = Task {
                var sender: Task<Void, Never>?
                defer { sender?.cancel(); Task { await cancelStream(options.audio) } }
                do {
                    try Task.checkCancellation()
                    if options.abortSignal?() == true { throw CancellationError() }
                    let connection = try factory(requestValue)
                    var normalFinish = false
                    defer { connection.close(code: normalFinish ? 1000 : nil) }
                    let abortWatcher: Task<Void, Never>? = options.abortSignal.map { signal in
                        Task {
                            while !Task.isCancelled {
                                if signal() { continuation.finish(throwing: CancellationError()); connection.close(code: nil); return }
                                do { try await Task.sleep(nanoseconds: 20_000_000) } catch { return }
                            }
                        }
                    }
                    defer { abortWatcher?.cancel() }
                    var finalized: [Int: [String]] = [:]
                    var pending: [Int: String] = [:]
                    var done: [Int: String] = [:]
                    var duration: Double?
                    for try await text in connection.messages {
                        try Task.checkCancellation()
                        let data = Data(text.utf8)
                        guard let raw = try? JSONDecoder().decode(JSONValue.self, from: data) else { continue }
                        if options.includeRawChunks == true { continuation.yield(.raw(rawValue: raw)) }
                        guard let event = try? JSONDecoder().decode(StreamingEvent.self, from: data) else { continue }
                        let channel = event.channelIndex ?? 0
                        let id = event.channelIndex.map { "channel-\($0)" }
                        switch event.type {
                        case "transcript.created":
                            continuation.yield(.streamStart(warnings: streamWarnings))
                            if sender == nil {
                                sender = Task {
                                    do {
                                        for try await audio in options.audio {
                                            try Task.checkCancellation()
                                            switch audio {
                                            case .binary(let bytes): try await connection.send(.binary(bytes))
                                            case .base64(let value): try await connection.send(.binary(convertBase64ToData(value)))
                                            }
                                        }
                                        try Task.checkCancellation()
                                        try await connection.send(.text(#"{"type":"audio.done"}"#))
                                    } catch { continuation.finish(throwing: error); connection.close(code: nil) }
                                }
                            }
                        case "transcript.partial":
                            if event.isFinal == true && event.speechFinal == true {
                                if let text = event.text, !text.isEmpty { finalized[channel, default: []].append(text) }
                                pending[channel] = nil
                                let end = event.start.flatMap { start in event.duration.map { start + $0 } }
                                continuation.yield(.transcriptFinal(id: id, text: event.text ?? "", startSecond: event.start, endSecond: end, channelIndex: event.channelIndex, providerMetadata: nil))
                            } else {
                                pending[channel] = event.text ?? ""
                                continuation.yield(.transcriptPartial(id: id, text: event.text ?? "", startSecond: event.start, durationInSeconds: event.duration, channelIndex: event.channelIndex, providerMetadata: nil))
                            }
                        case "transcript.done":
                            let accumulated = ((finalized[channel] ?? []) + (pending[channel].flatMap { $0.isEmpty ? nil : [$0] } ?? [])).joined(separator: " ")
                            done[channel] = event.text?.isEmpty == false ? event.text : accumulated
                            duration = event.duration ?? duration
                            if done.count >= expected {
                                normalFinish = true
                                continuation.yield(.finish(text: done.keys.sorted().compactMap { done[$0] }.joined(separator: "\n"), segments: [], language: xai.language, durationInSeconds: duration, providerMetadata: nil))
                                continuation.finish()
                                return
                            }
                        case "error": throw InvalidResponseDataError(data: raw, message: event.message ?? "xAI STT error")
                        default: break
                        }
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { _ in producer.cancel() }
        }
        return .init(stream: stream, request: .init(body: url.absoluteString), response: .init(timestamp: timestamp, modelId: modelId))
    }

    private func sttParams(_ options: XAITranscriptionModelOptions) -> [(String, String)] {
        var params: [(String, String)] = []
        if !modelId.isEmpty { params.append(("model", modelId)) }
        if let value = options.sampleRate { params.append(("sample_rate", String(value))) }
        if let value = options.language { params.append(("language", value)) }
        if let value = options.multichannel { params.append(("multichannel", String(value))) }
        if let value = options.channels { params.append(("channels", String(value))) }
        if let value = options.diarize { params.append(("diarize", String(value))) }
        if let value = options.fillerWords { params.append(("filler_words", String(value))) }
        if let value = options.vadThreshold { params.append(("vad_threshold", String(value))) }
        for value in options.keyterm?.values ?? [] { params.append(("keyterm", value)) }
        return params
    }
}
