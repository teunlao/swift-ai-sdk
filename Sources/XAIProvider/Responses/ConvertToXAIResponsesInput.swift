import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Converts AI SDK prompts to the xAI Responses API input format.
/// Mirrors `packages/xai/src/responses/convert-to-xai-responses-input.ts`.
func convertToXAIResponsesInput(
    prompt: LanguageModelV3Prompt,
    store: Bool? = nil
) async throws -> (input: XAIResponsesInput, warnings: [SharedV3Warning]) {
    _ = store // `store` is part of the upstream signature but currently not used.

    var input: XAIResponsesInput = []
    var warnings: [SharedV3Warning] = []

    for message in prompt {
        switch message {
        case .system(let content, _):
            input.append(.object([
                "role": .string("system"),
                "content": .string(content)
            ]))

        case .user(let parts, _):
            var contentParts: [JSONValue] = []
            contentParts.reserveCapacity(parts.count)

            for part in parts {
                switch part {
                case .text(let textPart):
                    contentParts.append(.object([
                        "type": .string("input_text"),
                        "text": .string(textPart.text)
                    ]))

                case .file(let filePart):
                    guard filePart.mediaType.hasPrefix("image/") else {
                        throw UnsupportedFunctionalityError(
                            functionality: "file part media type \(filePart.mediaType)"
                        )
                    }

                    let resolvedMediaType = filePart.mediaType == "image/*" ? "image/jpeg" : filePart.mediaType
                    let imageURL: String
                    switch filePart.data {
                    case .url(let url):
                        imageURL = url.absoluteString
                    case .base64(let base64):
                        imageURL = "data:\(resolvedMediaType);base64,\(convertToBase64(.string(base64)))"
                    case .data(let data):
                        imageURL = "data:\(resolvedMediaType);base64,\(convertToBase64(.data(data)))"
                    }

                    contentParts.append(.object([
                        "type": .string("input_image"),
                        "image_url": .string(imageURL)
                    ]))
                }
            }

            input.append(.object([
                "role": .string("user"),
                "content": .array(contentParts)
            ]))

        case .assistant(let parts, _):
            for part in parts {
                switch part {
                case .text(let textPart):
                    var payload: [String: JSONValue] = [
                        "role": .string("assistant"),
                        "content": .string(textPart.text)
                    ]

                    if let itemId = xaiItemId(from: textPart.providerOptions) {
                        payload["id"] = .string(itemId)
                    }

                    input.append(.object(payload))

                case .toolCall(let toolCallPart):
                    // Skip server-side tool calls (provider-executed) for Responses API input.
                    if toolCallPart.providerExecuted == true {
                        break
                    }

                    let itemId = xaiItemId(from: toolCallPart.providerOptions) ?? toolCallPart.toolCallId
                    input.append(.object([
                        "type": .string("function_call"),
                        "id": .string(itemId),
                        "call_id": .string(toolCallPart.toolCallId),
                        "name": .string(toolCallPart.toolName),
                        "arguments": .string(stringifyJSONValue(toolCallPart.input)),
                        "status": .string("completed")
                    ]))

                case .toolResult:
                    break

                case .reasoning:
                    warnings.append(.other(message: "xAI Responses API does not support reasoning in assistant messages"))

                case .file:
                    warnings.append(.other(message: "xAI Responses API does not support file in assistant messages"))
                }
            }

        case .tool(let parts, _):
            for part in parts {
                switch part {
                case .toolApprovalResponse:
                    continue
                case .toolResult(let toolResultPart):
                    let outputValue: String
                    switch toolResultPart.output {
                    case .text(let value, _), .errorText(let value, _):
                        outputValue = value
                    case .executionDenied(let reason, _):
                        outputValue = reason ?? "tool execution denied"
                    case .json(let value, _), .errorJson(let value, _):
                        outputValue = stringifyJSONValue(value)
                    case .content(let parts, _):
                        outputValue = parts.map { part -> String in
                            switch part {
                            case .text(let text):
                                return text
                            case .media:
                                return ""
                            }
                        }.joined()
                    }

                    input.append(.object([
                        "type": .string("function_call_output"),
                        "call_id": .string(toolResultPart.toolCallId),
                        "output": .string(outputValue)
                    ]))
                }
            }
        }
    }

    return (input: input, warnings: warnings)
}

private func xaiItemId(from providerOptions: SharedV3ProviderOptions?) -> String? {
    guard let providerOptions,
          let xai = providerOptions["xai"],
          case .string(let itemId) = xai["itemId"] else {
        return nil
    }
    return itemId
}

private func stringifyJSONValue(_ value: JSONValue) -> String {
    if let data = try? JSONEncoder().encode(value),
       let string = String(data: data, encoding: .utf8) {
        return string
    }
    return "null"
}

