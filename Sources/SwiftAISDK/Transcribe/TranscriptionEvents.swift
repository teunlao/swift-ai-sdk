import AISDKProvider
import AISDKProviderUtils

public struct TranscriptionStartEvent: Sendable {
    public struct Audio: Sendable {
        public let byteLength: Int?
        public let mediaType: String?
    }

    public let callId: String
    public let operationId: String
    public let provider: String
    public let modelId: String
    public let audio: Audio
    public let inputAudioFormat: TranscriptionModelV4StreamOptions.InputAudioFormat?
    public let maxRetries: Int?
    public let headers: [String: String]?
    public let providerOptions: ProviderOptions
}

public struct TranscriptionEndEvent: Sendable {
    public struct Audio: Sendable {
        public let byteLength: Int
        public let mediaType: String
    }

    public let callId: String
    public let operationId: String
    public let provider: String
    public let modelId: String
    public let audio: Audio
    public let text: String
    public let segments: [TranscriptionSegment]
    public let language: String?
    public let durationInSeconds: Double?
    public let usage: JSONObject?
    public let warnings: [SharedV4Warning]
    public let providerMetadata: ProviderMetadata?
    public let response: TranscriptionModelResponseMetadata
}

public typealias StreamTranscriptionStartEvent = TranscriptionStartEvent
public typealias StreamTranscriptionEndEvent = TranscriptionEndEvent
public typealias Experimental_StreamTranscriptionStartEvent = StreamTranscriptionStartEvent
public typealias Experimental_StreamTranscriptionEndEvent = StreamTranscriptionEndEvent
