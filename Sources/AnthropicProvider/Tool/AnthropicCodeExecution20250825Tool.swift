import Foundation
import AISDKProvider
import AISDKProviderUtils

// MARK: - Output types

public struct AnthropicCodeExecution20250825OutputFile: Codable, Equatable, Sendable {
    public let type: String
    public let fileId: String

    enum CodingKeys: String, CodingKey {
        case type
        case fileId = "file_id"
    }
}

public struct AnthropicCodeExecution20250825CodeExecutionResult: Codable, Equatable, Sendable {
    public let type: String
    public let stdout: String
    public let stderr: String
    public let returnCode: Int
    public let content: [AnthropicCodeExecution20250825OutputFile]

    enum CodingKeys: String, CodingKey {
        case type
        case stdout
        case stderr
        case returnCode = "return_code"
        case content
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        stdout = try container.decode(String.self, forKey: .stdout)
        stderr = try container.decode(String.self, forKey: .stderr)
        returnCode = try container.decode(Int.self, forKey: .returnCode)
        content = try container.decodeIfPresent([AnthropicCodeExecution20250825OutputFile].self, forKey: .content) ?? []
    }
}

public struct AnthropicCodeExecution20250825BashResult: Codable, Equatable, Sendable {
    public let type: String
    public let content: [AnthropicCodeExecution20250825OutputFile]
    public let stdout: String
    public let stderr: String
    public let returnCode: Int

    enum CodingKeys: String, CodingKey {
        case type
        case content
        case stdout
        case stderr
        case returnCode = "return_code"
    }
}

public struct AnthropicCodeExecution20250825ToolError: Codable, Equatable, Sendable {
    public let type: String
    public let errorCode: String

    enum CodingKeys: String, CodingKey {
        case type
        case errorCode = "error_code"
    }
}

public struct AnthropicCodeExecution20250825TextEditorViewResult: Codable, Equatable, Sendable {
    public let type: String
    public let content: String
    public let fileType: String
    public let numLines: Int?
    public let startLine: Int?
    public let totalLines: Int?

    enum CodingKeys: String, CodingKey {
        case type
        case content
        case fileType = "file_type"
        case numLines = "num_lines"
        case startLine = "start_line"
        case totalLines = "total_lines"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        content = try container.decode(String.self, forKey: .content)
        fileType = try container.decode(String.self, forKey: .fileType)

        guard container.contains(.numLines) else {
            throw DecodingError.keyNotFound(
                CodingKeys.numLines,
                DecodingError.Context(codingPath: container.codingPath, debugDescription: "Missing required key: num_lines")
            )
        }
        guard container.contains(.startLine) else {
            throw DecodingError.keyNotFound(
                CodingKeys.startLine,
                DecodingError.Context(codingPath: container.codingPath, debugDescription: "Missing required key: start_line")
            )
        }
        guard container.contains(.totalLines) else {
            throw DecodingError.keyNotFound(
                CodingKeys.totalLines,
                DecodingError.Context(codingPath: container.codingPath, debugDescription: "Missing required key: total_lines")
            )
        }

        numLines = try container.decodeIfPresent(Int.self, forKey: .numLines)
        startLine = try container.decodeIfPresent(Int.self, forKey: .startLine)
        totalLines = try container.decodeIfPresent(Int.self, forKey: .totalLines)
    }
}

public struct AnthropicCodeExecution20250825TextEditorCreateResult: Codable, Equatable, Sendable {
    public let type: String
    public let isFileUpdate: Bool

    enum CodingKeys: String, CodingKey {
        case type
        case isFileUpdate = "is_file_update"
    }
}

public struct AnthropicCodeExecution20250825TextEditorStrReplaceResult: Codable, Equatable, Sendable {
    public let type: String
    public let lines: [String]?
    public let newLines: Int?
    public let newStart: Int?
    public let oldLines: Int?
    public let oldStart: Int?

    enum CodingKeys: String, CodingKey {
        case type
        case lines
        case newLines = "new_lines"
        case newStart = "new_start"
        case oldLines = "old_lines"
        case oldStart = "old_start"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)

        guard container.contains(.lines) else {
            throw DecodingError.keyNotFound(
                CodingKeys.lines,
                DecodingError.Context(codingPath: container.codingPath, debugDescription: "Missing required key: lines")
            )
        }
        guard container.contains(.newLines) else {
            throw DecodingError.keyNotFound(
                CodingKeys.newLines,
                DecodingError.Context(codingPath: container.codingPath, debugDescription: "Missing required key: new_lines")
            )
        }
        guard container.contains(.newStart) else {
            throw DecodingError.keyNotFound(
                CodingKeys.newStart,
                DecodingError.Context(codingPath: container.codingPath, debugDescription: "Missing required key: new_start")
            )
        }
        guard container.contains(.oldLines) else {
            throw DecodingError.keyNotFound(
                CodingKeys.oldLines,
                DecodingError.Context(codingPath: container.codingPath, debugDescription: "Missing required key: old_lines")
            )
        }
        guard container.contains(.oldStart) else {
            throw DecodingError.keyNotFound(
                CodingKeys.oldStart,
                DecodingError.Context(codingPath: container.codingPath, debugDescription: "Missing required key: old_start")
            )
        }

        lines = try container.decodeIfPresent([String].self, forKey: .lines)
        newLines = try container.decodeIfPresent(Int.self, forKey: .newLines)
        newStart = try container.decodeIfPresent(Int.self, forKey: .newStart)
        oldLines = try container.decodeIfPresent(Int.self, forKey: .oldLines)
        oldStart = try container.decodeIfPresent(Int.self, forKey: .oldStart)
    }
}

public enum AnthropicCodeExecution20250825ToolResult: Codable, Equatable, Sendable {
    case codeExecutionResult(AnthropicCodeExecution20250825CodeExecutionResult)
    case bashCodeExecutionResult(AnthropicCodeExecution20250825BashResult)
    case toolError(AnthropicCodeExecution20250825ToolError)
    case textEditorViewResult(AnthropicCodeExecution20250825TextEditorViewResult)
    case textEditorCreateResult(AnthropicCodeExecution20250825TextEditorCreateResult)
    case textEditorStrReplaceResult(AnthropicCodeExecution20250825TextEditorStrReplaceResult)

    enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let single = try decoder.singleValueContainer()

        switch type {
        case "code_execution_result":
            self = .codeExecutionResult(try single.decode(AnthropicCodeExecution20250825CodeExecutionResult.self))
        case "bash_code_execution_result":
            self = .bashCodeExecutionResult(try single.decode(AnthropicCodeExecution20250825BashResult.self))
        case "bash_code_execution_tool_result_error",
             "text_editor_code_execution_tool_result_error":
            self = .toolError(try single.decode(AnthropicCodeExecution20250825ToolError.self))
        case "text_editor_code_execution_view_result":
            self = .textEditorViewResult(try single.decode(AnthropicCodeExecution20250825TextEditorViewResult.self))
        case "text_editor_code_execution_create_result":
            self = .textEditorCreateResult(try single.decode(AnthropicCodeExecution20250825TextEditorCreateResult.self))
        case "text_editor_code_execution_str_replace_result":
            self = .textEditorStrReplaceResult(try single.decode(AnthropicCodeExecution20250825TextEditorStrReplaceResult.self))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown code execution 20250825 result type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .codeExecutionResult(let value):
            try value.encode(to: encoder)
        case .bashCodeExecutionResult(let value):
            try value.encode(to: encoder)
        case .toolError(let value):
            try value.encode(to: encoder)
        case .textEditorViewResult(let value):
            try value.encode(to: encoder)
        case .textEditorCreateResult(let value):
            try value.encode(to: encoder)
        case .textEditorStrReplaceResult(let value):
            try value.encode(to: encoder)
        }
    }
}

public let anthropicCodeExecution20250825OutputSchema = FlexibleSchema(
    Schema<AnthropicCodeExecution20250825ToolResult>.codable(
        AnthropicCodeExecution20250825ToolResult.self,
        jsonSchema: anthropicCodeExecution20250825OutputJSONSchema
    )
)

private let anthropicCodeExecution20250825OutputJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "oneOf": .array([
        // code_execution_result
        .object([
            "type": .string("object"),
            "properties": .object([
                "type": .object(["const": .string("code_execution_result")]),
                "stdout": .object(["type": .string("string")]),
                "stderr": .object(["type": .string("string")]),
                "return_code": .object(["type": .string("number")]),
                "content": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "type": .object(["const": .string("code_execution_output")]),
                            "file_id": .object(["type": .string("string")]),
                        ]),
                        "required": .array([.string("type"), .string("file_id")]),
                        "additionalProperties": .bool(false),
                    ]),
                ]),
            ]),
            "required": .array([.string("type"), .string("stdout"), .string("stderr"), .string("return_code")]),
            "additionalProperties": .bool(false),
        ]),
        // bash_code_execution_result
        .object([
            "type": .string("object"),
            "properties": .object([
                "type": .object(["const": .string("bash_code_execution_result")]),
                "content": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "type": .object(["const": .string("bash_code_execution_output")]),
                            "file_id": .object(["type": .string("string")]),
                        ]),
                        "required": .array([.string("type"), .string("file_id")]),
                        "additionalProperties": .bool(false),
                    ]),
                ]),
                "stdout": .object(["type": .string("string")]),
                "stderr": .object(["type": .string("string")]),
                "return_code": .object(["type": .string("number")]),
            ]),
            "required": .array([
                .string("type"),
                .string("content"),
                .string("stdout"),
                .string("stderr"),
                .string("return_code"),
            ]),
            "additionalProperties": .bool(false),
        ]),
        // bash_code_execution_tool_result_error
        .object([
            "type": .string("object"),
            "properties": .object([
                "type": .object(["const": .string("bash_code_execution_tool_result_error")]),
                "error_code": .object(["type": .string("string")]),
            ]),
            "required": .array([.string("type"), .string("error_code")]),
            "additionalProperties": .bool(false),
        ]),
        // text_editor_code_execution_tool_result_error
        .object([
            "type": .string("object"),
            "properties": .object([
                "type": .object(["const": .string("text_editor_code_execution_tool_result_error")]),
                "error_code": .object(["type": .string("string")]),
            ]),
            "required": .array([.string("type"), .string("error_code")]),
            "additionalProperties": .bool(false),
        ]),
        // text_editor_code_execution_view_result
        .object([
            "type": .string("object"),
            "properties": .object([
                "type": .object(["const": .string("text_editor_code_execution_view_result")]),
                "content": .object(["type": .string("string")]),
                "file_type": .object(["type": .string("string")]),
                "num_lines": .object(["type": .array([.string("number"), .string("null")])]),
                "start_line": .object(["type": .array([.string("number"), .string("null")])]),
                "total_lines": .object(["type": .array([.string("number"), .string("null")])]),
            ]),
            "required": .array([
                .string("type"),
                .string("content"),
                .string("file_type"),
                .string("num_lines"),
                .string("start_line"),
                .string("total_lines"),
            ]),
            "additionalProperties": .bool(false),
        ]),
        // text_editor_code_execution_create_result
        .object([
            "type": .string("object"),
            "properties": .object([
                "type": .object(["const": .string("text_editor_code_execution_create_result")]),
                "is_file_update": .object(["type": .string("boolean")]),
            ]),
            "required": .array([.string("type"), .string("is_file_update")]),
            "additionalProperties": .bool(false),
        ]),
        // text_editor_code_execution_str_replace_result
        .object([
            "type": .string("object"),
            "properties": .object([
                "type": .object(["const": .string("text_editor_code_execution_str_replace_result")]),
                "lines": .object([
                    "type": .array([.string("array"), .string("null")]),
                    "items": .object(["type": .string("string")]),
                ]),
                "new_lines": .object(["type": .array([.string("number"), .string("null")])]),
                "new_start": .object(["type": .array([.string("number"), .string("null")])]),
                "old_lines": .object(["type": .array([.string("number"), .string("null")])]),
                "old_start": .object(["type": .array([.string("number"), .string("null")])]),
            ]),
            "required": .array([
                .string("type"),
                .string("lines"),
                .string("new_lines"),
                .string("new_start"),
                .string("old_lines"),
                .string("old_start"),
            ]),
            "additionalProperties": .bool(false),
        ]),
    ]),
])

// MARK: - Tool definition

private let anthropicCodeExecution20250825InputSchema = FlexibleSchema(
    jsonSchema(
        .object([
            "type": .string("object"),
            "oneOf": .array([
                .object([
                    "type": .string("object"),
                    "properties": .object([
                        "type": .object(["const": .string("programmatic-tool-call")]),
                        "code": .object(["type": .string("string")]),
                    ]),
                    "required": .array([.string("type"), .string("code")]),
                    "additionalProperties": .bool(false),
                ]),
                .object([
                    "type": .string("object"),
                    "properties": .object([
                        "type": .object(["const": .string("bash_code_execution")]),
                        "command": .object(["type": .string("string")]),
                    ]),
                    "required": .array([.string("type"), .string("command")]),
                    "additionalProperties": .bool(false),
                ]),
                .object([
                    "type": .string("object"),
                    "properties": .object([
                        "type": .object(["const": .string("text_editor_code_execution")]),
                        "command": .object(["const": .string("view")]),
                        "path": .object(["type": .string("string")]),
                    ]),
                    "required": .array([.string("type"), .string("command"), .string("path")]),
                    "additionalProperties": .bool(false),
                ]),
                .object([
                    "type": .string("object"),
                    "properties": .object([
                        "type": .object(["const": .string("text_editor_code_execution")]),
                        "command": .object(["const": .string("create")]),
                        "path": .object(["type": .string("string")]),
                        "file_text": .object(["type": .array([.string("string"), .string("null")])]),
                    ]),
                    "required": .array([.string("type"), .string("command"), .string("path")]),
                    "additionalProperties": .bool(false),
                ]),
                .object([
                    "type": .string("object"),
                    "properties": .object([
                        "type": .object(["const": .string("text_editor_code_execution")]),
                        "command": .object(["const": .string("str_replace")]),
                        "path": .object(["type": .string("string")]),
                        "old_str": .object(["type": .string("string")]),
                        "new_str": .object(["type": .string("string")]),
                    ]),
                    "required": .array([
                        .string("type"),
                        .string("command"),
                        .string("path"),
                        .string("old_str"),
                        .string("new_str"),
                    ]),
                    "additionalProperties": .bool(false),
                ]),
            ]),
        ])
    )
)

private let anthropicCodeExecution20250825ToolOutputSchema = FlexibleSchema(
    jsonSchema(anthropicCodeExecution20250825OutputJSONSchema)
)

private let anthropicCodeExecution20250825Factory = createProviderToolFactoryWithOutputSchema(
    id: "anthropic.code_execution_20250825",
    name: "code_execution",
    inputSchema: anthropicCodeExecution20250825InputSchema,
    outputSchema: anthropicCodeExecution20250825ToolOutputSchema
)

@discardableResult
public func anthropicCodeExecution20250825() -> Tool {
    anthropicCodeExecution20250825Factory(ProviderToolFactoryWithOutputSchemaOptions(args: [:]))
}
