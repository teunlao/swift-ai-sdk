import Foundation
import AISDKProvider
import AISDKProviderUtils

struct OpenResponsesInputConversionResult: Sendable {
    let input: [JSONValue]
    let instructions: String?
    let warnings: [SharedV4Warning]
}

func convertToOpenResponsesInput(prompt: LanguageModelV4Prompt, config: OpenResponsesConfig, providerTools: [String: LanguageModelV4ProviderTool]) async throws -> OpenResponsesInputConversionResult {
    var input: [JSONValue] = []
    var warnings: [SharedV4Warning] = []
    var system: [String] = []
    var replayed: Set<String> = []

    func appendReplay(_ replay: OpenResponsesExtensionReplay) {
        if case .item(let item) = replay {
            let key = item.type + ":" + item.id
            if replayed.insert(key).inserted { input.append(.object(item.fields)) }
        }
    }
    for message in prompt {
        switch message {
        case .system(let text, _): system.append(text)
        case .user(let parts, _):
            var content: [JSONValue] = []
            for part in parts {
                switch part {
                case .text(let text): content.append(["type": "input_text", "text": .string(text.text)])
                case .file(let file): content.append(try openResponsesInputFile(data: file.data, mediaType: file.mediaType, filename: file.filename, options: file.providerOptions, namespace: config.providerOptionsName))
                }
            }
            input.append(["type": "message", "role": "user", "content": .array(content)])
        case .assistant(let parts, _):
            var content: [JSONValue] = []
            var messageId: String?
            func flush() {
                guard !content.isEmpty else { return }
                var value: JSONObject = ["type": "message", "role": "assistant"]
                if config.strictResponseInput, messageId == nil {
                    value["content"] = .string(content.compactMap { value -> String? in
                        guard case .object(let part) = value else { return nil }
                        return openResponsesString(part["text"]) ?? openResponsesString(part["refusal"])
                    }.joined())
                } else {
                    if let messageId { value["id"] = .string(messageId) }
                    if config.strictResponseInput {
                        value["status"] = "completed"
                        value["content"] = .array(content.map { value in
                            guard case .object(var part) = value else { return value }
                            if part["type"] == "output_text" {
                                if part["annotations"] == nil { part["annotations"] = [] }
                                if part["logprobs"] == nil { part["logprobs"] = [] }
                            }
                            return .object(part)
                        })
                    } else { value["content"] = .array(content) }
                }
                input.append(.object(value))
                content = []
                messageId = nil
            }
            for part in parts {
                let metadata = openResponsesProviderData(part, namespace: config.providerOptionsName)
                if let replay = openResponsesExtensionReplay(metadata, registry: config.extensions) {
                    flush()
                    appendReplay(replay)
                    continue
                }
                let extensionPart: Experimental_OpenResponsesExtensionInputPart?
                let toolName: String?
                switch part {
                case .toolCall(let value): extensionPart = .toolCall(value); toolName = value.toolName
                case .toolResult(let value): extensionPart = .toolResult(value); toolName = value.toolName
                default: extensionPart = nil; toolName = nil
                }
                if let extensionPart, let toolName, let tool = providerTools[toolName], config.extensions.byProviderToolId[tool.id] != nil {
                    flush()
                    if let items = await openResponsesEncodeInput(extensionPart, tool: tool, registry: config.extensions) {
                        input += items.map { .object($0.fields) }
                    } else {
                        let kind = { if case .toolCall = extensionPart { return "tool-call" }; return "tool-result" }()
                        warnings.append(.unsupported(feature: "provider-defined tool \(tool.id) \(kind) history", details: nil))
                    }
                    continue
                }
                switch part {
                case .reasoning(let reasoning):
                    flush()
                    let id = openResponsesString(metadata?["itemId"])
                    let summary = openResponsesReasoningParts(metadata?["reasoningSummary"], type: "summary_text") ?? []
                    let reasoningContent = openResponsesReasoningParts(metadata?["reasoningContent"], type: "reasoning_text")
                    var value: JSONObject = ["type": "reasoning", "summary": .array(summary)]
                    if let id { value["id"] = .string(id) }
                    if let reasoningContent { value["content"] = .array(reasoningContent) }
                    else if metadata?.keys.contains("reasoningContent") != true, !reasoning.text.isEmpty { value["content"] = [["type": "reasoning_text", "text": .string(reasoning.text)]] }
                    if let encrypted = openResponsesString(metadata?["reasoningEncryptedContent"]) { value["encrypted_content"] = .string(encrypted) }
                    if let id, case .object(var previous) = input.last, previous["type"] == "reasoning", previous["id"] == .string(id) {
                        if case .array(let additions) = value["content"] {
                            let existing: [JSONValue]
                            if case .array(let parts) = previous["content"] { existing = parts } else { existing = [] }
                            previous["content"] = .array(existing + additions)
                            input[input.count - 1] = .object(previous)
                        }
                    } else { input.append(.object(value)) }
                case .text(let text):
                    let id = openResponsesString(metadata?["itemId"])
                    if !content.isEmpty, messageId != id { flush() }
                    messageId = id
                    var value: JSONObject = ["type": "output_text", "text": .string(text.text)]
                    if let annotations = OpenResponsesAnnotation.parse(metadata?["annotations"]) { value["annotations"] = .array(annotations.map { .object($0.fields) }) }
                    content.append(.object(value))
                case .toolCall(let call):
                    flush()
                    let arguments: String
                    if case .string(let raw) = call.input { arguments = raw } else { arguments = try openResponsesJSONString(call.input) }
                    let custom = providerTools[call.toolName]?.id == config.customToolId
                    var value: JSONObject = ["type": custom ? "custom_tool_call" : "function_call", "call_id": .string(call.toolCallId), "name": .string(call.toolName), custom ? "input" : "arguments": .string(arguments)]
                    if let id = openResponsesString(metadata?["itemId"]) { value["id"] = .string(id) }
                    input.append(.object(value))
                case .file, .custom, .reasoningFile, .toolResult: break
                }
            }
            flush()
        case .tool(let parts, _):
            for part in parts {
                guard case .toolResult(let result) = part else { continue }
                let metadata = result.providerOptions?[config.providerOptionsName]
                if let replay = openResponsesExtensionReplay(metadata, registry: config.extensions) { appendReplay(replay); continue }
                let tool = providerTools[result.toolName]
                if let tool, config.extensions.byProviderToolId[tool.id] != nil {
                    if let items = await openResponsesEncodeInput(.toolResult(result), tool: tool, registry: config.extensions) { input += items.map { .object($0.fields) } }
                    else { warnings.append(.unsupported(feature: "provider-defined tool \(tool.id) tool-result history", details: nil)) }
                    continue
                }
                let output: JSONValue
                switch result.output {
                case .text(let value, _), .errorText(let value, _): output = .string(value)
                case .executionDenied(let reason, _): output = .string(reason ?? "Tool call execution denied.")
                case .json(let value, _), .errorJson(let value, _): output = .string(try openResponsesJSONString(value))
                case .content(let values):
                    var content: [JSONValue] = []
                    for value in values {
                        switch value {
                        case .text(let text, _): content.append(["type": "input_text", "text": .string(text)])
                        case .file(let data, let mediaType, let filename, let options):
                            switch data {
                            case .data, .base64, .url: content.append(try openResponsesInputFile(data: data, mediaType: mediaType, filename: filename, options: options, namespace: config.providerOptionsName))
                            case .reference: warnings.append(.other(message: "unsupported tool content part type: file with data type: reference"))
                            case .text: warnings.append(.other(message: "unsupported tool content part type: file with data type: text"))
                            }
                        case .custom: warnings.append(.other(message: "unsupported tool content part type: custom"))
                        }
                    }
                    output = .array(content)
                }
                input.append(["type": tool?.id == config.customToolId ? "custom_tool_call_output" : "function_call_output", "call_id": .string(result.toolCallId), "output": output])
            }
        }
    }
    return .init(input: input, instructions: system.isEmpty ? nil : system.joined(separator: "\n"), warnings: warnings)
}

private func openResponsesInputFile(data: SharedV4FileData, mediaType: String, filename: String?, options: SharedV4ProviderOptions?, namespace: String) throws -> JSONValue {
    switch data {
    case .reference: throw UnsupportedFunctionalityError(functionality: "file parts with provider references")
    case .text: throw UnsupportedFunctionalityError(functionality: "text file parts")
    case .data, .base64, .url: break
    }
    let image = getTopLevelMediaType(mediaType) == "image"
    let detail = openResponsesString(options?[namespace]?["imageDetail"])
    let imageDetail = detail.flatMap { ["low", "high", "auto"].contains($0) ? $0 : nil } ?? "auto"
    if case .url(let url, let original) = data {
        return image ? ["type": "input_image", "image_url": .string(original ?? url.absoluteString), "detail": .string(imageDetail)] : ["type": "input_file", "file_url": .string(original ?? url.absoluteString)]
    }
    let file = LanguageModelV4FilePart(data: data, mediaType: mediaType, filename: filename, providerOptions: options)
    let fullType = try resolveFullMediaType(part: file)
    let base64: String
    switch data {
    case .data(let value): base64 = value.base64EncodedString()
    case .base64(let value): base64 = value
    case .url, .reference, .text: throw InvalidResponseDataError(data: mediaType, message: "Expected inline file data")
    }
    let encoded = "data:\(fullType);base64,\(base64)"
    return image ? ["type": "input_image", "image_url": .string(encoded), "detail": .string(imageDetail)] : ["type": "input_file", "filename": .string(filename ?? "data"), "file_data": .string(encoded)]
}

private enum OpenResponsesExtensionReplay {
    case item(Experimental_OpenResponsesExtensionItem)
    case reference
}
private func openResponsesExtensionReplay(_ metadata: JSONObject?, registry: OpenResponsesExtensionRegistry) -> OpenResponsesExtensionReplay? {
    guard case .object(let marker) = metadata?["openResponsesExtension"], case .string(let id) = marker["id"], let registration = registry.byId[id] else { return nil }
    if case .object(let fields) = marker["item"], let item = Experimental_OpenResponsesExtensionItem(wire: fields), registration.itemTypes.contains(item.type) { return .item(item) }
    if case .string = marker["itemId"] { return .reference }
    return nil
}
private func openResponsesEncodeInput(_ part: Experimental_OpenResponsesExtensionInputPart, tool: LanguageModelV4ProviderTool, registry: OpenResponsesExtensionRegistry) async -> [Experimental_OpenResponsesExtensionItem]? {
    guard let registration = registry.byProviderToolId[tool.id], let encode = registration.owner.encodeInput, !registration.owner.itemTypes.isEmpty else { return nil }
    do {
        guard let result = try await encode(part, tool) else { return nil }
        let items = result.items
        guard !items.isEmpty, items.allSatisfy({ registration.owner.itemTypes.contains($0.type) }) else { return nil }
        return items
    } catch {
        // Codec failures make this history unsupported for the request.
        return nil
    }
}
private func openResponsesReasoningParts(_ value: JSONValue?, type: String) -> [JSONValue]? {
    guard case .array(let values) = value else { return nil }
    var result: [JSONValue] = []
    for value in values {
        guard case .object(let part) = value, part["type"] == .string(type), case .string(let text) = part["text"] else { return nil }
        result.append(["type": .string(type), "text": .string(text)])
    }
    return result
}
private func openResponsesProviderData(_ part: LanguageModelV4MessagePart, namespace: String) -> JSONObject? {
    switch part {
    case .text(let value): return value.providerOptions?[namespace]
    case .reasoning(let value): return value.providerOptions?[namespace]
    case .file(let value): return value.providerOptions?[namespace]
    case .reasoningFile(let value): return value.providerOptions?[namespace]
    case .custom(let value): return value.providerOptions?[namespace]
    case .toolCall(let value): return value.providerOptions?[namespace]
    case .toolResult(let value): return value.providerOptions?[namespace]
    }
}
