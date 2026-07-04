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

public final class OpenAIRealtimeModel: RealtimeModelV4 {
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

        var request = try URLRequest.openAIRealtimeRequest(
            url: url,
            headers: combineHeaders(
                try config.headers(),
                ["Content-Type": "application/json"]
            ).compactMapValues { $0 },
            body: .object(body)
        )
        request.httpMethod = "POST"

        let fetch = config.fetch ?? openAIRealtimeDefaultFetch
        let fetchResponse = try await fetch(request)
        guard let httpResponse = fetchResponse.urlResponse as? HTTPURLResponse else {
            throw OpenAIRealtimeClientSecretError(message: "OpenAI realtime client secret request failed: invalid response")
        }

        let responseBody = try await fetchResponse.body.collectData()
        guard (200...299).contains(httpResponse.statusCode) else {
            let text = String(data: responseBody, encoding: .utf8) ?? ""
            throw OpenAIRealtimeClientSecretError(
                message: "OpenAI realtime client secret request failed: \(httpResponse.statusCode) \(text)"
            )
        }

        let decoded = try JSONDecoder().decode(OpenAIRealtimeClientSecretResponse.self, from: responseBody)
        return RealtimeModelV4ClientSecretResult(
            token: decoded.value,
            url: try openAIRealtimeWebSocketURL(baseURL: config.baseURL, modelId: modelId),
            expiresAt: decoded.expiresAt
        )
    }

    public func getWebSocketConfig(options: RealtimeModelV4WebSocketOptions) throws -> RealtimeModelV4WebSocketConfig {
        RealtimeModelV4WebSocketConfig(
            url: options.url,
            protocols: ["realtime", "openai-insecure-api-key.\(options.token)"]
        )
    }

    public func parseServerEvent(raw: JSONValue) throws -> [RealtimeModelV4ServerEvent] {
        [openAIRealtimeServerEvent(raw)]
    }

    public func serializeClientEvent(_ event: RealtimeModelV4ClientEvent) async throws -> JSONValue {
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

final class OpenAIRealtimeFactory: RealtimeFactoryV4, @unchecked Sendable {
    private let config: OpenAIRealtimeModelConfig

    init(config: OpenAIRealtimeModelConfig) {
        self.config = config
    }

    func realtimeModel(modelId: String) -> any RealtimeModelV4 {
        OpenAIRealtimeModel(modelId: modelId, config: config)
    }

    func getToken(options: RealtimeFactoryV4GetTokenOptions) async throws -> RealtimeFactoryV4GetTokenResult {
        let secret = try await realtimeModel(modelId: options.model).doCreateClientSecret(
            options: .init(
                expiresAfterSeconds: options.expiresAfterSeconds,
                sessionConfig: options.sessionConfig
            )
        )
        return RealtimeFactoryV4GetTokenResult(
            token: secret.token,
            url: secret.url,
            expiresAt: secret.expiresAt
        )
    }
}

private struct OpenAIRealtimeClientSecretResponse: Decodable, Sendable {
    let value: String
    let expiresAt: Int?

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

private func openAIRealtimeDefaultFetch(_ request: URLRequest) async throws -> FetchResponse {
    let (data, response) = try await URLSession.shared.data(for: request)
    return FetchResponse(body: .data(data), urlResponse: response)
}

private func openAIRealtimeWebSocketURL(baseURL: String, modelId: String) throws -> String {
    guard let base = URL(string: baseURL), let host = base.host else {
        throw InvalidArgumentError(argument: "baseURL", message: "invalid OpenAI realtime baseURL")
    }

    var components = URLComponents()
    components.scheme = "wss"
    components.host = host
    components.port = base.port
    components.path = "/v1/realtime"
    components.queryItems = [URLQueryItem(name: "model", value: modelId)]

    guard let url = components.url else {
        throw InvalidArgumentError(argument: "baseURL", message: "invalid OpenAI realtime websocket URL")
    }
    return url.absoluteString
}

private func openAIRealtimeServerEvent(_ raw: JSONValue) -> RealtimeModelV4ServerEvent {
    guard case .object(let event) = raw else {
        return .custom(rawType: "unknown", raw: raw)
    }

    let type = stringValue(event["type"]) ?? "unknown"
    switch type {
    case "session.created":
        return .sessionCreated(sessionId: stringValue(objectValue(event["session"])["id"]), raw: raw)
    case "session.updated":
        return .sessionUpdated(raw: raw)
    case "input_audio_buffer.speech_started":
        return .speechStarted(itemId: stringValue(event["item_id"]), raw: raw)
    case "input_audio_buffer.speech_stopped":
        return .speechStopped(itemId: stringValue(event["item_id"]), raw: raw)
    case "input_audio_buffer.committed":
        return .audioCommitted(
            itemId: stringValue(event["item_id"]),
            previousItemId: stringValue(event["previous_item_id"]),
            raw: raw
        )
    case "conversation.item.added":
        let item = objectValue(event["item"])
        return .conversationItemAdded(
            itemId: stringValue(item["id"]) ?? stringValue(event["item_id"]) ?? "",
            item: event["item"] ?? .object([:]),
            raw: raw
        )
    case "conversation.item.input_audio_transcription.completed":
        return .inputTranscriptionCompleted(
            itemId: stringValue(event["item_id"]) ?? "",
            transcript: stringValue(event["transcript"]) ?? "",
            raw: raw
        )
    case "response.created":
        return .responseCreated(
            responseId: stringValue(objectValue(event["response"])["id"]) ?? stringValue(event["response_id"]) ?? "",
            raw: raw
        )
    case "response.done":
        let response = objectValue(event["response"])
        return .responseDone(
            responseId: stringValue(response["id"]) ?? stringValue(event["response_id"]) ?? "",
            status: stringValue(response["status"]) ?? "completed",
            raw: raw
        )
    case "response.output_item.added":
        return .outputItemAdded(
            responseId: stringValue(event["response_id"]) ?? "",
            itemId: stringValue(objectValue(event["item"])["id"]) ?? stringValue(event["item_id"]) ?? "",
            raw: raw
        )
    case "response.output_item.done":
        return .outputItemDone(
            responseId: stringValue(event["response_id"]) ?? "",
            itemId: stringValue(objectValue(event["item"])["id"]) ?? stringValue(event["item_id"]) ?? "",
            raw: raw
        )
    case "response.content_part.added":
        return .contentPartAdded(
            responseId: stringValue(event["response_id"]) ?? "",
            itemId: stringValue(event["item_id"]) ?? "",
            raw: raw
        )
    case "response.content_part.done":
        return .contentPartDone(
            responseId: stringValue(event["response_id"]) ?? "",
            itemId: stringValue(event["item_id"]) ?? "",
            raw: raw
        )
    case "response.output_audio.delta":
        return .audioDelta(
            responseId: stringValue(event["response_id"]) ?? "",
            itemId: stringValue(event["item_id"]) ?? "",
            delta: stringValue(event["delta"]) ?? "",
            raw: raw
        )
    case "response.output_audio.done":
        return .audioDone(
            responseId: stringValue(event["response_id"]) ?? "",
            itemId: stringValue(event["item_id"]) ?? "",
            raw: raw
        )
    case "response.output_audio_transcript.delta":
        return .audioTranscriptDelta(
            responseId: stringValue(event["response_id"]) ?? "",
            itemId: stringValue(event["item_id"]) ?? "",
            delta: stringValue(event["delta"]) ?? "",
            raw: raw
        )
    case "response.output_audio_transcript.done":
        return .audioTranscriptDone(
            responseId: stringValue(event["response_id"]) ?? "",
            itemId: stringValue(event["item_id"]) ?? "",
            transcript: stringValue(event["transcript"]),
            raw: raw
        )
    case "response.output_text.delta":
        return .textDelta(
            responseId: stringValue(event["response_id"]) ?? "",
            itemId: stringValue(event["item_id"]) ?? "",
            delta: stringValue(event["delta"]) ?? "",
            raw: raw
        )
    case "response.output_text.done":
        return .textDone(
            responseId: stringValue(event["response_id"]) ?? "",
            itemId: stringValue(event["item_id"]) ?? "",
            text: stringValue(event["text"]),
            raw: raw
        )
    case "response.function_call_arguments.delta":
        return .functionCallArgumentsDelta(
            responseId: stringValue(event["response_id"]) ?? "",
            itemId: stringValue(event["item_id"]) ?? "",
            callId: stringValue(event["call_id"]) ?? "",
            delta: stringValue(event["delta"]) ?? "",
            raw: raw
        )
    case "response.function_call_arguments.done":
        return .functionCallArgumentsDone(
            responseId: stringValue(event["response_id"]) ?? "",
            itemId: stringValue(event["item_id"]) ?? "",
            callId: stringValue(event["call_id"]) ?? "",
            name: stringValue(event["name"]) ?? "",
            arguments: stringValue(event["arguments"]) ?? "",
            raw: raw
        )
    case "error":
        let error = objectValue(event["error"])
        return .error(
            message: stringValue(error["message"]) ?? stringValue(event["message"]) ?? "Unknown error",
            code: stringValue(error["code"]) ?? stringValue(event["code"]),
            raw: raw
        )
    default:
        return .custom(rawType: type, raw: raw)
    }
}

private func openAIRealtimeClientEvent(_ event: RealtimeModelV4ClientEvent, modelId: String) throws -> JSONValue {
    switch event {
    case .sessionUpdate(let config):
        return [
            "type": "session.update",
            "session": .object(try buildOpenAIRealtimeSessionConfig(config, modelId: modelId))
        ]
    case .inputAudioAppend(let audio):
        return ["type": "input_audio_buffer.append", "audio": .string(audio)]
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

private func stringValue(_ value: JSONValue?) -> String? {
    guard case .string(let string) = value else {
        return nil
    }
    return string
}

private extension URLRequest {
    static func openAIRealtimeRequest(url: String, headers: [String: String], body: JSONValue) throws -> URLRequest {
        guard let requestURL = URL(string: url) else {
            throw InvalidArgumentError(argument: "url", message: "invalid OpenAI realtime client secret URL")
        }

        let foundation = jsonValueToFoundation(body)
        guard JSONSerialization.isValidJSONObject(foundation) else {
            throw InvalidArgumentError(argument: "body", message: "invalid OpenAI realtime client secret body")
        }

        var request = URLRequest(url: requestURL)
        request.timeoutInterval = 24 * 60 * 60
        request.httpBody = try JSONSerialization.data(withJSONObject: foundation, options: [.sortedKeys])
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }
}
