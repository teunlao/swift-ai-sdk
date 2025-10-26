import Foundation

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/hume/src/hume-api-types.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

struct HumeSpeechAPIUtterance: Encodable, Sendable {
    var text: String
    var description: String?
    var speed: Double?
    var trailingSilence: Double?
    var voice: HumeSpeechAPIVoice?

    private enum CodingKeys: String, CodingKey {
        case text
        case description
        case speed
        case trailingSilence = "trailing_silence"
        case voice
    }
}

struct HumeSpeechAPIVoice: Encodable, Sendable {
    var id: String?
    var name: String?
    var provider: String?
}

struct HumeSpeechAPIContext: Encodable, Sendable {
    var generationID: String?
    var utterances: [HumeSpeechAPIUtterance]?

    private enum CodingKeys: String, CodingKey {
        case generationID = "generation_id"
        case utterances
    }
}

struct HumeSpeechAPITypes: Encodable, Sendable {
    var utterances: [HumeSpeechAPIUtterance]
    var context: HumeSpeechAPIContext?
    var format: Format

    struct Format: Encodable, Sendable {
        var type: String
    }
}
