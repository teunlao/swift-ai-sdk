import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct AnthropicToolSearchToolReference: Codable, Sendable, Equatable {
    public let type: String
    public let toolName: String
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
                "limit": .object(["type": .string("number")]),
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
                "limit": .object(["type": .string("number")]),
            ]),
            "required": .array([.string("query")]),
            "additionalProperties": .bool(false),
        ])
    )
)

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

private let anthropicToolSearchRegex20251119Factory = createProviderToolFactoryWithOutputSchema(
    id: "anthropic.tool_search_regex_20251119",
    name: "tool_search_tool_regex",
    inputSchema: anthropicToolSearchRegex20251119InputSchema,
    outputSchema: anthropicToolSearchToolOutputSchema
)

private let anthropicToolSearchBm2520251119Factory = createProviderToolFactoryWithOutputSchema(
    id: "anthropic.tool_search_bm25_20251119",
    name: "tool_search_tool_bm25",
    inputSchema: anthropicToolSearchBm2520251119InputSchema,
    outputSchema: anthropicToolSearchToolOutputSchema
)

@discardableResult
public func anthropicToolSearchRegex20251119() -> Tool {
    anthropicToolSearchRegex20251119Factory(ProviderToolFactoryWithOutputSchemaOptions(args: [:]))
}

@discardableResult
public func anthropicToolSearchBm2520251119() -> Tool {
    anthropicToolSearchBm2520251119Factory(ProviderToolFactoryWithOutputSchemaOptions(args: [:]))
}
