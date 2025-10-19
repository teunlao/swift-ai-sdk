import Foundation
import AISDKProvider
import AISDKProviderUtils

private let anthropicTextEditorInputSchemaWithUndo = FlexibleSchema(
    jsonSchema(
        .object([
            "type": .string("object"),
            "properties": .object([
                "command": .object(["type": .string("string")]),
                "path": .object(["type": .string("string")]),
                "file_text": .object(["type": .array([.string("string"), .string("null")])]),
                "insert_line": .object(["type": .array([.string("number"), .string("null")])]),
                "new_str": .object(["type": .array([.string("string"), .string("null")])]),
                "old_str": .object(["type": .array([.string("string"), .string("null")])]),
                "view_range": .object(["type": .array([.string("array"), .string("null")])])
            ]),
            "required": .array([.string("command"), .string("path")]),
            "additionalProperties": .bool(true)
        ])
    )
)

private let anthropicTextEditorInputSchema = FlexibleSchema(
    jsonSchema(
        .object([
            "type": .string("object"),
            "properties": .object([
                "command": .object(["type": .string("string")]),
                "path": .object(["type": .string("string")]),
                "file_text": .object(["type": .array([.string("string"), .string("null")])]),
                "insert_line": .object(["type": .array([.string("number"), .string("null")])]),
                "new_str": .object(["type": .array([.string("string"), .string("null")])]),
                "old_str": .object(["type": .array([.string("string"), .string("null")])]),
                "view_range": .object(["type": .array([.string("array"), .string("null")])])
            ]),
            "required": .array([.string("command"), .string("path")]),
            "additionalProperties": .bool(true)
        ])
    )
)

private let anthropicTextEditor20241022Factory = createProviderDefinedToolFactory(
    id: "anthropic.text_editor_20241022",
    name: "str_replace_editor",
    inputSchema: anthropicTextEditorInputSchemaWithUndo
)

private let anthropicTextEditor20250124Factory = createProviderDefinedToolFactory(
    id: "anthropic.text_editor_20250124",
    name: "str_replace_editor",
    inputSchema: anthropicTextEditorInputSchemaWithUndo
)

private let anthropicTextEditor20250429Factory = createProviderDefinedToolFactory(
    id: "anthropic.text_editor_20250429",
    name: "str_replace_based_edit_tool",
    inputSchema: anthropicTextEditorInputSchema
)

@discardableResult
public func anthropicTextEditor20241022() -> Tool {
    anthropicTextEditor20241022Factory(.init(args: [:]))
}

@discardableResult
public func anthropicTextEditor20250124() -> Tool {
    anthropicTextEditor20250124Factory(.init(args: [:]))
}

@discardableResult
public func anthropicTextEditor20250429() -> Tool {
    anthropicTextEditor20250429Factory(.init(args: [:]))
}
