import Foundation
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/fal/src/fal-transcription-model.ts (provider options schema)
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

struct FalTranscriptionOptions: Codable, Sendable {
    enum ChunkLevel: String, Codable, Sendable {
        case segment
        case word
    }

    enum LanguageValue: Sendable {
        case value(String)
        case null
    }

    enum NumSpeakersValue: Sendable {
        case unspecified
        case value(Int)
        case null
    }

    var language: LanguageValue
    var diarize: Bool
    var chunkLevel: ChunkLevel
    var version: String
    var batchSize: Int
    var numSpeakers: NumSpeakersValue

    enum CodingKeys: String, CodingKey {
        case language
        case diarize
        case chunkLevel = "chunkLevel"
        case version
        case batchSize = "batchSize"
        case numSpeakers = "numSpeakers"
    }

    init(language: LanguageValue, diarize: Bool, chunkLevel: ChunkLevel, version: String, batchSize: Int, numSpeakers: NumSpeakersValue) {
        self.language = language
        self.diarize = diarize
        self.chunkLevel = chunkLevel
        self.version = version
        self.batchSize = batchSize
        self.numSpeakers = numSpeakers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if container.contains(.language) {
            if try container.decodeNil(forKey: .language) {
                language = .null
            } else {
                let value = try container.decode(String.self, forKey: .language)
                language = .value(value)
            }
        } else {
            language = .value("en")
        }

        if container.contains(.diarize) {
            diarize = try container.decode(Bool.self, forKey: .diarize)
        } else {
            diarize = true
        }

        if container.contains(.chunkLevel) {
            chunkLevel = try container.decode(ChunkLevel.self, forKey: .chunkLevel)
        } else {
            chunkLevel = .segment
        }

        if container.contains(.version) {
            version = try container.decode(String.self, forKey: .version)
        } else {
            version = "3"
        }

        if container.contains(.batchSize) {
            batchSize = try container.decode(Int.self, forKey: .batchSize)
        } else {
            batchSize = 64
        }

        if container.contains(.numSpeakers) {
            if try container.decodeNil(forKey: .numSpeakers) {
                numSpeakers = .null
            } else {
                let value = try container.decode(Int.self, forKey: .numSpeakers)
                numSpeakers = .value(value)
            }
        } else {
            numSpeakers = .unspecified
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch language {
        case .value(let string):
            try container.encode(string, forKey: .language)
        case .null:
            try container.encodeNil(forKey: .language)
        }
        try container.encode(diarize, forKey: .diarize)
        try container.encode(chunkLevel, forKey: .chunkLevel)
        try container.encode(version, forKey: .version)
        try container.encode(batchSize, forKey: .batchSize)
        switch numSpeakers {
        case .value(let value):
            try container.encode(value, forKey: .numSpeakers)
        case .null:
            try container.encodeNil(forKey: .numSpeakers)
        case .unspecified:
            break
        }
    }
}

let falTranscriptionOptionsSchema = FlexibleSchema(
    Schema<FalTranscriptionOptions>.codable(
        FalTranscriptionOptions.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

extension FalTranscriptionOptions.LanguageValue: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else {
            let value = try container.decode(String.self)
            self = .value(value)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .value(let string):
            try container.encode(string)
        case .null:
            try container.encodeNil()
        }
    }
}

extension FalTranscriptionOptions.NumSpeakersValue: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else {
            let value = try container.decode(Int.self)
            self = .value(value)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .value(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        case .unspecified:
            break
        }
    }
}

