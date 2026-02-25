import AISDKProvider
import AISDKProviderUtils
import Foundation

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/open-responses/src/responses/convert-to-open-responses-input.ts
// Upstream commit: 73d5c59
//===----------------------------------------------------------------------===//

public struct OpenResponsesInputConversionResult: Sendable, Equatable {
    public let input: [JSONValue]
    public let instructions: String?
    public let warnings: [SharedV3Warning]

    public init(input: [JSONValue], instructions: String?, warnings: [SharedV3Warning]) {
        self.input = input
        self.instructions = instructions
        self.warnings = warnings
    }
}

public func convertToOpenResponsesInput(prompt: LanguageModelV3Prompt) async -> OpenResponsesInputConversionResult {
    var input: [JSONValue] = []
    var warnings: [SharedV3Warning] = []
    var systemMessages: [String] = []

    func jsonStringify(_ value: JSONValue) -> String {
        do {
            let data = try JSONEncoder().encode(value)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            switch value {
            case .array:
                return "[]"
            case .object:
                return "{}"
            default:
                return "{}"
            }
        }
    }

    for message in prompt {
        switch message {
        case .system(let content, _):
            systemMessages.append(content)

        case .user(let content, _):
            var userContent: [JSONValue] = []
            userContent.reserveCapacity(content.count)

            for part in content {
                switch part {
                case .text(let textPart):
                    userContent.append(.object([
                        "type": .string("input_text"),
                        "text": .string(textPart.text)
                    ]))

                case .file(let filePart):
                    if !filePart.mediaType.hasPrefix("image/") {
                        warnings.append(.other(message: "unsupported file content type: \(filePart.mediaType)"))
                        continue
                    }

                    let resolvedMediaType = filePart.mediaType == "image/*" ? "image/jpeg" : filePart.mediaType

                    let imageURL: String
                    switch filePart.data {
                    case .url(let url):
                        imageURL = url.absoluteString
                    case .data(let data):
                        let b64 = convertToBase64(.data(data))
                        imageURL = "data:\(resolvedMediaType);base64,\(b64)"
                    case .base64(let b64):
                        imageURL = "data:\(resolvedMediaType);base64,\(b64)"
                    }

                    userContent.append(.object([
                        "type": .string("input_image"),
                        "image_url": .string(imageURL)
                    ]))
                }
            }

            input.append(.object([
                "type": .string("message"),
                "role": .string("user"),
                "content": .array(userContent)
            ]))

        case .assistant(let content, _):
            var assistantContent: [JSONValue] = []
            var toolCalls: [JSONValue] = []

            for part in content {
                switch part {
                case .text(let textPart):
                    assistantContent.append(.object([
                        "type": .string("output_text"),
                        "text": .string(textPart.text)
                    ]))

                case .toolCall(let toolCallPart):
                    let argumentsValue: String
                    if case .string(let raw) = toolCallPart.input {
                        argumentsValue = raw
                    } else {
                        argumentsValue = jsonStringify(toolCallPart.input)
                    }

                    toolCalls.append(.object([
                        "type": .string("function_call"),
                        "call_id": .string(toolCallPart.toolCallId),
                        "name": .string(toolCallPart.toolName),
                        "arguments": .string(argumentsValue)
                    ]))

                default:
                    // Reasoning/file/tool results do not appear in V3 prompt assistant content in upstream.
                    continue
                }
            }

            if !assistantContent.isEmpty {
                input.append(.object([
                    "type": .string("message"),
                    "role": .string("assistant"),
                    "content": .array(assistantContent)
                ]))
            }

            input.append(contentsOf: toolCalls)

        case .tool(let content, _):
            for part in content {
                guard case .toolResult(let toolResult) = part else { continue }

                let contentValue: JSONValue
                switch toolResult.output {
                case .text(let value, _), .errorText(let value, _):
                    contentValue = .string(value)
                case .executionDenied(let reason, _):
                    contentValue = .string(reason ?? "Tool execution denied.")
                case .json(let value, _), .errorJson(let value, _):
                    contentValue = .string(jsonStringify(value))
                case .content(let value, _):
                    var parts: [JSONValue] = []
                    parts.reserveCapacity(value.count)

                    for item in value {
                        switch item {
                        case .text(let text):
                            parts.append(.object([
                                "type": .string("input_text"),
                                "text": .string(text)
                            ]))
                        case .media(let data, let mediaType):
                            parts.append(.object([
                                "type": .string("input_image"),
                                "image_url": .string("data:\(mediaType);base64,\(data)")
                            ]))
                        }
                    }

                    contentValue = .array(parts)
                }

                input.append(.object([
                    "type": .string("function_call_output"),
                    "call_id": .string(toolResult.toolCallId),
                    "output": contentValue
                ]))
            }
        }
    }

    let instructions = systemMessages.isEmpty ? nil : systemMessages.joined(separator: "\n")
    return OpenResponsesInputConversionResult(input: input, instructions: instructions, warnings: warnings)
}

