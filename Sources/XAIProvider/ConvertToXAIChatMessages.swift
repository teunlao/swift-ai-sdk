import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Converts AI SDK prompts to the xAI wire format.
/// Mirrors `packages/xai/src/convert-to-xai-chat-messages.ts`.
func convertToXAIChatMessages(_ prompt: LanguageModelV3Prompt) throws -> (messages: XAIChatPrompt, warnings: [LanguageModelV3CallWarning]) {
    var messages: XAIChatPrompt = []
    let warnings: [LanguageModelV3CallWarning] = []

    for message in prompt {
        switch message {
        case .system(let content, _):
            messages.append(XAIChatMessage(role: .system, textContent: content))

        case .user(let parts, _):
            if parts.count == 1, case .text(let textPart) = parts[0] {
                messages.append(XAIChatMessage(role: .user, textContent: textPart.text))
                continue
            }

            var contentParts: [XAIUserMessageContent] = []
            contentParts.reserveCapacity(parts.count)

            for part in parts {
                switch part {
                case .text(let textPart):
                    contentParts.append(.text(textPart.text))
                case .file(let filePart):
                    guard filePart.mediaType.hasPrefix("image/") else {
                        throw UnsupportedFunctionalityError(functionality: "file part media type \(filePart.mediaType)")
                    }

                    let resolvedMediaType = filePart.mediaType == "image/*" ? "image/jpeg" : filePart.mediaType
                    let url: String
                    switch filePart.data {
                    case .url(let fileURL):
                        url = fileURL.absoluteString
                    case .base64(let base64):
                        url = "data:\(resolvedMediaType);base64,\(base64)"
                    case .data(let data):
                        url = "data:\(resolvedMediaType);base64,\(convertDataToBase64(data))"
                    }

                    contentParts.append(.imageURL(url))
                }
            }

            messages.append(XAIChatMessage(role: .user, userContentParts: contentParts))

        case .assistant(let parts, _):
            var text = ""
            var toolCalls: [XAIChatMessage.ToolCall] = []

            for part in parts {
                switch part {
                case .text(let textPart):
                    text.append(textPart.text)
                case .toolCall(let toolCallPart):
                    toolCalls.append(
                        XAIChatMessage.ToolCall(
                            id: toolCallPart.toolCallId,
                            name: toolCallPart.toolName,
                            arguments: stringifyJSONValue(toolCallPart.input)
                        )
                    )
                case .reasoning, .file, .toolResult:
                    continue
                }
            }

            messages.append(XAIChatMessage(role: .assistant, textContent: text.isEmpty ? nil : text, toolCalls: toolCalls.isEmpty ? nil : toolCalls))

        case .tool(let results, _):
            for part in results {
                guard case .toolResult(let result) = part else { continue }
                let content: String
                switch result.output {
                case .text(let value, _):
                    content = value
                case .errorText(let value, _):
                    content = value
                case .executionDenied(let reason, _):
                    content = reason ?? "Tool execution denied."
                case .json(let value, _), .errorJson(let value, _):
                    content = stringifyJSONValue(value)
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
                    content = stringifyJSONValue(.array(jsonParts))
                }

                messages.append(
                    XAIChatMessage(
                        role: .tool,
                        textContent: content,
                        toolCallId: result.toolCallId
                    )
                )
            }
        }
    }

    return (messages, warnings)
}

private func stringifyJSONValue(_ value: JSONValue) -> String {
    if let data = try? JSONEncoder().encode(value),
       let string = String(data: data, encoding: .utf8) {
        return string
    }
    return "null"
}
