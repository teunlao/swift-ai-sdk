import Foundation
import AISDKProvider
import AISDKProviderUtils

public typealias OpenAIResponsesInput = [JSONValue]

public struct OpenAIResponsesResponse: Codable, Sendable {
    public struct Usage: Codable, Sendable {
        public struct InputTokensDetails: Codable, Sendable {
            public let cachedTokens: Int?
            public let cacheWriteTokens: Int?
            public let orchestrationInputTokens: Double?
            public let orchestrationInputCachedTokens: Double?

            enum CodingKeys: String, CodingKey {
                case cachedTokens = "cached_tokens"
                case cacheWriteTokens = "cache_write_tokens"
                case orchestrationInputTokens = "orchestration_input_tokens"
                case orchestrationInputCachedTokens = "orchestration_input_cached_tokens"
            }
        }

        public struct OutputTokensDetails: Codable, Sendable {
            public let reasoningTokens: Int?
            public let orchestrationOutputTokens: Double?

            enum CodingKeys: String, CodingKey {
                case reasoningTokens = "reasoning_tokens"
                case orchestrationOutputTokens = "orchestration_output_tokens"
            }
        }

        public let inputTokens: Int
        public let outputTokens: Int
        public let totalTokens: Double?
        public let inputTokensDetails: InputTokensDetails?
        public let outputTokensDetails: OutputTokensDetails?
        public let rawValue: JSONValue

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case totalTokens = "total_tokens"
            case inputTokensDetails = "input_tokens_details"
            case outputTokensDetails = "output_tokens_details"
        }

        public init(from decoder: Decoder) throws {
            rawValue = try JSONValue(from: decoder)
            let container = try decoder.container(keyedBy: CodingKeys.self)
            inputTokens = try container.decode(Int.self, forKey: .inputTokens)
            outputTokens = try container.decode(Int.self, forKey: .outputTokens)
            totalTokens = try container.decodeIfPresent(Double.self, forKey: .totalTokens)
            inputTokensDetails = try container.decodeIfPresent(InputTokensDetails.self, forKey: .inputTokensDetails)
            outputTokensDetails = try container.decodeIfPresent(OutputTokensDetails.self, forKey: .outputTokensDetails)
            let (uncached, readOverflow) = inputTokens.subtractingReportingOverflow(inputTokensDetails?.cachedTokens ?? 0)
            let (_, writeOverflow) = uncached.subtractingReportingOverflow(inputTokensDetails?.cacheWriteTokens ?? 0)
            let (_, textOverflow) = outputTokens.subtractingReportingOverflow(outputTokensDetails?.reasoningTokens ?? 0)
            guard !readOverflow && !writeOverflow && !textOverflow else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Usage counters exceed the core Int representation"))
            }
        }

        public func encode(to encoder: Encoder) throws { try rawValue.encode(to: encoder) }
    }

    public struct IncompleteDetails: Codable, Sendable {
        public let reason: String
    }

    public struct ErrorPayload: Codable, Sendable {
        public let message: String
        public let type: String
        public let param: JSONValue?
        public let code: String

        private enum CodingKeys: String, CodingKey { case message, type, param, code }
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            message = try container.decode(String.self, forKey: .message)
            type = try container.decode(String.self, forKey: .type)
            code = try container.decode(String.self, forKey: .code)
            param = container.contains(.param) ? try container.decode(JSONValue.self, forKey: .param) : nil
        }
    }

    public struct Reasoning: Codable, Sendable {
        public let context: String?
    }

    public let id: String?
    public let createdAt: TimeInterval?
    public let model: String?
    public let output: [JSONValue]?
    public let serviceTier: String?
    public let usage: Usage?
    public let incompleteDetails: IncompleteDetails?
    public let error: ErrorPayload?
    public let reasoning: Reasoning?
    private let projectedValue: JSONValue

    public init(from decoder: Decoder) throws {
        projectedValue = try projectOpenAIResponsesResponse(JSONValue(from: decoder))
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        createdAt = try container.decodeIfPresent(TimeInterval.self, forKey: .createdAt)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        if case .object(let fields) = projectedValue, case .array(let values)? = fields["output"] {
            output = values
        } else {
            output = nil
        }
        serviceTier = try container.decodeIfPresent(String.self, forKey: .serviceTier)
        usage = try container.decodeIfPresent(Usage.self, forKey: .usage)
        incompleteDetails = try container.decodeIfPresent(IncompleteDetails.self, forKey: .incompleteDetails)
        error = try container.decodeIfPresent(ErrorPayload.self, forKey: .error)
        reasoning = try container.decodeIfPresent(Reasoning.self, forKey: .reasoning)
    }

    public func encode(to encoder: Encoder) throws { try projectedValue.encode(to: encoder) }

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case model
        case output
        case serviceTier = "service_tier"
        case usage
        case incompleteDetails = "incomplete_details"
        case error
        case reasoning
    }
}

public struct OpenAIResponsesChunk: Codable, Sendable {
    public let rawValue: JSONValue
    public let usage: OpenAIResponsesResponse.Usage?

    private enum CodingKeys: String, CodingKey { case response, usage }
    public init(from decoder: Decoder) throws {
        rawValue = try projectOpenAIResponsesChunk(JSONValue(from: decoder))
        if case .object(let fields) = rawValue, case .object(let response)? = fields["response"], response["usage"] != nil {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let response = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .response)
            usage = try response.decodeIfPresent(OpenAIResponsesResponse.Usage.self, forKey: .usage)
        } else {
            usage = nil
        }
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
