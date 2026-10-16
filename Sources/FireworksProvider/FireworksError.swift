import Foundation
import AISDKProvider
import AISDKProviderUtils
import OpenAICompatibleProvider

public struct FireworksErrorData: Codable, Sendable, Equatable {
    public enum Payload: Codable, Sendable, Equatable {
        case string(String)
        case object(Details)
        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) { self = .string(text) }
            else { self = .object(try container.decode(Details.self)) }
        }
        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self { case .string(let value): try container.encode(value); case .object(let value): try container.encode(value) }
        }
        public var message: String { switch self { case .string(let text): text; case .object(let details): details.message } }
    }
    public struct Details: Codable, Sendable, Equatable {
        public enum Code: Codable, Sendable, Equatable {
            case string(String), number(Double)
            public init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let text = try? container.decode(String.self) { self = .string(text) }
                else { self = .number(try container.decode(Double.self)) }
            }
            public func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self { case .string(let text): try container.encode(text); case .number(let value): try container.encode(value) }
            }
        }
        public let message: String
        public let object: String?
        public let type: String?
        public let param: JSONValue?
        public let code: Code?
    }
    public let error: Payload
}

private let fireworksErrorSchema = FlexibleSchema(Schema<FireworksErrorData>.codable(FireworksErrorData.self, jsonSchema: .object(["type": .string("object")])))

public let fireworksErrorConfiguration = OpenAICompatibleErrorConfiguration(
    errorSchema: fireworksErrorSchema,
    errorToMessage: { $0.error.message },
    extractMessage: { value in
        try JSONDecoder().decode(FireworksErrorData.self, from: JSONEncoder().encode(value)).error.message
    }
)
