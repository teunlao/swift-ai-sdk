import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct OpenAIRealtimeModelConfig: Sendable {
    public let provider: String
    public let baseURL: String
    public let headers: @Sendable () throws -> [String: String?]
    public let fetch: FetchFunction?

    public init(
        provider: String,
        baseURL: String,
        headers: @escaping @Sendable () throws -> [String: String?],
        fetch: FetchFunction? = nil
    ) {
        self.provider = provider
        self.baseURL = baseURL
        self.headers = headers
        self.fetch = fetch
    }
}

public typealias Experimental_OpenAIRealtimeModelConfig = OpenAIRealtimeModelConfig

public final class OpenAIRealtimeModel: RealtimeModelV4ClientSecretWebSocket {
    public let specificationVersion = "v4"
    public let provider: String
    public let modelId: String

    private let config: OpenAIRealtimeModelConfig

    public init(modelId: String, config: OpenAIRealtimeModelConfig) {
        self.modelId = modelId
        self.provider = config.provider
        self.config = config
    }

    public func doCreateClientSecret(
        options: RealtimeModelV4ClientSecretOptions
    ) async throws -> RealtimeModelV4ClientSecretResult {
        let url = "\(config.baseURL)/realtime/client_secrets"
        let session = try options.sessionConfig.map(buildSessionObject) ?? [
            "type": "realtime",
            "model": .string(modelId)
        ]

        var body: [String: JSONValue] = [
            "session": .object(session)
        ]
        if let expiresAfterSeconds = options.expiresAfterSeconds {
            body["expires_after"] = [
                "anchor": "created_at",
                "seconds": .number(Double(expiresAfterSeconds))
            ]
        }

        try Task.checkCancellation()
        guard let endpoint = URL(string: url) else {
            throw InvalidArgumentError(argument: "url", message: "invalid OpenAI realtime client secret URL")
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 24 * 60 * 60
        request.httpBody = Data(try openAIJSONStringify(.object(body)).utf8)
        for (key, value) in combineHeaders(try config.headers(), ["Content-Type": "application/json"]).compactMapValues({ $0 }) {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let fetch = config.fetch ?? defaultFetchFunction()
        let fetchResponse = try await fetch(request)
        do {
            try Task.checkCancellation()
            guard let httpResponse = fetchResponse.urlResponse as? HTTPURLResponse else {
                throw OpenAIRealtimeClientSecretError(message: "OpenAI realtime client secret request failed: invalid response")
            }
            if !(200...299).contains(httpResponse.statusCode) {
                let text = try await fetchResponse.body.collectText()
                try Task.checkCancellation()
                throw OpenAIRealtimeClientSecretError(message: "OpenAI realtime client secret request failed: \(httpResponse.statusCode) \(text)")
            }
            let responseBody = try await fetchResponse.body.collectData()
            try Task.checkCancellation()
            let decoded = try JSONDecoder().decode(OpenAIRealtimeClientSecretResponse.self, from: responseBody)
            return RealtimeModelV4ClientSecretResult(
                token: decoded.value,
                url: try openAIRealtimeWebSocketURL(baseURL: config.baseURL, modelId: modelId),
                expiresAt: decoded.expiresAt
            )
        } catch {
            if case .stream(let stream) = fetchResponse.body { await cancelStream(stream) }
            throw error
        }
    }

    public func getWebSocketConfig(options: RealtimeModelV4WebSocketOptions) throws -> RealtimeModelV4WebSocketConfig {
        RealtimeModelV4WebSocketConfig(
            url: options.url,
            protocols: ["realtime", "openai-insecure-api-key.\(options.token)"]
        )
    }

    public func parseServerEvent(raw: JSONValue) throws -> [RealtimeModelV4ServerEvent] {
        [try openAIRealtimeServerEvent(raw)]
    }

    public func serializeClientEvent(_ event: RealtimeModelV4ClientEvent) async throws -> JSONValue? {
        try openAIRealtimeClientEvent(event, modelId: modelId)
    }

    public func buildSessionConfig(_ config: RealtimeModelV4SessionConfig) throws -> JSONValue {
        .object(try buildSessionObject(config))
    }

    private func buildSessionObject(_ config: RealtimeModelV4SessionConfig) throws -> [String: JSONValue] {
        try buildOpenAIRealtimeSessionConfig(config, modelId: modelId)
    }
}

public typealias Experimental_OpenAIRealtimeModel = OpenAIRealtimeModel

public struct OpenAIRealtimeOptions: Sendable, Equatable {
    public enum API: String, Sendable { case live, realtime }
    public let api: API?

    public init(api: API? = nil) { self.api = api }
}

public struct OpenAIRealtimeFactory: RealtimeFactoryV4 {
    private let config: OpenAIRealtimeModelConfig

    init(config: OpenAIRealtimeModelConfig) { self.config = config }

    public func callAsFunction(_ modelId: String, options: OpenAIRealtimeOptions = .init()) throws -> OpenAIRealtimeModel {
        let api = options.api ?? (modelId == "gpt-live-1" ? .live : .realtime)
        if api == .live { throw UnsupportedFunctionalityError(functionality: "OpenAI Live API") }
        return OpenAIRealtimeModel(modelId: modelId, config: .init(
            provider: "\(config.provider).realtime", baseURL: config.baseURL, headers: config.headers, fetch: config.fetch
        ))
    }

    public func realtimeModel(modelId: String) throws -> any RealtimeModelV4 { try self(modelId) }

    public func getToken(options: RealtimeFactoryV4GetTokenOptions) async throws -> RealtimeFactoryV4GetTokenResult {
        try await mint(options, api: nil)
    }

    public func getToken(options: RealtimeFactoryV4GetTokenOptions, api: OpenAIRealtimeOptions.API) async throws -> RealtimeFactoryV4GetTokenResult {
        try await mint(options, api: api)
    }

    private func mint(_ options: RealtimeFactoryV4GetTokenOptions, api: OpenAIRealtimeOptions.API?) async throws -> RealtimeFactoryV4GetTokenResult {
        let model = try self(options.model, options: .init(api: api))
        let secret = try await model.doCreateClientSecret(options: .init(expiresAfterSeconds: options.expiresAfterSeconds, sessionConfig: options.sessionConfig))
        return .init(token: secret.token, url: secret.url, expiresAt: secret.expiresAt)
    }
}

public typealias Experimental_OpenAIRealtimeFactory = OpenAIRealtimeFactory
public typealias Experimental_OpenAIRealtimeOptions = OpenAIRealtimeOptions

private struct OpenAIRealtimeClientSecretResponse: Decodable, Sendable {
    let value: String
    let expiresAt: Double?

    enum CodingKeys: String, CodingKey {
        case value
        case expiresAt = "expires_at"
    }
}

private struct OpenAIRealtimeClientSecretError: Error, LocalizedError, CustomStringConvertible, Sendable {
    let message: String

    var errorDescription: String? { message }
    var description: String { message }
}

private func openAIRealtimeWebSocketURL(baseURL: String, modelId: String) throws -> String {
    guard let base = URL(string: baseURL), let scheme = base.scheme?.lowercased(), let host = base.host else {
        throw InvalidArgumentError(argument: "baseURL", message: "invalid OpenAI realtime baseURL")
    }
    let defaults = ["http": 80, "https": 443, "ws": 80, "wss": 443, "ftp": 21]
    var authority = host.contains(":") ? "[\(host.lowercased())]" : host.lowercased()
    if let port = base.port, defaults[scheme] != port { authority += ":\(port)" }
    let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
    guard let model = modelId.addingPercentEncoding(withAllowedCharacters: allowed) else {
        throw InvalidArgumentError(argument: "modelId", message: "invalid OpenAI realtime model ID")
    }
    return "wss://\(authority)/v1/realtime?model=\(model)"
}

private func openAIRealtimeServerEvent(_ raw: JSONValue) throws -> RealtimeModelV4ServerEvent {
    guard case .object(let event) = raw else {
        throw TypeValidationError.wrap(value: raw, cause: SchemaValidationIssuesError(vendor: "openai", issues: "expected realtime event object"))
    }
    let type = try requiredString(event["type"], raw: raw)
    switch type {
    case "session.created":
        return .sessionCreated(sessionId: try stringValue(objectValue(event["session"])["id"]), raw: raw)
    case "session.updated":
        return .sessionUpdated(raw: raw)
    case "input_audio_buffer.speech_started":
        return .speechStarted(itemId: try stringValue(event["item_id"]), raw: raw)
    case "input_audio_buffer.speech_stopped":
        return .speechStopped(itemId: try stringValue(event["item_id"]), raw: raw)
    case "input_audio_buffer.committed":
        return .audioCommitted(
            itemId: try stringValue(event["item_id"]),
            previousItemId: try stringValue(event["previous_item_id"]),
            raw: raw
        )
    case "conversation.item.added":
        let item = objectValue(event["item"])
        return .conversationItemAdded(
            itemId: try requiredString(nullish(item["id"]) ?? event["item_id"], raw: raw),
            item: try requiredValue(event["item"], raw: raw),
            raw: raw
        )
    case "conversation.item.input_audio_transcription.completed":
        return .inputTranscriptionCompleted(
            itemId: try requiredString(event["item_id"], raw: raw),
            transcript: try stringValue(event["transcript"]) ?? "",
            raw: raw
        )
    case "response.created":
        return .responseCreated(
            responseId: try requiredString(nullish(objectValue(event["response"])["id"]) ?? event["response_id"], raw: raw),
            raw: raw
        )
    case "response.done":
        let response = objectValue(event["response"])
        return .responseDone(
            responseId: try requiredString(nullish(response["id"]) ?? event["response_id"], raw: raw),
            status: try stringValue(response["status"]) ?? "completed",
            raw: raw
        )
    case "response.output_item.added":
        return .outputItemAdded(
            responseId: try requiredString(event["response_id"], raw: raw),
            itemId: try requiredString(nullish(objectValue(event["item"])["id"]) ?? event["item_id"], raw: raw),
            raw: raw
        )
    case "response.output_item.done":
        return .outputItemDone(
            responseId: try requiredString(event["response_id"], raw: raw),
            itemId: try requiredString(nullish(objectValue(event["item"])["id"]) ?? event["item_id"], raw: raw),
            raw: raw
        )
    case "response.content_part.added":
        return .contentPartAdded(
            responseId: try requiredString(event["response_id"], raw: raw),
            itemId: try requiredString(event["item_id"], raw: raw),
            raw: raw
        )
    case "response.content_part.done":
        return .contentPartDone(
            responseId: try requiredString(event["response_id"], raw: raw),
            itemId: try requiredString(event["item_id"], raw: raw),
            raw: raw
        )
    case "response.output_audio.delta":
        return .audioDelta(
            responseId: try requiredString(event["response_id"], raw: raw),
            itemId: try requiredString(event["item_id"], raw: raw),
            delta: try requiredString(event["delta"], raw: raw),
            raw: raw
        )
    case "response.output_audio.done":
        return .audioDone(
            responseId: try requiredString(event["response_id"], raw: raw),
            itemId: try requiredString(event["item_id"], raw: raw),
            raw: raw
        )
    case "response.output_audio_transcript.delta":
        return .audioTranscriptDelta(
            responseId: try requiredString(event["response_id"], raw: raw),
            itemId: try requiredString(event["item_id"], raw: raw),
            delta: try requiredString(event["delta"], raw: raw),
            raw: raw
        )
    case "response.output_audio_transcript.done":
        return .audioTranscriptDone(
            responseId: try requiredString(event["response_id"], raw: raw),
            itemId: try requiredString(event["item_id"], raw: raw),
            transcript: try stringValue(event["transcript"]),
            raw: raw
        )
    case "response.output_text.delta":
        return .textDelta(
            responseId: try requiredString(event["response_id"], raw: raw),
            itemId: try requiredString(event["item_id"], raw: raw),
            delta: try requiredString(event["delta"], raw: raw),
            raw: raw
        )
    case "response.output_text.done":
        return .textDone(
            responseId: try requiredString(event["response_id"], raw: raw),
            itemId: try requiredString(event["item_id"], raw: raw),
            text: try stringValue(event["text"]),
            raw: raw
        )
    case "response.function_call_arguments.delta":
        return .functionCallArgumentsDelta(
            responseId: try requiredString(event["response_id"], raw: raw),
            itemId: try requiredString(event["item_id"], raw: raw),
            callId: try requiredString(event["call_id"], raw: raw),
            delta: try requiredString(event["delta"], raw: raw),
            raw: raw
        )
    case "response.function_call_arguments.done":
        return .functionCallArgumentsDone(
            responseId: try requiredString(event["response_id"], raw: raw),
            itemId: try requiredString(event["item_id"], raw: raw),
            callId: try requiredString(event["call_id"], raw: raw),
            name: try requiredString(event["name"], raw: raw),
            arguments: try requiredString(event["arguments"], raw: raw),
            raw: raw
        )
    case "error":
        let error = objectValue(event["error"])
        return .error(
            message: try stringValue(error["message"]) ?? stringValue(event["message"]) ?? "Unknown error",
            code: try stringValue(error["code"]) ?? stringValue(event["code"]),
            clientEventId: try stringValue(error["event_id"]),
            raw: raw
        )
    default:
        return .custom(rawType: type, raw: raw)
    }
}

private func openAIRealtimeClientEvent(_ event: RealtimeModelV4ClientEvent, modelId: String) throws -> JSONValue? {
    switch event {
    case let .sessionUpdate(config, eventId):
        var payload: [String: JSONValue] = [
            "type": "session.update",
            "session": .object(try buildOpenAIRealtimeSessionConfig(config, modelId: modelId))
        ]
        if let eventId {
            payload["event_id"] = .string(eventId)
        }
        return .object(payload)
    case let .inputAudioAppend(audio, eventId):
        var payload: [String: JSONValue] = ["type": "input_audio_buffer.append", "audio": .string(audio)]
        if let eventId {
            payload["event_id"] = .string(eventId)
        }
        return .object(payload)
    case .sessionStart, .sessionClose, .inputAudioMute, .inputAudioUnmute, .contextAppend:
        return nil
    case .inputAudioCommit:
        return ["type": "input_audio_buffer.commit"]
    case .inputAudioClear:
        return ["type": "input_audio_buffer.clear"]
    case .conversationItemCreate(let item):
        return ["type": "conversation.item.create", "item": openAIRealtimeConversationItem(item)]
    case .conversationItemTruncate(let itemId, let contentIndex, let audioEndMs):
        return [
            "type": "conversation.item.truncate",
            "item_id": .string(itemId),
            "content_index": .number(Double(contentIndex)),
            "audio_end_ms": .number(Double(audioEndMs))
        ]
    case .responseCreate(let options):
        var payload: [String: JSONValue] = ["type": "response.create"]
        if let options {
            var response: [String: JSONValue] = [:]
            if let modalities = options.modalities {
                response["output_modalities"] = .array(modalities.map(JSONValue.string))
            }
            if let instructions = options.instructions {
                response["instructions"] = .string(instructions)
            }
            if let metadata = options.metadata {
                response["metadata"] = .object(metadata)
            }
            payload["response"] = .object(response)
        }
        return .object(payload)
    case .responseCancel:
        return ["type": "response.cancel"]
    }
}

private func buildOpenAIRealtimeSessionConfig(
    _ config: RealtimeModelV4SessionConfig,
    modelId: String
) throws -> [String: JSONValue] {
    var session: [String: JSONValue] = [
        "type": "realtime",
        "model": .string(modelId)
    ]

    if let instructions = config.instructions {
        session["instructions"] = .string(instructions)
    }
    if let outputModalities = config.outputModalities {
        session["output_modalities"] = .array(outputModalities.map { .string($0.rawValue) })
    }

    var audio: [String: JSONValue] = [:]
    if config.inputAudioFormat != nil || config.inputAudioTranscription != nil || config.turnDetection != nil {
        var input: [String: JSONValue] = [:]
        if let inputAudioFormat = config.inputAudioFormat {
            input["format"] = openAIRealtimeAudioFormat(inputAudioFormat)
        }
        if let turnDetection = config.turnDetection {
            input["turn_detection"] = openAIRealtimeTurnDetection(turnDetection)
        }
        if let transcription = config.inputAudioTranscription {
            input["transcription"] = openAIRealtimeTranscriptionConfig(transcription)
        }
        audio["input"] = .object(input)
    }
    if config.outputAudioFormat != nil || config.voice != nil {
        var output: [String: JSONValue] = [:]
        if let outputAudioFormat = config.outputAudioFormat {
            output["format"] = openAIRealtimeAudioFormat(outputAudioFormat)
        }
        if let voice = config.voice {
            output["voice"] = .string(voice)
        }
        audio["output"] = .object(output)
    }
    if !audio.isEmpty {
        session["audio"] = .object(audio)
    }

    if let tools = config.tools, !tools.isEmpty {
        session["tools"] = .array(tools.map(openAIRealtimeTool))
        session["tool_choice"] = "auto"
    }

    if let providerOptions = config.providerOptions {
        for (key, value) in providerOptions {
            session[key] = value
        }
    }

    return session
}

private func openAIRealtimeAudioFormat(_ format: RealtimeModelV4SessionConfig.AudioFormat) -> JSONValue {
    var payload: [String: JSONValue] = ["type": .string(format.type)]
    if let rate = format.rate {
        payload["rate"] = .number(Double(rate))
    }
    return .object(payload)
}

private func openAIRealtimeTurnDetection(_ turnDetection: RealtimeModelV4SessionConfig.TurnDetection) -> JSONValue {
    switch turnDetection {
    case .disabled:
        return .null
    case let .serverVAD(threshold, silenceDurationMs, prefixPaddingMs):
        return openAIRealtimeVAD(
            type: "server_vad",
            threshold: threshold,
            silenceDurationMs: silenceDurationMs,
            prefixPaddingMs: prefixPaddingMs
        )
    case let .semanticVAD(threshold, silenceDurationMs, prefixPaddingMs):
        return openAIRealtimeVAD(
            type: "semantic_vad",
            threshold: threshold,
            silenceDurationMs: silenceDurationMs,
            prefixPaddingMs: prefixPaddingMs
        )
    }
}

private func openAIRealtimeVAD(
    type: String,
    threshold: Double?,
    silenceDurationMs: Int?,
    prefixPaddingMs: Int?
) -> JSONValue {
    var payload: [String: JSONValue] = ["type": .string(type)]
    if let threshold {
        payload["threshold"] = .number(threshold)
    }
    if let silenceDurationMs {
        payload["silence_duration_ms"] = .number(Double(silenceDurationMs))
    }
    if let prefixPaddingMs {
        payload["prefix_padding_ms"] = .number(Double(prefixPaddingMs))
    }
    return .object(payload)
}

private func openAIRealtimeTranscriptionConfig(_ config: RealtimeModelV4SessionConfig.TranscriptionConfig) -> JSONValue {
    var payload: [String: JSONValue] = [
        "model": .string(config.model ?? "gpt-realtime-whisper")
    ]
    if let language = config.language {
        payload["language"] = .string(language)
    }
    if let prompt = config.prompt {
        payload["prompt"] = .string(prompt)
    }
    return .object(payload)
}

private func openAIRealtimeTool(_ tool: RealtimeModelV4ToolDefinition) -> JSONValue {
    var payload: [String: JSONValue] = [
        "type": .string(tool.type),
        "name": .string(tool.name),
        "parameters": tool.parameters
    ]
    if let description = tool.description {
        payload["description"] = .string(description)
    }
    return .object(payload)
}

private func openAIRealtimeConversationItem(_ item: RealtimeModelV4ConversationItem) -> JSONValue {
    switch item {
    case .textMessage(let text):
        return [
            "type": "message",
            "role": "user",
            "content": [["type": "input_text", "text": .string(text)]]
        ]
    case .audioMessage(let audio):
        return [
            "type": "message",
            "role": "user",
            "content": [["type": "input_audio", "audio": .string(audio)]]
        ]
    case .functionCallOutput(let callId, _, let output):
        return [
            "type": "function_call_output",
            "call_id": .string(callId),
            "output": .string(output)
        ]
    }
}

private func objectValue(_ value: JSONValue?) -> [String: JSONValue] {
    guard case .object(let object) = value else {
        return [:]
    }
    return object
}

private func stringValue(_ value: JSONValue?) throws -> String? {
    guard let value, value != .null else { return nil }
    guard case .string(let string) = value else {
        throw TypeValidationError.wrap(value: value, cause: SchemaValidationIssuesError(vendor: "openai", issues: "expected realtime string field"))
    }
    return string
}

private func requiredValue(_ value: JSONValue?, raw: JSONValue) throws -> JSONValue {
    guard let value else {
        throw TypeValidationError.wrap(value: raw, cause: SchemaValidationIssuesError(vendor: "openai", issues: "missing realtime field"))
    }
    return value
}

private func requiredString(_ value: JSONValue?, raw: JSONValue) throws -> String {
    guard let string = try stringValue(value) else {
        throw TypeValidationError.wrap(value: raw, cause: SchemaValidationIssuesError(vendor: "openai", issues: "missing realtime string field"))
    }
    return string
}

private func nullish(_ value: JSONValue?) -> JSONValue? {
    value == .null ? nil : value
}
