import Foundation
import AISDKProviderUtils

public struct MistralSpeechModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    public static let voxtralMiniTts2603: Self = "voxtral-mini-tts-2603"
    public static let voxtralMiniTtsLatest: Self = "voxtral-mini-tts-latest"
}

public struct MistralSpeechModelOptions: Codable, Sendable, Equatable {
    public let refAudio: String?

    public init(refAudio: String? = nil) throws {
        if let refAudio, refAudio.isEmpty {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "refAudio must not be empty"))
        }
        self.refAudio = refAudio
    }

    private enum CodingKeys: String, CodingKey {
        case refAudio
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(refAudio: container.contains(.refAudio) ? container.decode(String.self, forKey: .refAudio) : nil)
    }
}

let mistralSpeechModelOptionsSchema = FlexibleSchema(
    Schema<MistralSpeechModelOptions>.codable(
        MistralSpeechModelOptions.self,
        jsonSchema: .object(["type": .string("object")])
    )
)
