import Foundation
import AISDKProvider
import AISDKProviderUtils

private func metadata(from providerOptions: SharedV3ProviderOptions?) -> [String: JSONValue] {
    guard let providerOptions, let metadata = providerOptions["openaiCompatible"] else {
        return [:]
    }
    return metadata
}

private func mergeMetadata(_ base: [String: JSONValue], with extra: [String: JSONValue]) -> [String: JSONValue] {
    guard !extra.isEmpty else { return base }
    var merged = base
    for (key, value) in extra {
        merged[key] = value
    }
    return merged
}

public func convertToOpenAICompatibleChatMessages(
    prompt: LanguageModelV3Prompt
) throws -> [JSONValue] {
    var messages: [JSONValue] = []

    for message in prompt {
        switch message {
        case .system(let content, let options):
            var payload: [String: JSONValue] = [
                "role": .string("system"),
                "content": .string(content)
            ]
            for (key, value) in metadata(from: options) {
                payload[key] = value
            }
            messages.append(.object(payload))

        case .user(let parts, let options):
            if parts.count == 1, case .text(let textPart) = parts[0] {
                var payload: [String: JSONValue] = [
                    "role": .string("user"),
                    "content": .string(textPart.text)
                ]
                let aggregatedMetadata = mergeMetadata(
                    metadata(from: options),
                    with: metadata(from: textPart.providerOptions)
                )
                for (key, value) in aggregatedMetadata {
                    payload[key] = value
                }
                messages.append(.object(payload))
                continue
            }

            var contentParts: [JSONValue] = []
            for part in parts {
                switch part {
                case .text(let textPart):
                    var payload: [String: JSONValue] = [
                        "type": .string("text"),
                        "text": .string(textPart.text)
                    ]
                    for (key, value) in metadata(from: textPart.providerOptions) {
                        payload[key] = value
                    }
                    contentParts.append(.object(payload))

                case .file(let filePart):
                    guard filePart.mediaType.hasPrefix("image/") else {
                        throw UnsupportedFunctionalityError(functionality: "file part media type \(filePart.mediaType)")
                    }

                    let mediaType: String = filePart.mediaType == "image/*" ? "image/jpeg" : filePart.mediaType

                    let data: String
                    switch filePart.data {
                    case .data(let bytes):
                        data = "data:\(mediaType);base64,\(convertToBase64(.data(bytes)))"
                    case .base64(let base64):
                        data = "data:\(mediaType);base64,\(convertToBase64(.string(base64)))"
                    case .url(let url):
                        data = url.absoluteString
                    }

                    var payload: [String: JSONValue] = [
                        "type": .string("image_url"),
                        "image_url": .object(["url": .string(data)])
                    ]
                    for (key, value) in metadata(from: filePart.providerOptions) {
                        payload[key] = value
                    }
                    contentParts.append(.object(payload))
                }
            }

            var payload: [String: JSONValue] = [
                "role": .string("user"),
                "content": .array(contentParts)
            ]
            for (key, value) in metadata(from: options) {
                payload[key] = value
            }
            messages.append(.object(payload))

        case .assistant(let contents, let options):
            var builder: [String: JSONValue] = [
                "role": .string("assistant")
            ]

            var textAccumulator = ""
            var toolCalls: [[String: JSONValue]] = []

            for content in contents {
                switch content {
                case .text(let textPart):
                    textAccumulator.append(textPart.text)
                case .toolCall(let call):
                    let inputData = try JSONEncoder().encode(call.input)
                    let arguments = String(data: inputData, encoding: .utf8) ?? "{}"
                    var payload: [String: JSONValue] = [
                        "type": .string("function"),
                        "id": .string(call.toolCallId),
                        "function": .object([
                            "name": .string(call.toolName),
                            "arguments": .string(arguments)
                        ])
                    ]
                    for (key, value) in metadata(from: call.providerOptions) {
                        payload[key] = value
                    }
                    toolCalls.append(payload)
                case .reasoning:
                    throw UnsupportedFunctionalityError(functionality: "reasoning content in assistant message")
                case .file:
                    throw UnsupportedFunctionalityError(functionality: "file content in assistant message")
                case .toolResult:
                    throw UnsupportedFunctionalityError(functionality: "tool result content in assistant message")
                }
            }

            if !textAccumulator.isEmpty {
                builder["content"] = .string(textAccumulator)
            }
            if !toolCalls.isEmpty {
                builder["tool_calls"] = .array(toolCalls.map(JSONValue.object))
            }

            for (key, value) in metadata(from: options) {
                builder[key] = value
            }

            messages.append(.object(builder))

        case .tool(let results, let options):
            for result in results {
                let output = result.output
                let contentValue: String
                switch output {
                case .text(let value), .errorText(let value):
                    contentValue = value
                case .executionDenied(let reason):
                    contentValue = reason ?? "Tool execution denied."
                case .json(let value), .errorJson(let value):
                    let jsonData = try JSONEncoder().encode(value)
                    contentValue = String(data: jsonData, encoding: .utf8) ?? "{}"
                case .content(let parts):
                    let jsonData = try JSONEncoder().encode(parts)
                    contentValue = String(data: jsonData, encoding: .utf8) ?? "[]"
                }

                var payload: [String: JSONValue] = [
                    "role": .string("tool"),
                    "tool_call_id": .string(result.toolCallId),
                    "content": .string(contentValue)
                ]

                let mergedMetadata = mergeMetadata(
                    metadata(from: options),
                    with: metadata(from: result.providerOptions)
                )
                for (key, value) in mergedMetadata {
                    payload[key] = value
                }

                messages.append(.object(payload))
            }
        }
    }

    return messages
}
