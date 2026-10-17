import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct AnthropicToolSearchToolReference: Codable, Sendable, Equatable {
    public let type: String
    public let toolName: String

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        toolName = try container.decode(String.self, forKey: .toolName)
        guard type == "tool_reference" else {
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Expected tool_reference")
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, toolName
    }
}

public let anthropicToolSearchRegex20251119OutputSchema = FlexibleSchema(
    Schema<[AnthropicToolSearchToolReference]>.codable(
        [AnthropicToolSearchToolReference].self,
        jsonSchema: .object([
            "type": .string("array"),
            "items": .object([
                "type": .string("object"),
                "properties": .object([
                    "type": .object([
                        "type": .string("string"),
                        "enum": .array([.string("tool_reference")]),
                    ]),
                    "toolName": .object(["type": .string("string")]),
                ]),
                "required": .array([.string("type"), .string("toolName")]),
                "additionalProperties": .bool(false),
            ]),
        ])
    )
)

private let anthropicToolSearchRegex20251119InputSchema = FlexibleSchema(
    jsonSchema(
        .object([
            "type": .string("object"),
            "properties": .object([
                "pattern": .object(["type": .string("string")]),
                "limit": .object(["type": .string("integer")]),
            ]),
            "required": .array([.string("pattern")]),
            "additionalProperties": .bool(false),
        ])
    )
)

private let anthropicToolSearchBm2520251119InputSchema = FlexibleSchema(
    jsonSchema(
        .object([
            "type": .string("object"),
            "properties": .object([
                "query": .object(["type": .string("string")]),
                "limit": .object(["type": .string("integer")]),
            ]),
            "required": .array([.string("query")]),
            "additionalProperties": .bool(false),
        ])
    )
)

public let anthropicToolSearchBm2520251119OutputSchema = anthropicToolSearchRegex20251119OutputSchema

private let anthropicToolSearchToolOutputSchema = FlexibleSchema(
    jsonSchema(
        .object([
            "type": .string("array"),
            "items": .object([
                "type": .string("object"),
                "properties": .object([
                    "type": .object([
                        "type": .string("string"),
                        "enum": .array([.string("tool_reference")]),
                    ]),
                    "toolName": .object(["type": .string("string")]),
                ]),
                "required": .array([.string("type"), .string("toolName")]),
                "additionalProperties": .bool(false),
            ]),
        ])
    )
)

private let anthropicToolSearchRegex20251119Factory = createProviderExecutedToolFactory(
    id: "anthropic.tool_search_regex_20251119",
    name: "tool_search_tool_regex",
    inputSchema: anthropicToolSearchRegex20251119InputSchema,
    outputSchema: anthropicToolSearchToolOutputSchema,
    supportsDeferredResults: true
)

private let anthropicToolSearchBm2520251119Factory = createProviderExecutedToolFactory(
    id: "anthropic.tool_search_bm25_20251119",
    name: "tool_search_tool_bm25",
    inputSchema: anthropicToolSearchBm2520251119InputSchema,
    outputSchema: anthropicToolSearchToolOutputSchema,
    supportsDeferredResults: true
)

@discardableResult
public func anthropicToolSearchRegex20251119(_ options: ProviderExecutedToolFactoryOptions = .init()) -> Tool {
    anthropicToolSearchRegex20251119Factory(options)
}

@discardableResult
public func anthropicToolSearchBm2520251119(_ options: ProviderExecutedToolFactoryOptions = .init()) -> Tool {
    anthropicToolSearchBm2520251119Factory(options)
}
