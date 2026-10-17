import Foundation
import AISDKProvider
import AISDKProviderUtils

func convertToAlibabaChatMessages(prompt: LanguageModelV4Prompt, cacheControlValidator: CacheControlValidator? = nil, preserveThinking: Bool = false) throws -> [JSONValue] {
    let lastUser = prompt.lastIndex { if case .user = $0 { true } else { false } } ?? -1
    var messages: [JSONValue] = []
    for (index, message) in prompt.enumerated() {
        let options: SharedV4ProviderOptions?
        switch message {
        case .system(_, let value), .user(_, let value), .assistant(_, let value), .tool(_, let value): options = value
        }
        let messageCache = cacheControlValidator?.getCacheControl(options)
        switch message {
        case .system(let text, _):
            messages.append(["role": "system", "content": messageCache.map { [["type": "text", "text": .string(text), "cache_control": $0]] } ?? .string(text)])
        case .user(let parts, _):
            let content = try parts.enumerated().map { position, part -> JSONValue in
                let options: SharedV4ProviderOptions?
                switch part { case .text(let value): options = value.providerOptions; case .file(let value): options = value.providerOptions }
                let cache = cacheControlValidator?.getCacheControl(options) ?? (position == parts.count - 1 ? messageCache : Optional<JSONValue>.none)
                var value: JSONObject
                switch part {
                case .text(let text): value = ["type": "text", "text": .string(text.text)]
                case .file(let file):
                    switch file.data {
                    case .reference: throw UnsupportedFunctionalityError(functionality: "file parts with provider references")
                    case .text: throw UnsupportedFunctionalityError(functionality: "text file parts")
                    case .url, .data, .base64: break
                    }
                    guard getTopLevelMediaType(file.mediaType) == "image" else { throw UnsupportedFunctionalityError(functionality: "Only image file parts are supported") }
                    let url: String
                    switch file.data {
                    case .url(let value, let original): url = original ?? value.absoluteString
                    case .data(let value): url = "data:\(try resolveFullMediaType(part: file));base64,\(value.base64EncodedString())"
                    case .base64(let value): url = "data:\(try resolveFullMediaType(part: file));base64,\(value)"
                    case .reference, .text: throw UnsupportedFunctionalityError(functionality: "file data type")
                    }
                    value = ["type": "image_url", "image_url": ["url": .string(url)]]
                }
                if let cache { value["cache_control"] = cache }
                return .object(value)
            }
            messages.append(["role": "user", "content": .array(content)])
        case .assistant(let parts, _):
            var text = ""
            var reasoning = ""
            var tools: [JSONValue] = []
            for part in parts {
                switch part {
                case .text(let value): text += value.text
                case .reasoning(let value): if preserveThinking || index > lastUser { reasoning += value.text }
                case .toolCall(let call): tools.append(["id": .string(call.toolCallId), "type": "function", "function": ["name": .string(call.toolName), "arguments": .string(try alibabaJSONString(call.input))]])
                case .file, .toolResult, .reasoningFile, .custom: break
                }
            }
            guard !text.isEmpty || !tools.isEmpty || !reasoning.isEmpty else { continue }
            let content: JSONValue
            if text.isEmpty && tools.isEmpty && !reasoning.isEmpty { content = .null }
            else if let cache = messageCache { content = [["type": "text", "text": .string(text), "cache_control": cache]] }
            else { content = text.isEmpty ? .null : .string(text) }
            var value: JSONObject = ["role": "assistant", "content": content]
            if !reasoning.isEmpty { value["reasoning_content"] = .string(reasoning) }
            if !tools.isEmpty { value["tool_calls"] = .array(tools) }
            messages.append(.object(value))
        case .tool(let parts, _):
            let results = parts.compactMap { part -> LanguageModelV4ToolResultPart? in if case .toolResult(let value) = part { value } else { nil } }
            for (position, result) in results.enumerated() {
                let cache = cacheControlValidator?.getCacheControl(result.providerOptions) ?? (position == results.count - 1 ? messageCache : Optional<JSONValue>.none)
                let output: String
                switch result.output {
                case .text(let value, _), .errorText(let value, _): output = value
                case .executionDenied(let reason, _): output = reason ?? "Tool call execution denied."
                case .json(let value, _), .errorJson(let value, _): output = try alibabaJSONString(value)
                case .content(let value): output = try alibabaJSONString(value)
                }
                let content: JSONValue = cache.map { [["type": "text", "text": .string(output), "cache_control": $0]] } ?? .string(output)
                messages.append(["role": "tool", "tool_call_id": .string(result.toolCallId), "content": content])
            }
        }
    }
    return messages
}

func alibabaJSONString<Value: Encodable>(_ value: Value) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}
