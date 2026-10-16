import Foundation
import AISDKProvider
import AISDKProviderUtils

func convertToMoonshotAIChatMessages(prompt: LanguageModelV4Prompt, modelId: String, providerOptionsName: String, responseFormat: JSONValue?) async throws -> (messages: [JSONValue], warnings: [SharedV4Warning]) {
    var messages: [JSONValue] = []
    var warnings: [SharedV4Warning] = []
    let family = moonshotModelFamily(modelId)
    func invalid(_ message: String) -> InvalidPromptError { .init(prompt: String(describing: prompt), message: message) }
    for (index, message) in prompt.enumerated() {
        let providerOptions: SharedV4ProviderOptions?
        let role: String
        switch message {
        case .system(_, let options): providerOptions = options; role = "system"
        case .user(_, let options): providerOptions = options; role = "user"
        case .assistant(_, let options): providerOptions = options; role = "assistant"
        case .tool(_, let options): providerOptions = options; role = "tool"
        }
        let options = try await parseProviderOptions(provider: providerOptionsName, providerOptions: providerOptions, schema: moonshotMessageOptionsSchema)
        if options?.partial == true && role != "assistant" { throw invalid("Moonshot AI Partial Mode requires `partial: true` on an assistant message.") }
        if options?.tools != nil && role != "system" { throw invalid("Moonshot dynamic tools must be configured on a system message.") }
        var payload: [String: JSONValue] = ["role": .string(role)]
        if let name = options?.name { payload["name"] = .string(name) }
        switch message {
        case .system(let content, _):
            if let tools = options?.tools, !tools.isEmpty {
                if !content.isEmpty { throw invalid("A Moonshot dynamic-tool system message must use empty content because the API forbids content alongside tools.") }
                if family != .k3 && family != .unknown {
                    warnings.append(.unsupported(feature: "dynamic tool loading for model \"\(modelId)\"", details: "Moonshot documents dynamic tool loading only for Kimi K3. The dynamic system message has been omitted."))
                    continue
                }
                let definitions = tools.map { LanguageModelV4Tool.function(.init(name: $0.name, inputSchema: .object($0.inputSchema), description: $0.description, strict: $0.strict)) }
                let prepared = try prepareMoonshotTools(tools: definitions, modelId: modelId)
                warnings.append(contentsOf: prepared.warnings)
                messages.append(.object(["role": .string("system"), "tools": .array(prepared.tools ?? [])]))
                continue
            }
            payload["content"] = .string(content)
        case .user(let content, _):
            if content.count == 1, case .text(let text) = content[0] { payload["content"] = .string(text.text) }
            else {
                payload["content"] = .array(try content.map { part in
                    switch part {
                    case .text(let text): return .object(["type": .string("text"), "text": .string(text.text)])
                    case .file(let file): return try moonshotFilePart(file)
                    }
                })
            }
        case .assistant(let content, _):
            if options?.partial == true {
                if index != prompt.count - 1 { throw invalid("Moonshot AI Partial Mode requires the partial assistant message to be the final message.") }
                if case .object(let format) = responseFormat, format["type"] == .string("json_object") { throw invalid("Moonshot AI Partial Mode cannot be combined with JSON object response format.") }
                payload["partial"] = .bool(true)
            }
            var text = "", reasoning = ""
            var calls: [JSONValue] = []
            for part in content {
                switch part {
                case .text(let part): text += part.text
                case .reasoning(let part): reasoning += part.text
                case .toolCall(let call): calls.append(.object(["id": .string(call.toolCallId), "type": .string("function"), "function": .object(["name": .string(call.toolName), "arguments": .string(try moonshotJSONString(call.input))])]))
                default: break
                }
            }
            payload["content"] = text.isEmpty && !calls.isEmpty ? .null : .string(text)
            if !reasoning.isEmpty { payload["reasoning_content"] = .string(reasoning) }
            if !calls.isEmpty { payload["tool_calls"] = .array(calls) }
        case .tool(let content, _):
            if options?.name != nil { warnings.append(.unsupported(feature: "message name on tool messages", details: nil)) }
            for part in content {
                guard case .toolResult(let result) = part else { continue }
                let value: String
                switch result.output {
                case .text(let text, _), .errorText(let text, _): value = text
                case .executionDenied(let reason, _): value = reason ?? "Tool call execution denied."
                case .json(let json, _), .errorJson(let json, _): value = try moonshotJSONString(json)
                case .content(let parts): value = try moonshotJSONString(parts)
                }
                messages.append(.object(["role": .string("tool"), "tool_call_id": .string(result.toolCallId), "content": .string(value)]))
            }
            continue
        }
        messages.append(.object(payload))
    }
    return (messages, warnings)
}

private func moonshotFilePart(_ part: LanguageModelV4FilePart) throws -> JSONValue {
    let top = getTopLevelMediaType(part.mediaType)
    func unsupported() -> UnsupportedFunctionalityError { .init(functionality: "file part media type \(part.mediaType)") }
    let url: String
    switch part.data {
    case .reference(let reference):
        guard top == "image" || top == "video" else { throw unsupported() }
        url = try resolveProviderReference(reference: reference, provider: "moonshotai")
        guard url.hasPrefix("ms://") else { throw UnsupportedFunctionalityError(functionality: "Moonshot file provider references without an ms:// URL") }
    case .text(let text):
        guard top == "text" else { throw unsupported() }
        return .object(["type": .string("text"), "text": .string(text)])
    case .data(let data) where top == "text": return .object(["type": .string("text"), "text": .string(String(decoding: data, as: UTF8.self))])
    case .base64(let value) where top == "text": return .object(["type": .string("text"), "text": .string(String(decoding: try convertBase64ToData(value), as: UTF8.self))])
    case .url(let value, let original) where top == "text": return .object(["type": .string("text"), "text": .string(original ?? value.absoluteString)])
    case .url, .data, .base64:
        guard top == "image" || top == "video" else { throw unsupported() }
        let images = ["image/jpeg", "image/png", "image/gif", "image/webp", "image/bmp", "image/heic", "image/heif"]
        let videos = ["video/mp4", "video/mpeg", "video/mov", "video/avi", "video/x-flv", "video/mpg", "video/webm", "video/wmv", "video/3gpp"]
        let type: String
        let isURL: Bool
        switch part.data { case .url: type = part.mediaType; isURL = true; default: type = try resolveFullMediaType(part: part); isURL = false }
        guard (top == "image" ? images : videos).contains(type) || (isURL && (type == top || type == "\(top)/*")) else { throw UnsupportedFunctionalityError(functionality: "file part media type \(type)") }
        switch part.data {
        case .url(let value, let original): url = original ?? value.absoluteString
        case .data(let data): url = "data:\(type);base64,\(data.base64EncodedString())"
        case .base64(let value): url = "data:\(type);base64,\(value)"
        default: throw unsupported()
        }
    }
    return .object(["type": .string("\(top)_url"), "\(top)_url": .object(["url": .string(url)])])
}
