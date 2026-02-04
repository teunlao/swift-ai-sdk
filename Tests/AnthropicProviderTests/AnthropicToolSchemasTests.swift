import Testing
import AISDKProvider
@testable import AnthropicProvider

@Suite("Anthropic tool schemas")
struct AnthropicToolSchemasTests {
    @Test("bash_20241022 tool input schema matches upstream shape")
    func bash20241022ToolSchema() async throws {
        let tool = anthropicBash20241022()

        let input = try await tool.inputSchema.resolve().jsonSchema()

        #expect(input == .object([
            "type": .string("object"),
            "required": .array([.string("command")]),
            "properties": .object([
                "command": .object(["type": .string("string")]),
                "restart": .object(["type": .string("boolean")]),
            ]),
            "additionalProperties": .bool(false),
        ]))
    }

    @Test("computer_20241022 tool input schema matches upstream shape")
    func computer20241022ToolSchema() async throws {
        let tool = anthropicComputer20241022(.init(displayWidthPx: 1024, displayHeightPx: 768))

        let input = try await tool.inputSchema.resolve().jsonSchema()

        #expect(input == .object([
            "type": .string("object"),
            "properties": .object([
                "action": .object([
                    "type": .string("string"),
                    "enum": .array([
                        .string("key"),
                        .string("type"),
                        .string("mouse_move"),
                        .string("left_click"),
                        .string("left_click_drag"),
                        .string("right_click"),
                        .string("middle_click"),
                        .string("double_click"),
                        .string("screenshot"),
                        .string("cursor_position"),
                    ]),
                ]),
                "coordinate": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("integer")]),
                ]),
                "text": .object([
                    "type": .string("string"),
                ]),
            ]),
            "required": .array([.string("action")]),
            "additionalProperties": .bool(false),
        ]))
    }

    @Test("computer_20250124 tool input schema matches upstream shape")
    func computer20250124ToolSchema() async throws {
        let tool = anthropicComputer20250124(.init(displayWidthPx: 1024, displayHeightPx: 768))

        let input = try await tool.inputSchema.resolve().jsonSchema()

        #expect(input == .object([
            "type": .string("object"),
            "properties": .object([
                "action": .object([
                    "type": .string("string"),
                    "enum": .array([
                        .string("key"),
                        .string("hold_key"),
                        .string("type"),
                        .string("cursor_position"),
                        .string("mouse_move"),
                        .string("left_mouse_down"),
                        .string("left_mouse_up"),
                        .string("left_click"),
                        .string("left_click_drag"),
                        .string("right_click"),
                        .string("middle_click"),
                        .string("double_click"),
                        .string("triple_click"),
                        .string("scroll"),
                        .string("wait"),
                        .string("screenshot"),
                    ]),
                ]),
                "coordinate": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("integer")]),
                    "minItems": .number(2),
                    "maxItems": .number(2),
                ]),
                "duration": .object([
                    "type": .string("number"),
                ]),
                "scroll_amount": .object([
                    "type": .string("number"),
                ]),
                "scroll_direction": .object([
                    "type": .string("string"),
                    "enum": .array([
                        .string("up"),
                        .string("down"),
                        .string("left"),
                        .string("right"),
                    ]),
                ]),
                "start_coordinate": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("integer")]),
                    "minItems": .number(2),
                    "maxItems": .number(2),
                ]),
                "text": .object([
                    "type": .string("string"),
                ]),
            ]),
            "required": .array([.string("action")]),
            "additionalProperties": .bool(false),
        ]))
    }

    @Test("computer_20251124 tool input schema matches upstream shape")
    func computer20251124ToolSchema() async throws {
        let tool = anthropicComputer20251124(.init(displayWidthPx: 1024, displayHeightPx: 768, enableZoom: true))

        let input = try await tool.inputSchema.resolve().jsonSchema()

        #expect(input == .object([
            "type": .string("object"),
            "properties": .object([
                "action": .object([
                    "type": .string("string"),
                    "enum": .array([
                        .string("key"),
                        .string("hold_key"),
                        .string("type"),
                        .string("cursor_position"),
                        .string("mouse_move"),
                        .string("left_mouse_down"),
                        .string("left_mouse_up"),
                        .string("left_click"),
                        .string("left_click_drag"),
                        .string("right_click"),
                        .string("middle_click"),
                        .string("double_click"),
                        .string("triple_click"),
                        .string("scroll"),
                        .string("wait"),
                        .string("screenshot"),
                        .string("zoom"),
                    ]),
                ]),
                "coordinate": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("integer")]),
                    "minItems": .number(2),
                    "maxItems": .number(2),
                ]),
                "duration": .object([
                    "type": .string("number"),
                ]),
                "region": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("integer")]),
                    "minItems": .number(4),
                    "maxItems": .number(4),
                ]),
                "scroll_amount": .object([
                    "type": .string("number"),
                ]),
                "scroll_direction": .object([
                    "type": .string("string"),
                    "enum": .array([
                        .string("up"),
                        .string("down"),
                        .string("left"),
                        .string("right"),
                    ]),
                ]),
                "start_coordinate": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("integer")]),
                    "minItems": .number(2),
                    "maxItems": .number(2),
                ]),
                "text": .object([
                    "type": .string("string"),
                ]),
            ]),
            "required": .array([.string("action")]),
            "additionalProperties": .bool(false),
        ]))
    }

    @Test("text_editor_20241022 tool input schema matches upstream shape")
    func textEditor20241022ToolSchema() async throws {
        let tool = anthropicTextEditor20241022()

        let input = try await tool.inputSchema.resolve().jsonSchema()

        #expect(input == .object([
            "type": .string("object"),
            "properties": .object([
                "command": .object([
                    "type": .string("string"),
                    "enum": .array([
                        .string("view"),
                        .string("create"),
                        .string("str_replace"),
                        .string("insert"),
                        .string("undo_edit"),
                    ]),
                ]),
                "path": .object(["type": .string("string")]),
                "file_text": .object(["type": .string("string")]),
                "insert_line": .object(["type": .string("integer")]),
                "new_str": .object(["type": .string("string")]),
                "insert_text": .object(["type": .string("string")]),
                "old_str": .object(["type": .string("string")]),
                "view_range": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("integer")]),
                ]),
            ]),
            "required": .array([.string("command"), .string("path")]),
            "additionalProperties": .bool(false),
        ]))
    }

    @Test("text_editor_20250429 tool input schema matches upstream shape")
    func textEditor20250429ToolSchema() async throws {
        let tool = anthropicTextEditor20250429()

        let input = try await tool.inputSchema.resolve().jsonSchema()

        #expect(input == .object([
            "type": .string("object"),
            "properties": .object([
                "command": .object([
                    "type": .string("string"),
                    "enum": .array([
                        .string("view"),
                        .string("create"),
                        .string("str_replace"),
                        .string("insert"),
                    ]),
                ]),
                "path": .object(["type": .string("string")]),
                "file_text": .object(["type": .string("string")]),
                "insert_line": .object(["type": .string("integer")]),
                "new_str": .object(["type": .string("string")]),
                "insert_text": .object(["type": .string("string")]),
                "old_str": .object(["type": .string("string")]),
                "view_range": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("integer")]),
                ]),
            ]),
            "required": .array([.string("command"), .string("path")]),
            "additionalProperties": .bool(false),
        ]))
    }

    @Test("text_editor_20250728 tool input schema and args schema match upstream shape")
    func textEditor20250728ToolSchema() async throws {
        let tool = anthropicTextEditor20250728(.init())

        let input = try await tool.inputSchema.resolve().jsonSchema()
        let argsSchema = try await anthropicTextEditor20250728ArgsSchema.resolve().jsonSchema()

        #expect(argsSchema == .object([
            "type": .string("object"),
            "properties": .object([
                "maxCharacters": .object(["type": .string("number")]),
            ]),
            "additionalProperties": .bool(false),
        ]))

        #expect(input == .object([
            "type": .string("object"),
            "properties": .object([
                "command": .object([
                    "type": .string("string"),
                    "enum": .array([
                        .string("view"),
                        .string("create"),
                        .string("str_replace"),
                        .string("insert"),
                    ]),
                ]),
                "path": .object(["type": .string("string")]),
                "file_text": .object(["type": .string("string")]),
                "insert_line": .object(["type": .string("integer")]),
                "new_str": .object(["type": .string("string")]),
                "insert_text": .object(["type": .string("string")]),
                "old_str": .object(["type": .string("string")]),
                "view_range": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("integer")]),
                ]),
            ]),
            "required": .array([.string("command"), .string("path")]),
            "additionalProperties": .bool(false),
        ]))
    }

    @Test("tool_search_regex_20251119 tool input/output schemas match upstream shape")
    func toolSearchRegex20251119ToolSchemas() async throws {
        let tool = anthropicToolSearchRegex20251119()

        let input = try await tool.inputSchema.resolve().jsonSchema()
        let output = try await tool.outputSchema?.resolve().jsonSchema()

        #expect(input == .object([
            "type": .string("object"),
            "properties": .object([
                "pattern": .object(["type": .string("string")]),
                "limit": .object(["type": .string("number")]),
            ]),
            "required": .array([.string("pattern")]),
            "additionalProperties": .bool(false),
        ]))

        #expect(output == .object([
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
        ]))
    }

    @Test("tool_search_bm25_20251119 tool input/output schemas match upstream shape")
    func toolSearchBm2520251119ToolSchemas() async throws {
        let tool = anthropicToolSearchBm2520251119()

        let input = try await tool.inputSchema.resolve().jsonSchema()
        let output = try await tool.outputSchema?.resolve().jsonSchema()

        #expect(input == .object([
            "type": .string("object"),
            "properties": .object([
                "query": .object(["type": .string("string")]),
                "limit": .object(["type": .string("number")]),
            ]),
            "required": .array([.string("query")]),
            "additionalProperties": .bool(false),
        ]))

        #expect(output == .object([
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
        ]))
    }

    @Test("code_execution_20250522 tool input/output schemas match upstream shape")
    func codeExecution20250522ToolSchemas() async throws {
        let tool = anthropicCodeExecution20250522()

        let input = try await tool.inputSchema.resolve().jsonSchema()
        let output = try await tool.outputSchema?.resolve().jsonSchema()

        #expect(input == .object([
            "type": .string("object"),
            "properties": .object([
                "code": .object(["type": .string("string")]),
            ]),
            "required": .array([.string("code")]),
            "additionalProperties": .bool(false),
        ]))

        #expect(output == .object([
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
        ]))
    }

    @Test("code_execution_20250825 tool input/output schemas match upstream shape")
    func codeExecution20250825ToolSchemas() async throws {
        let tool = anthropicCodeExecution20250825()

        let input = try await tool.inputSchema.resolve().jsonSchema()
        let output = try await tool.outputSchema?.resolve().jsonSchema()

        #expect(input == .object([
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
        ]))

        #expect(output == .object([
            "type": .string("object"),
            "oneOf": .array([
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
                .object([
                    "type": .string("object"),
                    "properties": .object([
                        "type": .object(["const": .string("bash_code_execution_tool_result_error")]),
                        "error_code": .object(["type": .string("string")]),
                    ]),
                    "required": .array([.string("type"), .string("error_code")]),
                    "additionalProperties": .bool(false),
                ]),
                .object([
                    "type": .string("object"),
                    "properties": .object([
                        "type": .object(["const": .string("text_editor_code_execution_tool_result_error")]),
                        "error_code": .object(["type": .string("string")]),
                    ]),
                    "required": .array([.string("type"), .string("error_code")]),
                    "additionalProperties": .bool(false),
                ]),
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
                .object([
                    "type": .string("object"),
                    "properties": .object([
                        "type": .object(["const": .string("text_editor_code_execution_create_result")]),
                        "is_file_update": .object(["type": .string("boolean")]),
                    ]),
                    "required": .array([.string("type"), .string("is_file_update")]),
                    "additionalProperties": .bool(false),
                ]),
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
        ]))
    }

    @Test("memory_20250818 tool input schema matches upstream shape")
    func memory20250818ToolSchema() async throws {
        let tool = anthropicMemory20250818()

        let input = try await tool.inputSchema.resolve().jsonSchema()

        #expect(input == .object([
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
        ]))
    }
}
