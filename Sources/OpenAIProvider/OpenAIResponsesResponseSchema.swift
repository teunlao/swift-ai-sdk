import AISDKProvider
import AISDKProviderUtils

private indirect enum ResponseField: Sendable {
    case string, number, bool, any
    case literal(String), enumeration([String])
    case array(ResponseField), record(ResponseField)
    case object([String: ResponseField], loose: Bool = false)
    case optional(ResponseField), nullable(ResponseField), tagged([String: ResponseField]), union([ResponseField])

    var optional: Self { .optional(self) }
    var nullish: Self { .optional(.nullable(self)) }

    func parse(_ value: JSONValue?, path: String = "response") throws -> JSONValue? {
        if case .optional(let field) = self {
            guard let value else { return nil }
            return try field.parse(value, path: path)
        }
        if case .any = self { return value }
        guard let value else { throw invalid(.null, path) }
        switch (self, value) {
        case (.string, .string), (.number, .number), (.bool, .bool): return value
        case (.literal(let expected), .string(let actual)) where expected == actual: return value
        case (.enumeration(let allowed), .string(let actual)) where allowed.contains(actual): return value
        case (.nullable, .null): return .null
        case (.nullable(let field), _): return try field.parse(value, path: path)
        case (.array(let field), .array(let values)):
            return .array(try values.enumerated().map { try field.parse($0.element, path: "\(path)[\($0.offset)]") ?? .null })
        case (.record(let field), .object(let fields)):
            var result: [String: JSONValue] = [:]
            for (key, entry) in fields { result[key] = try field.parse(entry, path: "\(path).\(key)") }
            return .object(result)
        case (.object(let fields, let loose), .object(let values)):
            var result = loose ? values : [:]
            for (key, field) in fields { result[key] = try field.parse(values[key], path: "\(path).\(key)") }
            return .object(result)
        case (.tagged(let variants), .object(let fields)):
            guard case .string(let type)? = fields["type"], let variant = variants[type] else { throw invalid(value, path) }
            return try variant.parse(value, path: path)
        case (.union(let fields), _):
            for field in fields {
                do { return try field.parse(value, path: path) } catch is TypeValidationError { continue }
            }
            throw invalid(value, path)
        default: throw invalid(value, path)
        }
    }

    private func invalid(_ value: JSONValue, _ path: String) -> TypeValidationError {
        TypeValidationError.wrap(value: value, cause: SchemaValidationIssuesError(vendor: "openai", issues: "Invalid Responses field at \(path)"))
    }
}

private func tagged(_ variants: [String: [String: ResponseField]]) -> ResponseField {
    .tagged(variants.mapValues { ResponseField.object($0) })
}

private let responseStrings: ResponseField = .array(.string)
private let responseStatus: ResponseField = .enumeration(["in_progress", "completed", "incomplete"])
private let responseLogprobs: ResponseField = .array(.object([
    "token": .string, "logprob": .number,
    "top_logprobs": .array(.object(["token": .string, "logprob": .number]))
]))
private let responseAnnotation: ResponseField = tagged([
    "url_citation": ["type": .literal("url_citation"), "start_index": .number, "end_index": .number, "url": .string, "title": .string],
    "file_citation": ["type": .literal("file_citation"), "file_id": .string, "filename": .string, "index": .number],
    "container_file_citation": ["type": .literal("container_file_citation"), "container_id": .string, "file_id": .string, "filename": .string, "start_index": .number, "end_index": .number],
    "file_path": ["type": .literal("file_path"), "file_id": .string, "index": .number]
])
private let responseWebAction: ResponseField = tagged([
    "search": ["type": .literal("search"), "query": ResponseField.string.nullish, "queries": responseStrings.nullish,
               "sources": ResponseField.array(tagged(["url": ["type": .literal("url"), "url": .string], "api": ["type": .literal("api"), "name": .string]])).nullish],
    "open_page": ["type": .literal("open_page"), "url": ResponseField.string.nullish],
    "find_in_page": ["type": .literal("find_in_page"), "url": ResponseField.string.nullish, "pattern": ResponseField.string.nullish]
])
private let responseComputerAction: ResponseField = {
    let keys = responseStrings.nullish
    let point: [String: ResponseField] = ["x": .number, "y": .number, "keys": keys]
    func pointFields(_ type: String, extra: [String: ResponseField] = [:]) -> [String: ResponseField] {
        point.merging(extra.merging(["type": .literal(type)]) { _, new in new }) { _, new in new }
    }
    return tagged([
        "click": pointFields("click", extra: ["button": .enumeration(["left", "right", "wheel", "back", "forward"])]),
        "double_click": pointFields("double_click"),
        "drag": ["type": .literal("drag"), "path": .array(.object(["x": .number, "y": .number])), "keys": keys],
        "keypress": ["type": .literal("keypress"), "keys": responseStrings],
        "move": pointFields("move"), "screenshot": ["type": .literal("screenshot")],
        "scroll": pointFields("scroll", extra: ["scroll_x": .number, "scroll_y": .number]),
        "type": ["type": .literal("type"), "text": .string], "wait": ["type": .literal("wait")]
    ])
}()
private let responseMCPError: ResponseField = .union([
    .string, .object(["type": ResponseField.string.optional, "code": ResponseField.union([.string, .number]).optional, "message": ResponseField.string.optional], loose: true)
])
private let responsePatch: ResponseField = tagged([
    "create_file": ["type": .literal("create_file"), "path": .string, "diff": .string],
    "delete_file": ["type": .literal("delete_file"), "path": .string],
    "update_file": ["type": .literal("update_file"), "path": .string, "diff": .string]
])
private let responseOutput: ResponseField = tagged([
    "message": ["type": .literal("message"), "role": .literal("assistant"), "id": .string,
                "phase": ResponseField.enumeration(["commentary", "final_answer"]).nullish,
                "content": .array(.object(["type": .literal("output_text"), "text": .string, "logprobs": responseLogprobs.nullish, "annotations": .array(responseAnnotation)]))],
    "web_search_call": ["type": .literal("web_search_call"), "id": .string, "status": .string, "action": responseWebAction.nullish],
    "file_search_call": ["type": .literal("file_search_call"), "id": .string, "queries": responseStrings,
                         "results": ResponseField.array(.object(["attributes": .record(.union([.string, .number, .bool])), "file_id": .string, "filename": .string, "score": .number, "text": .string])).nullish],
    "code_interpreter_call": ["type": .literal("code_interpreter_call"), "id": .string, "code": .nullable(.string), "container_id": .string,
                              "outputs": .nullable(.array(tagged(["logs": ["type": .literal("logs"), "logs": .string], "image": ["type": .literal("image"), "url": .string]])))],
    "image_generation_call": ["type": .literal("image_generation_call"), "id": .string, "result": .string],
    "local_shell_call": ["type": .literal("local_shell_call"), "id": .string, "call_id": .string,
                         "action": .object(["type": .literal("exec"), "command": responseStrings, "timeout_ms": ResponseField.number.optional, "user": ResponseField.string.optional, "working_directory": ResponseField.string.optional, "env": ResponseField.record(.string).optional])],
    "function_call": ["type": .literal("function_call"), "id": .string, "call_id": .string, "name": .string, "arguments": .string,
                      "async": ResponseField.bool.nullish, "namespace": ResponseField.string.nullish,
                      "caller": tagged(["direct": ["type": .literal("direct")], "program": ["type": .literal("program"), "caller_id": .string]]).nullish],
    "program": ["type": .literal("program"), "id": .string, "call_id": .string, "code": .string, "fingerprint": .string],
    "program_output": ["type": .literal("program_output"), "id": .string, "call_id": .string, "result": .string, "status": .enumeration(["completed", "incomplete"])],
    "custom_tool_call": ["type": .literal("custom_tool_call"), "id": .string, "call_id": .string, "name": .string, "input": .string, "async": ResponseField.bool.nullish],
    "computer_call": ["type": .literal("computer_call"), "id": .string, "call_id": ResponseField.string.nullish, "status": responseStatus,
                      "action": responseComputerAction.nullish, "actions": ResponseField.array(responseComputerAction).nullish,
                      "pending_safety_checks": ResponseField.array(.object(["id": .string, "code": ResponseField.string.nullish, "message": ResponseField.string.nullish])).nullish],
    "reasoning": ["type": .literal("reasoning"), "id": .string, "encrypted_content": ResponseField.string.nullish,
                  "summary": .array(.object(["type": .literal("summary_text"), "text": .string]))],
    "mcp_call": ["type": .literal("mcp_call"), "id": .string, "status": .string, "arguments": .string, "name": .string, "server_label": .string,
                 "output": ResponseField.string.nullish, "error": responseMCPError.nullish, "approval_request_id": ResponseField.string.nullish],
    "mcp_list_tools": ["type": .literal("mcp_list_tools"), "id": .string, "server_label": .string,
                       "tools": .array(.object(["name": .string, "description": ResponseField.string.optional, "input_schema": .any, "annotations": ResponseField.record(.any).optional])), "error": responseMCPError.optional],
    "mcp_approval_request": ["type": .literal("mcp_approval_request"), "id": .string, "server_label": .string, "name": .string, "arguments": .string, "approval_request_id": ResponseField.string.optional],
    "apply_patch_call": ["type": .literal("apply_patch_call"), "id": .string, "call_id": .string, "status": .enumeration(["in_progress", "completed"]), "operation": responsePatch],
    "shell_call": ["type": .literal("shell_call"), "id": .string, "call_id": .string, "status": responseStatus, "action": .object(["commands": responseStrings])],
    "compaction": ["type": .literal("compaction"), "id": .string, "encrypted_content": .string],
    "shell_call_output": ["type": .literal("shell_call_output"), "id": .string, "call_id": .string, "status": responseStatus,
                          "output": .array(.object(["stdout": .string, "stderr": .string, "outcome": tagged(["timeout": ["type": .literal("timeout")], "exit": ["type": .literal("exit"), "exit_code": .number]])]))],
    "tool_search_call": ["type": .literal("tool_search_call"), "id": .string, "execution": .enumeration(["server", "client"]), "call_id": .nullable(.string), "status": responseStatus, "arguments": .any],
    "tool_search_output": ["type": .literal("tool_search_output"), "id": .string, "execution": .enumeration(["server", "client"]), "call_id": .nullable(.string), "status": responseStatus, "tools": .array(.record(.any))]
])
private let responseUsage: ResponseField = .object([
    "input_tokens": .number, "output_tokens": .number, "total_tokens": ResponseField.number.optional,
    "input_tokens_details": ResponseField.object(["cached_tokens": ResponseField.number.nullish, "cache_write_tokens": ResponseField.number.nullish, "orchestration_input_tokens": ResponseField.number.nullish, "orchestration_input_cached_tokens": ResponseField.number.nullish], loose: true).nullish,
    "output_tokens_details": ResponseField.object(["reasoning_tokens": ResponseField.number.nullish, "orchestration_output_tokens": ResponseField.number.nullish], loose: true).nullish
], loose: true)
private let responseObject: ResponseField = .object([
    "id": ResponseField.string.optional, "created_at": ResponseField.number.optional, "model": ResponseField.string.optional,
    "error": ResponseField.object(["message": .string, "type": .string, "code": .string, "param": ResponseField.string.nullish]).nullish,
    "output": ResponseField.array(responseOutput).optional,
    "service_tier": ResponseField.string.nullish,
    "reasoning": ResponseField.object(["context": ResponseField.string.nullish]).nullish,
    "incomplete_details": ResponseField.object(["reason": .string]).nullish,
    "usage": responseUsage.nullish
])

func projectOpenAIResponsesResponse(_ value: JSONValue) throws -> JSONValue {
    try responseObject.parse(value)!
}
