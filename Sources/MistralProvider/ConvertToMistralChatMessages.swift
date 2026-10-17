import Foundation
import AISDKProvider
import AISDKProviderUtils

public func convertToMistralChatMessages(prompt: LanguageModelV4Prompt) throws -> [JSONValue] {
    var messages: [JSONValue] = []
    for (index, message) in prompt.enumerated() {
        switch message {
        case .system(let content, _):
            messages.append(["role": "system", "content": .string(content)])
        case .user(let parts, _):
            let content = try parts.map { part -> JSONValue in
                switch part {
                case .text(let text): return ["type": "text", "text": .string(text.text)]
                case .file(let file):
                    switch file.data {
                    case .reference: throw UnsupportedFunctionalityError(functionality: "file parts with provider references")
                    case .text: throw UnsupportedFunctionalityError(functionality: "text file parts")
                    case .data, .base64, .url: break
                    }
                    let isImage = getTopLevelMediaType(file.mediaType) == "image"
                    if !isImage {
                        let mediaType: String
                        if case .url = file.data { mediaType = file.mediaType }
                        else { mediaType = try resolveFullMediaType(part: file) }
                        guard mediaType == "application/pdf" else {
                            throw UnsupportedFunctionalityError(functionality: "Only images and PDF file parts are supported")
                        }
                    }
                    let url: String
                    switch file.data {
                    case .url(let value, let original): url = original ?? value.absoluteString
                    case .data(let value): url = "data:\(try resolveFullMediaType(part: file));base64,\(value.base64EncodedString())"
                    case .base64(let value): url = "data:\(try resolveFullMediaType(part: file));base64,\(value)"
                    case .reference, .text: throw UnsupportedFunctionalityError(functionality: "file part data type")
                    }
                    return isImage ? ["type": "image_url", "image_url": .string(url)]
                        : ["type": "document_url", "document_url": .string(url)]
                }
            }
            messages.append(["role": "user", "content": .array(content)])
        case .assistant(let parts, _):
            var text = ""
            var hasReasoning = false
            var content: [JSONValue] = []
            var tools: [JSONValue] = []
            for part in parts {
                switch part {
                case .text(let value):
                    text += value.text
                    content.append(["type": "text", "text": .string(value.text)])
                case .reasoning(let value):
                    hasReasoning = true
                    content.append(["type": "thinking", "thinking": [["type": "text", "text": .string(value.text)]], "closed": true])
                case .toolCall(let value):
                    tools.append(["id": .string(value.toolCallId), "type": "function", "function": [
                        "name": .string(value.toolName), "arguments": .string(try mistralJSONString(value.input))
                    ]])
                case .file, .reasoningFile, .toolResult, .custom:
                    throw UnsupportedFunctionalityError(functionality: "Unsupported content type in assistant message")
                }
            }
            var payload: [String: JSONValue] = ["role": "assistant", "content": hasReasoning ? .array(content) : .string(text)]
            if index == prompt.count - 1 { payload["prefix"] = true }
            if !tools.isEmpty { payload["tool_calls"] = .array(tools) }
            messages.append(.object(payload))
        case .tool(let parts, _):
            for part in parts {
                guard case .toolResult(let result) = part else { continue }
                let content: String
                switch result.output {
                case .text(let value, _), .errorText(let value, _): content = value
                case .executionDenied(let reason, _): content = reason ?? "Tool call execution denied."
                case .json(let value, _), .errorJson(let value, _): content = try mistralJSONString(value)
                case .content(let values): content = try mistralJSONString(values)
                }
                messages.append(["role": "tool", "name": .string(result.toolName), "tool_call_id": .string(result.toolCallId), "content": .string(content)])
            }
        }
    }
    return messages
}

func mistralJSONString<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}
