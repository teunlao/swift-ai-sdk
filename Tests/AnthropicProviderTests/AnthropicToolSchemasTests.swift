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
            "return_code": .number(0),
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

    @Test("Execution output schemas reject fractional and unrepresentable integer fields", arguments: [
        ("code_execution_result", "return_code", 1.5),
        ("code_execution_result", "return_code", 1e100),
        ("text_editor_code_execution_view_result", "num_lines", 1.5),
        ("text_editor_code_execution_str_replace_result", "old_lines", 1.5)
    ])
    func invalidResultCount(_ type: String, _ key: String, _ count: Double) async throws {
        let tool = anthropicTools.codeExecution20250825()
        let schema = try #require(tool.outputSchema).resolve()
        var result: [String: JSONValue]
        switch type {
        case "code_execution_result": result = ["type": .string(type), "stdout": .string(""), "stderr": .string(""), "return_code": .number(0)]
        case "text_editor_code_execution_view_result": result = ["type": .string(type), "content": .string("file"), "file_type": .string("text"), "num_lines": .number(1), "start_line": .number(1), "total_lines": .number(1)]
        default: result = ["type": .string(type), "lines": .null, "new_lines": .null, "new_start": .null, "old_lines": .null, "old_start": .null]
        }
        result[key] = .number(count)
        guard case .failure = await schema.validate(JSONValue.object(result)) else {
            Issue.record("Expected malformed integer result rejection")
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

    @Test("Search limits and memory positions require integer counts", arguments: ["regex", "bm25", "memory-view", "memory-insert"])
    func inputCounts(_ kind: String) async throws {
        let tool: Tool
        var input: [String: JSONValue]
        let field: String
        switch kind {
        case "regex":
            tool = anthropicTools.toolSearchRegex20251119()
            input = ["pattern": .string("weather"), "limit": .number(2)]
            field = "limit"
        case "bm25":
            tool = anthropicTools.toolSearchBm2520251119()
            input = ["query": .string("weather"), "limit": .number(2)]
            field = "limit"
        case "memory-view":
            tool = anthropicTools.memory20250818()
            input = ["command": .string("view"), "path": .string("/notes"), "view_range": .array([.number(1), .number(2)])]
            field = "view_range"
        default:
            tool = anthropicTools.memory20250818()
            input = ["command": .string("insert"), "path": .string("/notes"), "insert_text": .string("line"), "insert_line": .number(1)]
            field = "insert_line"
        }
        let schema = tool.inputSchema.resolve()
        guard case .success(let validated) = await schema.validate(JSONValue.object(input)) else { Issue.record("Expected integer action count"); return }
        #expect(validated == .object(input))
        input[field] = field == "view_range" ? .array([.number(1.5), .number(2)]) : .number(1.5)
        guard case .failure = await schema.validate(JSONValue.object(input)) else { Issue.record("Expected fractional action count rejection"); return }
    }

    @Test("Computer scrolling accepts whole click counts", arguments: [20250124, 20251124, 20260801])
    func scrollingCounts(_ version: Int) async throws {
        let tool: Tool
        switch version {
        case 20250124: tool = anthropicTools.computer20250124(.init(displayWidthPx: 1024, displayHeightPx: 768))
        case 20251124: tool = anthropicTools.computer20251124(.init(displayWidthPx: 1024, displayHeightPx: 768))
        default: tool = anthropicTools.computerToolset20260801()
        }
        let schema = tool.inputSchema.resolve()
        var input: [String: JSONValue] = ["action": .string("scroll"), "scroll_amount": .number(2), "scroll_direction": .string("down")]
        guard case .success(let validated) = await schema.validate(JSONValue.object(input)) else { Issue.record("Expected integer scroll count"); return }
        #expect(validated == .object(input))
        input["scroll_amount"] = .number(1.5)
        guard case .failure = await schema.validate(JSONValue.object(input)) else { Issue.record("Expected fractional scroll count rejection"); return }
    }

    @Test("Advisor results preserve text, encrypted output and typed failures")
    func advisorResults() async throws {
        let schema = try #require(anthropicTools.advisor20260301(.init(model: "claude-opus-4-7")).outputSchema).resolve()
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
            "type": .string("advisor_result"), "text": .string("advice"), "stopReason": .number(1),
        ])) else {
            Issue.record("Expected advisor stopReason to require a string")
            return
        }
    }
}
