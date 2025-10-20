import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Text editor tool arguments (version 20250728).

 Port of `@ai-sdk/anthropic/src/tool/text-editor_20250728.ts`.
 */
public struct AnthropicTextEditor20250728Args: Codable, Sendable, Equatable {
    /// Optional parameter to control truncation when viewing large files.
    /// Only compatible with text_editor_20250728 and later versions.
    public var maxCharacters: Int?

    public init(maxCharacters: Int? = nil) {
        self.maxCharacters = maxCharacters
    }
}

public let anthropicTextEditor20250728ArgsSchema = FlexibleSchema(
    Schema<AnthropicTextEditor20250728Args>.codable(
        AnthropicTextEditor20250728Args.self,
        jsonSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "maxCharacters": .object([
                    "type": .array([.string("number"), .string("null")])
                ])
            ]),
            "additionalProperties": .bool(true)
        ])
    )
)

private let anthropicTextEditor20250728InputSchema = FlexibleSchema(
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
                "path": .object([
                    "type": .string("string")
                ]),
                "file_text": .object([
                    "type": .array([.string("string"), .string("null")])
                ]),
                "insert_line": .object([
                    "type": .array([.string("integer"), .string("null")])
                ]),
                "new_str": .object([
                    "type": .array([.string("string"), .string("null")])
                ]),
                "old_str": .object([
                    "type": .array([.string("string"), .string("null")])
                ]),
                "view_range": .object([
                    "type": .array([.string("array"), .string("null")]),
                    "items": .object(["type": .string("integer")])
                ])
            ]),
            "required": .array([.string("command"), .string("path")]),
            "additionalProperties": .bool(true)
        ])
    )
)

/// Creates a text editor tool (version 20250728) that gives Claude access to view and modify text files.
///
/// Claude can use an Anthropic-defined text editor tool to view and modify text files,
/// helping you debug, fix, and improve your code or other text documents. This allows Claude
/// to directly interact with your files, providing hands-on assistance rather than just suggesting changes.
///
/// Note: This version does not support the "undo_edit" command and adds optional max_characters parameter.
///
/// Supported models: Claude Sonnet 4, Opus 4, and Opus 4.1
///
/// Tool name must be `str_replace_based_edit_tool`.
///
/// - Parameter args: Optional configuration including max_characters for truncation control
/// - Returns: A configured text editor tool
///
/// **Input Schema**:
/// - `command`: The commands to run. Allowed options are: `view`, `create`, `str_replace`, `insert`.
///   Note: `undo_edit` is not supported in Claude 4 models.
/// - `path`: Absolute path to file or directory, e.g. `/repo/file.py` or `/repo`.
/// - `file_text`: Required parameter of `create` command, with the content of the file to be created.
/// - `insert_line`: Required parameter of `insert` command. The `new_str` will be inserted AFTER the line `insert_line` of `path`.
/// - `new_str`: Optional parameter of `str_replace` command containing the new string (if not given, no string will be added). Required parameter of `insert` command containing the string to insert.
/// - `old_str`: Required parameter of `str_replace` command containing the string in `path` to replace.
/// - `view_range`: Optional parameter of `view` command when `path` points to a file. If none is given, the full file is shown. If provided, the file will be shown in the indicated line number range, e.g. [11, 12] will show lines 11 and 12. Indexing at 1 to start. Setting `[start_line, -1]` shows all lines from `start_line` to the end of the file.
///
/// Port of `@ai-sdk/anthropic/src/tool/text-editor_20250728.ts`.
public let anthropicTextEditor20250728: @Sendable (AnthropicTextEditor20250728Args) -> Tool =
    createProviderDefinedToolFactory(
        id: "anthropic.text_editor_20250728",
        name: "str_replace_based_edit_tool",
        inputSchema: anthropicTextEditor20250728InputSchema
    ) { options in
        var args: [String: JSONValue] = [:]
        if let maxCharacters = options.maxCharacters {
            args["max_characters"] = .number(Double(maxCharacters))
        }
        return ProviderDefinedToolFactoryOptions(args: args)
    }
