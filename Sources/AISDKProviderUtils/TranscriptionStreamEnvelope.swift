import Foundation
import AISDKProvider

public let TRANSCRIPTION_STREAM_START_FRAME_TYPE = "transcription-stream.start"
public let TRANSCRIPTION_STREAM_AUDIO_DONE_FRAME_TYPE = "transcription-stream.audio-done"

public struct TranscriptionStreamStartFrame: Sendable, Encodable, Equatable {
    public let type = TRANSCRIPTION_STREAM_START_FRAME_TYPE
    public let inputAudioFormat: SharedV4AudioFormat
    public let providerOptions: SharedV4ProviderOptions?
    public let includeRawChunks: Bool?

    public init(
        inputAudioFormat: SharedV4AudioFormat,
        providerOptions: SharedV4ProviderOptions? = nil,
        includeRawChunks: Bool? = nil
    ) {
        self.inputAudioFormat = inputAudioFormat
        self.providerOptions = providerOptions
        self.includeRawChunks = includeRawChunks
    }
}

public enum TranscriptionStreamClientFrame: Sendable, Equatable {
    case start(frame: TranscriptionStreamStartFrame)
    case audioDone
    case invalid(message: String)
    case unknown
}

public func parseTranscriptionStreamClientFrame(_ text: String) -> TranscriptionStreamClientFrame {
    guard let value = try? jsonValue(from: secureJsonParse(text)) else { return .invalid(message: "malformed JSON") }
    guard case .object(let frame) = value else { return .invalid(message: "frame must be a JSON object") }
    guard case .string(let type)? = frame["type"] else { return .invalid(message: "frame type must be a string") }
    switch type {
    case TRANSCRIPTION_STREAM_AUDIO_DONE_FRAME_TYPE: return .audioDone
    case TRANSCRIPTION_STREAM_START_FRAME_TYPE:
        guard case .object(let format)? = frame["inputAudioFormat"], case .string(let audioType)? = format["type"] else {
            return .invalid(message: "start frame must have an inputAudioFormat object with a string type")
        }
        let rate: Int?
        if let rawRate = format["rate"] {
            guard case .number(let number) = rawRate, let integer = Int(exactly: number) else {
                return .invalid(message: "inputAudioFormat.rate must be a number when present")
            }
            rate = integer
        } else { rate = nil }
        let options: SharedV4ProviderOptions?
        if let rawOptions = frame["providerOptions"] {
            guard case .object = rawOptions,
                  let data = try? JSONEncoder().encode(rawOptions),
                  let decoded = try? JSONDecoder().decode(SharedV4ProviderOptions.self, from: data) else {
                return .invalid(message: "providerOptions must be an object when present")
            }
            options = decoded
        } else { options = nil }
        let rawChunks: Bool?
        if let value = frame["includeRawChunks"] {
            guard case .bool(let flag) = value else { return .invalid(message: "includeRawChunks must be a boolean when present") }
            rawChunks = flag
        } else { rawChunks = nil }
        return .start(frame: .init(inputAudioFormat: .init(type: audioType, rate: rate), providerOptions: options, includeRawChunks: rawChunks))
    default: return .unknown
    }
}

public func serializeTranscriptionStreamPart(_ part: TranscriptionModelV4StreamPart) -> String? {
    guard let data = try? JSONEncoder().encode(TranscriptionPartEnvelope(part: part)) else { return nil }
    return String(decoding: data, as: UTF8.self)
}

public func parseTranscriptionStreamPart(_ text: String) -> TranscriptionModelV4StreamPart? {
    guard (try? secureJsonParse(text)) != nil else { return nil }
    return try? JSONDecoder().decode(TranscriptionPartEnvelope.self, from: Data(text.utf8)).part
}

private struct TranscriptionPartEnvelope: Codable {
    let part: TranscriptionModelV4StreamPart

    init(part: TranscriptionModelV4StreamPart) { self.part = part }

    private enum Keys: String, CodingKey {
        case type, warnings, id, delta, text, startSecond, endSecond, durationInSeconds, channelIndex
        case providerMetadata, timestamp, modelId, headers, body, segments, language, usage, rawValue, error
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Keys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "stream-start":
            part = .streamStart(warnings: try container.decode([SharedV4Warning].self, forKey: .warnings))
        case "transcript-delta":
            part = .transcriptDelta(
                id: try Self.optional(String.self, .id, container),
                delta: try container.decode(String.self, forKey: .delta),
                providerMetadata: try Self.optional(SharedV4ProviderMetadata.self, .providerMetadata, container)
            )
        case "transcript-partial":
            part = .transcriptPartial(
                id: try Self.optional(String.self, .id, container), text: try container.decode(String.self, forKey: .text),
                startSecond: try Self.optional(Double.self, .startSecond, container),
                durationInSeconds: try Self.optional(Double.self, .durationInSeconds, container),
                channelIndex: try Self.optional(Int.self, .channelIndex, container),
                providerMetadata: try Self.optional(SharedV4ProviderMetadata.self, .providerMetadata, container)
            )
        case "transcript-final":
            part = .transcriptFinal(
                id: try Self.optional(String.self, .id, container), text: try container.decode(String.self, forKey: .text),
                startSecond: try Self.optional(Double.self, .startSecond, container),
                endSecond: try Self.optional(Double.self, .endSecond, container),
                channelIndex: try Self.optional(Int.self, .channelIndex, container),
                providerMetadata: try Self.optional(SharedV4ProviderMetadata.self, .providerMetadata, container)
            )
        case "finish":
            part = .finish(
                text: try container.decode(String.self, forKey: .text),
                segments: try container.decode([TranscriptionModelV4Result.Segment].self, forKey: .segments),
                language: try Self.optional(String.self, .language, container),
                durationInSeconds: try Self.optional(Double.self, .durationInSeconds, container),
                usage: try Self.optional(JSONObject.self, .usage, container),
                providerMetadata: try Self.optional(SharedV4ProviderMetadata.self, .providerMetadata, container)
            )
        case "response-metadata":
            let timestamp: Date?
            if let text = try container.decodeIfPresent(String.self, forKey: .timestamp) {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = formatter.date(from: text) { timestamp = date }
                else {
                    formatter.formatOptions = [.withInternetDateTime]
                    guard let date = formatter.date(from: text) else {
                        throw DecodingError.dataCorruptedError(forKey: .timestamp, in: container, debugDescription: "Invalid timestamp")
                    }
                    timestamp = date
                }
            } else { timestamp = nil }
            part = .responseMetadata(
                timestamp: timestamp, modelId: try Self.optional(String.self, .modelId, container),
                headers: try Self.optional(SharedV4Headers.self, .headers, container),
                body: try Self.optional(JSONValue.self, .body, container)
            )
        case "raw": part = .raw(rawValue: try container.decode(JSONValue.self, forKey: .rawValue))
        case "error": part = .error(error: try container.decode(JSONValue.self, forKey: .error))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown transcription part")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        switch part {
        case .streamStart(let warnings):
            try container.encode("stream-start", forKey: .type)
            try container.encode(warnings, forKey: .warnings)
        case let .transcriptDelta(id, delta, metadata):
            try container.encode("transcript-delta", forKey: .type)
            try container.encodeIfPresent(id, forKey: .id)
            try container.encode(delta, forKey: .delta)
            try container.encodeIfPresent(metadata, forKey: .providerMetadata)
        case let .transcriptPartial(id, text, startSecond, duration, channelIndex, metadata):
            try container.encode("transcript-partial", forKey: .type)
            try container.encodeIfPresent(id, forKey: .id)
            try container.encode(text, forKey: .text)
            try container.encodeIfPresent(startSecond, forKey: .startSecond)
            try container.encodeIfPresent(duration, forKey: .durationInSeconds)
            try container.encodeIfPresent(channelIndex, forKey: .channelIndex)
            try container.encodeIfPresent(metadata, forKey: .providerMetadata)
        case let .transcriptFinal(id, text, startSecond, endSecond, channelIndex, metadata):
            try container.encode("transcript-final", forKey: .type)
            try container.encodeIfPresent(id, forKey: .id)
            try container.encode(text, forKey: .text)
            try container.encodeIfPresent(startSecond, forKey: .startSecond)
            try container.encodeIfPresent(endSecond, forKey: .endSecond)
            try container.encodeIfPresent(channelIndex, forKey: .channelIndex)
            try container.encodeIfPresent(metadata, forKey: .providerMetadata)
        case let .finish(text, segments, language, duration, usage, metadata):
            try container.encode("finish", forKey: .type)
            try container.encode(text, forKey: .text)
            try container.encode(segments, forKey: .segments)
            try container.encodeIfPresent(language, forKey: .language)
            try container.encodeIfPresent(duration, forKey: .durationInSeconds)
            try container.encodeIfPresent(usage, forKey: .usage)
            try container.encodeIfPresent(metadata, forKey: .providerMetadata)
        case let .responseMetadata(timestamp, modelId, headers, body):
            try container.encode("response-metadata", forKey: .type)
            if let timestamp {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                try container.encode(formatter.string(from: timestamp), forKey: .timestamp)
            }
            try container.encodeIfPresent(modelId, forKey: .modelId)
            try container.encodeIfPresent(headers, forKey: .headers)
            try container.encodeIfPresent(body, forKey: .body)
        case .raw(let value):
            try container.encode("raw", forKey: .type)
            try container.encode(value, forKey: .rawValue)
        case .error(let error):
            try container.encode("error", forKey: .type)
            try container.encode(error, forKey: .error)
        }
    }

    private static func optional<T: Decodable>(_ type: T.Type, _ key: Keys, _ container: KeyedDecodingContainer<Keys>) throws -> T? {
        container.contains(key) ? try container.decode(type, forKey: key) : nil
    }
}
