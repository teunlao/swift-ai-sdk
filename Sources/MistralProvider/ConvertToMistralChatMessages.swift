import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/mistral/src/convert-to-mistral-chat-messages.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public func convertToMistralChatMessages(
    prompt: LanguageModelV3Prompt
) throws -> [JSONValue] {
    var messages: [JSONValue] = []

    for (index, message) in prompt.enumerated() {
        let isLastMessage = index == prompt.count - 1

        switch message {
        case .system(let content, _):
            messages.append(.object([
                "role": .string("system"),
                "content": .string(content)
            ]))

        case .user(let parts, _):
            var contentParts: [JSONValue] = []

            for part in parts {
                switch part {
                case .text(let textPart):
                    contentParts.append(.object([
                        "type": .string("text"),
                        "text": .string(textPart.text)
                    ]))

                case .file(let filePart):
                    if filePart.mediaType.hasPrefix("image/") {
                        let mediaType = filePart.mediaType == "image/*" ? "image/jpeg" : filePart.mediaType

                        let imageURL: String
                        switch filePart.data {
                        case .data(let data):
                            imageURL = "data:\(mediaType);base64,\(convertToBase64(.data(data)))"
                        case .base64(let base64):
                            imageURL = "data:\(mediaType);base64,\(convertToBase64(.string(base64)))"
                        case .url(let url):
                            imageURL = url.absoluteString
                        }

                        contentParts.append(.object([
                            "type": .string("image_url"),
                            "image_url": .string(imageURL)
                        ]))
                    } else if filePart.mediaType == "application/pdf" {
                        guard case let .url(url) = filePart.data else {
                            throw UnsupportedFunctionalityError(functionality: "Only PDF URLs are supported in user file parts")
                        }

                        contentParts.append(.object([
                            "type": .string("document_url"),
                            "document_url": .string(url.absoluteString)
                        ]))
                    } else {
                        throw UnsupportedFunctionalityError(functionality: "Only images and PDF file parts are supported")
                    }
                }
            }

            messages.append(.object([
                "role": .string("user"),
                "content": .array(contentParts)
            ]))

        case .assistant(let parts, _):
            var textAccumulator = ""
            var toolCalls: [JSONValue] = []

            for part in parts {
                switch part {
                case .text(let textPart):
                    textAccumulator.append(textPart.text)
                case .reasoning(let reasoningPart):
                    textAccumulator.append(reasoningPart.text)
                case .toolCall(let toolCall):
                    let argumentsData = try JSONEncoder().encode(toolCall.input)
                    let arguments = String(data: argumentsData, encoding: .utf8) ?? "{}"

                    toolCalls.append(.object([
                        "id": .string(toolCall.toolCallId),
                        "type": .string("function"),
                        "function": .object([
                            "name": .string(toolCall.toolName),
                            "arguments": .string(arguments)
                        ])
                    ]))
                case .file:
                    throw UnsupportedFunctionalityError(functionality: "file content in assistant messages")
                case .toolResult:
                    throw UnsupportedFunctionalityError(functionality: "tool result content in assistant messages")
                }
            }

            var payload: [String: JSONValue] = [
                "role": .string("assistant"),
                "content": .string(textAccumulator)
            ]

            if isLastMessage {
                payload["prefix"] = .bool(true)
            }

            if !toolCalls.isEmpty {
                payload["tool_calls"] = .array(toolCalls)
            }

            messages.append(.object(payload))

        case .tool(let results, _):
            for result in results {
                let contentValue = try stringifyToolOutput(result.output)

                messages.append(.object([
                    "role": .string("tool"),
                    "name": .string(result.toolName),
                    "tool_call_id": .string(result.toolCallId),
                    "content": .string(contentValue)
                ]))
            }
        }
    }

    return messages
}

private func stringifyToolOutput(_ output: LanguageModelV3ToolResultOutput) throws -> String {
    switch output {
    case .text(let value), .errorText(let value):
        return value
    case .executionDenied(let reason):
        return reason ?? "Tool execution denied."
    case .json(let value), .errorJson(let value):
        let data = try JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    case .content(let parts):
        let data = try JSONEncoder().encode(parts)
        return String(data: data, encoding: .utf8) ?? "[]"
    }
}
