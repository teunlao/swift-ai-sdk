import Foundation
import AISDKProvider
import AISDKProviderUtils

typealias OpenAIChatPrompt = [JSONValue]

struct OpenAIChatMessagesConverter {
    static func convert(
        prompt: LanguageModelV3Prompt,
        systemMessageMode: OpenAIChatSystemMessageMode
    ) throws -> (messages: OpenAIChatPrompt, warnings: [SharedV3Warning]) {
        var messages: OpenAIChatPrompt = []
        var warnings: [SharedV3Warning] = []

        for message in prompt {
            switch message {
            case .system(let content, _):
                switch systemMessageMode {
                case .system:
                    messages.append(.object([
                        "role": .string("system"),
                        "content": .string(content)
                    ]))
                case .developer:
                    messages.append(.object([
                        "role": .string("developer"),
                        "content": .string(content)
                    ]))
                case .remove:
                    warnings.append(.other(message: "system messages are removed for this model"))
                }

            case .user(let parts, _):
                if parts.count == 1, case .text(let textPart) = parts[0] {
                    messages.append(.object([
                        "role": .string("user"),
                        "content": .string(textPart.text)
                    ]))
                    continue
                }

                var convertedParts: [JSONValue] = []
                convertedParts.reserveCapacity(parts.count)

                for (partIndex, part) in parts.enumerated() {
                    switch part {
                    case .text(let textPart):
                        convertedParts.append(.object([
                            "type": .string("text"),
                            "text": .string(textPart.text)
                        ]))

                    case .file(let filePart):
                        let mediaType = filePart.mediaType

                        if mediaType.hasPrefix("image/") {
                            let urlValue: String
                            switch filePart.data {
                            case .url(let url):
                                urlValue = url.absoluteString
                            case .base64(let base64):
                                let resolved = mediaType == "image/*" ? "image/jpeg" : mediaType
                                urlValue = "data:\(resolved);base64,\(base64)"
                            case .data(let data):
                                let resolved = mediaType == "image/*" ? "image/jpeg" : mediaType
                                urlValue = "data:\(resolved);base64,\(convertDataToBase64(data))"
                            }

                            var imageURL: [String: JSONValue] = [
                                "url": .string(urlValue)
                            ]

                            if let detail = openAIImageDetail(from: filePart.providerOptions) {
                                imageURL["detail"] = .string(detail)
                            }

                            convertedParts.append(.object([
                                "type": .string("image_url"),
                                "image_url": .object(imageURL)
                            ]))
                        } else if mediaType.hasPrefix("audio/") {
                            let format = try audioFormat(for: mediaType)
                            let base64Data: String
                            switch filePart.data {
                            case .data(let data):
                                base64Data = convertDataToBase64(data)
                            case .base64(let base64):
                                base64Data = base64
                            case .url:
                                throw UnsupportedFunctionalityError(functionality: "audio file parts with URLs")
                            }

                            convertedParts.append(.object([
                                "type": .string("input_audio"),
                                "input_audio": .object([
                                    "data": .string(base64Data),
                                    "format": .string(format)
                                ])
                            ]))
                        } else if mediaType == "application/pdf" {
                            guard case .url = filePart.data else {
                                let fileObject: JSONValue
                                switch filePart.data {
                                case .base64(let base64):
                                    if base64.hasPrefix("file-") {
                                        fileObject = .object([
                                            "file_id": .string(base64)
                                        ])
                                    } else {
                                        let encoded = "data:application/pdf;base64,\(base64)"
                                        fileObject = .object([
                                            "filename": .string(filePart.filename ?? "part-\(partIndex).pdf"),
                                            "file_data": .string(encoded)
                                        ])
                                    }
                                case .data(let data):
                                    let encoded = "data:application/pdf;base64,\(convertDataToBase64(data))"
                                    fileObject = .object([
                                        "filename": .string(filePart.filename ?? "part-\(partIndex).pdf"),
                                        "file_data": .string(encoded)
                                    ])
                                case .url:
                                    throw UnsupportedFunctionalityError(functionality: "PDF file parts with URLs")
                                }

                                convertedParts.append(.object([
                                    "type": .string("file"),
                                    "file": fileObject
                                ]))
                                continue
                            }
                            throw UnsupportedFunctionalityError(functionality: "PDF file parts with URLs")
                        } else {
                            throw UnsupportedFunctionalityError(functionality: "file part media type \(mediaType)")
                        }
                    }
                }

                messages.append(.object([
                    "role": .string("user"),
                    "content": .array(convertedParts)
                ]))

            case .assistant(let parts, _):
                var text = ""
                var toolCalls: [JSONValue] = []

                for part in parts {
                    switch part {
                    case .text(let textPart):
                        text.append(textPart.text)
                    case .toolCall(let toolCall):
                        let arguments = try encodeJSONValue(toolCall.input)
                        toolCalls.append(.object([
                            "type": .string("function"),
                            "id": .string(toolCall.toolCallId),
                            "function": .object([
                                "name": .string(toolCall.toolName),
                                "arguments": .string(arguments)
                            ])
                        ]))
                    case .toolResult, .file, .reasoning:
                        throw UnsupportedFunctionalityError(functionality: "assistant content part \(part)")
                    }
                }

                var messageObject: [String: JSONValue] = [
                    "role": .string("assistant"),
                    "content": .string(text)
                ]

                if !toolCalls.isEmpty {
                    messageObject["tool_calls"] = .array(toolCalls)
                }

                messages.append(.object(messageObject))

            case .tool(let toolResponses, _):
                for part in toolResponses {
                    guard case .toolResult(let toolResponse) = part else { continue }
                    let contentValue: String
                    switch toolResponse.output {
                    case .text(let value, _), .errorText(let value, _):
                        contentValue = value
                    case .executionDenied(let reason, _):
                        contentValue = reason ?? "Tool execution denied."
                    case .json(let value, _), .errorJson(let value, _):
                        contentValue = try encodeJSONValue(value)
                    case .content(let parts, _):
                        contentValue = try encodeEncodable(parts)
                    }

                    messages.append(.object([
                        "role": .string("tool"),
                        "tool_call_id": .string(toolResponse.toolCallId),
                        "content": .string(contentValue)
                    ]))
                }
            }
        }

        return (messages, warnings)
    }

    private static func openAIImageDetail(from options: SharedV3ProviderOptions?) -> String? {
        guard let detailValue = options?["openai"]?["imageDetail"] else { return nil }
        if case .string(let detail) = detailValue {
            return detail
        }
        return nil
    }

    private static func audioFormat(for mediaType: String) throws -> String {
        switch mediaType {
        case "audio/wav":
            return "wav"
        case "audio/mp3", "audio/mpeg":
            return "mp3"
        default:
            throw UnsupportedFunctionalityError(functionality: "audio content parts with media type \(mediaType)")
        }
    }

    private static func encodeJSONValue(_ value: JSONValue) throws -> String {
        func toAny(_ value: JSONValue) -> Any {
            switch value {
            case .null: return NSNull()
            case .bool(let bool): return bool
            case .number(let number): return number
            case .string(let string): return string
            case .array(let array): return array.map { toAny($0) }
            case .object(let object): return object.mapValues { toAny($0) }
            }
        }

        let data = try JSONSerialization.data(withJSONObject: toAny(value), options: [])
        guard let string = String(data: data, encoding: .utf8) else {
            throw UnsupportedFunctionalityError(functionality: "Unable to encode JSON value")
        }
        return string
    }

    private static func encodeEncodable<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        let data = try encoder.encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw UnsupportedFunctionalityError(functionality: "Unable to encode JSON value")
        }
        return string
    }
}
