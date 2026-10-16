import Foundation
import AISDKProvider
import AISDKProviderUtils

struct BedrockChatMessages: Sendable {
    let system: [JSONValue]
    let messages: [JSONValue]
}

public struct BedrockReasoningMetadata: Codable, Sendable, Equatable {
    public let signature: String?
    public let redactedData: String?
    public let redactedContent: String?
    public init(signature: String? = nil, redactedData: String? = nil, redactedContent: String? = nil) {
        self.signature = signature
        self.redactedData = redactedData
        self.redactedContent = redactedContent
    }
}
public let bedrockReasoningMetadataSchema = bedrockOptionalFieldsSchema(BedrockReasoningMetadata.self, fields: ["signature", "redactedData", "redactedContent"])

private let imageFormats = ["image/jpeg": "jpeg", "image/png": "png", "image/gif": "gif", "image/webp": "webp"]
private let documentFormats = [
    "application/pdf": "pdf", "text/csv": "csv", "application/msword": "doc",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document": "docx",
    "application/vnd.ms-excel": "xls", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": "xlsx",
    "text/html": "html", "text/plain": "txt", "text/markdown": "md"
]
private let videoFormats = [
    "video/x-matroska": "mkv", "video/quicktime": "mov", "video/mp4": "mp4", "video/webm": "webm",
    "video/x-flv": "flv", "video/mpeg": "mpeg", "video/mpg": "mpg", "video/wmv": "wmv",
    "video/x-ms-wmv": "wmv", "video/3gpp": "three_gp"
]

func convertToBedrockChatMessages(_ prompt: LanguageModelV4Prompt, isMistral: Bool = false) async throws -> BedrockChatMessages {
    var blocks: [[LanguageModelV4Message]] = []
    func role(_ message: LanguageModelV4Message) -> String {
        switch message {
        case .system: return "system"
        case .assistant: return "assistant"
        case .user, .tool: return "user"
        }
    }
    for message in prompt {
        if let last = blocks.last?.last, role(last) == role(message) {
            blocks[blocks.count - 1].append(message)
        } else {
            blocks.append([message])
        }
    }
    var system: [JSONValue] = []
    var messages: [JSONValue] = []
    var documentCounter = 0
    func documentName(_ filename: String?) -> String {
        if let filename, !filename.isEmpty {
            let name = stripFileExtension(filename)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "[^a-zA-Z0-9 ()\\[\\]-]", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let shortened = String(name.prefix(200)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !shortened.isEmpty { return shortened }
        }
        documentCounter += 1
        return "document-\(documentCounter)"
    }
    func appendUser(_ content: [JSONValue]) {
        if case .object(var last)? = messages.last,
           last["role"] == .string("user"), case .array(var previous)? = last["content"],
           previous.contains(where: { if case .object(let block) = $0 { return block["toolResult"] != nil }; return false }) {
            previous.append(contentsOf: content)
            last["content"] = .array(previous)
            messages[messages.count - 1] = .object(last)
        } else {
            messages.append(.object(["role": .string("user"), "content": .array(content)]))
        }
    }
    for (blockIndex, block) in blocks.enumerated() {
        let isLastBlock = blockIndex == blocks.count - 1
        guard let first = block.first else { continue }
        switch role(first) {
        case "system":
            guard messages.isEmpty else {
                throw UnsupportedFunctionalityError(functionality: "Multiple system messages that are separated by user/assistant messages")
            }
            for case .system(let text, let options) in block {
                system.append(.object(["text": .string(text)]))
                appendCachePoint(options, to: &system)
            }
        case "user":
            var content: [JSONValue] = []
            for message in block {
                switch message {
                case .user(let parts, let options):
                    for part in parts {
                        switch part {
                        case .text(let part):
                            let guardOptions = try await parseBedrockOptions(providerOptions: part.providerOptions, schema: bedrockTextPartProviderOptionsSchema)
                            if guardOptions?.guardContent == true {
                                var text: [String: JSONValue] = ["text": .string(part.text)]
                                if let qualifiers = guardOptions?.guardContentQualifiers { text["qualifiers"] = .array(qualifiers.map { .string($0.rawValue) }) }
                                content.append(.object(["guardContent": .object(["text": .object(text)])]))
                            } else {
                                content.append(.object(["text": .string(part.text)]))
                            }
                            appendCachePoint(part.providerOptions, to: &content)
                        case .file(let part):
                            content.append(try await convertFile(part, toolResult: false, documentName: documentName))
                            appendCachePoint(part.providerOptions, to: &content)
                        }
                    }
                    appendCachePoint(options, to: &content)
                case .tool(let parts, let options):
                    for case .toolResult(let part) in parts {
                        content.append(try await convertToolResult(part, isMistral: isMistral, documentName: documentName))
                        appendCachePoint(part.providerOptions, to: &content)
                    }
                    appendCachePoint(options, to: &content)
                default: break
                }
            }
            appendUser(content)
        default:
            var assistant: [JSONValue] = []
            var toolResults: [JSONValue] = []
            func flushAssistant() {
                if assistant.contains(where: { if case .object(let value) = $0 { return value["cachePoint"] == nil }; return true }) {
                    messages.append(.object(["role": .string("assistant"), "content": .array(assistant)]))
                }
                assistant.removeAll()
            }
            func flushResults() {
                if !toolResults.isEmpty { appendUser(toolResults); toolResults.removeAll() }
            }
            for (messageIndex, message) in block.enumerated() {
                guard case .assistant(let parts, let options) = message else { continue }
                let hasReasoning = parts.contains { if case .reasoning = $0 { return true }; return false }
                for (partIndex, part) in parts.enumerated() {
                    if case .toolResult = part {} else { flushResults() }
                    let partOptions: SharedV4ProviderOptions?
                    switch part {
                    case .text(let part):
                        partOptions = part.providerOptions
                        if !part.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || hasReasoning {
                            let text = isLastBlock && messageIndex == block.count - 1 && partIndex == parts.count - 1 ? part.text.trimmingCharacters(in: .whitespacesAndNewlines) : part.text
                            assistant.append(.object(["text": .string(text)]))
                        }
                    case .reasoning(let part):
                        partOptions = part.providerOptions
                        let metadata = try await parseBedrockOptions(providerOptions: part.providerOptions, schema: bedrockReasoningMetadataSchema)
                        if let signature = metadata?.signature {
                            assistant.append(.object(["reasoningContent": .object(["reasoningText": .object(["text": .string(part.text), "signature": .string(signature)])])]))
                        } else if let redacted = metadata?.redactedContent {
                            assistant.append(.object(["reasoningContent": .object(["redactedContent": .string(redacted)])]))
                        } else if let redacted = metadata?.redactedData {
                            assistant.append(.object(["reasoningContent": .object(["redactedReasoning": .object(["data": .string(redacted)])])]))
                        }
                    case .toolCall(let part):
                        partOptions = part.providerOptions
                        let name = part.toolName.replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "", options: .regularExpression)
                        let input: JSONValue
                        if case .object = part.input { input = part.input } else { input = .object(["rawInvalidInput": part.input]) }
                        assistant.append(.object(["toolUse": .object([
                            "toolUseId": .string(normalizeToolCallId(part.toolCallId, isMistral: isMistral)),
                            "name": .string(name.isEmpty ? "_" : name), "input": input
                        ])]))
                    case .toolResult(let part):
                        partOptions = part.providerOptions
                        flushAssistant()
                        toolResults.append(try await convertToolResult(part, isMistral: isMistral, documentName: documentName))
                    case .file(let part):
                        partOptions = part.providerOptions
                    case .custom(let part):
                        partOptions = part.providerOptions
                    case .reasoningFile(let part):
                        partOptions = part.providerOptions
                    }
                    if case .toolResult = part { appendCachePoint(partOptions, to: &toolResults) } else { appendCachePoint(partOptions, to: &assistant) }
                }
                if case .toolResult? = parts.last { appendCachePoint(options, to: &toolResults) } else { appendCachePoint(options, to: &assistant) }
            }
            flushResults()
            flushAssistant()
        }
    }
    return BedrockChatMessages(system: system, messages: messages)
}

private func convertFile(_ part: LanguageModelV4FilePart, toolResult: Bool, documentName: (String?) -> String) async throws -> JSONValue {
    let mediaType: String
    let source: JSONValue
    switch part.data {
    case .reference:
        throw UnsupportedFunctionalityError(functionality: toolResult ? "tool result file data of type \"reference\"" : "file parts with provider references")
    case .text(let text):
        guard !toolResult else { throw UnsupportedFunctionalityError(functionality: "tool result file data of type \"text\"") }
        mediaType = isFullMediaType(part.mediaType) ? part.mediaType : "text/plain"
        source = .object(["bytes": .string(Data(text.utf8).base64EncodedString())])
    case .url(let url, let original):
        guard url.scheme == "s3" else { throw UnsupportedFunctionalityError(functionality: toolResult ? "tool result file data of type \"url\"" : "File URL data") }
        mediaType = try resolveFullMediaType(part: part)
        source = .object(["s3Location": .object(["uri": .string(original ?? url.absoluteString)])])
    case .data(let data):
        mediaType = try resolveFullMediaType(part: part)
        source = .object(["bytes": .string(data.base64EncodedString())])
    case .base64(let base64):
        mediaType = try resolveFullMediaType(part: part)
        source = .object(["bytes": .string(base64)])
    }
    let topLevel: String
    if case .text = part.data { topLevel = "text" } else { topLevel = getTopLevelMediaType(mediaType) }
    if topLevel == "image" || topLevel == "video" {
        let formats = topLevel == "image" ? imageFormats : videoFormats
        let format = try requireFormat(mediaType, formats: formats, kind: topLevel)
        let block: JSONValue = .object([topLevel: .object(["format": .string(format), "source": source])])
        if !toolResult && topLevel == "image" {
            switch part.data {
            case .data, .base64:
                if try await parseBedrockOptions(providerOptions: part.providerOptions, schema: bedrockImagePartProviderOptionsSchema)?.guardContent == true {
                    return .object(["guardContent": block])
                }
            default: break
            }
        }
        return block
    }
    if case .url = part.data { throw UnsupportedFunctionalityError(functionality: toolResult ? "tool result file data of type \"url\"" : "File URL data") }
    var document: [String: JSONValue] = [
        "format": .string(try requireFormat(mediaType, formats: documentFormats, kind: "file")),
        "name": .string(documentName(part.filename)), "source": source
    ]
    if try await parseBedrockOptions(providerOptions: part.providerOptions, schema: bedrockFilePartProviderOptionsSchema)?.citations?.enabled == true {
        document["citations"] = .object(["enabled": .bool(true)])
    }
    return .object(["document": .object(document)])
}

private func convertToolResult(_ part: LanguageModelV4ToolResultPart, isMistral: Bool, documentName: (String?) -> String) async throws -> JSONValue {
    var content: [JSONValue] = []
    switch part.output {
    case .text(let text, _), .errorText(let text, _): content = [.object(["text": .string(text)])]
    case .executionDenied(let reason, _): content = [.object(["text": .string(reason ?? "Tool call execution denied.")])]
    case .json(let value, _), .errorJson(let value, _): content = [.object(["text": .string(try bedrockJSONString(value))])]
    case .content(let parts):
        for part in parts {
            switch part {
            case .text(let text, _): content.append(.object(["text": .string(text)]))
            case .file(let data, let mediaType, let filename, let options):
                content.append(try await convertFile(.init(data: data, mediaType: mediaType, filename: filename, providerOptions: options), toolResult: true, documentName: documentName))
            case .custom: throw UnsupportedFunctionalityError(functionality: "unsupported tool content part type: custom")
            }
        }
    }
    return .object(["toolResult": .object(["toolUseId": .string(normalizeToolCallId(part.toolCallId, isMistral: isMistral)), "content": .array(content)])])
}

private func requireFormat(_ mediaType: String, formats: [String: String], kind: String) throws -> String {
    guard let format = formats[mediaType] else {
        throw UnsupportedFunctionalityError(functionality: "\(kind) mime type: \(mediaType)", message: "Unsupported \(kind) mime type: \(mediaType), expected one of: \(formats.keys.sorted().joined(separator: ", "))")
    }
    return format
}

private func appendCachePoint(_ options: SharedV4ProviderOptions?, to content: inout [JSONValue]) {
    let canonical = options?["amazonBedrock"]?["cachePoint"].flatMap { $0 == .null ? nil : $0 }
    guard let cachePoint = canonical ?? options?["bedrock"]?["cachePoint"] else { return }
    switch cachePoint {
    case .null, .bool(false), .number(0), .string(""): return
    default: content.append(.object(["cachePoint": cachePoint]))
    }
}

func bedrockJSONString(_ value: JSONValue) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: jsonValueToFoundation(value), options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes])
    return String(decoding: data, as: UTF8.self)
}
