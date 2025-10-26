import Foundation
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/elevenlabs/src/elevenlabs-speech-model.ts (provider options schema)
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

struct ElevenLabsSpeechOptions: Codable, Sendable {
    struct VoiceSettings: Codable, Sendable {
        var stability: Double?
        var similarityBoost: Double?
        var style: Double?
        var useSpeakerBoost: Bool?

        enum CodingKeys: String, CodingKey {
            case stability
            case similarityBoost
            case style
            case useSpeakerBoost
        }

        init(stability: Double? = nil, similarityBoost: Double? = nil, style: Double? = nil, useSpeakerBoost: Bool? = nil) {
            self.stability = stability
            self.similarityBoost = similarityBoost
            self.style = style
            self.useSpeakerBoost = useSpeakerBoost
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            if let stability = try container.decodeIfPresent(Double.self, forKey: .stability) {
                guard (0...1).contains(stability) else {
                    throw DecodingError.dataCorruptedError(forKey: .stability, in: container, debugDescription: "stability must be between 0 and 1")
                }
                self.stability = stability
            }

            if let similarityBoost = try container.decodeIfPresent(Double.self, forKey: .similarityBoost) {
                guard (0...1).contains(similarityBoost) else {
                    throw DecodingError.dataCorruptedError(forKey: .similarityBoost, in: container, debugDescription: "similarityBoost must be between 0 and 1")
                }
                self.similarityBoost = similarityBoost
            }

            if let style = try container.decodeIfPresent(Double.self, forKey: .style) {
                guard (0...1).contains(style) else {
                    throw DecodingError.dataCorruptedError(forKey: .style, in: container, debugDescription: "style must be between 0 and 1")
                }
                self.style = style
            }

            self.useSpeakerBoost = try container.decodeIfPresent(Bool.self, forKey: .useSpeakerBoost)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(stability, forKey: .stability)
            try container.encodeIfPresent(similarityBoost, forKey: .similarityBoost)
            try container.encodeIfPresent(style, forKey: .style)
            try container.encodeIfPresent(useSpeakerBoost, forKey: .useSpeakerBoost)
        }
    }

    struct PronunciationDictionaryLocator: Codable, Sendable {
        let pronunciationDictionaryId: String
        let versionId: String?

        enum CodingKeys: String, CodingKey {
            case pronunciationDictionaryId
            case versionId
        }

        init(pronunciationDictionaryId: String, versionId: String?) {
            self.pronunciationDictionaryId = pronunciationDictionaryId
            self.versionId = versionId
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let identifier = try container.decode(String.self, forKey: .pronunciationDictionaryId)
            let version = try container.decodeIfPresent(String.self, forKey: .versionId)
            self.init(pronunciationDictionaryId: identifier, versionId: version)
        }
    }

    enum ApplyTextNormalization: String, Codable, Sendable {
        case auto
        case on
        case off
    }

    var languageCode: String?
    var voiceSettings: VoiceSettings?
    var pronunciationDictionaryLocators: [PronunciationDictionaryLocator]?
    var seed: UInt32?
    var previousText: String?
    var nextText: String?
    var previousRequestIds: [String]?
    var nextRequestIds: [String]?
    var applyTextNormalization: ApplyTextNormalization?
    var applyLanguageTextNormalization: Bool?
    var enableLogging: Bool?

    enum CodingKeys: String, CodingKey {
        case languageCode
        case voiceSettings
        case pronunciationDictionaryLocators
        case seed
        case previousText
        case nextText
        case previousRequestIds
        case nextRequestIds
        case applyTextNormalization
        case applyLanguageTextNormalization
        case enableLogging
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        languageCode = try container.decodeIfPresent(String.self, forKey: .languageCode)
        voiceSettings = try container.decodeIfPresent(VoiceSettings.self, forKey: .voiceSettings)

        if let locators = try container.decodeIfPresent([PronunciationDictionaryLocator].self, forKey: .pronunciationDictionaryLocators) {
            guard locators.count <= 3 else {
                throw DecodingError.dataCorruptedError(forKey: .pronunciationDictionaryLocators, in: container, debugDescription: "pronunciationDictionaryLocators accepts at most 3 entries")
            }
            pronunciationDictionaryLocators = locators
        }

        if let seedValue = try container.decodeIfPresent(UInt32.self, forKey: .seed) {
            seed = seedValue
        }

        previousText = try container.decodeIfPresent(String.self, forKey: .previousText)
        nextText = try container.decodeIfPresent(String.self, forKey: .nextText)

        if let previous = try container.decodeIfPresent([String].self, forKey: .previousRequestIds) {
            guard previous.count <= 3 else {
                throw DecodingError.dataCorruptedError(forKey: .previousRequestIds, in: container, debugDescription: "previousRequestIds accepts at most 3 entries")
            }
            previousRequestIds = previous
        }

        if let next = try container.decodeIfPresent([String].self, forKey: .nextRequestIds) {
            guard next.count <= 3 else {
                throw DecodingError.dataCorruptedError(forKey: .nextRequestIds, in: container, debugDescription: "nextRequestIds accepts at most 3 entries")
            }
            nextRequestIds = next
        }

        applyTextNormalization = try container.decodeIfPresent(ApplyTextNormalization.self, forKey: .applyTextNormalization)
        applyLanguageTextNormalization = try container.decodeIfPresent(Bool.self, forKey: .applyLanguageTextNormalization)
        enableLogging = try container.decodeIfPresent(Bool.self, forKey: .enableLogging)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(languageCode, forKey: .languageCode)
        try container.encodeIfPresent(voiceSettings, forKey: .voiceSettings)
        try container.encodeIfPresent(pronunciationDictionaryLocators, forKey: .pronunciationDictionaryLocators)
        if let seed {
            try container.encode(seed, forKey: .seed)
        }
        try container.encodeIfPresent(previousText, forKey: .previousText)
        try container.encodeIfPresent(nextText, forKey: .nextText)
        try container.encodeIfPresent(previousRequestIds, forKey: .previousRequestIds)
        try container.encodeIfPresent(nextRequestIds, forKey: .nextRequestIds)
        try container.encodeIfPresent(applyTextNormalization, forKey: .applyTextNormalization)
        try container.encodeIfPresent(applyLanguageTextNormalization, forKey: .applyLanguageTextNormalization)
        try container.encodeIfPresent(enableLogging, forKey: .enableLogging)
    }
}

let elevenLabsSpeechOptionsSchema = FlexibleSchema(
    Schema<ElevenLabsSpeechOptions>.codable(
        ElevenLabsSpeechOptions.self,
        jsonSchema: .object(["type": .string("object")])
    )
)
