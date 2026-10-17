import Foundation
import AISDKProvider

func parseAnthropicToolResult(_ value: JSONValue, block: String) throws -> JSONValue {
    if block == "web_search_tool_result", case .array(let results) = value {
        return .array(try results.map { value in
            let object = try wireObject(value)
            try wireLiteral(object, "type", "web_search_result")
            try wireString(object, "url")
            try wireString(object, "title", nullable: true)
            try wireString(object, "encrypted_content")
            if object["page_age"] != nil { try wireString(object, "page_age", nullable: true) }
            return .object(object.filter { ["type", "url", "title", "encrypted_content", "page_age"].contains($0.key) })
        })
    }
    var object = try wireObject(value)
    guard case .string(let type) = object["type"] else { throw wireError("Missing tool result type") }
    if type.hasSuffix("_tool_result_error") {
        let expected = block.replacingOccurrences(of: "_tool_result", with: "_tool_result_error")
        guard type == expected else { throw wireError("Invalid tool error type") }
        try wireString(object, "error_code")
        return .object(object.filter { $0.key == "type" || $0.key == "error_code" })
    }
    var keys = ["type"]
    switch (block, type) {
    case ("web_fetch_tool_result", "web_fetch_result"):
        try wireString(object, "url")
        try wireString(object, "retrieved_at", nullable: true)
        var document = try wireObject(object["content"] ?? .null)
        try wireLiteral(document, "type", "document")
        try wireString(document, "title", nullable: true)
        if let citations = document["citations"] {
            let citations = try wireObject(citations)
            try wireBoolean(citations, "enabled")
            document["citations"] = .object(citations.filter { $0.key == "enabled" })
        }
        let source = try wireObject(document["source"] ?? .null)
        let isPDF = source["type"] == .string("base64") && source["media_type"] == .string("application/pdf")
        let isText = source["type"] == .string("text") && source["media_type"] == .string("text/plain")
        guard isPDF || isText else { throw wireError("Invalid fetched document source") }
        try wireString(source, "data")
        document["source"] = .object(source.filter { ["type", "media_type", "data"].contains($0.key) })
        object["content"] = .object(document.filter { ["type", "title", "citations", "source"].contains($0.key) })
        keys += ["url", "retrieved_at", "content"]
    case ("code_execution_tool_result", "code_execution_result"),
         ("code_execution_tool_result", "encrypted_code_execution_result"),
         ("bash_code_execution_tool_result", "bash_code_execution_result"):
        let stdoutKey = type == "encrypted_code_execution_result" ? "encrypted_stdout" : "stdout"
        try wireString(object, stdoutKey)
        try wireString(object, "stderr")
        try wireInteger(object, "return_code")
        if let content = object["content"] {
            guard case .array(let files) = content else { throw wireError("Invalid code output files") }
            object["content"] = .array(try files.map { file in
                let file = try wireObject(file)
                try wireLiteral(file, "type", type == "bash_code_execution_result" ? "bash_code_execution_output" : "code_execution_output")
                try wireString(file, "file_id")
                return .object(file.filter { $0.key == "type" || $0.key == "file_id" })
            })
        } else if block == "bash_code_execution_tool_result" {
            throw wireError("Missing bash output files")
        } else {
            object["content"] = .array([])
        }
        keys += [stdoutKey, "stderr", "return_code", "content"]
    case ("text_editor_code_execution_tool_result", "text_editor_code_execution_create_result"):
        try wireBoolean(object, "is_file_update")
        keys += ["is_file_update"]
    case ("text_editor_code_execution_tool_result", "text_editor_code_execution_view_result"):
        try wireString(object, "content")
        try wireString(object, "file_type")
        for key in ["num_lines", "start_line", "total_lines"] { try wireInteger(object, key, nullable: true) }
        keys += ["content", "file_type", "num_lines", "start_line", "total_lines"]
    case ("text_editor_code_execution_tool_result", "text_editor_code_execution_str_replace_result"):
        if object["lines"] != .null {
            guard case .array(let lines) = object["lines"], lines.allSatisfy({ if case .string = $0 { return true }; return false }) else { throw wireError("Invalid text editor lines") }
        }
        for key in ["new_lines", "new_start", "old_lines", "old_start"] { try wireInteger(object, key, nullable: true) }
        keys += ["lines", "new_lines", "new_start", "old_lines", "old_start"]
    case ("tool_search_tool_result", "tool_search_tool_search_result"):
        guard case .array(let references) = object["tool_references"] else { throw wireError("Missing tool references") }
        for reference in references {
            let reference = try wireObject(reference)
            try wireLiteral(reference, "type", "tool_reference")
            try wireString(reference, "tool_name")
        }
        keys += ["tool_references"]
    case ("advisor_tool_result", "advisor_result"), ("advisor_tool_result", "advisor_redacted_result"):
        let key = type == "advisor_result" ? "text" : "encrypted_content"
        try wireString(object, key)
        if object["stop_reason"] != nil { try wireString(object, "stop_reason", nullable: true) }
        keys += [key, "stop_reason"]
    default:
        throw wireError("Invalid \(block) content type: \(type)")
    }
    return .object(object.filter { keys.contains($0.key) })
}

private func wireObject(_ value: JSONValue) throws -> [String: JSONValue] {
    guard case .object(let object) = value else { throw wireError("Expected object") }
    return object
}

private func wireString(_ object: [String: JSONValue], _ key: String, nullable: Bool = false) throws {
    if nullable && object[key] == .null { return }
    guard case .string = object[key] else { throw wireError("Expected string at \(key)") }
}

private func wireInteger(_ object: [String: JSONValue], _ key: String, nullable: Bool = false) throws {
    if nullable && object[key] == .null { return }
    guard case .number(let number) = object[key], Int(exactly: number) != nil else { throw wireError("Expected representable integer at \(key)") }
}

private func wireBoolean(_ object: [String: JSONValue], _ key: String) throws {
    guard case .bool = object[key] else { throw wireError("Expected boolean at \(key)") }
}

private func wireLiteral(_ object: [String: JSONValue], _ key: String, _ value: String) throws {
    guard object[key] == .string(value) else { throw wireError("Expected \(value) at \(key)") }
}

private func wireError(_ message: String) -> DecodingError {
    .dataCorrupted(.init(codingPath: [], debugDescription: message))
}
