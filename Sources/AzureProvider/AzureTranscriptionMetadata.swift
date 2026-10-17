import Foundation

public struct AzureTranscriptionProviderMetadata: Codable, Sendable {
    public let azure: Content
    public init(azure: Content) { self.azure = azure }

    public struct Content: Codable, Sendable {
        public let phrases: [Phrase]
        public init(phrases: [Phrase]) { self.phrases = phrases }
    }

    public enum Nullable<Value: Codable & Sendable>: Codable, Sendable {
        case null
        case value(Value)

        public var unwrapped: Value? {
            if case .value(let value) = self { return value }
            return nil
        }
        public init(from decoder: Decoder) throws {
            let value = try decoder.singleValueContainer()
            if value.decodeNil() { self = .null }
            else { self = .value(try value.decode(Value.self)) }
        }
        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .null: try container.encodeNil()
            case .value(let value): try container.encode(value)
            }
        }
    }

    public struct Phrase: Codable, Sendable {
        public let text: String
        public let offsetMilliseconds: Nullable<Double>?
        public let durationMilliseconds: Nullable<Double>?
        public let locale: Nullable<String>?
        public let speaker: Nullable<Double>?
        public let confidence: Nullable<Double>?
        public let words: Nullable<[Word]>?

        public init(text: String, offsetMilliseconds: Nullable<Double>? = nil, durationMilliseconds: Nullable<Double>? = nil,
                    locale: Nullable<String>? = nil, speaker: Nullable<Double>? = nil,
                    confidence: Nullable<Double>? = nil, words: Nullable<[Word]>? = nil) {
            self.text = text
            self.offsetMilliseconds = offsetMilliseconds
            self.durationMilliseconds = durationMilliseconds
            self.locale = locale
            self.speaker = speaker
            self.confidence = confidence
            self.words = words
        }

        private enum CodingKeys: String, CodingKey {
            case text, offsetMilliseconds, durationMilliseconds, locale, speaker, confidence, words
        }
        public init(from decoder: Decoder) throws {
            let fields = try decoder.container(keyedBy: CodingKeys.self)
            text = try fields.decode(String.self, forKey: .text)
            offsetMilliseconds = try fields.nullable(Double.self, forKey: .offsetMilliseconds)
            durationMilliseconds = try fields.nullable(Double.self, forKey: .durationMilliseconds)
            locale = try fields.nullable(String.self, forKey: .locale)
            speaker = try fields.nullable(Double.self, forKey: .speaker)
            confidence = try fields.nullable(Double.self, forKey: .confidence)
            words = try fields.nullable([Word].self, forKey: .words)
        }
    }

    public struct Word: Codable, Sendable {
        public let text: String
        public let offsetMilliseconds: Nullable<Double>?
        public let durationMilliseconds: Nullable<Double>?

        public init(text: String, offsetMilliseconds: Nullable<Double>? = nil, durationMilliseconds: Nullable<Double>? = nil) {
            self.text = text
            self.offsetMilliseconds = offsetMilliseconds
            self.durationMilliseconds = durationMilliseconds
        }
        private enum CodingKeys: String, CodingKey { case text, offsetMilliseconds, durationMilliseconds }
        public init(from decoder: Decoder) throws {
            let fields = try decoder.container(keyedBy: CodingKeys.self)
            text = try fields.decode(String.self, forKey: .text)
            offsetMilliseconds = try fields.nullable(Double.self, forKey: .offsetMilliseconds)
            durationMilliseconds = try fields.nullable(Double.self, forKey: .durationMilliseconds)
        }
    }
}

private extension KeyedDecodingContainer {
    func nullable<T: Codable & Sendable>(_ type: T.Type, forKey key: Key) throws -> AzureTranscriptionProviderMetadata.Nullable<T>? {
        guard contains(key) else { return nil }
        return try decode(AzureTranscriptionProviderMetadata.Nullable<T>.self, forKey: key)
    }
}
