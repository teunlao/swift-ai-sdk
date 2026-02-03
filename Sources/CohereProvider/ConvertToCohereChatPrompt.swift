import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/cohere/src/convert-to-cohere-chat-prompt.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

func convertToCohereChatPrompt(_ prompt: LanguageModelV3Prompt) throws -> CohereChatPromptConversion {
    var messages: [JSONValue] = []
    var documents: [JSONValue] = []
    let warnings: [SharedV3Warning] = []

    for message in prompt {
        switch message {
        case .system(let content, _):
            messages.append(.object([
                "role": .string("system"),
                "content": .string(content)
            ]))

        case .user(let parts, _):
            var aggregatedText = ""

            for part in parts {
                switch part {
                case .text(let textPart):
                    aggregatedText.append(textPart.text)

                case .file(let filePart):
                    let textContent: String

                    switch filePart.data {
                    case .base64(let value):
                        textContent = value
                    case .data(let data):
                        guard filePart.mediaType.hasPrefix("text/") || filePart.mediaType == "application/json" else {
                            throw UnsupportedFunctionalityError(
                                functionality: "document media type: \(filePart.mediaType)",
                                message: "Media type '\(filePart.mediaType)' is not supported. Supported media types are: text/* and application/json."
                            )
                        }
                        guard let decoded = String(data: data, encoding: .utf8) else {
                            throw UnsupportedFunctionalityError(
                                functionality: "document media type: \(filePart.mediaType)",
                                message: "Expected UTF-8 encoded text content."
                            )
                        }
                        textContent = decoded
                    case .url:
                        throw UnsupportedFunctionalityError(
                            functionality: "File URL data",
                            message: "URLs should be downloaded by the AI SDK and not reach the Cohere converter."
                        )
                    }

                    var dataObject: [String: JSONValue] = [
                        "text": .string(textContent)
                    ]
                    if let filename = filePart.filename {
                        dataObject["title"] = .string(filename)
                    }

                    documents.append(.object([
                        "data": .object(dataObject)
                    ]))
                }
            }

            messages.append(.object([
                "role": .string("user"),
                "content": .string(aggregatedText)
            ]))

        case .assistant(let parts, _):
            var text = ""
            var toolCalls: [JSONValue] = []

            for part in parts {
                switch part {
                case .text(let textPart):
                    text.append(textPart.text)
                case .reasoning:
                    continue
                case .toolCall(let call):
                    let argumentsData = try JSONEncoder().encode(call.input)
                    let arguments = String(data: argumentsData, encoding: .utf8) ?? "{}"
                    toolCalls.append(.object([
                        "id": .string(call.toolCallId),
                        "type": .string("function"),
                        "function": .object([
                            "name": .string(call.toolName),
                            "arguments": .string(arguments)
                        ])
                    ]))
                case .file, .toolResult:
                    continue
                }
            }

            var payload: [String: JSONValue] = [
                "role": .string("assistant")
            ]

            if !toolCalls.isEmpty {
                payload["tool_calls"] = .array(toolCalls)
            } else {
                payload["content"] = .string(text)
            }

            messages.append(.object(payload))

        case .tool(let results, _):
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
                    contentValue = try canonicalJSONString(from: value)
                case .content(let parts, _):
                    contentValue = try canonicalJSONString(from: parts)
                }

                messages.append(.object([
                    "role": .string("tool"),
                    "content": .string(contentValue),
                    "tool_call_id": .string(result.toolCallId)
                ]))
            }
        }
    }

    return CohereChatPromptConversion(messages: messages, documents: documents, warnings: warnings)
}

private func canonicalJSONString(from value: JSONValue) throws -> String {
    return try canonicalJSONString(any: jsonValueToFoundation(value))
}

private func canonicalJSONString(from parts: [LanguageModelV3ToolResultContentPart]) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    let data = try encoder.encode(parts)
    guard let any = try? JSONSerialization.jsonObject(with: data) else {
        guard let string = String(data: data, encoding: .utf8) else { return "[]" }
        return string
    }
    return try canonicalJSONString(any: any)
}

private func canonicalJSONString(any: Any) throws -> String {
    let normalized = try normalizeJSONObject(any)
    let data = try JSONSerialization.data(withJSONObject: normalized, options: [])
    guard let string = String(data: data, encoding: .utf8) else {
        throw EncodingError.invalidValue(
            any,
            EncodingError.Context(codingPath: [], debugDescription: "Failed to encode canonical JSON string")
        )
    }
    return string
}

private func normalizeJSONObject(_ value: Any) throws -> Any {
    if let dict = value as? [String: Any] {
        let sortedKeys = dict.keys.sorted()
        var result: [String: Any] = [:]
        for key in sortedKeys {
            result[key] = try normalizeJSONObject(dict[key] as Any)
        }
        return result
    }

    if let array = value as? [Any] {
        return try array.map { try normalizeJSONObject($0) }
    }

    return value
}
