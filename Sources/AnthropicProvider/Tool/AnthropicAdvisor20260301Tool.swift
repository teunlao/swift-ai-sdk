import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct AnthropicAdvisor20260301Options: Codable, Sendable, Equatable {
    public struct Caching: Codable, Sendable, Equatable {
        public enum Kind: String, Codable, Sendable, Equatable {
            case ephemeral
        }

        public enum TTL: String, Codable, Sendable, Equatable {
            case fiveMinutes = "5m"
            case oneHour = "1h"
        }

        public var type: Kind
        public var ttl: TTL

        public init(type: Kind = .ephemeral, ttl: TTL) {
            self.type = type
            self.ttl = ttl
        }
    }

    public var model: String
    public var maxUses: Int?
    public var caching: Caching?

    public init(
        model: String,
        maxUses: Int? = nil,
        caching: Caching? = nil
    ) {
        self.model = model
        self.maxUses = maxUses
        self.caching = caching
    }
}

public let anthropicAdvisor20260301ArgsSchema = FlexibleSchema(
    Schema<AnthropicAdvisor20260301Options>.codable(
        AnthropicAdvisor20260301Options.self,
        jsonSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "model": .object(["type": .string("string")]),
                "maxUses": .object(["type": .string("number")]),
                "caching": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "type": .object(["const": .string("ephemeral")]),
                        "ttl": .object([
                            "type": .string("string"),
                            "enum": .array([.string("5m"), .string("1h")]),
                        ]),
                    ]),
                    "required": .array([.string("type"), .string("ttl")]),
                    "additionalProperties": .bool(false),
                ]),
            ]),
            "required": .array([.string("model")]),
            "additionalProperties": .bool(false),
        ])
    )
)

public let anthropicAdvisor20260301OutputSchema = FlexibleSchema(
    jsonSchema(
        .object([
            "type": .string("object"),
            "oneOf": .array([
                .object([
                    "type": .string("object"),
                    "properties": .object([
                        "type": .object(["const": .string("advisor_result")]),
                        "text": .object(["type": .string("string")]),
                    ]),
                    "required": .array([.string("type"), .string("text")]),
                    "additionalProperties": .bool(false),
                ]),
                .object([
                    "type": .string("object"),
                    "properties": .object([
                        "type": .object(["const": .string("advisor_redacted_result")]),
                        "encryptedContent": .object(["type": .string("string")]),
                    ]),
                    "required": .array([.string("type"), .string("encryptedContent")]),
                    "additionalProperties": .bool(false),
                ]),
                .object([
                    "type": .string("object"),
                    "properties": .object([
                        "type": .object(["const": .string("advisor_tool_result_error")]),
                        "errorCode": .object(["type": .string("string")]),
                    ]),
                    "required": .array([.string("type"), .string("errorCode")]),
                    "additionalProperties": .bool(false),
                ]),
            ]),
        ])
    )
)

private let anthropicAdvisor20260301InputSchema = FlexibleSchema(
    jsonSchema(
        .object([
            "type": .string("object"),
            "properties": .object([:]),
            "additionalProperties": .bool(false),
        ])
    )
)

private let anthropicAdvisor20260301Factory = createProviderToolFactoryWithOutputSchema(
    id: "anthropic.advisor_20260301",
    name: "advisor",
    inputSchema: anthropicAdvisor20260301InputSchema,
    outputSchema: anthropicAdvisor20260301OutputSchema,
    supportsDeferredResults: true
)

@discardableResult
public func anthropicAdvisor20260301(_ options: AnthropicAdvisor20260301Options) -> Tool {
    var args: [String: JSONValue] = [
        "model": .string(options.model)
    ]
    if let maxUses = options.maxUses {
        args["maxUses"] = .number(Double(maxUses))
    }
    if let caching = options.caching {
        args["caching"] = .object([
            "type": .string(caching.type.rawValue),
            "ttl": .string(caching.ttl.rawValue),
        ])
    }
    return anthropicAdvisor20260301Factory(
        ProviderToolFactoryWithOutputSchemaOptions(args: args)
    )
}
