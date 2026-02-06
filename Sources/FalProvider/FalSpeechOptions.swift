import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/fal/src/fal-speech-model.ts (provider options schema)
// Upstream commit: f3a72bc2a0433fda9506b7c7ac1b28b4adafcfc9
//===----------------------------------------------------------------------===//

struct FalSpeechProviderOptions: Decodable, Sendable {
    let options: [String: JSONValue]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawOptions = try container.decode([String: JSONValue].self)
        self.options = try Self.normalize(rawOptions)
    }

    private static func normalize(_ rawOptions: [String: JSONValue]) throws -> [String: JSONValue] {
        var result: [String: JSONValue] = [:]

        if let voiceSetting = rawOptions["voice_setting"] {
            result["voice_setting"] = try normalizeVoiceSetting(voiceSetting)
        }

        if let audioSetting = rawOptions["audio_setting"] {
            switch audioSetting {
            case .null, .object:
                result["audio_setting"] = audioSetting
            default:
                throw DecodingError.dataCorrupted(.init(
                    codingPath: [],
                    debugDescription: "Expected 'audio_setting' to be an object or null"
                ))
            }
        }

        if let languageBoost = rawOptions["language_boost"] {
            switch languageBoost {
            case .null:
                result["language_boost"] = .null
            case .string(let value):
                guard falLanguageBoosts.contains(value) else {
                    throw DecodingError.dataCorrupted(.init(
                        codingPath: [],
                        debugDescription: "Invalid language_boost value: \(value)"
                    ))
                }
                result["language_boost"] = .string(value)
            default:
                throw DecodingError.dataCorrupted(.init(
                    codingPath: [],
                    debugDescription: "Expected 'language_boost' to be a string or null"
                ))
            }
        }

        if let pronunciationDict = rawOptions["pronunciation_dict"] {
            switch pronunciationDict {
            case .null:
                result["pronunciation_dict"] = .null
            case .object(let object):
                var validated: [String: JSONValue] = [:]
                validated.reserveCapacity(object.count)
                for (key, value) in object {
                    guard case .string(let string) = value else {
                        throw DecodingError.dataCorrupted(.init(
                            codingPath: [],
                            debugDescription: "Expected 'pronunciation_dict.\(key)' to be a string"
                        ))
                    }
                    validated[key] = .string(string)
                }
                result["pronunciation_dict"] = .object(validated)
            default:
                throw DecodingError.dataCorrupted(.init(
                    codingPath: [],
                    debugDescription: "Expected 'pronunciation_dict' to be an object or null"
                ))
            }
        }

        // Pass through unknown keys (z.looseObject behavior).
        for (key, value) in rawOptions where !falSpeechKnownKeys.contains(key) {
            result[key] = value
        }

        return result
    }

    private static func normalizeVoiceSetting(_ value: JSONValue) throws -> JSONValue {
        if value == .null {
            return .null
        }

        guard case .object(let object) = value else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [],
                debugDescription: "Expected 'voice_setting' to be an object or null"
            ))
        }

        // Strip unknown keys (z.object().partial() behavior) and validate known keys.
        var normalized: [String: JSONValue] = [:]

        if let speed = object["speed"] {
            normalized["speed"] = try validateNumberOrNull("voice_setting.speed", speed)
        }
        if let vol = object["vol"] {
            normalized["vol"] = try validateNumberOrNull("voice_setting.vol", vol)
        }
        if let voiceId = object["voice_id"] {
            normalized["voice_id"] = try validateStringOrNull("voice_setting.voice_id", voiceId)
        }
        if let pitch = object["pitch"] {
            normalized["pitch"] = try validateNumberOrNull("voice_setting.pitch", pitch)
        }
        if let englishNormalization = object["english_normalization"] {
            normalized["english_normalization"] = try validateBoolOrNull(
                "voice_setting.english_normalization",
                englishNormalization
            )
        }
        if let emotion = object["emotion"] {
            normalized["emotion"] = try validateEmotionOrNull("voice_setting.emotion", emotion)
        }

        // Preserve empty object if 'voice_setting' was provided.
        return .object(normalized)
    }
}

let falSpeechProviderOptionsSchema = FlexibleSchema(
    Schema<FalSpeechProviderOptions>.codable(
        FalSpeechProviderOptions.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

private let falSpeechKnownKeys: Set<String> = [
    "voice_setting",
    "audio_setting",
    "language_boost",
    "pronunciation_dict",
]

private func validateStringOrNull(_ key: String, _ value: JSONValue) throws -> JSONValue {
    switch value {
    case .string, .null:
        return value
    default:
        throw DecodingError.dataCorrupted(.init(
            codingPath: [],
            debugDescription: "Expected '\(key)' to be a string or null"
        ))
    }
}

private func validateBoolOrNull(_ key: String, _ value: JSONValue) throws -> JSONValue {
    switch value {
    case .bool, .null:
        return value
    default:
        throw DecodingError.dataCorrupted(.init(
            codingPath: [],
            debugDescription: "Expected '\(key)' to be a boolean or null"
        ))
    }
}

private func validateNumberOrNull(_ key: String, _ value: JSONValue) throws -> JSONValue {
    switch value {
    case .number, .null:
        return value
    default:
        throw DecodingError.dataCorrupted(.init(
            codingPath: [],
            debugDescription: "Expected '\(key)' to be a number or null"
        ))
    }
}

private func validateEmotionOrNull(_ key: String, _ value: JSONValue) throws -> JSONValue {
    switch value {
    case .null:
        return .null
    case .string(let string):
        guard falEmotions.contains(string) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [],
                debugDescription: "Invalid \(key) value: \(string)"
            ))
        }
        return value
    default:
        throw DecodingError.dataCorrupted(.init(
            codingPath: [],
            debugDescription: "Expected '\(key)' to be a string or null"
        ))
    }
}

