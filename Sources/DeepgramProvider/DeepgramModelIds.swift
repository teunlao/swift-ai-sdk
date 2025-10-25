import Foundation

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/deepgram/src/deepgram-transcription-options.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct DeepgramTranscriptionModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public extension DeepgramTranscriptionModelId {
    static let base: Self = "base"
    static let baseGeneral: Self = "base-general"
    static let baseMeeting: Self = "base-meeting"
    static let basePhonecall: Self = "base-phonecall"
    static let baseFinance: Self = "base-finance"
    static let baseConversationalAI: Self = "base-conversationalai"
    static let baseVoicemail: Self = "base-voicemail"
    static let baseVideo: Self = "base-video"
    static let enhanced: Self = "enhanced"
    static let enhancedGeneral: Self = "enhanced-general"
    static let enhancedMeeting: Self = "enhanced-meeting"
    static let enhancedPhonecall: Self = "enhanced-phonecall"
    static let enhancedFinance: Self = "enhanced-finance"
    static let nova: Self = "nova"
    static let novaGeneral: Self = "nova-general"
    static let novaPhonecall: Self = "nova-phonecall"
    static let novaMedical: Self = "nova-medical"
    static let nova2: Self = "nova-2"
    static let nova2General: Self = "nova-2-general"
    static let nova2Meeting: Self = "nova-2-meeting"
    static let nova2Phonecall: Self = "nova-2-phonecall"
    static let nova2Finance: Self = "nova-2-finance"
    static let nova2ConversationalAI: Self = "nova-2-conversationalai"
    static let nova2Voicemail: Self = "nova-2-voicemail"
    static let nova2Video: Self = "nova-2-video"
    static let nova2Medical: Self = "nova-2-medical"
    static let nova2Drivethru: Self = "nova-2-drivethru"
    static let nova2Automotive: Self = "nova-2-automotive"
    static let nova2ATC: Self = "nova-2-atc"
    static let nova3: Self = "nova-3"
    static let nova3General: Self = "nova-3-general"
    static let nova3Medical: Self = "nova-3-medical"
}
