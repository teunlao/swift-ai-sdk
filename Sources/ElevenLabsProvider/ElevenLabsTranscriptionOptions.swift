import Foundation
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/elevenlabs/src/elevenlabs-transcription-model.ts (provider options schema)
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

struct ElevenLabsTranscriptionOptions: Codable, Sendable {
    enum TimestampsGranularity: String, Codable, Sendable {
        case none
        case word
        case character
    }

    enum FileFormat: String, Codable, Sendable {
        case pcm_s16le_16
        case other
    }

    var languageCode: String?
    var tagAudioEvents: Bool?
    var numSpeakers: Int?
    var timestampsGranularity: TimestampsGranularity?
    var diarize: Bool?
    var fileFormat: FileFormat?

    enum CodingKeys: String, CodingKey {
        case languageCode
        case tagAudioEvents
        case numSpeakers
        case timestampsGranularity
        case diarize
        case fileFormat
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        languageCode = try container.decodeIfPresent(String.self, forKey: .languageCode)
        tagAudioEvents = try container.decodeIfPresent(Bool.self, forKey: .tagAudioEvents) ?? true

        if let speakers = try container.decodeIfPresent(Int.self, forKey: .numSpeakers) {
            guard (1...32).contains(speakers) else {
                throw DecodingError.dataCorruptedError(forKey: .numSpeakers, in: container, debugDescription: "numSpeakers must be between 1 and 32")
            }
            numSpeakers = speakers
        }

        timestampsGranularity = try container.decodeIfPresent(TimestampsGranularity.self, forKey: .timestampsGranularity) ?? .word
        diarize = try container.decodeIfPresent(Bool.self, forKey: .diarize) ?? false
        fileFormat = try container.decodeIfPresent(FileFormat.self, forKey: .fileFormat) ?? .other
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(languageCode, forKey: .languageCode)
        try container.encodeIfPresent(tagAudioEvents, forKey: .tagAudioEvents)
        try container.encodeIfPresent(numSpeakers, forKey: .numSpeakers)
        try container.encodeIfPresent(timestampsGranularity, forKey: .timestampsGranularity)
        try container.encodeIfPresent(diarize, forKey: .diarize)
        try container.encodeIfPresent(fileFormat, forKey: .fileFormat)
    }
}

let elevenLabsTranscriptionOptionsSchema = FlexibleSchema(
    Schema<ElevenLabsTranscriptionOptions>.codable(
        ElevenLabsTranscriptionOptions.self,
        jsonSchema: .object(["type": .string("object")])
    )
)
