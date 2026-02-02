import Foundation
import AISDKProvider
import AISDKProviderUtils

private let anthropicMemory20250818InputSchema = FlexibleSchema(
    jsonSchema(
        .object([
            "type": .string("object"),
            "oneOf": .array([
                .object([
                    "type": .string("object"),
                    "properties": .object([
                        "command": .object(["const": .string("view")]),
                        "path": .object(["type": .string("string")]),
                        "view_range": .object([
                            "type": .string("array"),
                            "items": .object(["type": .string("number")]),
                            "minItems": .number(2),
                            "maxItems": .number(2),
                        ]),
                    ]),
                    "required": .array([.string("command"), .string("path")]),
                    "additionalProperties": .bool(false),
                ]),
                .object([
                    "type": .string("object"),
                    "properties": .object([
                        "command": .object(["const": .string("create")]),
                        "path": .object(["type": .string("string")]),
                        "file_text": .object(["type": .string("string")]),
                    ]),
                    "required": .array([.string("command"), .string("path"), .string("file_text")]),
                    "additionalProperties": .bool(false),
                ]),
                .object([
                    "type": .string("object"),
                    "properties": .object([
                        "command": .object(["const": .string("str_replace")]),
                        "path": .object(["type": .string("string")]),
                        "old_str": .object(["type": .string("string")]),
                        "new_str": .object(["type": .string("string")]),
                    ]),
                    "required": .array([
                        .string("command"),
                        .string("path"),
                        .string("old_str"),
                        .string("new_str"),
                    ]),
                    "additionalProperties": .bool(false),
                ]),
                .object([
                    "type": .string("object"),
                    "properties": .object([
                        "command": .object(["const": .string("insert")]),
                        "path": .object(["type": .string("string")]),
                        "insert_line": .object(["type": .string("number")]),
                        "insert_text": .object(["type": .string("string")]),
                    ]),
                    "required": .array([
                        .string("command"),
                        .string("path"),
                        .string("insert_line"),
                        .string("insert_text"),
                    ]),
                    "additionalProperties": .bool(false),
                ]),
                .object([
                    "type": .string("object"),
                    "properties": .object([
                        "command": .object(["const": .string("delete")]),
                        "path": .object(["type": .string("string")]),
                    ]),
                    "required": .array([.string("command"), .string("path")]),
                    "additionalProperties": .bool(false),
                ]),
                .object([
                    "type": .string("object"),
                    "properties": .object([
                        "command": .object(["const": .string("rename")]),
                        "old_path": .object(["type": .string("string")]),
                        "new_path": .object(["type": .string("string")]),
                    ]),
                    "required": .array([.string("command"), .string("old_path"), .string("new_path")]),
                    "additionalProperties": .bool(false),
                ]),
            ]),
        ])
    )
)

private let anthropicMemory20250818Factory = createProviderDefinedToolFactory(
    id: "anthropic.memory_20250818",
    name: "memory",
    inputSchema: anthropicMemory20250818InputSchema
)

@discardableResult
public func anthropicMemory20250818() -> Tool {
    anthropicMemory20250818Factory(ProviderDefinedToolFactoryOptions(args: [:]))
}

