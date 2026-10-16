import Foundation
import AISDKProvider
import AISDKProviderUtils

func convertGoogleInteractionsPrompt(_ prompt: LanguageModelV4Prompt, options: GoogleLanguageModelInteractionsOptions?, warnings: inout [SharedV4Warning]) throws -> (input: [JSONValue], system: String?) {
    let previous = options?.previousInteractionId
    let compact = previous != nil && options?.store != false
    if previous != nil && options?.store == false { warnings.append(.other(message: "google.interactions: providerOptions.google.previousInteractionId was set together with store: false. These are incoherent (the prior interaction cannot be referenced when nothing was stored on the server); the full history will be sent and previous_interaction_id will still be emitted.")) }
    var dropped: Set<String> = []
    var steps: [JSONValue] = []
    var system: [String] = []
    func opts(_ part: LanguageModelV4MessagePart) -> JSONObject {
        switch part {
        case .text(let p): return p.providerOptions?["google"] ?? [:]
        case .file(let p): return p.providerOptions?["google"] ?? [:]
        case .reasoning(let p): return p.providerOptions?["google"] ?? [:]
        case .reasoningFile(let p): return p.providerOptions?["google"] ?? [:]
        case .toolCall(let p): return p.providerOptions?["google"] ?? [:]
        case .toolResult(let p): return p.providerOptions?["google"] ?? [:]
        case .custom(let p): return p.providerOptions?["google"] ?? [:]
        }
    }
    for message in prompt {
        switch message {
        case .system(let text, _): system.append(text)
        case .user(let content, _):
            var blocks: [JSONValue] = []
            for part in content {
                switch part {
                case .text(let text):
                    if let last = blocks.indices.last, case .object(let object) = blocks[last], case .string(let previous) = object["text"] {
                        blocks[last] = .object(["type": .string("text"), "text": .string(previous + "\n\n" + text.text)])
                    } else { blocks.append(.object(["type": .string("text"), "text": .string(text.text)])) }
                case .file(let file):
                    if let block = try interactionsFile(file, mediaResolution: options?.mediaResolution, warnings: &warnings) { blocks.append(block) }
                }
            }
            if !blocks.isEmpty { steps.append(.object(["type": .string("user_input"), "content": .array(blocks)])) }
        case .assistant(let content, _):
            if compact && content.contains(where: { opts($0)["interactionId"] == previous.map(JSONValue.string) }) {
                for part in content { if case .toolCall(let call) = part { dropped.insert(call.toolCallId) } }
                continue
            }
            var pending: [JSONValue] = []
            func flush() { if !pending.isEmpty { steps.append(.object(["type": .string("model_output"), "content": .array(pending)])); pending = [] } }
            for part in content {
                let metadata = opts(part)
                switch part {
                case .text(let text): pending.append(.object(["type": .string("text"), "text": .string(text.text)]))
                case .file(let file): if let block = try interactionsFile(file, mediaResolution: options?.mediaResolution, warnings: &warnings) { pending.append(block) }
                case .reasoning(let text):
                    flush()
                    var step: JSONObject = ["type": .string("thought")]
                    if let signature = metadata["signature"], signature != .null { step["signature"] = signature }
                    if !text.text.isEmpty { step["summary"] = .array([.object(["type": .string("text"), "text": .string(text.text)])]) }
                    steps.append(.object(step))
                case .toolCall(let call):
                    flush()
                    var args = call.input
                    if case .string(let text) = args {
                        if let parsed = try? JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) {
                            if case .object = parsed { args = parsed } else { args = .object(["value": parsed]) }
                        } else { args = .object(["value": .string(text)]) }
                    }
                    var step: JSONObject = ["type": .string("function_call"), "id": .string(call.toolCallId), "name": .string(call.toolName), "arguments": args]
                    if let signature = metadata["signature"], signature != .null { step["signature"] = signature }
                    steps.append(.object(step))
                case .custom(let custom):
                    flush()
                    var step: JSONObject = [:]
                    if custom.kind == "google.processing_call", case .string = metadata["processingId"] { step = ["type": .string("processing_call"), "id": metadata["processingId"]!] }
                    else if custom.kind == "google.processing_result", case .string = metadata["processingCallId"] { step = ["type": .string("processing_result"), "call_id": metadata["processingCallId"]!] }
                    else { warnings.append(.other(message: "google.interactions: unsupported or invalid custom assistant content part \"\(custom.kind)\"; part dropped.")); continue }
                    if let signature = metadata["signature"], signature != .null { step["signature"] = signature }
                    steps.append(.object(step))
                case .reasoningFile: warnings.append(.other(message: "google.interactions: unsupported assistant content part type \"reasoning-file\"; part dropped."))
                case .toolResult: warnings.append(.other(message: "google.interactions: unsupported assistant content part type \"tool-result\"; part dropped."))
                }
            }
            flush()
        case .tool(let content, _):
            var blocks: [JSONValue] = []
            for part in content {
                guard case .toolResult(let result) = part else { warnings.append(.other(message: "google.interactions: unsupported tool message part type \"tool-approval-response\"; part dropped.")); continue }
                if compact && dropped.contains(result.toolCallId) { continue }
                var block: JSONObject = ["type": .string("function_result"), "call_id": .string(result.toolCallId), "name": .string(result.toolName)]
                if let signature = result.providerOptions?["google"]?["signature"], signature != .null { block["signature"] = signature }
                switch result.output {
                case .text(let text, _): block["result"] = .string(text)
                case .json(let value, _): block["result"] = .string(try googleJSONString(value))
                case .errorText(let text, _): block["result"] = .string(text); block["is_error"] = .bool(true)
                case .errorJson(let value, _): block["result"] = .string(try googleJSONString(value)); block["is_error"] = .bool(true)
                case .executionDenied(let reason, _): block["result"] = .string(reason ?? "Tool execution denied by user."); block["is_error"] = .bool(true)
                case .content(let values):
                    var result: [JSONValue] = []
                    for value in values {
                        switch value {
                        case .text(let text, _): result.append(.object(["type": .string("text"), "text": .string(text)]))
                        case .file(let data, let type, let filename, let providerOptions):
                            guard getTopLevelMediaType(type) == "image" else { warnings.append(.other(message: "google.interactions: tool-result file with mediaType \"\(type)\" is not supported (Interactions `function_result.result` accepts only text and image content); part dropped.")); continue }
                            if case .text = data { warnings.append(.other(message: "google.interactions: tool-result image part with `data.type === \"text\"` is not representable as an image; part dropped.")); continue }
                            if let file = try interactionsFile(.init(data: data, mediaType: type, filename: filename, providerOptions: providerOptions), warnings: &warnings) { result.append(file) }
                        case .custom: warnings.append(.other(message: "google.interactions: tool-result content part type \"custom\" is not supported; part dropped."))
                        }
                    }
                    block["result"] = .array(result)
                }
                blocks.append(.object(block))
            }
            if !blocks.isEmpty { steps.append(.object(["type": .string("user_input"), "content": .array(blocks)])) }
        }
    }
    return (steps, system.isEmpty ? nil : system.joined(separator: "\n\n"))
}

private func interactionsFile(_ part: LanguageModelV4FilePart, mediaResolution: String? = nil, warnings: inout [SharedV4Warning]) throws -> JSONValue? {
    if case .text(let text) = part.data { return .object(["type": .string("text"), "text": .string(text)]) }
    let top = getTopLevelMediaType(part.mediaType)
    let kind: String
    switch top { case "image", "audio", "video": kind = top; case "application", "text": kind = "document"; default: warnings.append(.other(message: "google.interactions: unsupported file media type \"\(part.mediaType)\"; part dropped.")); return nil }
    var result: JSONObject = ["type": .string(kind)]
    if let mediaResolution, kind == "image" || kind == "video" { result["resolution"] = .string(mediaResolution) }
    if kind == "video", let processing = part.providerOptions?["google"]?["processing"], processing != .null {
        if processing == .string("agentic") || processing == .string("static") { result["processing"] = processing }
        else if case .object(let config) = processing, config["type"] == .string("static") {
            var value: JSONObject = ["type": .string("static")]
            for (key, wire) in [("startOffset", "start_offset"), ("endOffset", "end_offset")] {
                if case .number(let number) = config[key] { value[wire] = .string("\(try googleJSONString(.number(number)))s") }
            }
            if case .number = config["fps"] { value["fps"] = config["fps"] }
            result["processing"] = .object(value)
        } else { warnings.append(.other(message: "google.interactions: invalid providerOptions.google.processing on video file part; expected \"agentic\", \"static\", or a static processing configuration. Option dropped.")) }
    }
    switch part.data {
    case .data(let bytes): result["data"] = .string(bytes.base64EncodedString()); result["mime_type"] = .string(try resolveFullMediaType(part: part))
    case .base64(let bytes): result["data"] = .string(bytes); result["mime_type"] = .string(try resolveFullMediaType(part: part))
    case .url(let url, _): result["uri"] = .string(url.absoluteString); if isFullMediaType(part.mediaType) { result["mime_type"] = .string(part.mediaType) }
    case .reference(let reference): result["uri"] = .string(try resolveProviderReference(reference: reference, provider: "google")); if isFullMediaType(part.mediaType) { result["mime_type"] = .string(part.mediaType) }
    case .text: break
    }
    return .object(result)
}

func prepareGoogleInteractionsTools(_ tools: [LanguageModelV4Tool]?, choice: LanguageModelV4ToolChoice?, warnings: inout [SharedV4Warning]) -> (tools: [JSONValue], choice: JSONValue?) {
    var result: [JSONValue] = []
    var hasFunction = false
    for tool in tools ?? [] {
        switch tool {
        case .function(let function):
            hasFunction = true
            result.append(.object(["type": .string("function"), "name": .string(function.name), "description": .string(function.description ?? ""), "parameters": function.inputSchema]))
        case .provider(let provider):
            let args = provider.args
            var fields: JSONObject = [:]
            switch provider.id {
            case "google.google_search":
                fields["type"] = .string("google_search")
                if case .object(let types) = args["searchTypes"] {
                    let names = [("webSearch", "web_search"), ("imageSearch", "image_search")].compactMap { key, wire -> JSONValue? in if let value = types[key], value != .null { return .string(wire) }; return nil }
                    if !names.isEmpty { fields["search_types"] = .array(names) }
                }
            case "google.code_execution", "google.url_context": fields["type"] = .string(String(provider.id.dropFirst(7)))
            case "google.file_search":
                fields["type"] = .string("file_search")
                for (key, wire) in [("fileSearchStoreNames", "file_search_store_names"), ("topK", "top_k"), ("metadataFilter", "metadata_filter")] { if let value = args[key], value != .null { fields[wire] = value } }
            case "google.google_maps":
                fields["type"] = .string("google_maps")
                for (key, wire) in [("latitude", "latitude"), ("longitude", "longitude"), ("enableWidget", "enable_widget")] { if let value = args[key], value != .null { fields[wire] = value } }
            case "google.computer_use":
                fields = ["type": .string("computer_use"), "environment": args["environment"].flatMap { $0 == .null ? nil : $0 } ?? .string("browser")]
                if let value = args["excludedPredefinedFunctions"], value != .null { fields["excludedPredefinedFunctions"] = value }
            case "google.mcp_server":
                fields["type"] = .string("mcp_server")
                for (key, wire) in [("name", "name"), ("url", "url"), ("headers", "headers"), ("allowedTools", "allowed_tools")] { if let value = args[key], value != .null { fields[wire] = value } }
            case "google.retrieval":
                fields = ["type": .string("retrieval"), "retrieval_types": args["retrievalTypes"].flatMap { $0 == .null ? nil : $0 } ?? .array([.string("vertex_ai_search")])]
                if let value = args["vertexAiSearchConfig"], value != .null { fields["vertex_ai_search_config"] = value }
            default: warnings.append(.unsupported(feature: "provider-defined tool \(provider.id)", details: "provider-defined tool \(provider.id) is not supported by google.interactions; tool dropped.")); continue
            }
            result.append(.object(fields))
        }
    }
    let mapped: JSONValue?
    if hasFunction {
        switch choice {
        case .auto?: mapped = .string("auto")
        case .none?: mapped = .string("none")
        case .required?: mapped = .string("any")
        case .tool(let name)?: mapped = .object(["allowed_tools": .object(["mode": .string("validated"), "tools": .array([.string(name)])])])
        case nil: mapped = nil
        }
    } else { mapped = nil }
    return (result, mapped)
}
