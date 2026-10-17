import Foundation
import AISDKProviderUtils

public struct MistralTranscriptionModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    public static let voxtralMini2602: Self = "voxtral-mini-2602"
    public static let voxtralMiniLatest: Self = "voxtral-mini-latest"
}

public struct MistralTranscriptionModelOptions: Codable, Sendable, Equatable {
    public enum TimestampGranularity: String, Codable, Sendable {
        case segment
        case word
    }

    public let language: String?
    public let temperature: Double?
    public let timestampGranularities: [TimestampGranularity]?
    public let diarize: Bool?
    public let contextBias: [String]?

    public init(
        language: String? = nil,
        temperature: Double? = nil,
        timestampGranularities: [TimestampGranularity]? = nil,
        diarize: Bool? = nil,
        contextBias: [String]? = nil
    ) throws {
        if let language, language.isEmpty {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "language must not be empty"))
        }
        if let temperature, !temperature.isFinite {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "temperature must be finite"))
        }
        if let timestampGranularities, timestampGranularities.isEmpty {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "timestampGranularities must not be empty"))
        }
        if let contextBias {
            guard contextBias.count <= 100,
                  contextBias.allSatisfy({ !$0.isEmpty && $0.unicodeScalars.allSatisfy { !contextBiasSeparators.contains($0) } }) else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "contextBias must contain at most 100 nonempty items without commas or whitespace"))
            }
        }
        self.language = language
        self.temperature = temperature
        self.timestampGranularities = timestampGranularities
        self.diarize = diarize
        self.contextBias = contextBias
    }

    private enum CodingKeys: String, CodingKey {
        case language, temperature, timestampGranularities, diarize, contextBias
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            language: container.contains(.language) ? container.decode(String.self, forKey: .language) : nil,
            temperature: container.contains(.temperature) ? container.decode(Double.self, forKey: .temperature) : nil,
            timestampGranularities: container.contains(.timestampGranularities)
                ? container.decode([TimestampGranularity].self, forKey: .timestampGranularities) : nil,
            diarize: container.contains(.diarize) ? container.decode(Bool.self, forKey: .diarize) : nil,
            contextBias: container.contains(.contextBias) ? container.decode([String].self, forKey: .contextBias) : nil
        )
    }
}

// ECMAScript whitespace matches the upstream context-bias regular expression.
private let contextBiasSeparators = CharacterSet(charactersIn: ",\u{0009}\u{000A}\u{000B}\u{000C}\u{000D}\u{0020}\u{00A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{FEFF}")

let mistralTranscriptionModelOptionsSchema = FlexibleSchema(
    Schema<MistralTranscriptionModelOptions>.codable(
        MistralTranscriptionModelOptions.self,
        jsonSchema: .object(["type": .string("object")])
    )
)
