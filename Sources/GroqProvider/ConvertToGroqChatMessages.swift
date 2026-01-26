import Foundation
import AISDKProvider
import AISDKProviderUtils

struct GroqChatMessageBuilder {
    static func convert(_ prompt: LanguageModelV3Prompt) throws -> [JSONValue] {
        var messages: [JSONValue] = []

        for message in prompt {
            switch message {
            case .system(let content, _):
                messages.append(.object([
                    "role": .string("system"),
                    "content": .string(content)
                ]))

            case .user(let parts, _):
                if parts.count == 1, case .text(let textPart) = parts[0] {
                    messages.append(.object([
                        "role": .string("user"),
                        "content": .string(textPart.text)
                    ]))
                    continue
                }

                var contentArray: [JSONValue] = []
                for part in parts {
                    switch part {
                    case .text(let textPart):
                        contentArray.append(.object([
                            "type": .string("text"),
                            "text": .string(textPart.text)
                        ]))

                    case .file(let filePart):
                        guard filePart.mediaType.hasPrefix("image/") else {
                            throw UnsupportedFunctionalityError(functionality: "Non-image file content parts")
                        }

                        let mimeType = filePart.mediaType == "image/*" ? "image/jpeg" : filePart.mediaType
                        let urlValue: String
                        switch filePart.data {
                        case .data(let data):
                            urlValue = "data:\(mimeType);base64,\(convertDataToBase64(data))"
                        case .base64(let base64):
                            urlValue = "data:\(mimeType);base64,\(base64)"
                        case .url(let url):
                            urlValue = url.absoluteString
                        }

                        contentArray.append(.object([
                            "type": .string("image_url"),
                            "image_url": .object([
                                "url": .string(urlValue)
                            ])
                        ]))
                    }
                }

                messages.append(.object([
                    "role": .string("user"),
                    "content": .array(contentArray)
                ]))

            case .assistant(let parts, _):
                var text = ""
                var reasoning = ""
                var toolCalls: [JSONValue] = []

                for part in parts {
                    switch part {
                    case .text(let textPart):
                        text += textPart.text

                    case .reasoning(let reasoningPart):
                        reasoning += reasoningPart.text

                    case .toolCall(let callPart):
                        toolCalls.append(.object([
                            "id": .string(callPart.toolCallId),
                            "type": .string("function"),
                            "function": .object([
                                "name": .string(callPart.toolName),
                                "arguments": .string(stringifyJSONValue(callPart.input))
                            ])
                        ]))

                    case .file, .toolResult:
                        // assistant messages do not support files or tool results
                        break
                    }
                }

                var payload: [String: JSONValue] = [
                    "role": .string("assistant")
                ]
                if !text.isEmpty {
                    payload["content"] = .string(text)
                }
                if !reasoning.isEmpty {
                    payload["reasoning"] = .string(reasoning)
                }
                if !toolCalls.isEmpty {
                    payload["tool_calls"] = .array(toolCalls)
                }

                messages.append(.object(payload))

            case .tool(let parts, _):
                for part in parts {
                    guard case .toolResult(let toolResult) = part else { continue }
                    let contentValue: String
                    switch toolResult.output {
                    case .text(let value, _):
                        contentValue = value
                    case .executionDenied(let reason, _):
                        contentValue = reason ?? "Tool execution denied."
                    case .errorText(let value, _):
                        contentValue = value
                    case .json(let value, _), .errorJson(let value, _):
                        contentValue = stringifyJSONValue(value)
                    case .content(let parts, _):
                        let jsonParts = parts.map { part -> JSONValue in
                            switch part {
                            case .text(let text):
                                return .object([
                                    "type": .string("text"),
                                    "text": .string(text)
                                ])
                            case .media(let data, let mediaType):
                                return .object([
                                    "type": .string("media"),
                                    "mediaType": .string(mediaType),
                                    "data": .string(data)
                                ])
                            }
                        }
                        contentValue = stringifyJSONValue(.array(jsonParts))
                    }

                    messages.append(.object([
                        "role": .string("tool"),
                        "tool_call_id": .string(toolResult.toolCallId),
                        "content": .string(contentValue)
                    ]))
                }
            }
        }

        return messages
    }
}

func convertToGroqChatMessages(_ prompt: LanguageModelV3Prompt) throws -> [JSONValue] {
    try GroqChatMessageBuilder.convert(prompt)
}

func stringifyJSONValue(_ value: JSONValue) -> String {
    if let data = try? JSONEncoder().encode(value),
       let string = String(data: data, encoding: .utf8) {
        return string
    }
    return "null"
}
