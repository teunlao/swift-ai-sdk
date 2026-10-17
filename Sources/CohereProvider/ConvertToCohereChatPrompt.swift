import Foundation
import AISDKProvider
import AISDKProviderUtils

func convertToCohereChatPrompt(_ prompt: LanguageModelV4Prompt) async throws -> CohereChatPromptConversion {
    var messages: [JSONValue] = []
    var documents: [JSONValue] = []
    for message in prompt {
        switch message {
        case .system(let content, _): messages.append(["role": "system", "content": .string(content)])
        case .user(let parts, _):
            var content: [JSONValue] = []
            var text = ""
            var hasImage = false
            for part in parts {
                switch part {
                case .text(let value):
                    if !value.text.isEmpty {
                        text += value.text
                        content.append(["type": "text", "text": .string(value.text)])
                    }
                case .file(let file):
                    if getTopLevelMediaType(file.mediaType) == "image" {
                        hasImage = true
                        let url = try cohereImageUrl(file)
                        let options = try await parseProviderOptions(provider: "cohere", providerOptions: file.providerOptions, schema: cohereImagePartProviderOptions)
                        var image: JSONObject = ["url": .string(url)]
                        if let detail = options?.detail { image["detail"] = .string(detail.rawValue) }
                        content.append(["type": "image_url", "image_url": .object(image)])
                    } else {
                        let documentText: String
                        switch file.data {
                        case .reference: throw UnsupportedFunctionalityError(functionality: "file parts with provider references")
                        case .url:
                            throw UnsupportedFunctionalityError(functionality: "File URL data", message: "URLs should be downloaded by the AI SDK and not reach this point. This indicates a configuration issue.")
                        case .text(let value): documentText = value
                        case .base64(let value): documentText = value
                        case .data(let data):
                            var bytes = data
                            if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes.removeFirst(3) }
                            documentText = String(decoding: bytes, as: UTF8.self)
                        }
                        var data: JSONObject = ["text": .string(documentText)]
                        if let title = file.filename { data["title"] = .string(title) }
                        documents.append(["data": .object(data)])
                    }
                }
            }
            messages.append(["role": "user", "content": hasImage ? .array(content) : .string(text)])
        case .assistant(let parts, _):
            var text = ""
            var tools: [JSONValue] = []
            for part in parts {
                switch part {
                case .text(let value): text += value.text
                case .toolCall(let call):
                    tools.append(["id": .string(call.toolCallId), "type": "function", "function": ["name": .string(call.toolName), "arguments": .string(try cohereJSONString(call.input))]])
                case .reasoning, .reasoningFile, .file, .toolResult, .custom: break
                }
            }
            var payload: JSONObject = ["role": "assistant"]
            if tools.isEmpty { payload["content"] = .string(text) }
            else { payload["tool_calls"] = .array(tools) }
            messages.append(.object(payload))
        case .tool(let parts, _):
            for part in parts {
                guard case .toolResult(let result) = part else { continue }
                let content: String
                switch result.output {
                case .text(let value, _), .errorText(let value, _): content = value
                case .executionDenied(let reason, _): content = reason ?? "Tool call execution denied."
                case .json(let value, _), .errorJson(let value, _): content = try cohereJSONString(value)
                case .content(let value): content = try cohereJSONString(value)
                }
                messages.append(["role": "tool", "tool_call_id": .string(result.toolCallId), "content": .string(content)])
            }
        }
    }
    return .init(messages: messages, documents: documents, warnings: [])
}

private func cohereImageUrl(_ file: LanguageModelV4FilePart) throws -> String {
    switch file.data {
    case .url(let value, let original): return original ?? value.absoluteString
    case .data(let value): return "data:\(try resolveFullMediaType(part: file));base64,\(value.base64EncodedString())"
    case .base64(let value): return "data:\(try resolveFullMediaType(part: file));base64,\(value)"
    case .reference: throw UnsupportedFunctionalityError(functionality: "image file parts with provider references")
    case .text: throw UnsupportedFunctionalityError(functionality: "image file parts with text data")
    }
}

func cohereJSONString<Value: Encodable>(_ value: Value) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}
