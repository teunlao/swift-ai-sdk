/**
 Specification for a realtime model that supports bidirectional audio/text communication.

 Port of upstream realtime model V4 provider contracts.
 */
public protocol RealtimeModelV4: Sendable {
    var specificationVersion: String { get }
    var provider: String { get }
    var modelId: String { get }

    /// Conversation semantics and supported transports, when declared.
    var capabilities: RealtimeModelV4Capabilities? { get }

    func parseServerEvent(raw: JSONValue) throws -> [RealtimeModelV4ServerEvent]

    /// Creates a raw-event parser for one connection, discarded on disconnect.
    /// `nil` means `parseServerEvent` is used directly.
    func createServerEventParser() -> (@Sendable (JSONValue) throws -> [RealtimeModelV4ServerEvent])?

    /// nil skips sending; .some(.null) is a JSON null frame.
    func serializeClientEvent(_ event: RealtimeModelV4ClientEvent) async throws -> JSONValue?
    func buildSessionConfig(_ config: RealtimeModelV4SessionConfig) throws -> JSONValue
    func getHealthCheckResponse(raw: JSONValue) throws -> JSONValue?
}

extension RealtimeModelV4 {
    public var specificationVersion: String { "v4" }

    public var capabilities: RealtimeModelV4Capabilities? { nil }

    public func createServerEventParser() -> (@Sendable (JSONValue) throws -> [RealtimeModelV4ServerEvent])? {
        nil
    }

    public func getHealthCheckResponse(raw: JSONValue) throws -> JSONValue? {
        nil
    }
}

/**
 A realtime model reachable from the browser through an ephemeral client secret
 and a WebSocket. Upstream marks both methods optional; the legacy connection is
 assumed when a model declares no `connections`.
 */
public protocol RealtimeModelV4ClientSecretWebSocket: RealtimeModelV4 {
    /// Server-side: creates a short-lived client secret for browser WebSocket connections.
    func doCreateClientSecret(
        options: RealtimeModelV4ClientSecretOptions
    ) async throws -> RealtimeModelV4ClientSecretResult

    /// Browser-side: the WebSocket URL and protocols for a client secret.
    func getWebSocketConfig(options: RealtimeModelV4WebSocketOptions) throws -> RealtimeModelV4WebSocketConfig
}

/// A realtime model reachable from a server over a WebSocket.
public protocol RealtimeModelV4ServerWebSocket: RealtimeModelV4 {
    /// Server-only connection settings. Headers can contain long-lived credentials.
    func getServerWebSocketConfig() async throws -> RealtimeModelV4ServerWebSocketConfig
}

/// A realtime model reachable over WebRTC.
public protocol RealtimeModelV4WebRTC: RealtimeModelV4 {
    /// Provider-specific setup for the WebRTC event channel.
    func getWebRTCConfig() -> RealtimeModelV4WebRTCConfig

    /// Server-side SDP exchange. Only the answer and session id go back to the client.
    func doCreateWebRTCSession(
        options: RealtimeModelV4WebRTCSessionOptions
    ) async throws -> RealtimeModelV4WebRTCSession
}

public struct RealtimeModelV4Capabilities: Sendable, Equatable {
    public enum Conversation: String, Sendable, Equatable {
        case continuous
        case turnBased = "turn-based"
    }

    public enum Transport: String, Sendable, Equatable {
        case websocket
        case webrtc
    }

    public enum Connection: String, Sendable, Equatable {
        case clientSecretWebSocket = "client-secret-websocket"
        case serverWebSocket = "server-websocket"
        case webrtc
    }

    public enum Startup: String, Sendable, Equatable {
        case sessionStart = "session-start"
        case sessionUpdate = "session-update"
    }

    public enum Finalization: String, Sendable, Equatable {
        case sessionClose = "session-close"
        case transportClose = "transport-close"
    }

    public let conversation: Conversation
    public let transports: [Transport]
    /// `nil` preserves the legacy client-secret WebSocket connection.
    public let connections: [Connection]?
    /// `nil` preserves session-update startup. WebRTC setup may start the session.
    public let startup: Startup?
    /// `nil` preserves transport-close finalization.
    public let finalization: Finalization?

    public init(
        conversation: Conversation,
        transports: [Transport],
        connections: [Connection]? = nil,
        startup: Startup? = nil,
        finalization: Finalization? = nil
    ) {
        self.conversation = conversation
        self.transports = transports
        self.connections = connections
        self.startup = startup
        self.finalization = finalization
    }
}

public struct RealtimeModelV4ServerWebSocketConfig: Sendable, Equatable {
    public let url: String
    public let headers: [String: String]

    public init(url: String, headers: [String: String]) {
        self.url = url
        self.headers = headers
    }
}

public struct RealtimeModelV4WebRTCConfig: Sendable, Equatable {
    public let dataChannelLabel: String

    public init(dataChannelLabel: String) {
        self.dataChannelLabel = dataChannelLabel
    }
}

public struct RealtimeModelV4WebRTCSessionOptions: Sendable {
    public let sdp: String
    public let sessionConfig: RealtimeModelV4SessionConfig?
    public let abortSignal: (@Sendable () -> Bool)?

    public init(
        sdp: String,
        sessionConfig: RealtimeModelV4SessionConfig? = nil,
        abortSignal: (@Sendable () -> Bool)? = nil
    ) {
        self.sdp = sdp
        self.sessionConfig = sessionConfig
        self.abortSignal = abortSignal
    }
}

public struct RealtimeModelV4WebRTCSession: Sendable, Equatable {
    public let sessionId: String
    public let sdp: String

    public init(sessionId: String, sdp: String) {
        self.sessionId = sessionId
        self.sdp = sdp
    }
}

public protocol RealtimeFactoryV4: Sendable {
    func realtimeModel(modelId: String) throws -> any RealtimeModelV4
    func getToken(options: RealtimeFactoryV4GetTokenOptions) async throws -> RealtimeFactoryV4GetTokenResult
}

public struct RealtimeFactoryV4GetTokenOptions: Sendable, Equatable {
    public let model: String
    public let expiresAfterSeconds: Int?
    public let sessionConfig: RealtimeModelV4SessionConfig?

    public init(
        model: String,
        expiresAfterSeconds: Int? = nil,
        sessionConfig: RealtimeModelV4SessionConfig? = nil
    ) {
        self.model = model
        self.expiresAfterSeconds = expiresAfterSeconds
        self.sessionConfig = sessionConfig
    }
}

public struct RealtimeFactoryV4GetTokenResult: Sendable, Equatable {
    public let token: String
    public let url: String
    public let expiresAt: Double?

    public init(token: String, url: String, expiresAt: Double? = nil) {
        self.token = token
        self.url = url
        self.expiresAt = expiresAt
    }
}

public struct RealtimeModelV4ClientSecretOptions: Sendable, Equatable {
    public let expiresAfterSeconds: Int?
    public let sessionConfig: RealtimeModelV4SessionConfig?

    public init(expiresAfterSeconds: Int? = nil, sessionConfig: RealtimeModelV4SessionConfig? = nil) {
        self.expiresAfterSeconds = expiresAfterSeconds
        self.sessionConfig = sessionConfig
    }
}

public struct RealtimeModelV4ClientSecretResult: Sendable, Equatable {
    public let token: String
    public let url: String
    public let expiresAt: Double?

    public init(token: String, url: String, expiresAt: Double? = nil) {
        self.token = token
        self.url = url
        self.expiresAt = expiresAt
    }
}

public struct RealtimeModelV4WebSocketOptions: Sendable, Equatable {
    public let token: String
    public let url: String

    public init(token: String, url: String) {
        self.token = token
        self.url = url
    }
}

public struct RealtimeModelV4WebSocketConfig: Sendable, Equatable {
    public let url: String
    public let protocols: [String]?

    public init(url: String, protocols: [String]? = nil) {
        self.url = url
        self.protocols = protocols
    }
}

public struct RealtimeModelV4SessionConfig: Sendable, Equatable {
    public let instructions: String?
    public let voice: String?
    public let outputModalities: [OutputModality]?
    public let inputAudioFormat: AudioFormat?
    public let inputAudioTranscription: TranscriptionConfig?
    public let outputAudioTranscription: TranscriptionConfig?
    public let outputAudioFormat: AudioFormat?
    public let turnDetection: TurnDetection?
    public let tools: [RealtimeModelV4ToolDefinition]?
    public let providerOptions: [String: JSONValue]?

    public init(
        instructions: String? = nil,
        voice: String? = nil,
        outputModalities: [OutputModality]? = nil,
        inputAudioFormat: AudioFormat? = nil,
        inputAudioTranscription: TranscriptionConfig? = nil,
        outputAudioTranscription: TranscriptionConfig? = nil,
        outputAudioFormat: AudioFormat? = nil,
        turnDetection: TurnDetection? = nil,
        tools: [RealtimeModelV4ToolDefinition]? = nil,
        providerOptions: [String: JSONValue]? = nil
    ) {
        self.instructions = instructions
        self.voice = voice
        self.outputModalities = outputModalities
        self.inputAudioFormat = inputAudioFormat
        self.inputAudioTranscription = inputAudioTranscription
        self.outputAudioTranscription = outputAudioTranscription
        self.outputAudioFormat = outputAudioFormat
        self.turnDetection = turnDetection
        self.tools = tools
        self.providerOptions = providerOptions
    }

    public enum OutputModality: String, Sendable, Equatable, Codable {
        case text
        case audio
    }

    public typealias AudioFormat = SharedV4AudioFormat

    public struct TranscriptionConfig: Sendable, Equatable, Codable {
        public let model: String?
        public let language: String?
        public let prompt: String?

        public init(model: String? = nil, language: String? = nil, prompt: String? = nil) {
            self.model = model
            self.language = language
            self.prompt = prompt
        }
    }

    public enum TurnDetection: Sendable, Equatable {
        case serverVAD(threshold: Double?, silenceDurationMs: Int?, prefixPaddingMs: Int?)
        case semanticVAD(threshold: Double?, silenceDurationMs: Int?, prefixPaddingMs: Int?)
        case disabled
    }
}

public struct RealtimeModelV4ToolDefinition: Sendable, Equatable, Codable {
    public let type: String
    public let name: String
    public let description: String?
    public let parameters: JSONValue

    public init(
        name: String,
        parameters: JSONValue,
        description: String? = nil,
        type: String = "function"
    ) {
        self.type = type
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

public enum RealtimeModelV4ConversationItem: Sendable, Equatable {
    case textMessage(text: String)
    case audioMessage(audio: String)
    case functionCallOutput(callId: String, name: String?, output: String)
}

public enum RealtimeModelV4ClientEvent: Sendable, Equatable {
    case sessionUpdate(config: RealtimeModelV4SessionConfig, eventId: String? = nil)
    case sessionStart(config: RealtimeModelV4SessionConfig, eventId: String? = nil)
    case sessionClose(eventId: String? = nil)
    case inputAudioMute(eventId: String? = nil)
    case inputAudioUnmute(eventId: String? = nil)
    case contextAppend(
        content: String,
        delegationId: String?,
        eventId: String? = nil,
        providerOptions: SharedV4ProviderOptions? = nil
    )
    case inputAudioAppend(audio: String, eventId: String? = nil)
    case inputAudioCommit
    case inputAudioClear
    case conversationItemCreate(item: RealtimeModelV4ConversationItem)
    case conversationItemTruncate(itemId: String, contentIndex: Int, audioEndMs: Int)
    case responseCreate(options: ResponseCreateOptions?)
    case responseCancel

    public struct ResponseCreateOptions: Sendable, Equatable {
        public let modalities: [String]?
        public let instructions: String?
        public let metadata: [String: JSONValue]?

        public init(modalities: [String]? = nil, instructions: String? = nil, metadata: [String: JSONValue]? = nil) {
            self.modalities = modalities
            self.instructions = instructions
            self.metadata = metadata
        }
    }
}

public enum RealtimeModelV4ServerEvent: Sendable, Equatable {
    public enum Party: String, Sendable, Equatable {
        case client
        case provider
    }

    public enum Speaker: String, Sendable, Equatable {
        case user
        case assistant
    }

    case sessionStarted(sessionId: String, delegationMode: Party?, raw: JSONValue)
    case sessionClosed(sessionId: String?, usageSeconds: Double, reason: String, raw: JSONValue)
    /// `usageSeconds` is a cumulative duration snapshot, not an increment.
    case sessionUsage(usageSeconds: Double, contextWindowUsageRatio: Double?, raw: JSONValue)
    case audioChunk(delta: String, raw: JSONValue)
    case transcriptFragment(speaker: Speaker, delta: String, startMs: Double, endMs: Double, raw: JSONValue)
    case delegationCreated(delegationId: String, target: Party?, offsetMs: Double?, responseId: String?, raw: JSONValue)
    /// `command` is the provider-native command name that was acknowledged.
    case commandAcknowledged(command: String, clientEventId: String?, raw: JSONValue)
    case sessionCreated(sessionId: String?, raw: JSONValue)
    case sessionUpdated(raw: JSONValue)
    case speechStarted(itemId: String?, raw: JSONValue)
    case speechStopped(itemId: String?, raw: JSONValue)
    case audioCommitted(itemId: String?, previousItemId: String?, raw: JSONValue)
    case conversationItemAdded(itemId: String, item: JSONValue, raw: JSONValue)
    case inputTranscriptionCompleted(itemId: String, transcript: String, raw: JSONValue)
    case responseCreated(responseId: String, raw: JSONValue)
    case responseDone(responseId: String, status: String, raw: JSONValue)
    case outputItemAdded(responseId: String, itemId: String, raw: JSONValue)
    case outputItemDone(responseId: String, itemId: String, raw: JSONValue)
    case contentPartAdded(responseId: String, itemId: String, raw: JSONValue)
    case contentPartDone(responseId: String, itemId: String, raw: JSONValue)
    case audioDelta(responseId: String, itemId: String, delta: String, raw: JSONValue)
    case audioDone(responseId: String, itemId: String, raw: JSONValue)
    case audioTranscriptDelta(responseId: String, itemId: String, delta: String, raw: JSONValue)
    case audioTranscriptDone(responseId: String, itemId: String, transcript: String?, raw: JSONValue)
    case textDelta(responseId: String, itemId: String, delta: String, raw: JSONValue)
    case textDone(responseId: String, itemId: String, text: String?, raw: JSONValue)
    case functionCallArgumentsDelta(responseId: String, itemId: String, callId: String, delta: String, raw: JSONValue)
    case functionCallArgumentsDone(responseId: String, itemId: String, callId: String, name: String, arguments: String, raw: JSONValue)
    case error(message: String, code: String?, clientEventId: String? = nil, raw: JSONValue)
    case custom(rawType: String, raw: JSONValue)
}
