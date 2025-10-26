import Foundation

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/elevenlabs/src/elevenlabs-*-options.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct ElevenLabsTranscriptionModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public extension ElevenLabsTranscriptionModelId {
    static let scribeV1: Self = "scribe_v1"
    static let scribeV1Experimental: Self = "scribe_v1_experimental"
}

public struct ElevenLabsSpeechModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public extension ElevenLabsSpeechModelId {
    static let elevenV3: Self = "eleven_v3"
    static let elevenMultilingualV2: Self = "eleven_multilingual_v2"
    static let elevenFlashV25: Self = "eleven_flash_v2_5"
    static let elevenFlashV2: Self = "eleven_flash_v2"
    static let elevenTurboV25: Self = "eleven_turbo_v2_5"
    static let elevenTurboV2: Self = "eleven_turbo_v2"
    static let elevenMonolingualV1: Self = "eleven_monolingual_v1"
    static let elevenMultilingualV1: Self = "eleven_multilingual_v1"
}

public typealias ElevenLabsSpeechVoiceId = String
