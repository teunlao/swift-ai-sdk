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

private func audioFormat(for mediaType: String) -> String? {
    switch mediaType {
    case "audio/wav":
        return "wav"
    case "audio/mp3", "audio/mpeg":
        return "mp3"
    default:
        return nil
    }
}

private func inlineBase64(from data: SharedV4FileData) throws -> String {
    switch data {
    case .data(let bytes):
        return convertToBase64(.data(bytes))
    case .base64(let base64):
        return convertToBase64(.string(base64))
    case .url, .reference, .text:
        throw UnsupportedFunctionalityError(functionality: "non-inline file data")
    }
}

private func textContent(from data: SharedV4FileData) throws -> String {
    switch data {
    case .data(let bytes):
        return String(decoding: bytes, as: UTF8.self)
    case .base64(let base64):
        return String(decoding: try convertBase64ToData(base64), as: UTF8.self)
    case .url(let url):
        return url.absoluteString
    case .reference, .text:
        throw UnsupportedFunctionalityError(functionality: "non-decodable text file data")
    }
}

private func encodedJSONString<T: Encodable>(_ value: T) throws -> String {
    String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
}

private func thoughtSignature(from providerOptions: SharedV4ProviderOptions?) -> String? {
    guard let value = providerOptions?["google"]?["thoughtSignature"] else {
        return nil
    }

    switch value {
    case .string(let signature):
        return signature
    case .number(let number):
        return String(number)
    case .bool(let flag):
        return String(flag)
    case .null:
        return nil
    case .array, .object:
        return try? encodedJSONString(value)
    }
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
                for (key, value) in metadata(from: textPart.providerOptions) {
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
            // Reasoning parts in assistant messages are accumulated and
            // sent as a top-level `reasoning_content` field on the
            // outgoing assistant message. This matches the upstream
            // `@ai-sdk/openai-compatible` behavior and lets reasoning
            // models (DeepSeek, Kimi, Qwen3, GLM, etc.) round-trip
            // their prior turn's reasoning back to the provider for
            // continuity. Per-provider field naming overrides (e.g.
            // OpenRouter's `reasoning_details`) can still be applied
            // by callers via the `openaiCompatible` providerOptions
            // namespace, which `metadata(from:)` merges into the final
            // payload below.
            var reasoningAccumulator = ""
            var toolCalls: [[String: JSONValue]] = []

            for content in contents {
                switch content {
                case .text(let textPart):
                    textAccumulator.append(textPart.text)
                case .reasoning(let reasoningPart):
                    reasoningAccumulator.append(reasoningPart.text)
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
                case .file:
                    throw UnsupportedFunctionalityError(functionality: "file content in assistant message")
                case .toolResult:
                    throw UnsupportedFunctionalityError(functionality: "tool result content in assistant message")
                case .custom:
                    throw UnsupportedFunctionalityError(functionality: "custom content in assistant message")
                }
            }

            builder["content"] = .string(textAccumulator)
            if !reasoningAccumulator.isEmpty {
                builder["reasoning_content"] = .string(reasoningAccumulator)
            }
            if !toolCalls.isEmpty {
                builder["tool_calls"] = .array(toolCalls.map(JSONValue.object))
            }

            for (key, value) in metadata(from: options) {
                builder[key] = value
            }

            messages.append(.object(builder))

        case .tool(let results, let options):
            for part in results {
                guard case .toolResult(let result) = part else { continue }
                let output = result.output
                let contentValue: String
                switch output {
                case .text(let value, _), .errorText(let value, _):
                    contentValue = value
                case .executionDenied(let reason, _):
                    contentValue = reason ?? "Tool execution denied."
                case .json(let value, _), .errorJson(let value, _):
                    let jsonData = try JSONEncoder().encode(value)
                    contentValue = String(data: jsonData, encoding: .utf8) ?? "{}"
                case .content(let parts, _):
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

public func convertToOpenAICompatibleChatMessages(
    prompt: LanguageModelV4Prompt
) throws -> [JSONValue] {
    var messages: [JSONValue] = []

    for message in prompt {
        switch message {
        case .system(let content, let providerOptions):
            var payload: [String: JSONValue] = [
                "role": .string("system"),
                "content": .string(content)
            ]
            for (key, value) in metadata(from: providerOptions) {
                payload[key] = value
            }
            messages.append(.object(payload))

        case .user(let parts, let providerOptions):
            if parts.count == 1, case .text(let textPart) = parts[0] {
                var payload: [String: JSONValue] = [
                    "role": .string("user"),
                    "content": .string(textPart.text)
                ]
                for (key, value) in metadata(from: textPart.providerOptions) {
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
                    switch filePart.data {
                    case .reference:
                        throw UnsupportedFunctionalityError(
                            functionality: "file parts with provider references"
                        )
                    case .text:
                        throw UnsupportedFunctionalityError(functionality: "text file parts")
                    case .url, .data, .base64:
                        break
                    }

                    var payload: [String: JSONValue]
                    let topLevelMediaType = getTopLevelMediaType(filePart.mediaType)

                    switch topLevelMediaType {
                    case "image":
                        let url: String
                        switch filePart.data {
                        case .url(let value):
                            url = value.absoluteString
                        case .data, .base64:
                            let mediaType = try resolveFullMediaType(part: filePart)
                            url = "data:\(mediaType);base64,\(try inlineBase64(from: filePart.data))"
                        case .reference, .text:
                            throw UnsupportedFunctionalityError(
                                functionality: "file part media type \(filePart.mediaType)"
                            )
                        }
                        payload = [
                            "type": .string("image_url"),
                            "image_url": .object(["url": .string(url)])
                        ]

                    case "audio":
                        if case .url = filePart.data {
                            throw UnsupportedFunctionalityError(
                                functionality: "audio file parts with URLs"
                            )
                        }
                        let mediaType = try resolveFullMediaType(part: filePart)
                        guard let format = audioFormat(for: mediaType) else {
                            throw UnsupportedFunctionalityError(
                                functionality: "audio media type \(mediaType)"
                            )
                        }
                        payload = [
                            "type": .string("input_audio"),
                            "input_audio": .object([
                                "data": .string(try inlineBase64(from: filePart.data)),
                                "format": .string(format)
                            ])
                        ]

                    case "application":
                        if case .url = filePart.data {
                            throw UnsupportedFunctionalityError(
                                functionality: "PDF file parts with URLs"
                            )
                        }
                        let mediaType = try resolveFullMediaType(part: filePart)
                        guard mediaType == "application/pdf" else {
                            throw UnsupportedFunctionalityError(
                                functionality: "file part media type \(mediaType)"
                            )
                        }
                        payload = [
                            "type": .string("file"),
                            "file": .object([
                                "filename": .string(filePart.filename ?? "document.pdf"),
                                "file_data": .string(
                                    "data:application/pdf;base64,\(try inlineBase64(from: filePart.data))"
                                )
                            ])
                        ]

                    case "text":
                        payload = [
                            "type": .string("text"),
                            "text": .string(try textContent(from: filePart.data))
                        ]

                    default:
                        throw UnsupportedFunctionalityError(
                            functionality: "file part media type \(filePart.mediaType)"
                        )
                    }

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
            for (key, value) in metadata(from: providerOptions) {
                payload[key] = value
            }
            messages.append(.object(payload))

        case .assistant(let parts, let providerOptions):
            var text = ""
            var reasoning = ""
            var toolCalls: [JSONValue] = []

            for part in parts {
                switch part {
                case .text(let textPart):
                    text += textPart.text
                case .reasoning(let reasoningPart):
                    reasoning += reasoningPart.text
                case .toolCall(let toolCall):
                    var payload: [String: JSONValue] = [
                        "id": .string(toolCall.toolCallId),
                        "type": .string("function"),
                        "function": .object([
                            "name": .string(toolCall.toolName),
                            "arguments": .string(try encodedJSONString(toolCall.input))
                        ])
                    ]
                    for (key, value) in metadata(from: toolCall.providerOptions) {
                        payload[key] = value
                    }
                    if let signature = thoughtSignature(from: toolCall.providerOptions) {
                        payload["extra_content"] = .object([
                            "google": .object([
                                "thought_signature": .string(signature)
                            ])
                        ])
                    }
                    toolCalls.append(.object(payload))
                case .file, .custom, .reasoningFile, .toolResult:
                    continue
                }
            }

            var payload: [String: JSONValue] = [
                "role": .string("assistant"),
                "content": toolCalls.isEmpty || !text.isEmpty ? .string(text) : .null
            ]
            if !reasoning.isEmpty {
                payload["reasoning_content"] = .string(reasoning)
            }
            if !toolCalls.isEmpty {
                payload["tool_calls"] = .array(toolCalls)
            }
            for (key, value) in metadata(from: providerOptions) {
                payload[key] = value
            }
            messages.append(.object(payload))

        case .tool(let parts, _):
            for part in parts {
                guard case .toolResult(let toolResult) = part else {
                    continue
                }

                let contentValue: String
                switch toolResult.output {
                case .text(let value, _), .errorText(let value, _):
                    contentValue = value
                case .executionDenied(let reason, _):
                    contentValue = reason ?? "Tool call execution denied."
                case .json(let value, _), .errorJson(let value, _):
                    contentValue = try encodedJSONString(value)
                case .content(let value):
                    contentValue = try encodedJSONString(value)
                }

                var payload: [String: JSONValue] = [
                    "role": .string("tool"),
                    "tool_call_id": .string(toolResult.toolCallId),
                    "content": .string(contentValue)
                ]
                for (key, value) in metadata(from: toolResult.providerOptions) {
                    payload[key] = value
                }
                messages.append(.object(payload))
            }
        }
    }

    return messages
}
