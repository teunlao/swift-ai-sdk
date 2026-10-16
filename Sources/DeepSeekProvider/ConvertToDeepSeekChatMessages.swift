import Foundation
import AISDKProvider
import AISDKProviderUtils

func convertToDeepSeekChatMessages(
    prompt: LanguageModelV4Prompt,
    responseFormat: LanguageModelV4ResponseFormat?,
    modelId: String,
    providerOptionsName: String,
    supportsAssistantPrefixCompletion: Bool,
    supportsStructuredOutputs: Bool
) async throws -> (messages: [JSONValue], warnings: [SharedV4Warning]) {
    var messages: [JSONValue] = []
    var warnings: [SharedV4Warning] = []
    if case .json(let schema, _, _) = responseFormat {
        if let schema {
            if !supportsStructuredOutputs {
                messages.append(["role": "system", "content": .string("Return JSON that conforms to the following schema: " + (try deepSeekJSONString(schema)))])
                warnings.append(.compatibility(feature: "responseFormat JSON schema", details: "JSON response schema is injected into the system message."))
            }
        } else { messages.append(["role": "system", "content": "Return JSON."]) }
    }
    let lastUser = prompt.lastIndex { if case .user = $0 { return true }; return false } ?? -1
    let nativeV4 = isDeepSeekV4Model(modelId)
    for (index, message) in prompt.enumerated() {
        let messageProviderOptions: SharedV4ProviderOptions?
        switch message {
        case .system(_, let options), .user(_, let options), .assistant(_, let options), .tool(_, let options): messageProviderOptions = options
        }
        let settings = try await parseProviderOptions(provider: providerOptionsName, providerOptions: messageProviderOptions,
                                                     schema: deepSeekMessageOptionsSchema)
        if settings?.prefix == true, case .assistant = message {} else if settings?.prefix == true {
            throw InvalidPromptError(prompt: String(describing: prompt), message: "DeepSeek assistant prefix completion requires `prefix: true` on an assistant message.")
        }
        var payload: [String: JSONValue]
        switch message {
        case .system(let text, _): payload = ["role": "system", "content": .string(text)]
        case .user(let parts, _):
            let hasImage = parts.contains { part in
                guard case .file(let file) = part, getTopLevelMediaType(file.mediaType) == "image" else { return false }
                if case .text = file.data { return false }
                return true
            }
            if !hasImage {
                var text = ""
                for part in parts {
                    if case .text(let value) = part { text += value.text }
                    else { warnings.append(.unsupported(feature: "user message part type: file", details: nil)) }
                }
                payload = ["role": "user", "content": .string(text)]
            } else {
                var content: [JSONValue] = []
                for part in parts {
                    switch part {
                    case .text(let value): content.append(["type": "text", "text": .string(value.text)])
                    case .file(let file):
                        if getTopLevelMediaType(file.mediaType) == "image", !deepSeekIsTextData(file.data) {
                            content.append(try await deepSeekImage(file, namespace: providerOptionsName, prompt: prompt, allowsFileData: true))
                        } else { warnings.append(.unsupported(feature: "user message part type: file", details: nil)) }
                    }
                }
                payload = ["role": "user", "content": .array(content)]
            }
        case .assistant(let parts, _):
            if settings?.prefix == true {
                guard index == prompt.count - 1 else {
                    throw InvalidPromptError(prompt: String(describing: prompt), message: "DeepSeek assistant prefix completion requires the prefixed assistant message to be the final message.")
                }
                guard supportsAssistantPrefixCompletion else {
                    throw UnsupportedFunctionalityError(functionality: "DeepSeek assistant prefix completion", message: "DeepSeek assistant prefix completion requires a beta base URL ending in `/beta`.")
                }
            }
            var text = ""
            var reasoning: String?
            var tools: [JSONValue] = []
            for part in parts {
                switch part {
                case .text(let value): text += value.text
                case .reasoning(let value):
                    if index > lastUser || nativeV4 { reasoning = (reasoning ?? "") + value.text }
                case .toolCall(let value):
                    tools.append(["id": .string(value.toolCallId), "type": "function", "function": ["name": .string(value.toolName), "arguments": .string(try deepSeekJSONString(value.input))]])
                default: break
                }
            }
            payload = ["role": "assistant", "content": .string(text)]
            if let reasoning { payload["reasoning_content"] = .string(reasoning) }
            else if nativeV4 { payload["reasoning_content"] = "" }
            if settings?.prefix == true { payload["prefix"] = true }
            if !tools.isEmpty { payload["tool_calls"] = .array(tools) }
        case .tool(let parts, _):
            if settings?.name != nil { warnings.append(.unsupported(feature: "message name on tool messages", details: nil)) }
            for part in parts {
                guard case .toolResult(let result) = part else { continue }
                let content: JSONValue
                switch result.output {
                case .text(let text, _), .errorText(let text, _): content = .string(text)
                case .executionDenied(let reason, _): content = .string(reason ?? "Tool call execution denied.")
                case .json(let value, _), .errorJson(let value, _): content = .string(try deepSeekJSONString(value))
                case .content(let values):
                    let hasImage = values.contains { part in
                        guard case .file(let data, let mediaType, _, _) = part, getTopLevelMediaType(mediaType) == "image" else { return false }
                        return !deepSeekIsTextData(data)
                    }
                    if !hasImage { content = .string(try deepSeekJSONString(values)) }
                    else {
                        var output: [JSONValue] = []
                        for part in values {
                            switch part {
                            case .text(let text, _): output.append(["type": "text", "text": .string(text)])
                            case .file(let data, let mediaType, let filename, let providerOptions):
                                if getTopLevelMediaType(mediaType) == "image", !deepSeekIsTextData(data) {
                                    let file = LanguageModelV4FilePart(data: data, mediaType: mediaType, filename: filename, providerOptions: providerOptions)
                                    output.append(try await deepSeekImage(file, namespace: providerOptionsName, prompt: prompt, allowsFileData: false))
                                } else { warnings.append(.unsupported(feature: "tool result content part type: file", details: nil)) }
                            case .custom: warnings.append(.unsupported(feature: "tool result content part type: custom", details: nil))
                            }
                        }
                        content = .array(output)
                    }
                }
                messages.append(["role": "tool", "tool_call_id": .string(result.toolCallId), "content": content])
            }
            continue
        }
        if let name = settings?.name { payload["name"] = .string(name) }
        messages.append(.object(payload))
    }
    return (messages, warnings)
}

private func deepSeekIsTextData(_ data: SharedV4FileData) -> Bool {
    if case .text = data { return true }
    return false
}

private func deepSeekImage(_ file: LanguageModelV4FilePart, namespace: String, prompt: LanguageModelV4Prompt, allowsFileData: Bool) async throws -> JSONValue {
    if case .reference(let reference) = file.data {
        return ["type": "file", "file_id": .string(try resolveProviderReference(reference: reference, provider: "deepseek"))]
    }
    let settings = try await parseProviderOptions(provider: namespace, providerOptions: file.providerOptions, schema: deepSeekFilePartOptionsSchema)
    let mediaType = try resolveFullMediaType(part: file)
    guard ["image/gif", "image/jpeg", "image/jpg", "image/png", "image/webp"].contains(mediaType) else {
        throw UnsupportedFunctionalityError(functionality: "DeepSeek image media type \(mediaType)", message: "DeepSeek supports JPEG, PNG, GIF, and WebP image inputs.")
    }
    let url: String
    switch file.data {
    case .url(let value, _):
        url = value.absoluteString
        guard url.count <= 8192 else { throw InvalidPromptError(prompt: String(describing: prompt), message: "DeepSeek image URLs must not exceed 8192 characters.") }
        if allowsFileData, settings?.fileData == true {
            throw InvalidPromptError(prompt: String(describing: prompt), message: "DeepSeek `fileData` image parts require inline data, not a URL.")
        }
    case .data(let data): url = "data:\(mediaType == "image/jpg" ? "image/jpeg" : mediaType);base64,\(data.base64EncodedString())"
    case .base64(let data): url = "data:\(mediaType == "image/jpg" ? "image/jpeg" : mediaType);base64,\(data)"
    case .reference, .text: throw UnsupportedFunctionalityError(functionality: "DeepSeek image data")
    }
    if allowsFileData, settings?.fileData == true {
        guard settings?.imageDetail == nil else {
            throw InvalidPromptError(prompt: String(describing: prompt), message: "DeepSeek `imageDetail` cannot be combined with `fileData`.")
        }
        var content: [String: JSONValue] = ["type": "file", "file_data": .string(url)]
        if let filename = file.filename { content["filename"] = .string(filename) }
        return .object(content)
    }
    var image: [String: JSONValue] = ["url": .string(url)]
    if let detail = settings?.imageDetail { image["detail"] = .string(detail) }
    return ["type": "image_url", "image_url": .object(image)]
}

func deepSeekJSONString<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}
