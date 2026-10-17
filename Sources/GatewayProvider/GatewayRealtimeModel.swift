import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class GatewayRealtimeModel: RealtimeModelV4ClientSecretWebSocket {
    public let modelId: String
    public var provider: String { "gateway.realtime" }
    private let config: GatewayConfig
    private let teamIdOrSlug: String?

    init(modelId: String, config: GatewayConfig, teamIdOrSlug: String?) {
        self.modelId = modelId
        self.config = config
        self.teamIdOrSlug = teamIdOrSlug
    }

    public func doCreateClientSecret(options: RealtimeModelV4ClientSecretOptions = .init()) async throws -> RealtimeModelV4ClientSecretResult {
        let secret = try await GatewayClientSecrets(config: config).mint(model: modelId, expiresAfterSeconds: options.expiresAfterSeconds)
        return .init(token: secret.token, url: try gatewayWebSocketURL(config.baseURL, modelId: modelId, endpoint: "realtime-model"), expiresAt: secret.expiresAt)
    }

    public func getWebSocketConfig(options: RealtimeModelV4WebSocketOptions) throws -> RealtimeModelV4WebSocketConfig {
        .init(url: options.url, protocols: getGatewayRealtimeProtocols(options.token, teamIdOrSlug: teamIdOrSlug))
    }

    public func parseServerEvent(raw: JSONValue) throws -> [RealtimeModelV4ServerEvent] {
        let data = try JSONEncoder().encode(raw)
        return [try JSONDecoder().decode(GatewayRealtimeServerEvent.self, from: data).event]
    }

    public func serializeClientEvent(_ event: RealtimeModelV4ClientEvent) async throws -> JSONValue {
        var body: [String: JSONValue]
        var eventId: String?
        switch event {
        case .sessionUpdate(let config, let id):
            body = ["type": "session-update", "config": try buildSessionConfig(config)]; eventId = id
        case .sessionStart(let config, let id):
            body = ["type": "session-start", "config": try buildSessionConfig(config)]; eventId = id
        case .sessionClose(let id): body = ["type": "session-close"]; eventId = id
        case .inputAudioMute(let id): body = ["type": "input-audio-mute"]; eventId = id
        case .inputAudioUnmute(let id): body = ["type": "input-audio-unmute"]; eventId = id
        case .contextAppend(let content, let delegationId, let id, let options):
            body = ["type": "context-append", "content": .string(content), "delegationId": delegationId.map(JSONValue.string) ?? .null]
            if let options { body["providerOptions"] = try gatewayJSON(options) }
            eventId = id
        case .inputAudioAppend(let audio, let id): body = ["type": "input-audio-append", "audio": .string(audio)]; eventId = id
        case .inputAudioCommit: body = ["type": "input-audio-commit"]
        case .inputAudioClear: body = ["type": "input-audio-clear"]
        case .conversationItemCreate(let item):
            var value: [String: JSONValue]
            switch item {
            case .textMessage(let text): value = ["type": "text-message", "role": "user", "text": .string(text)]
            case .audioMessage(let audio): value = ["type": "audio-message", "role": "user", "audio": .string(audio)]
            case .functionCallOutput(let callId, let name, let output):
                value = ["type": "function-call-output", "callId": .string(callId), "output": .string(output)]
                if let name { value["name"] = .string(name) }
            }
            body = ["type": "conversation-item-create", "item": .object(value)]
        case .conversationItemTruncate(let itemId, let contentIndex, let audioEndMs):
            body = ["type": "conversation-item-truncate", "itemId": .string(itemId), "contentIndex": .number(Double(contentIndex)), "audioEndMs": .number(Double(audioEndMs))]
        case .responseCreate(let options):
            body = ["type": "response-create"]
            if let options {
                var value: [String: JSONValue] = [:]
                if let modalities = options.modalities { value["modalities"] = .array(modalities.map(JSONValue.string)) }
                if let instructions = options.instructions { value["instructions"] = .string(instructions) }
                if let metadata = options.metadata { value["metadata"] = .object(metadata) }
                body["options"] = .object(value)
            }
        case .responseCancel: body = ["type": "response-cancel"]
        }
        if let eventId { body["eventId"] = .string(eventId) }
        return .object(body)
    }

    public func buildSessionConfig(_ config: RealtimeModelV4SessionConfig) throws -> JSONValue {
        var body: [String: JSONValue] = [:]
        if let value = config.instructions { body["instructions"] = .string(value) }
        if let value = config.voice { body["voice"] = .string(value) }
        if let value = config.outputModalities { body["outputModalities"] = try gatewayJSON(value) }
        if let value = config.inputAudioFormat { body["inputAudioFormat"] = try gatewayJSON(value) }
        if let value = config.outputAudioFormat { body["outputAudioFormat"] = try gatewayJSON(value) }
        if let value = config.inputAudioTranscription { body["inputAudioTranscription"] = try gatewayJSON(value) }
        if let value = config.outputAudioTranscription { body["outputAudioTranscription"] = try gatewayJSON(value) }
        if let value = config.tools { body["tools"] = try gatewayJSON(value) }
        if let value = config.providerOptions { body["providerOptions"] = .object(value) }
        if let value = config.turnDetection {
            var detection: [String: JSONValue]
            let settings: (Double?, Int?, Int?)
            switch value {
            case .serverVAD(let threshold, let silence, let prefix): detection = ["type": "server-vad"]; settings = (threshold, silence, prefix)
            case .semanticVAD(let threshold, let silence, let prefix): detection = ["type": "semantic-vad"]; settings = (threshold, silence, prefix)
            case .disabled: detection = ["type": "disabled"]; settings = (nil, nil, nil)
            }
            if let value = settings.0 { detection["threshold"] = .number(value) }
            if let value = settings.1 { detection["silenceDurationMs"] = .number(Double(value)) }
            if let value = settings.2 { detection["prefixPaddingMs"] = .number(Double(value)) }
            body["turnDetection"] = .object(detection)
        }
        return .object(body)
    }
}

public struct GatewayRealtimeFactory: RealtimeFactoryV4 {
    let config: GatewayConfig
    let teamIdOrSlug: String?

    public func callAsFunction(_ modelId: String) -> GatewayRealtimeModel {
        GatewayRealtimeModel(modelId: modelId, config: config, teamIdOrSlug: teamIdOrSlug)
    }

    public func callAsFunction(_ modelId: GatewayRealtimeModelId) -> GatewayRealtimeModel { self(modelId.rawValue) }

    public func realtimeModel(modelId: String) -> any RealtimeModelV4 { self(modelId) }

    public func getToken(options: RealtimeFactoryV4GetTokenOptions) async throws -> RealtimeFactoryV4GetTokenResult {
        let result = try await self(options.model).doCreateClientSecret(options: .init(expiresAfterSeconds: options.expiresAfterSeconds, sessionConfig: options.sessionConfig))
        return .init(token: result.token, url: result.url, expiresAt: result.expiresAt)
    }
}

struct GatewayClientSecret: Decodable, Sendable {
    let token: String
    let expiresAt: Int?
}

struct GatewayClientSecrets: Sendable {
    let config: GatewayConfig

    func mint(model: String, expiresAfterSeconds: Int?, routeKind: String? = nil) async throws -> GatewayClientSecret {
        let headers = try await config.headers()
        do {
            var body: [String: JSONValue] = ["model": .string(model)]
            if let expiresAfterSeconds { body["expiresIn"] = .number(Double(expiresAfterSeconds)) }
            if let routeKind { body["routeKind"] = .string(routeKind) }
            let response = try await postJsonToAPI(
                url: gatewayAPIURL(baseURL: config.baseURL, path: "/v1/realtime/client-secrets", queryItems: []),
                headers: headers.compactMapValues { $0 }, body: JSONValue.object(body),
                failedResponseHandler: makeGatewayFailedResponseHandler(),
                successfulResponseHandler: createJsonResponseHandler(responseSchema: gatewaySchema(GatewayClientSecret.self)), fetch: config.fetch
            )
            return response.value
        } catch {
            throw asGatewayError(error, authMethod: parseAuthMethod(from: headers.compactMapValues { $0 }))
        }
    }
}

private struct GatewayRealtimeServerEvent: Decodable {
    let event: RealtimeModelV4ServerEvent
    private enum Key: String, CodingKey {
        case type, raw, sessionId, delegationMode, usage, seconds, reason, contextWindowUsageRatio
        case delta, speaker, startMs, endMs, delegationId, target, offsetMs, responseId
        case command, clientEventId, itemId, previousItemId, item, transcript, status, callId, name, arguments, text, message, code, rawType
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        func string(_ key: Key) throws -> String { try c.decode(String.self, forKey: key) }
        func optional(_ key: Key) throws -> String? { try c.decodeIfPresent(String.self, forKey: key) }
        func number(_ key: Key) throws -> Double { try c.decode(Double.self, forKey: key) }
        func optionalNumber(_ key: Key) throws -> Double? { try c.decodeIfPresent(Double.self, forKey: key) }
        func seconds() throws -> Double { try c.nestedContainer(keyedBy: Key.self, forKey: .usage).decode(Double.self, forKey: .seconds) }
        let type = try string(.type)
        let raw = try c.decode(JSONValue.self, forKey: .raw)
        switch type {
        case "session-started": event = .sessionStarted(sessionId: try string(.sessionId), delegationMode: try optional(.delegationMode).flatMap(RealtimeModelV4ServerEvent.Party.init(rawValue:)), raw: raw)
        case "session-closed": event = .sessionClosed(sessionId: try optional(.sessionId), usageSeconds: try seconds(), reason: try string(.reason), raw: raw)
        case "session-usage": event = .sessionUsage(usageSeconds: try seconds(), contextWindowUsageRatio: try optionalNumber(.contextWindowUsageRatio), raw: raw)
        case "audio-chunk": event = .audioChunk(delta: try string(.delta), raw: raw)
        case "transcript-fragment":
            let speaker = try string(.speaker)
            guard let value = RealtimeModelV4ServerEvent.Speaker(rawValue: speaker) else { throw DecodingError.dataCorruptedError(forKey: .speaker, in: c, debugDescription: "Invalid realtime speaker") }
            event = .transcriptFragment(speaker: value, delta: try string(.delta), startMs: try number(.startMs), endMs: try number(.endMs), raw: raw)
        case "delegation-created": event = .delegationCreated(delegationId: try string(.delegationId), target: try optional(.target).flatMap(RealtimeModelV4ServerEvent.Party.init(rawValue:)), offsetMs: try optionalNumber(.offsetMs), responseId: try optional(.responseId), raw: raw)
        case "command-acknowledged": event = .commandAcknowledged(command: try string(.command), clientEventId: try optional(.clientEventId), raw: raw)
        case "session-created": event = .sessionCreated(sessionId: try optional(.sessionId), raw: raw)
        case "session-updated": event = .sessionUpdated(raw: raw)
        case "speech-started": event = .speechStarted(itemId: try optional(.itemId), raw: raw)
        case "speech-stopped": event = .speechStopped(itemId: try optional(.itemId), raw: raw)
        case "audio-committed": event = .audioCommitted(itemId: try optional(.itemId), previousItemId: try optional(.previousItemId), raw: raw)
        case "conversation-item-added": event = .conversationItemAdded(itemId: try string(.itemId), item: try c.decode(JSONValue.self, forKey: .item), raw: raw)
        case "input-transcription-completed": event = .inputTranscriptionCompleted(itemId: try string(.itemId), transcript: try string(.transcript), raw: raw)
        case "response-created": event = .responseCreated(responseId: try string(.responseId), raw: raw)
        case "response-done": event = .responseDone(responseId: try string(.responseId), status: try string(.status), raw: raw)
        case "output-item-added": event = .outputItemAdded(responseId: try string(.responseId), itemId: try string(.itemId), raw: raw)
        case "output-item-done": event = .outputItemDone(responseId: try string(.responseId), itemId: try string(.itemId), raw: raw)
        case "content-part-added": event = .contentPartAdded(responseId: try string(.responseId), itemId: try string(.itemId), raw: raw)
        case "content-part-done": event = .contentPartDone(responseId: try string(.responseId), itemId: try string(.itemId), raw: raw)
        case "audio-delta": event = .audioDelta(responseId: try string(.responseId), itemId: try string(.itemId), delta: try string(.delta), raw: raw)
        case "audio-done": event = .audioDone(responseId: try string(.responseId), itemId: try string(.itemId), raw: raw)
        case "audio-transcript-delta": event = .audioTranscriptDelta(responseId: try string(.responseId), itemId: try string(.itemId), delta: try string(.delta), raw: raw)
        case "audio-transcript-done": event = .audioTranscriptDone(responseId: try string(.responseId), itemId: try string(.itemId), transcript: try optional(.transcript), raw: raw)
        case "text-delta": event = .textDelta(responseId: try string(.responseId), itemId: try string(.itemId), delta: try string(.delta), raw: raw)
        case "text-done": event = .textDone(responseId: try string(.responseId), itemId: try string(.itemId), text: try optional(.text), raw: raw)
        case "function-call-arguments-delta": event = .functionCallArgumentsDelta(responseId: try string(.responseId), itemId: try string(.itemId), callId: try string(.callId), delta: try string(.delta), raw: raw)
        case "function-call-arguments-done": event = .functionCallArgumentsDone(responseId: try string(.responseId), itemId: try string(.itemId), callId: try string(.callId), name: try string(.name), arguments: try string(.arguments), raw: raw)
        case "error": event = .error(message: try string(.message), code: try optional(.code), clientEventId: try optional(.clientEventId), raw: raw)
        case "custom": event = .custom(rawType: try string(.rawType), raw: raw)
        default: event = .custom(rawType: type, raw: raw)
        }
    }
}
