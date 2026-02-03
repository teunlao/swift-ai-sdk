import Foundation
import AISDKProvider
import AISDKProviderUtils

public typealias OpenAIResponsesInput = [JSONValue]

public struct OpenAIResponsesResponse: Codable, Sendable {
    public struct Usage: Codable, Sendable {
        public struct InputTokensDetails: Codable, Sendable {
            public let cachedTokens: Int?

            enum CodingKeys: String, CodingKey {
                case cachedTokens = "cached_tokens"
            }
        }

        public struct OutputTokensDetails: Codable, Sendable {
            public let reasoningTokens: Int?

            enum CodingKeys: String, CodingKey {
                case reasoningTokens = "reasoning_tokens"
            }
        }

        public let inputTokens: Int
        public let outputTokens: Int
        public let inputTokensDetails: InputTokensDetails?
        public let outputTokensDetails: OutputTokensDetails?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case inputTokensDetails = "input_tokens_details"
            case outputTokensDetails = "output_tokens_details"
        }
    }

    public struct IncompleteDetails: Codable, Sendable {
        public let reason: String?
    }

    public struct ErrorPayload: Codable, Sendable {
        public let code: String
        public let message: String
    }

    public let id: String
    public let createdAt: TimeInterval?
    public let model: String
    public let output: [JSONValue]
    public let serviceTier: String?
    public let usage: Usage
    public let warnings: [LanguageModelV3CallWarningRecord]?
    public let incompleteDetails: IncompleteDetails?
    public let finishReason: String?
    public let error: ErrorPayload?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case model
        case output
        case serviceTier = "service_tier"
        case usage
        case warnings
        case incompleteDetails = "incomplete_details"
        case finishReason = "finish_reason"
        case error
    }
}

public struct LanguageModelV3CallWarningRecord: Codable, Sendable {
    public let type: String
    public let message: String?
    public let setting: String?

    public init(type: String, message: String? = nil, setting: String? = nil) {
        self.type = type
        self.message = message
        self.setting = setting
    }

    public func toWarning() -> SharedV3Warning {
        switch type {
        case "unsupported-setting":
            return .unsupported(feature: setting ?? "unknown", details: message)
        case "compatibility":
            return .compatibility(feature: setting ?? "unknown", details: message)
        default:
            return .other(message: message ?? "OpenAI warning")
        }
    }
}

public struct OpenAIResponsesChunk: Codable, Sendable {
    public let rawValue: JSONValue

    public init(rawValue: JSONValue) {
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(JSONValue.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var type: String? {
        guard case .object(let object) = rawValue,
              case .string(let value) = object["type"] else {
            return nil
        }
        return value
    }
}

public let openAIResponsesChunkSchema = FlexibleSchema(
    Schema.codable(
        OpenAIResponsesChunk.self,
        jsonSchema: .object([
            "type": .string("object")
        ])
    )
)

public let openAIResponsesResponseSchema = FlexibleSchema(
    Schema.codable(
        OpenAIResponsesResponse.self,
        jsonSchema: .object([
            "type": .string("object")
        ])
    )
)
