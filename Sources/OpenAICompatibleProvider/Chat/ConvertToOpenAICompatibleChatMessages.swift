import Foundation
import AISDKProvider
import AISDKProviderUtils

private func compatibleMetadata(_ options: SharedV4ProviderOptions?) -> [String: JSONValue] { options?["openaiCompatible"] ?? [:] }
private func compatibleJSON<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}
private func compatibleSignature(_ options: SharedV4ProviderOptions?, key: String) -> String? {
    func truthy(_ value: JSONValue?) -> Bool {
        switch value {
        case nil, .null: return false
        case .bool(let value): return value
        case .number(let value): return value != 0 && !value.isNaN
        case .string(let value): return !value.isEmpty
        case .array, .object: return true
        }
    }
    func string(_ value: JSONValue) -> String {
        switch value {
        case .string(let value): return value
        case .number(let value): return Int(exactly: value).map(String.init) ?? String(value)
        case .bool(let value): return value ? "true" : "false"
        case .null: return "null"
        case .object: return "[object Object]"
        case .array(let values): return values.map { $0 == .null ? "" : string($0) }.joined(separator: ",")
        }
    }
    let selected = options?[key]?["thoughtSignature"]
    let value = truthy(selected) ? selected : options?["google"]?["thoughtSignature"]
    guard let value, truthy(value) else { return nil }
    return string(value)
}
private func compatibleFile(_ part: LanguageModelV4FilePart, provider: String) throws -> JSONValue {
    var value: [String: JSONValue]
    if case .reference(let reference) = part.data {
        value = ["type": "file", "file": ["file_id": .string(try resolveProviderReference(reference: reference, provider: provider))]]
    } else {
        if case .text = part.data { throw UnsupportedFunctionalityError(functionality: "text file parts") }
        func base64() throws -> String {
            switch part.data {
            case .data(let data): return data.base64EncodedString()
            case .base64(let value): return value
            default: throw UnsupportedFunctionalityError(functionality: "inline file data")
            }
        }
        switch getTopLevelMediaType(part.mediaType) {
        case "image", "video":
            let url: String
            if case .url(let source, _) = part.data { url = source.absoluteString }
            else { url = "data:\(try resolveFullMediaType(part: part));base64,\(try base64())" }
            if getTopLevelMediaType(part.mediaType) == "video" { value = ["type": "video_url", "video_url": ["url": .string(url)]] }
            else { value = ["type": "image_url", "image_url": ["url": .string(url)]] }
        case "audio":
            if case .url = part.data { throw UnsupportedFunctionalityError(functionality: "audio file parts with URLs") }
            let mediaType = try resolveFullMediaType(part: part)
            let format: String
            switch mediaType {
            case "audio/wav", "audio/wave", "audio/x-wav": format = "wav"
            case "audio/mpeg", "audio/mp3": format = "mp3"
            default: throw UnsupportedFunctionalityError(functionality: "audio media type \(mediaType)")
            }
            value = ["type": "input_audio", "input_audio": ["data": .string(try base64()), "format": .string(format)]]
        case "application":
            if case .url = part.data { throw UnsupportedFunctionalityError(functionality: "PDF file parts with URLs") }
            let mediaType = try resolveFullMediaType(part: part)
            guard mediaType == "application/pdf" else { throw UnsupportedFunctionalityError(functionality: "file part media type \(mediaType)") }
            value = ["type": "file", "file": ["filename": .string(part.filename ?? "document.pdf"), "file_data": .string("data:application/pdf;base64,\(try base64())")]]
        case "text":
            let text: String
            switch part.data {
            case .url(let url, _): text = url.absoluteString
            case .data(let data): text = String(decoding: data, as: UTF8.self)
            case .base64(let data): text = String(decoding: try convertBase64ToData(data), as: UTF8.self)
            default: throw UnsupportedFunctionalityError(functionality: "text file data")
            }
            value = ["type": "text", "text": .string(text)]
        default: throw UnsupportedFunctionalityError(functionality: "file part media type \(part.mediaType)")
        }
    }
    value.merge(compatibleMetadata(part.providerOptions)) { _, new in new }
    return .object(value)
}

public func convertToOpenAICompatibleChatMessages(
    prompt: LanguageModelV4Prompt,
    provider: String = "openaiCompatible",
    providerOptionsKey: String = "google",
    supportsMultiPartToolContent: Bool = false
) throws -> [JSONValue] {
    var messages: [JSONValue] = []
    for message in prompt {
        var payload: [String: JSONValue]
        switch message {
        case .system(let content, let options):
            payload = ["role": "system", "content": .string(content)]
            payload.merge(compatibleMetadata(options)) { _, new in new }
        case .user(let parts, let options):
            if parts.count == 1, case .text(let text) = parts[0] {
                payload = ["role": "user", "content": .string(text.text)]
                payload.merge(compatibleMetadata(text.providerOptions)) { _, new in new }
            } else {
                let content = try parts.map { part -> JSONValue in
                    switch part {
                    case .text(let text):
                        var value: [String: JSONValue] = ["type": "text", "text": .string(text.text)]
                        value.merge(compatibleMetadata(text.providerOptions)) { _, new in new }
                        return .object(value)
                    case .file(let file): return try compatibleFile(file, provider: provider)
                    }
                }
                payload = ["role": "user", "content": .array(content)]
                payload.merge(compatibleMetadata(options)) { _, new in new }
            }
        case .assistant(let parts, let options):
            var text = ""
            var reasoning = ""
            var tools: [JSONValue] = []
            for part in parts {
                switch part {
                case .text(let value): text += value.text
                case .reasoning(let value): reasoning += value.text
                case .toolCall(let value):
                    var tool: [String: JSONValue] = ["id": .string(value.toolCallId), "type": "function", "function": ["name": .string(value.toolName), "arguments": .string(try compatibleJSON(value.input))]]
                    tool.merge(compatibleMetadata(value.providerOptions)) { _, new in new }
                    if let signature = compatibleSignature(value.providerOptions, key: providerOptionsKey) { tool["extra_content"] = ["google": ["thought_signature": .string(signature)]] }
                    tools.append(.object(tool))
                default: break
                }
            }
            payload = ["role": "assistant", "content": !tools.isEmpty && text.isEmpty ? .null : .string(text)]
            if !reasoning.isEmpty { payload["reasoning_content"] = .string(reasoning) }
            if !tools.isEmpty { payload["tool_calls"] = .array(tools) }
            payload.merge(compatibleMetadata(options)) { _, new in new }
        case .tool(let parts, _):
            for part in parts {
                guard case .toolResult(let result) = part else { continue }
                let content: JSONValue
                switch result.output {
                case .text(let text, _), .errorText(let text, _): content = .string(text)
                case .executionDenied(let reason, _): content = .string(reason ?? "Tool call execution denied.")
                case .json(let value, _), .errorJson(let value, _): content = .string(try compatibleJSON(value))
                case .content(let values):
                    if !supportsMultiPartToolContent { content = .string(try compatibleJSON(values)) }
                    else {
                        content = .array(try values.map { value in
                            switch value {
                            case .text(let text, let options):
                                var item: [String: JSONValue] = ["type": "text", "text": .string(text)]
                                item.merge(compatibleMetadata(options)) { _, new in new }
                                return .object(item)
                            case .file(let data, let mediaType, let filename, let options):
                                return try compatibleFile(.init(data: data, mediaType: mediaType, filename: filename, providerOptions: options), provider: provider)
                            case .custom: throw UnsupportedFunctionalityError(functionality: "tool content part type custom")
                            }
                        })
                    }
                }
                var tool: [String: JSONValue] = ["role": "tool", "tool_call_id": .string(result.toolCallId), "content": content]
                tool.merge(compatibleMetadata(result.providerOptions)) { _, new in new }
                messages.append(.object(tool))
            }
            continue
        }
        messages.append(.object(payload))
    }
    return messages
}
