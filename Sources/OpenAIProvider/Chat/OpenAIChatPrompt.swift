import Foundation
import AISDKProvider
import AISDKProviderUtils

typealias OpenAIChatPrompt = [JSONValue]

struct OpenAIChatMessagesConverter {
    static func convert(
        prompt: LanguageModelV4Prompt,
        systemMessageMode: OpenAIChatSystemMessageMode
    ) throws -> (messages: OpenAIChatPrompt, warnings: [SharedV4Warning]) {
        var messages: OpenAIChatPrompt = []
        var warnings: [SharedV4Warning] = []

        for message in prompt {
            switch message {
            case .system(let content, let providerOptions):
                switch systemMessageMode {
                case .system, .developer:
                    let contentValue: JSONValue
                    if let breakpoint = openAIPromptCacheBreakpoint(from: providerOptions) {
                        contentValue = .array([.object([
                            "type": .string("text"),
                            "text": .string(content),
                            "prompt_cache_breakpoint": breakpoint
                        ])])
                    } else {
                        contentValue = .string(content)
                    }
                    messages.append(.object([
                        "role": .string(systemMessageMode == .system ? "system" : "developer"),
                        "content": contentValue
                    ]))
                case .remove:
                    warnings.append(.other(message: "system messages are removed for this model"))
                }

            case .user(let parts, _):
                if parts.count == 1,
                   case .text(let part) = parts[0],
                   openAIPromptCacheBreakpoint(from: part.providerOptions) == nil {
                    messages.append(.object(["role": .string("user"), "content": .string(part.text)]))
                    continue
                }
                var content: [JSONValue] = []
                for (index, part) in parts.enumerated() {
                    switch part {
                    case .text(let part):
                        content.append(contentPart([
                            "type": .string("text"), "text": .string(part.text)
                        ], providerOptions: part.providerOptions))
                    case .file(let part):
                        content.append(try fileContent(part, index: index))
                    }
                }
                messages.append(.object(["role": .string("user"), "content": .array(content)]))

            case .assistant(let parts, _):
                var text = ""
                var textParts: [JSONValue] = []
                var hasBreakpoint = false
                var toolCalls: [JSONValue] = []
                for part in parts {
                    switch part {
                    case .text(let part):
                        text += part.text
                        textParts.append(contentPart([
                            "type": .string("text"), "text": .string(part.text)
                        ], providerOptions: part.providerOptions))
                        hasBreakpoint = hasBreakpoint || openAIPromptCacheBreakpoint(from: part.providerOptions) != nil
                    case .toolCall(let part):
                        let input: JSONValue
                        if case .object = part.input { input = part.input } else { input = .object([:]) }
                        toolCalls.append(.object([
                            "type": .string("function"),
                            "id": .string(part.toolCallId),
                            "function": .object([
                                "name": .string(part.toolName),
                                "arguments": .string(try encodeJSON(input))
                            ])
                        ]))
                    case .file, .custom, .reasoning, .reasoningFile, .toolResult:
                        continue
                    }
                }
                var converted: [String: JSONValue] = [
                    "role": .string("assistant"),
                    "content": hasBreakpoint ? .array(textParts) : (toolCalls.isEmpty || !text.isEmpty ? .string(text) : .null)
                ]
                if !toolCalls.isEmpty { converted["tool_calls"] = .array(toolCalls) }
                messages.append(.object(converted))

            case .tool(let parts, _):
                for part in parts {
                    guard case .toolResult(let result) = part else { continue }
                    let value: String
                    switch result.output {
                    case .text(let text, _):
                        value = text
                    case .errorText(let text, _):
                        value = try encodeJSON(.object(["error": .string(text)]))
                    case .errorJson(let json, _):
                        value = try encodeJSON(.object(["error": json]))
                    case .executionDenied(let reason, _):
                        value = reason ?? "Tool call execution denied."
                    case .json(let json, _):
                        value = try encodeJSON(json)
                    case .content(let parts):
                        value = try encodeJSON(.array(try parts.map(toolResultContent)))
                    }
                    let breakpoint = promptCacheBreakpoint(from: result.output)
                        ?? openAIPromptCacheBreakpoint(from: result.providerOptions)
                    let content: JSONValue
                    if let breakpoint {
                        content = .array([.object([
                            "type": .string("text"), "text": .string(value),
                            "prompt_cache_breakpoint": breakpoint
                        ])])
                    } else {
                        content = .string(value)
                    }
                    messages.append(.object([
                        "role": .string("tool"), "tool_call_id": .string(result.toolCallId), "content": content
                    ]))
                }
            }
        }
        return (messages, warnings)
    }

    private static func fileContent(_ part: LanguageModelV4FilePart, index: Int) throws -> JSONValue {
        let content: [String: JSONValue]
        switch part.data {
        case .reference(let reference):
            content = [
                "type": .string("file"),
                "file": .object(["file_id": .string(try resolveProviderReference(reference: reference, provider: "openai"))])
            ]
        case .text:
            throw UnsupportedFunctionalityError(functionality: "text file parts")
        case .url, .data, .base64:
            switch getTopLevelMediaType(part.mediaType) {
            case "image":
                let url: String
                if case .url(let value, _) = part.data {
                    url = value.absoluteString
                } else {
                    url = "data:\(try resolveFullMediaType(part: part));base64,\(try base64Data(part.data))"
                }
                var image: [String: JSONValue] = ["url": .string(url)]
                if let detail = part.providerOptions?["openai"]?["imageDetail"] { image["detail"] = detail }
                content = ["type": .string("image_url"), "image_url": .object(image)]
            case "audio":
                if case .url = part.data {
                    throw UnsupportedFunctionalityError(functionality: "audio file parts with URLs")
                }
                let mediaType = try resolveFullMediaType(part: part)
                let format: String
                switch mediaType {
                case "audio/wav": format = "wav"
                case "audio/mp3", "audio/mpeg": format = "mp3"
                default:
                    throw UnsupportedFunctionalityError(functionality: "audio content parts with media type \(mediaType)")
                }
                content = [
                    "type": .string("input_audio"),
                    "input_audio": .object(["data": .string(try base64Data(part.data)), "format": .string(format)])
                ]
            default:
                let mediaType = try resolveFullMediaType(part: part)
                guard mediaType == "application/pdf" else {
                    throw UnsupportedFunctionalityError(functionality: "file part media type \(mediaType)")
                }
                if case .url = part.data {
                    throw UnsupportedFunctionalityError(functionality: "PDF file parts with URLs")
                }
                content = [
                    "type": .string("file"),
                    "file": .object([
                        "filename": .string(part.filename ?? "part-\(index).pdf"),
                        "file_data": .string("data:application/pdf;base64,\(try base64Data(part.data))")
                    ])
                ]
            }
        }
        return contentPart(content, providerOptions: part.providerOptions)
    }

    private static func contentPart(_ content: [String: JSONValue], providerOptions: SharedV4ProviderOptions?) -> JSONValue {
        var content = content
        if let breakpoint = openAIPromptCacheBreakpoint(from: providerOptions) {
            content["prompt_cache_breakpoint"] = breakpoint
        }
        return .object(content)
    }

    private static func promptCacheBreakpoint(from output: LanguageModelV4ToolResultOutput) -> JSONValue? {
        switch output {
        case .text(_, let options), .json(_, let options), .executionDenied(_, let options),
             .errorText(_, let options), .errorJson(_, let options):
            return openAIPromptCacheBreakpoint(from: options)
        case .content(let parts):
            for part in parts {
                let options: SharedV4ProviderOptions?
                switch part {
                case .text(_, let value), .file(_, _, _, let value), .custom(let value): options = value
                }
                if let breakpoint = openAIPromptCacheBreakpoint(from: options) { return breakpoint }
            }
            return nil
        }
    }

    private static func toolResultContent(_ part: LanguageModelV4ToolResultContentPart) throws -> JSONValue {
        var content: [String: JSONValue]
        let options: SharedV4ProviderOptions?
        switch part {
        case .text(let text, let providerOptions):
            content = ["type": .string("text"), "text": .string(text)]
            options = providerOptions
        case .file(let data, let mediaType, let filename, let providerOptions):
            content = ["type": .string("file"), "data": try fileDataJSON(data)]
            content["mediaType"] = .string(mediaType)
            if let filename { content["filename"] = .string(filename) }
            options = providerOptions
        case .custom(let providerOptions):
            content = ["type": .string("custom")]
            options = providerOptions
        }
        if let options { content["providerOptions"] = .object(options.mapValues(JSONValue.object)) }
        return .object(content)
    }

    private static func fileDataJSON(_ data: SharedV4FileData) throws -> JSONValue {
        switch data {
        case .data(let bytes):
            return .object(["type": .string("data"), "data": .object(Dictionary(uniqueKeysWithValues: bytes.enumerated().map { (String($0.offset), .number(Double($0.element))) }))])
        case .base64(let value): return .object(["type": .string("data"), "data": .string(value)])
        case .text(let value): return .object(["type": .string("text"), "text": .string(value)])
        case .url(let url, _): return .object(["type": .string("url"), "url": .string(url.absoluteString)])
        case .reference(let reference): return .object(["type": .string("reference"), "reference": .object(reference.mapValues(JSONValue.string))])
        }
    }

    private static func base64Data(_ data: SharedV4FileData) throws -> String {
        switch data {
        case .data(let value): return convertDataToBase64(value)
        case .base64(let value): return value
        default: throw UnsupportedFunctionalityError(functionality: "file data cannot be encoded as base64")
        }
    }

    private static func encodeJSON(_ value: JSONValue) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}
