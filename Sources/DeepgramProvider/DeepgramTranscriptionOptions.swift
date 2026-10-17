import Foundation
import AISDKProviderUtils

public struct DeepgramTranscriptionModelOptions: Codable, Sendable, Equatable {
    public enum Summarize: Codable, Sendable, Equatable {
        case v2
        case disabled
        public init(from decoder: Decoder) throws {
            let value = try decoder.singleValueContainer()
            if (try? value.decode(String.self)) == "v2" { self = .v2 }
            else if (try? value.decode(Bool.self)) == false { self = .disabled }
            else { throw DecodingError.dataCorruptedError(in: value, debugDescription: "Expected v2 or false") }
        }
        public func encode(to encoder: Encoder) throws {
            var value = encoder.singleValueContainer()
            switch self { case .v2: try value.encode("v2"); case .disabled: try value.encode(false) }
        }
    }
    public enum Redact: Codable, Sendable, Equatable {
        case single(String)
        case multiple([String])
        public init(from decoder: Decoder) throws {
            let value = try decoder.singleValueContainer()
            if let string = try? value.decode(String.self) { self = .single(string) }
            else { self = .multiple(try value.decode([String].self)) }
        }
        public func encode(to encoder: Encoder) throws {
            var value = encoder.singleValueContainer()
            switch self { case .single(let string): try value.encode(string); case .multiple(let strings): try value.encode(strings) }
        }
    }
    public var language: String?
    public var detectLanguage: Bool?
    public var smartFormat: Bool?
    public var punctuate: Bool?
    public var paragraphs: Bool?
    public var summarize: Summarize?
    public var topics: Bool?
    public var intents: Bool?
    public var sentiment: Bool?
    public var detectEntities: Bool?
    public var redact: Redact?
    public var replace: String?
    public var search: String?
    public var keyterm: String?
    public var diarize: Bool?
    public var utterances: Bool?
    public var uttSplit: Double?
    public var fillerWords: Bool?
    public init() {}
}

let deepgramTranscriptionModelOptionsSchema = FlexibleSchema(
    Schema<DeepgramTranscriptionModelOptions>.codable(DeepgramTranscriptionModelOptions.self, jsonSchema: ["type": "object"])
)
