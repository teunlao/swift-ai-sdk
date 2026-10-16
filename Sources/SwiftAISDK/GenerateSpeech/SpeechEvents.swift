import AISDKProvider
import AISDKProviderUtils

public struct GenerateSpeechStartEvent: Sendable {
    public let callId: String
    public let operationId: String
    public let provider: String
    public let modelId: String
    public let text: String
    public let voice: String?
    public let outputFormat: String?
    public let instructions: String?
    public let speed: Double?
    public let language: String?
    public let maxRetries: Int
    public let headers: [String: String]?
    public let providerOptions: ProviderOptions
}

public struct GenerateSpeechEndEvent: Sendable {
    public struct Audio: Sendable {
        public let byteLength: Int
        public let mediaType: String
        public let format: String
    }

    public let callId: String
    public let operationId: String
    public let provider: String
    public let modelId: String
    public let text: String
    public let audio: Audio
    public let usage: JSONObject?
    public let warnings: [SharedV4Warning]
    public let providerMetadata: ProviderMetadata?
    public let response: SpeechModelResponseMetadata
}
