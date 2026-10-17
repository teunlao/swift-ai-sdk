import Foundation
import AISDKProviderUtils

public struct ElevenLabsSpeechModelOptions: Codable, Sendable {
    public struct VoiceSettings: Codable, Sendable {
        public var stability: Double?
        public var similarityBoost: Double?
        public var style: Double?
        public var useSpeakerBoost: Bool?

        public init(stability: Double? = nil, similarityBoost: Double? = nil, style: Double? = nil, useSpeakerBoost: Bool? = nil) {
            self.stability = stability
            self.similarityBoost = similarityBoost
            self.style = style
            self.useSpeakerBoost = useSpeakerBoost
        }

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case stability, similarityBoost, style, useSpeakerBoost
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            for key in CodingKeys.allCases where container.contains(key) {
                if try container.decodeNil(forKey: key) {
                    throw DecodingError.valueNotFound(Double.self, .init(codingPath: container.codingPath + [key], debugDescription: "Voice settings must not be null"))
                }
            }
            stability = try container.decodeIfPresent(Double.self, forKey: .stability)
            similarityBoost = try container.decodeIfPresent(Double.self, forKey: .similarityBoost)
            style = try container.decodeIfPresent(Double.self, forKey: .style)
            useSpeakerBoost = try container.decodeIfPresent(Bool.self, forKey: .useSpeakerBoost)
            for value in [stability, similarityBoost, style].compactMap({ $0 }) where !(0...1).contains(value) {
                throw DecodingError.dataCorrupted(.init(codingPath: container.codingPath, debugDescription: "Voice settings must be between 0 and 1"))
            }
        }
    }

    public struct PronunciationDictionaryLocator: Codable, Sendable {
        public var pronunciationDictionaryId: String
        public var versionId: String?

        public init(pronunciationDictionaryId: String, versionId: String? = nil) {
            self.pronunciationDictionaryId = pronunciationDictionaryId
            self.versionId = versionId
        }

        private enum CodingKeys: String, CodingKey { case pronunciationDictionaryId, versionId }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            pronunciationDictionaryId = try container.decode(String.self, forKey: .pronunciationDictionaryId)
            versionId = try container.contains(.versionId) ? container.decode(String.self, forKey: .versionId) : nil
        }
    }

    public enum ApplyTextNormalization: String, Codable, Sendable { case auto, on, off }

    public var languageCode: String?
    public var voiceSettings: VoiceSettings?
    public var pronunciationDictionaryLocators: [PronunciationDictionaryLocator]?
    public var seed: Double?
    public var previousText: String?
    public var nextText: String?
    public var previousRequestIds: [String]?
    public var nextRequestIds: [String]?
    public var applyTextNormalization: ApplyTextNormalization?
    public var applyLanguageTextNormalization: Bool?
    public var enableLogging: Bool?

    public init(
        languageCode: String? = nil,
        voiceSettings: VoiceSettings? = nil,
        pronunciationDictionaryLocators: [PronunciationDictionaryLocator]? = nil,
        seed: Double? = nil,
        previousText: String? = nil,
        nextText: String? = nil,
        previousRequestIds: [String]? = nil,
        nextRequestIds: [String]? = nil,
        applyTextNormalization: ApplyTextNormalization? = nil,
        applyLanguageTextNormalization: Bool? = nil,
        enableLogging: Bool? = nil
    ) {
        self.languageCode = languageCode
        self.voiceSettings = voiceSettings
        self.pronunciationDictionaryLocators = pronunciationDictionaryLocators
        self.seed = seed
        self.previousText = previousText
        self.nextText = nextText
        self.previousRequestIds = previousRequestIds
        self.nextRequestIds = nextRequestIds
        self.applyTextNormalization = applyTextNormalization
        self.applyLanguageTextNormalization = applyLanguageTextNormalization
        self.enableLogging = enableLogging
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case languageCode, voiceSettings, pronunciationDictionaryLocators, seed, previousText, nextText
        case previousRequestIds, nextRequestIds, applyTextNormalization, applyLanguageTextNormalization, enableLogging
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        for key in CodingKeys.allCases where container.contains(key) {
            if try container.decodeNil(forKey: key) {
                throw DecodingError.valueNotFound(String.self, .init(codingPath: container.codingPath + [key], debugDescription: "Speech options must not be null"))
            }
        }
        languageCode = try container.decodeIfPresent(String.self, forKey: .languageCode)
        voiceSettings = try container.decodeIfPresent(VoiceSettings.self, forKey: .voiceSettings)
        pronunciationDictionaryLocators = try container.decodeIfPresent([PronunciationDictionaryLocator].self, forKey: .pronunciationDictionaryLocators)
        seed = try container.decodeIfPresent(Double.self, forKey: .seed)
        previousText = try container.decodeIfPresent(String.self, forKey: .previousText)
        nextText = try container.decodeIfPresent(String.self, forKey: .nextText)
        previousRequestIds = try container.decodeIfPresent([String].self, forKey: .previousRequestIds)
        nextRequestIds = try container.decodeIfPresent([String].self, forKey: .nextRequestIds)
        applyTextNormalization = try container.decodeIfPresent(ApplyTextNormalization.self, forKey: .applyTextNormalization)
        applyLanguageTextNormalization = try container.decodeIfPresent(Bool.self, forKey: .applyLanguageTextNormalization)
        enableLogging = try container.decodeIfPresent(Bool.self, forKey: .enableLogging)
        if let seed, !(0...4294967295).contains(seed) {
            throw DecodingError.dataCorruptedError(forKey: .seed, in: container, debugDescription: "seed must be between 0 and 4294967295")
        }
        for count in [pronunciationDictionaryLocators?.count, previousRequestIds?.count, nextRequestIds?.count].compactMap({ $0 }) where count > 3 {
            throw DecodingError.dataCorrupted(.init(codingPath: container.codingPath, debugDescription: "At most 3 dictionary locators or request IDs are supported"))
        }
    }
}

let elevenLabsSpeechModelOptionsSchema = FlexibleSchema(
    Schema<ElevenLabsSpeechModelOptions>.codable(
        ElevenLabsSpeechModelOptions.self,
        jsonSchema: .object(["type": .string("object")])
    )
)
