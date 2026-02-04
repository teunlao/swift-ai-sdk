import Foundation
import AISDKProvider
import AISDKProviderUtils

private let anthropicTextEditorInputSchemaWithUndo = FlexibleSchema(
    jsonSchema(
        .object([
            "type": .string("object"),
            "properties": .object([
                "command": .object([
                    "type": .string("string"),
                    "enum": .array([
                        .string("view"),
                        .string("create"),
                        .string("str_replace"),
                        .string("insert"),
                        .string("undo_edit")
                    ])
                ]),
                "path": .object(["type": .string("string")]),
                "file_text": .object(["type": .string("string")]),
                "insert_line": .object(["type": .string("integer")]),
                "new_str": .object(["type": .string("string")]),
                "insert_text": .object(["type": .string("string")]),
                "old_str": .object(["type": .string("string")]),
                "view_range": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("integer")])
                ])
            ]),
            "required": .array([.string("command"), .string("path")]),
            "additionalProperties": .bool(false)
        ])
    )
)

private let anthropicTextEditorInputSchema = FlexibleSchema(
    jsonSchema(
        .object([
            "type": .string("object"),
            "properties": .object([
                "command": .object([
                    "type": .string("string"),
                    "enum": .array([
                        .string("view"),
                        .string("create"),
                        .string("str_replace"),
                        .string("insert")
                    ])
                ]),
                "path": .object(["type": .string("string")]),
                "file_text": .object(["type": .string("string")]),
                "insert_line": .object(["type": .string("integer")]),
                "new_str": .object(["type": .string("string")]),
                "insert_text": .object(["type": .string("string")]),
                "old_str": .object(["type": .string("string")]),
                "view_range": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("integer")])
                ])
            ]),
            "required": .array([.string("command"), .string("path")]),
            "additionalProperties": .bool(false)
        ])
    )
)

private let anthropicTextEditor20241022Factory = createProviderToolFactory(
    id: "anthropic.text_editor_20241022",
    name: "str_replace_editor",
    inputSchema: anthropicTextEditorInputSchemaWithUndo
)

private let anthropicTextEditor20250124Factory = createProviderToolFactory(
    id: "anthropic.text_editor_20250124",
    name: "str_replace_editor",
    inputSchema: anthropicTextEditorInputSchemaWithUndo
)

private let anthropicTextEditor20250429Factory = createProviderToolFactory(
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
