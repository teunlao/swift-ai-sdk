import AISDKProvider
import AISDKProviderUtils

private indirect enum WireField: Sendable {
    case string, number, bool, any
    case literal(String), enumeration([String])
    case array(WireField), record(WireField)
    case object([String: WireField], loose: Bool = false)
    case optional(WireField), nullable(WireField), tagged([String: WireField]), union([WireField])

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
        case (.string, .string), (.bool, .bool): return value
        case (.number, .number(let number)) where number.isFinite: return value
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

private func tagged(_ variants: [String: [String: WireField]]) -> WireField {
    .tagged(variants.mapValues { WireField.object($0) })
}

private let responseStrings: WireField = .array(.string)
private let responseStatus: WireField = .enumeration(["in_progress", "completed", "incomplete"])
private let responseLogprobs: WireField = .array(.object([
    "token": .string, "logprob": .number,
    "top_logprobs": .array(.object(["token": .string, "logprob": .number]))
]))
private let responseAnnotation: WireField = tagged([
    "url_citation": ["type": .literal("url_citation"), "start_index": .number, "end_index": .number, "url": .string, "title": .string],
    "file_citation": ["type": .literal("file_citation"), "file_id": .string, "filename": .string, "index": .number],
    "container_file_citation": ["type": .literal("container_file_citation"), "container_id": .string, "file_id": .string, "filename": .string, "start_index": .number, "end_index": .number],
    "file_path": ["type": .literal("file_path"), "file_id": .string, "index": .number]
])
private let responseWebAction: WireField = tagged([
    "search": ["type": .literal("search"), "query": WireField.string.nullish, "queries": responseStrings.nullish,
               "sources": WireField.array(tagged(["url": ["type": .literal("url"), "url": .string], "api": ["type": .literal("api"), "name": .string]])).nullish],
    "open_page": ["type": .literal("open_page"), "url": WireField.string.nullish],
    "find_in_page": ["type": .literal("find_in_page"), "url": WireField.string.nullish, "pattern": WireField.string.nullish]
])
private let responseComputerAction: WireField = {
    let keys = responseStrings.nullish
    let point: [String: WireField] = ["x": .number, "y": .number, "keys": keys]
    func pointFields(_ type: String, extra: [String: WireField] = [:]) -> [String: WireField] {
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
private let responseMCPError: WireField = .union([
    .string, .object(["type": WireField.string.optional, "code": WireField.union([.string, .number]).optional, "message": WireField.string.optional], loose: true)
])
private let responsePatch: WireField = tagged([
    "create_file": ["type": .literal("create_file"), "path": .string, "diff": .string],
    "delete_file": ["type": .literal("delete_file"), "path": .string],
    "update_file": ["type": .literal("update_file"), "path": .string, "diff": .string]
])
private let responseOutputFields: [String: [String: WireField]] = [
    "message": ["type": .literal("message"), "role": .literal("assistant"), "id": .string,
                "phase": WireField.enumeration(["commentary", "final_answer"]).nullish,
                "content": .array(.object(["type": .literal("output_text"), "text": .string, "logprobs": responseLogprobs.nullish, "annotations": .array(responseAnnotation)]))],
    "web_search_call": ["type": .literal("web_search_call"), "id": .string, "status": .string, "action": responseWebAction.nullish],
    "file_search_call": ["type": .literal("file_search_call"), "id": .string, "queries": responseStrings,
                         "results": WireField.array(.object(["attributes": .record(.union([.string, .number, .bool])), "file_id": .string, "filename": .string, "score": .number, "text": .string])).nullish],
    "code_interpreter_call": ["type": .literal("code_interpreter_call"), "id": .string, "code": .nullable(.string), "container_id": .string,
                              "outputs": .nullable(.array(tagged(["logs": ["type": .literal("logs"), "logs": .string], "image": ["type": .literal("image"), "url": .string]])))],
    "image_generation_call": ["type": .literal("image_generation_call"), "id": .string, "result": .string],
    "local_shell_call": ["type": .literal("local_shell_call"), "id": .string, "call_id": .string,
                         "action": .object(["type": .literal("exec"), "command": responseStrings, "timeout_ms": WireField.number.optional, "user": WireField.string.optional, "working_directory": WireField.string.optional, "env": WireField.record(.string).optional])],
    "function_call": ["type": .literal("function_call"), "id": .string, "call_id": .string, "name": .string, "arguments": .string,
                      "async": WireField.bool.nullish, "namespace": WireField.string.nullish,
                      "caller": tagged(["direct": ["type": .literal("direct")], "program": ["type": .literal("program"), "caller_id": .string]]).nullish],
    "program": ["type": .literal("program"), "id": .string, "call_id": .string, "code": .string, "fingerprint": .string],
    "program_output": ["type": .literal("program_output"), "id": .string, "call_id": .string, "result": .string, "status": .enumeration(["completed", "incomplete"])],
    "custom_tool_call": ["type": .literal("custom_tool_call"), "id": .string, "call_id": .string, "name": .string, "input": .string, "async": WireField.bool.nullish],
    "computer_call": ["type": .literal("computer_call"), "id": .string, "call_id": WireField.string.nullish, "status": responseStatus,
                      "action": responseComputerAction.nullish, "actions": WireField.array(responseComputerAction).nullish,
                      "pending_safety_checks": WireField.array(.object(["id": .string, "code": WireField.string.nullish, "message": WireField.string.nullish])).nullish],
    "reasoning": ["type": .literal("reasoning"), "id": .string, "encrypted_content": WireField.string.nullish,
                  "summary": .array(.object(["type": .literal("summary_text"), "text": .string]))],
    "mcp_call": ["type": .literal("mcp_call"), "id": .string, "status": .string, "arguments": .string, "name": .string, "server_label": .string,
                 "output": WireField.string.nullish, "error": responseMCPError.nullish, "approval_request_id": WireField.string.nullish],
    "mcp_list_tools": ["type": .literal("mcp_list_tools"), "id": .string, "server_label": .string,
                       "tools": .array(.object(["name": .string, "description": WireField.string.optional, "input_schema": .any, "annotations": WireField.record(.any).optional])), "error": responseMCPError.optional],
    "mcp_approval_request": ["type": .literal("mcp_approval_request"), "id": .string, "server_label": .string, "name": .string, "arguments": .string, "approval_request_id": WireField.string.optional],
    "apply_patch_call": ["type": .literal("apply_patch_call"), "id": .string, "call_id": .string, "status": .enumeration(["in_progress", "completed"]), "operation": responsePatch],
    "shell_call": ["type": .literal("shell_call"), "id": .string, "call_id": .string, "status": responseStatus, "action": .object(["commands": responseStrings])],
    "compaction": ["type": .literal("compaction"), "id": .string, "encrypted_content": .string],
    "shell_call_output": ["type": .literal("shell_call_output"), "id": .string, "call_id": .string, "status": responseStatus,
                          "output": .array(.object(["stdout": .string, "stderr": .string, "outcome": tagged(["timeout": ["type": .literal("timeout")], "exit": ["type": .literal("exit"), "exit_code": .number]])]))],
    "tool_search_call": ["type": .literal("tool_search_call"), "id": .string, "execution": .enumeration(["server", "client"]), "call_id": .nullable(.string), "status": responseStatus, "arguments": .any],
    "tool_search_output": ["type": .literal("tool_search_output"), "id": .string, "execution": .enumeration(["server", "client"]), "call_id": .nullable(.string), "status": responseStatus, "tools": .array(.record(.any))]
]
private let responseOutput = tagged(responseOutputFields)
private let responseUsage: WireField = .object([
    "input_tokens": .number, "output_tokens": .number, "total_tokens": WireField.number.optional,
    "input_tokens_details": WireField.object(["cached_tokens": WireField.number.nullish, "cache_write_tokens": WireField.number.nullish, "orchestration_input_tokens": WireField.number.nullish, "orchestration_input_cached_tokens": WireField.number.nullish], loose: true).nullish,
    "output_tokens_details": WireField.object(["reasoning_tokens": WireField.number.nullish, "orchestration_output_tokens": WireField.number.nullish], loose: true).nullish
], loose: true)
private let responseFields: [String: WireField] = [
    "id": WireField.string.optional, "created_at": WireField.number.optional, "model": WireField.string.optional,
    "error": WireField.object(["message": .string, "type": .string, "code": .string, "param": WireField.string.nullish]).nullish,
    "output": WireField.array(responseOutput).optional,
    "service_tier": WireField.string.nullish,
    "reasoning": WireField.object(["context": WireField.string.nullish]).nullish,
    "incomplete_details": WireField.object(["reason": .string]).nullish,
    "usage": responseUsage.nullish
]
private let responseObject: WireField = .object(responseFields)

private func streamItems(added: Bool) -> WireField {
    var variants = responseOutputFields
    func keep(_ type: String, _ keys: Set<String>) -> [String: WireField] {
        variants[type]!.filter { keys.contains($0.key) }
    }
    variants["message"] = keep("message", ["type", "id", "phase"])
    variants["reasoning"] = keep("reasoning", ["type", "id", "encrypted_content"])
    if added {
        variants["web_search_call"] = keep("web_search_call", ["type", "id", "status"])
        for type in ["file_search_call", "image_generation_call", "mcp_list_tools", "mcp_approval_request"] {
            variants[type] = keep(type, ["type", "id"])
        }
        variants["mcp_call"] = keep("mcp_call", ["type", "id", "status", "approval_request_id"])
        variants["code_interpreter_call"]?["status"] = .string
        variants["compaction"]?["encrypted_content"] = WireField.string.nullish
    } else {
        variants["function_call"]?["status"] = responseStatus
        variants["custom_tool_call"]?["status"] = .literal("completed")
    }
    return tagged(variants)
}

private let streamChunks: [String: WireField] = {
    var chunks: [String: WireField] = [:]
    func event(_ type: String, _ fields: [String: WireField]) {
        chunks[type] = .object(fields.merging(["type": .literal(type)]) { _, new in new })
    }
    event("response.output_item.added", ["output_index": .number, "item": streamItems(added: true)])
    event("response.output_item.done", ["output_index": .number, "item": streamItems(added: false)])
    event("response.output_text.delta", ["item_id": .string, "output_index": WireField.number.nullish, "delta": .string, "logprobs": responseLogprobs.nullish])
    let terminal = responseFields.filter { ["usage", "incomplete_details", "reasoning", "service_tier"].contains($0.key) }
    for type in ["response.completed", "response.incomplete"] { event(type, ["response": .object(terminal)]) }
    event("response.failed", ["sequence_number": .number, "response": .object(terminal.merging([
        "error": WireField.object(["code": WireField.string.nullish, "message": .string]).nullish
    ]) { _, new in new })])
    let created: WireField = .object(["id": .string, "created_at": .number, "model": .string, "service_tier": responseFields["service_tier"]!])
    for type in ["response.created", "response.in_progress"] { event(type, ["response": created]) }
    for type in ["response.function_call_arguments.delta", "response.custom_tool_call_input.delta", "response.code_interpreter_call_code.delta", "response.apply_patch_call_operation_diff.delta"] {
        var fields: [String: WireField] = ["item_id": .string, "output_index": .number, "delta": .string]
        if type == "response.apply_patch_call_operation_diff.delta" { fields["obfuscation"] = WireField.string.nullish }
        event(type, fields)
    }
    for (type, key) in [
        ("response.function_call_arguments.done", "arguments"), ("response.code_interpreter_call_code.done", "code"),
        ("response.image_generation_call.partial_image", "partial_image_b64"), ("response.apply_patch_call_operation_diff.done", "diff")
    ] { event(type, ["item_id": .string, "output_index": .number, key: .string]) }
    event("response.output_text.annotation.added", ["annotation": responseAnnotation])
    for type in ["response.reasoning_summary_part.added", "response.reasoning_summary_part.done", "response.reasoning_summary_text.delta"] {
        var fields: [String: WireField] = ["item_id": .string, "output_index": WireField.number.nullish, "summary_index": .number]
        if type == "response.reasoning_summary_text.delta" { fields["delta"] = .string }
        event(type, fields)
    }
    chunks["error"] = .union([
        .object(["type": .literal("error"), "sequence_number": .number, "error": .object([
            "type": .string, "code": WireField.string.nullish, "message": .string, "param": WireField.string.nullish
        ])]),
        .object(["type": .literal("error"), "sequence_number": .number, "code": WireField.string.nullish, "message": .string, "param": WireField.string.nullish])
    ])
    return chunks
}()

func projectOpenAIResponsesChunk(_ value: JSONValue) throws -> JSONValue {
    guard case .object(let fields) = value, case .string(let type)? = fields["type"] else {
        throw TypeValidationError.wrap(value: value, cause: SchemaValidationIssuesError(vendor: "openai", issues: "Expected Responses event type"))
    }
    let isUnknownItem: Bool = {
        guard type == "response.output_item.added" || type == "response.output_item.done",
              case .object(let item)? = fields["item"], case .string(let itemType)? = item["type"] else { return false }
        return responseOutputFields[itemType] == nil
    }()
    guard let schema = streamChunks[type], !isUnknownItem else {
        return .object(["type": .string("unknown_chunk"), "message": .string(type)])
    }
    return try schema.parse(value)!
}

func projectOpenAIResponsesResponse(_ value: JSONValue) throws -> JSONValue {
    try responseObject.parse(value)!
}
