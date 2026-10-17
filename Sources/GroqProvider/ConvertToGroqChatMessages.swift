import Foundation
import AISDKProvider
import AISDKProviderUtils

func convertToGroqChatMessages(_ prompt: LanguageModelV4Prompt) throws -> [JSONValue] {
    var messages: [JSONValue] = []
    for message in prompt {
        switch message {
        case .system(let content, _): messages.append(["role": "system", "content": .string(content)])
        case .user(let parts, _):
            if parts.count == 1, case .text(let text) = parts[0] {
                messages.append(["role": "user", "content": .string(text.text)])
                continue
            }
            let content = try parts.map { part -> JSONValue in
                switch part {
                case .text(let text): return ["type": "text", "text": .string(text.text)]
                case .file(let file):
                    switch file.data {
                    case .reference: throw UnsupportedFunctionalityError(functionality: "file parts with provider references")
                    case .text: throw UnsupportedFunctionalityError(functionality: "text file parts")
                    case .url, .data, .base64: break
                    }
                    guard getTopLevelMediaType(file.mediaType) == "image" else {
                        throw UnsupportedFunctionalityError(functionality: "Non-image file content parts")
                    }
                    let url: String
                    switch file.data {
                    case .url(let value, let original): url = original ?? value.absoluteString
                    case .data(let value): url = "data:\(try resolveFullMediaType(part: file));base64,\(value.base64EncodedString())"
                    case .base64(let value): url = "data:\(try resolveFullMediaType(part: file));base64,\(value)"
                    case .reference, .text: throw UnsupportedFunctionalityError(functionality: "file part data type")
                    }
                    return ["type": "image_url", "image_url": ["url": .string(url)]]
                }
            }
            messages.append(["role": "user", "content": .array(content)])
        case .assistant(let parts, _):
            var text = ""
            var reasoning = ""
            var tools: [JSONValue] = []
            for part in parts {
                switch part {
                case .text(let value): text += value.text
                case .reasoning(let value): reasoning += value.text
                case .toolCall(let call): tools.append(["id": .string(call.toolCallId), "type": "function", "function": ["name": .string(call.toolName), "arguments": .string(try groqJSONString(call.input))]])
                case .file, .reasoningFile, .toolResult, .custom: break
                }
            }
            var payload: JSONObject = ["role": "assistant", "content": .string(text)]
            if !reasoning.isEmpty { payload["reasoning"] = .string(reasoning) }
            if !tools.isEmpty { payload["tool_calls"] = .array(tools) }
            messages.append(.object(payload))
        case .tool(let parts, _):
            for part in parts {
                guard case .toolResult(let result) = part else { continue }
                let content: String
                switch result.output {
                case .text(let value, _), .errorText(let value, _): content = value
                case .executionDenied(let reason, _): content = reason ?? "Tool call execution denied."
                case .json(let value, _), .errorJson(let value, _): content = try groqJSONString(value)
                case .content(let value): content = try groqJSONString(value)
                }
                messages.append(["role": "tool", "tool_call_id": .string(result.toolCallId), "content": .string(content)])
            }
        }
    }
    return messages
}

func groqJSONString<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}
