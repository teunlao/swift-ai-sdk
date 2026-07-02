/**
 Specification for a realtime model that supports bidirectional audio/text communication.

 Port of upstream realtime model V4 provider contracts.
 */
public protocol RealtimeModelV4: Sendable {
    var specificationVersion: String { get }
    var provider: String { get }
    var modelId: String { get }

    func doCreateClientSecret(
        options: RealtimeModelV4ClientSecretOptions
    ) async throws -> RealtimeModelV4ClientSecretResult

    func getWebSocketConfig(options: RealtimeModelV4WebSocketOptions) throws -> RealtimeModelV4WebSocketConfig
    func parseServerEvent(raw: JSONValue) throws -> [RealtimeModelV4ServerEvent]
    func serializeClientEvent(_ event: RealtimeModelV4ClientEvent) async throws -> JSONValue
    func buildSessionConfig(_ config: RealtimeModelV4SessionConfig) throws -> JSONValue
    func getHealthCheckResponse(raw: JSONValue) throws -> JSONValue?
}

extension RealtimeModelV4 {
    public var specificationVersion: String { "v4" }

    public func getHealthCheckResponse(raw: JSONValue) throws -> JSONValue? {
        nil
    }
}

public protocol RealtimeFactoryV4: Sendable {
    func realtimeModel(modelId: String) -> any RealtimeModelV4
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
    public let expiresAt: Int?

    public init(token: String, url: String, expiresAt: Int? = nil) {
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
    public let expiresAt: Int?

    public init(token: String, url: String, expiresAt: Int? = nil) {
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

    public struct AudioFormat: Sendable, Equatable, Codable {
        public let type: String
        public let rate: Int?

        public init(type: String, rate: Int? = nil) {
            self.type = type
            self.rate = rate
        }
    }

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
    case sessionUpdate(config: RealtimeModelV4SessionConfig)
    case inputAudioAppend(audio: String)
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
    case error(message: String, code: String?, raw: JSONValue)
    case custom(rawType: String, raw: JSONValue)
}
