import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct XAITranscriptionModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
    public static let grokVoiceTranscribe20: Self = "grok-voice-transcribe-2.0"
}

public struct XAITranscriptionModelOptions: Codable, Sendable, Equatable {
    public enum AudioFormat: String, Codable, Sendable { case pcm, mulaw, alaw, opus }
    public enum Keyterm: Codable, Sendable, Equatable {
        case text(String), terms([String])
        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(String.self) { self = .text(value) }
            else { self = .terms(try container.decode([String].self)) }
        }
        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self { case .text(let value): try container.encode(value); case .terms(let value): try container.encode(value) }
        }
        var values: [String] { switch self { case .text(let value): [value]; case .terms(let value): value } }
    }
    public struct Streaming: Codable, Sendable, Equatable {
        public var interimResults: Bool?
        public var endpointing: Int?
        public var smartTurn: Double?
        public var smartTurnTimeout: Int?
        public init(interimResults: Bool? = nil, endpointing: Int? = nil, smartTurn: Double? = nil, smartTurnTimeout: Int? = nil) {
            self.interimResults = interimResults; self.endpointing = endpointing; self.smartTurn = smartTurn; self.smartTurnTimeout = smartTurnTimeout
        }
    }
    public var audioFormat: AudioFormat?
    public var sampleRate: Int?
    public var language: String?
    public var format: Bool?
    public var multichannel: Bool?
    public var channels: Int?
    public var diarize: Bool?
    public var keyterm: Keyterm?
    public var fillerWords: Bool?
    public var vadThreshold: Double?
    public var streaming: Streaming?
    public init(audioFormat: AudioFormat? = nil, sampleRate: Int? = nil, language: String? = nil, format: Bool? = nil, multichannel: Bool? = nil, channels: Int? = nil, diarize: Bool? = nil, keyterm: Keyterm? = nil, fillerWords: Bool? = nil, vadThreshold: Double? = nil, streaming: Streaming? = nil) {
        self.audioFormat = audioFormat; self.sampleRate = sampleRate; self.language = language; self.format = format; self.multichannel = multichannel; self.channels = channels; self.diarize = diarize; self.keyterm = keyterm; self.fillerWords = fillerWords; self.vadThreshold = vadThreshold; self.streaming = streaming
    }
}

let xaiTranscriptionOptionsSchema = FlexibleSchema(Schema<XAITranscriptionModelOptions>(jsonSchemaResolver: { .object(["type": .string("object")]) }, validator: { value in
    do {
        let json = try jsonValue(from: value)
        guard case .object(let object) = json else { throw InvalidArgumentError(argument: "providerOptions", message: "Expected an object") }
        for key in ["vadThreshold", "streaming"] where object[key] == .null { throw InvalidArgumentError(argument: key, message: "Expected a non-null option") }
        if case .object(let streaming) = object["streaming"] {
            for key in ["interimResults", "endpointing", "smartTurn", "smartTurnTimeout"] where streaming[key] == .null { throw InvalidArgumentError(argument: key, message: "Expected a non-null option") }
        }
        let options = try JSONDecoder().decode(XAITranscriptionModelOptions.self, from: JSONEncoder().encode(json))
        func require(_ valid: Bool, _ argument: String) throws { if !valid { throw InvalidArgumentError(argument: argument, message: "Invalid xAI transcription option") } }
        if let value = options.sampleRate { try require([8000, 16000, 22050, 24000, 44100, 48000].contains(value), "sampleRate") }
        if let value = options.channels { try require((2...8).contains(value), "channels") }
        if let value = options.vadThreshold { try require((0...1).contains(value), "vadThreshold") }
        if let value = options.streaming?.endpointing { try require((0...5000).contains(value), "endpointing") }
        if let value = options.streaming?.smartTurn { try require((0...1).contains(value), "smartTurn") }
        if let value = options.streaming?.smartTurnTimeout { try require((1...5000).contains(value), "smartTurnTimeout") }
        return .success(value: options)
    } catch { return .failure(error: TypeValidationError.wrap(value: value, cause: error)) }
}))
