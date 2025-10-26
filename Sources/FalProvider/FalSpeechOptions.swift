import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/fal/src/fal-speech-model.ts (provider options schema)
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

struct FalSpeechOptions: Codable, Sendable {
    struct VoiceSettings: Codable, Sendable {
        var speed: Double?
        var vol: Double?
        var voiceId: String?
        var pitch: Double?
        var englishNormalization: Bool?
        var emotion: String?

        enum CodingKeys: String, CodingKey {
            case speed
            case vol
            case voiceId = "voice_id"
            case pitch
            case englishNormalization = "english_normalization"
            case emotion
        }

        init(speed: Double? = nil, vol: Double? = nil, voiceId: String? = nil, pitch: Double? = nil, englishNormalization: Bool? = nil, emotion: String? = nil) throws {
            if let emotion, !falEmotions.contains(emotion) {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid emotion value: \(emotion)"))
            }
            self.speed = speed
            self.vol = vol
            self.voiceId = voiceId
            self.pitch = pitch
            self.englishNormalization = englishNormalization
            self.emotion = emotion
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let speed = try container.decodeIfPresent(Double.self, forKey: .speed)
            let vol = try container.decodeIfPresent(Double.self, forKey: .vol)
            let voiceId = try container.decodeIfPresent(String.self, forKey: .voiceId)
            let pitch = try container.decodeIfPresent(Double.self, forKey: .pitch)
            let englishNormalization = try container.decodeIfPresent(Bool.self, forKey: .englishNormalization)
            let emotion = try container.decodeIfPresent(String.self, forKey: .emotion)
            try self.init(speed: speed, vol: vol, voiceId: voiceId, pitch: pitch, englishNormalization: englishNormalization, emotion: emotion)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(speed, forKey: .speed)
            try container.encodeIfPresent(vol, forKey: .vol)
            try container.encodeIfPresent(voiceId, forKey: .voiceId)
            try container.encodeIfPresent(pitch, forKey: .pitch)
            try container.encodeIfPresent(englishNormalization, forKey: .englishNormalization)
            try container.encodeIfPresent(emotion, forKey: .emotion)
        }
    }

    var voiceSetting: VoiceSettings?
    var audioSetting: [String: JSONValue]?
    var languageBoost: String?
    var pronunciationDict: [String: String]?

    enum CodingKeys: String, CodingKey {
        case voiceSetting = "voice_setting"
        case audioSetting = "audio_setting"
        case languageBoost = "language_boost"
        case pronunciationDict = "pronunciation_dict"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        voiceSetting = try container.decodeIfPresent(VoiceSettings.self, forKey: .voiceSetting)
        audioSetting = try container.decodeIfPresent([String: JSONValue].self, forKey: .audioSetting)
        if let boost = try container.decodeIfPresent(String.self, forKey: .languageBoost) {
            guard falLanguageBoosts.contains(boost) else {
                throw DecodingError.dataCorruptedError(forKey: .languageBoost, in: container, debugDescription: "Invalid language boost value: \(boost)")
            }
            languageBoost = boost
        }
        pronunciationDict = try container.decodeIfPresent([String: String].self, forKey: .pronunciationDict)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(voiceSetting, forKey: .voiceSetting)
        try container.encodeIfPresent(audioSetting, forKey: .audioSetting)
        try container.encodeIfPresent(languageBoost, forKey: .languageBoost)
        try container.encodeIfPresent(pronunciationDict, forKey: .pronunciationDict)
    }

    init() {}
}

let falSpeechOptionsSchema = FlexibleSchema(
    Schema<FalSpeechOptions>.codable(
        FalSpeechOptions.self,
        jsonSchema: .object(["type": .string("object")])
    )
)
