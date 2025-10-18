import Foundation
import AISDKProvider
import AISDKProviderUtils

struct OpenAIResponsesInputBuilder {
    static func makeInput(
        prompt: LanguageModelV3Prompt,
        systemMessageMode: SystemMessageMode = .system,
        fileIdPrefixes: [String]? = ["file-"],
        store: Bool = true
    ) async throws -> (input: OpenAIResponsesInput, warnings: [LanguageModelV3CallWarning]) {
        var items: [JSONValue] = []
        var warnings: [LanguageModelV3CallWarning] = []

        for message in prompt {
            switch message {
            case let .system(content, _):
                switch systemMessageMode {
                case .system:
                    items.append(systemItem(role: "system", content: content))
                case .developer:
                    items.append(systemItem(role: "developer", content: content))
                case .remove:
                    warnings.append(.other(message: "system messages are removed for this model"))
                }

            case let .user(parts, _):
                let content: [JSONValue] = try parts.enumerated().map { index, part in
                    switch part {
                    case .text(let textPart):
                        return .object([
                            "type": .string("input_text"),
                            "text": .string(textPart.text)
                        ])
                    case .file(let filePart):
                        return try convertFilePart(part: filePart, index: index, prefixes: fileIdPrefixes)
                    }
                }

                items.append(.object([
                    "role": .string("user"),
                    "content": .array(content)
                ]))

            case let .assistant(parts, _):
                for part in parts {
                    switch part {
                    case .text(let textPart):
                        items.append(.object([
                            "role": .string("assistant"),
                            "content": .array([
                                .object([
                                    "type": .string("output_text"),
                                    "text": .string(textPart.text)
                                ])
                            ])
                        ]))
                    case .toolCall(let callPart):
                        if callPart.providerExecuted == true { continue }
                        items.append(try makeToolCallItem(part: callPart))
                    case .toolResult(let resultPart):
                        if store {
                            items.append(.object([
                                "type": .string("item_reference"),
                                "id": .string(resultPart.toolCallId)
                            ]))
                        } else {
                            items.append(try makeToolResultItem(part: resultPart))
                        }
                    case .file, .reasoning:
                        continue
                    }
                }

            case .tool:
                throw UnsupportedFunctionalityError(functionality: "tool messages not yet supported")
            }
        }

        return (items, warnings)
    }

    private static func systemItem(role: String, content: String) -> JSONValue {
        .object([
            "role": .string(role),
            "content": .array([
                .object([
                    "type": .string("output_text"),
                    "text": .string(content)
                ])
            ])
        ])
    }

    private static func convertFilePart(part: LanguageModelV3FilePart, index: Int, prefixes: [String]?) throws -> JSONValue {
        if part.mediaType.hasPrefix("image/") {
            let mediaType = part.mediaType == "image/*" ? "image/jpeg" : part.mediaType
            switch part.data {
            case .url(let url):
                return .object([
                    "type": .string("input_image"),
                    "image_url": .string(url.absoluteString)
                ])
            case .base64(let value):
                if isFileId(value, prefixes: prefixes) {
                    return .object([
                        "type": .string("input_image"),
                        "file_id": .string(value)
                    ])
                }
                return .object([
                    "type": .string("input_image"),
                    "image_url": .string("data:\(mediaType);base64,\(value)")
                ])
            case .data(let data):
                let base64 = convertDataToBase64(data)
                return .object([
                    "type": .string("input_image"),
                    "image_url": .string("data:\(mediaType);base64,\(base64)")
                ])
            }
        }

        if part.mediaType == "application/pdf" {
            switch part.data {
            case .url(let url):
                return .object([
                    "type": .string("input_file"),
                    "file_url": .string(url.absoluteString)
                ])
            case .base64(let value):
                if isFileId(value, prefixes: prefixes) {
                    return .object([
                        "type": .string("input_file"),
                        "file_id": .string(value)
                    ])
                }
                return .object([
                    "type": .string("input_file"),
                    "filename": .string(part.filename ?? "part-\(index).pdf"),
                    "file_data": .string("data:application/pdf;base64,\(value)")
                ])
            case .data(let data):
                let base64 = convertDataToBase64(data)
                return .object([
                    "type": .string("input_file"),
                    "filename": .string(part.filename ?? "part-\(index).pdf"),
                    "file_data": .string("data:application/pdf;base64,\(base64)")
                ])
            }
        }

        throw UnsupportedFunctionalityError(functionality: "file media type \(part.mediaType)")
    }

    private static func isFileId(_ value: String, prefixes: [String]?) -> Bool {
        guard let prefixes else { return false }
        return prefixes.contains { value.hasPrefix($0) }
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

        let anyValue = toAny(value)
        let data = try JSONSerialization.data(withJSONObject: anyValue, options: [])
        guard let string = String(data: data, encoding: .utf8) else {
            throw UnsupportedFunctionalityError(functionality: "Unable to encode JSON value")
        }
        return string
    }

    private static func toolResultOutputToJSON(_ output: LanguageModelV3ToolResultOutput) -> JSONValue {
        switch output {
        case .text(let value):
            return .string(value)
        case .json(let value):
            return value
        case .executionDenied(let reason):
            return .object([
                "type": .string("execution_denied"),
                "reason": reason.map(JSONValue.string) ?? .null
            ])
        case .errorText(let value):
            return .object([
                "type": .string("error_text"),
                "value": .string(value)
            ])
        case .errorJson(let value):
            return .object([
                "type": .string("error_json"),
                "value": value
            ])
        case .content(let parts):
            return .array(parts.map { part in
                switch part {
                case .text(let text):
                    return .object([
                        "type": .string("text"),
                        "text": .string(text)
                    ])
                case .media(let data, let mediaType):
                    return .object([
                        "type": .string("media"),
                        "data": .string(data),
                        "media_type": .string(mediaType)
                    ])
                }
            })
        }
    }

    private static func makeToolCallItem(part: LanguageModelV3ToolCallPart) throws -> JSONValue {
        let arguments = try encodeJSONValue(part.input)
        return .object([
            "type": .string("function_call"),
            "call_id": .string(part.toolCallId),
            "name": .string(part.toolName),
            "arguments": .string(arguments)
        ])
    }

    private static func makeToolResultItem(part: LanguageModelV3ToolResultPart) throws -> JSONValue {
        let jsonValue = toolResultOutputToJSON(part.output)
        let resultJSON = try encodeJSONValue(jsonValue)
        return .object([
            "type": .string("function_call_output"),
            "call_id": .string(part.toolCallId),
            "output": .string(resultJSON)
        ])
    }

    enum SystemMessageMode {
        case system
        case developer
        case remove
    }
}
