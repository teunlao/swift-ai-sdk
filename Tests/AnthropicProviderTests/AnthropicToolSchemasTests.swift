import Testing
import AISDKProvider
import AISDKProviderUtils
@testable import AnthropicProvider

@Suite("Anthropic tool schemas")
struct AnthropicToolSchemasTests {
    @Test("computer toolset validates action coordinates and executes client actions")
    func computerToolsetActions() async throws {
        let tool = anthropicTools.computerToolset20260801(options: .init(execute: { input, _ in
            .value(input)
        }))
        let input: JSONValue = .object(["action": .string("key"), "text": .string("ctrl+s"), "repeat": .number(2)])
        let schema = tool.inputSchema.resolve()
        guard case .success(let validated) = await schema.validate(input) else {
            Issue.record("Expected a valid computer key action")
            return
        }
        let execute = try #require(tool.execute)
        let output = try await execute(validated, ToolExecutionOptions(toolCallId: "key-1", messages: [])).resolve()
        #expect(output == input)
        for invalid: JSONValue in [
            .object(["action": .string("mouse_move"), "coordinate": .array([.number(1)])]),
            .object(["action": .string("key"), "repeat": .number(1.5)]),
        ] {
            guard case .failure = await schema.validate(invalid) else {
                Issue.record("Expected malformed computer action rejection")
                continue
            }
        }
    }

    @Test("code execution results default omitted files and reject null files", arguments: [20250522, 20250825, 20260120])
    func codeExecutionFileDefaults(version: Int) async throws {
        let tool: Tool
        switch version {
        case 20250522: tool = anthropicTools.codeExecution20250522()
        case 20250825: tool = anthropicTools.codeExecution20250825()
        default: tool = anthropicTools.codeExecution20260120()
        }
        let outputSchema = try #require(tool.outputSchema)
        let schema = outputSchema.resolve()
        var result: [String: JSONValue] = [
            "type": .string("code_execution_result"),
            "stdout": .string("done"),
            "stderr": .string(""),
            "return_code": .number(0.5),
        ]
        guard case .success(let output) = await schema.validate(JSONValue.object(result)) else {
            Issue.record("Expected a code execution result with omitted files")
            return
        }
        result["content"] = .array([])
        #expect(output == .object(result))
        result["content"] = .null
        guard case .failure = await schema.validate(JSONValue.object(result)) else {
            Issue.record("Expected null output files rejection")
            return
        }
    }

    @Test("typed code execution output rejects an unknown result discriminator")
    func typedCodeExecutionDiscriminator() async throws {
        let schema = anthropicCodeExecution20250522OutputSchema.resolve()
        guard case .failure = await schema.validate([
            "type": "unknown_result",
            "stdout": "done",
            "stderr": "",
            "return_code": 0,
        ] as [String: Any]) else {
            Issue.record("Expected unknown code execution result rejection")
            return
        }
    }

    @Test("advisor token budget rejects values below the API minimum")
    func advisorTokenBudget() async throws {
        let schema = anthropicAdvisor20260301ArgsSchema.resolve()
        guard case .failure = await schema.validate(["model": "advisor", "maxTokens": 1023] as [String: Any]) else {
            Issue.record("Expected undersized advisor token budget rejection")
            return
        }
        guard case .success(let args) = await schema.validate(["model": "advisor", "maxTokens": 1024] as [String: Any]) else {
            Issue.record("Expected the minimum advisor token budget")
            return
        }
        #expect(args.maxTokens == 1024)
    }

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

    @Test("code_execution_20260120 tool input/output schemas match upstream shape")
    func codeExecution20260120ToolSchemas() async throws {
        let tool = anthropicCodeExecution20260120()

        let input = try await tool.inputSchema.resolve().jsonSchema()
        let output = try await tool.outputSchema?.resolve().jsonSchema()
        let legacyInput = try await anthropicCodeExecution20250825().inputSchema.resolve().jsonSchema()

        #expect(input == legacyInput)

        #expect(output == .object([
            "type": .string("object"),
            "oneOf": .array([
                .object([
                    "type": .string("object"),
                    "properties": .object([
                        "type": .object(["const": .string("encrypted_code_execution_result")]),
                        "encrypted_stdout": .object(["type": .string("string")]),
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
                    "required": .array([
                        .string("type"),
                        .string("encrypted_stdout"),
                        .string("stderr"),
                        .string("return_code"),
                    ]),
                    "additionalProperties": .bool(false),
                ]),
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

    @Test("web_fetch_20260209 tool input/output schemas match upstream shape")
    func webFetch20260209ToolSchemas() async throws {
        let tool = anthropicWebFetch20260209()

        let input = try await tool.inputSchema.resolve().jsonSchema()
        let output = try await tool.outputSchema?.resolve().jsonSchema()
        let legacyOutput = try await anthropicWebFetch20250910().outputSchema?.resolve().jsonSchema()

        #expect(input == .object([
            "type": .string("object"),
            "required": .array([.string("url")]),
            "properties": .object([
                "url": .object(["type": .string("string")])
            ]),
            "additionalProperties": .bool(false),
        ]))

        #expect(output == legacyOutput)
    }

    @Test("web_search_20260209 tool input/output schemas match upstream shape")
    func webSearch20260209ToolSchemas() async throws {
        let tool = anthropicWebSearch20260209()

        let input = try await tool.inputSchema.resolve().jsonSchema()
        let output = try await tool.outputSchema?.resolve().jsonSchema()
        let legacyOutput = try await anthropicWebSearch20250305().outputSchema?.resolve().jsonSchema()

        #expect(input == .object([
            "type": .string("object"),
            "required": .array([.string("query")]),
            "properties": .object([
                "query": .object(["type": .string("string")])
            ]),
            "additionalProperties": .bool(false),
        ]))

        #expect(output == legacyOutput)
    }

    @Test("advisor_20260301 factory and schemas match upstream contract")
    func advisor20260301ToolContract() async throws {
        let tool = anthropicAdvisor20260301(.init(
            model: "claude-opus-4-7",
            maxUses: 4,
            caching: .init(ttl: .oneHour)
        ))

        let args = try await anthropicAdvisor20260301ArgsSchema.resolve().jsonSchema()
        let input = try await tool.inputSchema.resolve().jsonSchema()

        #expect(tool.id == "anthropic.advisor_20260301")
        #expect(tool.name == "advisor")
        #expect(tool.supportsDeferredResults == true)
        #expect(tool.args == [
            "model": .string("claude-opus-4-7"),
            "maxUses": .number(4),
            "caching": .object([
                "type": .string("ephemeral"),
                "ttl": .string("1h"),
            ]),
        ])
        #expect(args == .object([
            "type": .string("object"),
            "properties": .object([
                "model": .object(["type": .string("string")]),
                "maxUses": .object(["type": .string("number")]),
                "maxTokens": .object(["type": .string("integer"), "minimum": .number(1024)]),
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
        ]))
        #expect(input == .object([
            "type": .string("object"),
            "properties": .object([:]),
            "additionalProperties": .bool(false),
        ]))
        let outputSchema = try #require(tool.outputSchema)
        let schema = outputSchema.resolve()
        for result: JSONValue in [
            .object(["type": .string("advisor_result"), "text": .string("advice"), "stopReason": .string("max_tokens")]),
            .object(["type": .string("advisor_redacted_result"), "encryptedContent": .string("opaque"), "stopReason": .string("end_turn")]),
            .object(["type": .string("advisor_tool_result_error"), "errorCode": .string("overloaded")]),
        ] {
            guard case .success(let validated) = await schema.validate(result) else {
                Issue.record("Expected a valid advisor result")
                continue
            }
            #expect(validated == result)
        }
        guard case .failure = await schema.validate(JSONValue.object([
            "type": .string("advisor_result"),
            "text": .string("advice"),
            "stopReason": .number(1),
        ])) else {
            Issue.record("Expected advisor stopReason to require a string")
            return
        }
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
