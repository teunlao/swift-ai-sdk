import Foundation
import AISDKProvider
import AISDKProviderUtils

struct OpenAIResponsesInputBuilder {
    static func makeInput(
        prompt: LanguageModelV3Prompt,
        systemMessageMode: OpenAIResponsesSystemMessageMode = .system,
        fileIdPrefixes: [String]? = ["file-"],
        store: Bool = true,
        hasLocalShellTool: Bool = false
    ) async throws -> (input: OpenAIResponsesInput, warnings: [LanguageModelV3CallWarning]) {
        var items: [JSONValue] = []
        var warnings: [LanguageModelV3CallWarning] = []
        var reasoningReferences: Set<String> = []

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
                let content = try parts.enumerated().map { index, part in
                    try convertUserPart(part, index: index, prefixes: fileIdPrefixes)
                }

                items.append(.object([
                    "role": .string("user"),
                    "content": .array(content)
                ]))

            case let .assistant(parts, _):
                var reasoningMessages: [String: ReasoningAccumulator] = [:]

                for part in parts {
                    switch part {
                    case .text(let textPart):
                        var payload: [String: JSONValue] = [
                            "role": .string("assistant"),
                            "content": .array([
                                .object([
                                    "type": .string("output_text"),
                                    "text": .string(textPart.text)
                                ])
                            ])
                        ]

                        if let itemId = extractOpenAIItemId(from: textPart.providerOptions) {
                            payload["id"] = .string(itemId)
                        }

                        items.append(.object(payload))

                    case .toolCall(let callPart):
                        if callPart.providerExecuted == true {
                            continue
                        }

                        if hasLocalShellTool, callPart.toolName == "local_shell" {
                            let parsed = try await validateTypes(
                                ValidateTypesOptions(value: callPart.input, schema: openaiLocalShellInputSchema)
                            )

                            var action: [String: JSONValue] = [
                                "type": .string("exec"),
                                "command": .array(parsed.action.command.map(JSONValue.string))
                            ]
                            if let timeout = parsed.action.timeoutMs {
                                action["timeout_ms"] = .number(Double(timeout))
                            }
                            if let user = parsed.action.user {
                                action["user"] = .string(user)
                            }
                            if let workingDirectory = parsed.action.workingDirectory {
                                action["working_directory"] = .string(workingDirectory)
                            }
                            if let env = parsed.action.env {
                                action["env"] = .object(env.mapValues(JSONValue.string))
                            }

                            var payload: [String: JSONValue] = [
                                "type": .string("local_shell_call"),
                                "call_id": .string(callPart.toolCallId),
                                "action": .object(action)
                            ]

                            if let itemId = extractOpenAIItemId(from: callPart.providerOptions) {
                                payload["id"] = .string(itemId)
                            }

                            items.append(.object(payload))
                            continue
                        }

                        let arguments = try encodeJSONValue(callPart.input)
                        var payload: [String: JSONValue] = [
                            "type": .string("function_call"),
                            "call_id": .string(callPart.toolCallId),
                            "name": .string(callPart.toolName),
                            "arguments": .string(arguments)
                        ]
                        if let itemId = extractOpenAIItemId(from: callPart.providerOptions) {
                            payload["id"] = .string(itemId)
                        }
                        items.append(.object(payload))

                    case .toolResult(let resultPart):
                        if store {
                            items.append(.object([
                                "type": .string("item_reference"),
                                "id": .string(resultPart.toolCallId)
                            ]))
                        } else {
                            items.append(try makeToolResultItem(part: resultPart))
                        }

                    case .reasoning(let reasoningPart):
                        let providerOptions = try await parseProviderOptions(
                            provider: "openai",
                            providerOptions: reasoningPart.providerOptions,
                            schema: openAIResponsesReasoningProviderOptionsSchema
                        )

                        guard let reasoningId = providerOptions?.itemId else {
                            warnings.append(.other(message: "Non-OpenAI reasoning parts are not supported. Skipping reasoning part: \(reasoningPart.text)."))
                            continue
                        }

                        if store {
                            if !reasoningReferences.contains(reasoningId) {
                                items.append(.object([
                                    "type": .string("item_reference"),
                                    "id": .string(reasoningId)
                                ]))
                                reasoningReferences.insert(reasoningId)
                            }
                            continue
                        }

                        var accumulator = reasoningMessages[reasoningId]
                        if accumulator == nil {
                            let newAccumulator = ReasoningAccumulator(
                                id: reasoningId,
                                encryptedContent: providerOptions?.reasoningEncryptedContent,
                                summaryParts: [],
                                itemIndex: items.count
                            )
                            items.append(newAccumulator.asJSONValue())
                            reasoningMessages[reasoningId] = newAccumulator
                            accumulator = newAccumulator
                        }

                        guard var existing = accumulator else { continue }

                        if !reasoningPart.text.isEmpty {
                            existing.summaryParts.append(.object([
                                "type": .string("summary_text"),
                                "text": .string(reasoningPart.text)
                            ]))
                            items[existing.itemIndex] = existing.asJSONValue()
                            reasoningMessages[reasoningId] = existing
                        } else {
                            warnings.append(.other(message: "Cannot append empty reasoning part to existing reasoning sequence. Skipping reasoning part for id \(reasoningId)."))
                        }

                    case .file:
                        continue
                    }
                }

            case let .tool(parts, _):
                for part in parts {
                    switch part.output {
                    case .json(let value):
                        if hasLocalShellTool, part.toolName == "local_shell" {
                            let parsed = try await validateTypes(
                                ValidateTypesOptions(value: value, schema: openaiLocalShellOutputSchema)
                            )

                            items.append(.object([
                                "type": .string("local_shell_call_output"),
                                "call_id": .string(part.toolCallId),
                                "output": .string(parsed.output)
                            ]))
                            continue
                        }
                        let jsonString = try encodeJSONValue(value)
                        items.append(makeToolResultObject(toolCallId: part.toolCallId, output: .string(jsonString)))

                    case .text(let value):
                        items.append(makeToolResultObject(toolCallId: part.toolCallId, output: .string(value)))

                    case .executionDenied(let reason):
                        let message = reason ?? "Tool execution denied."
                        items.append(makeToolResultObject(toolCallId: part.toolCallId, output: .string(message)))

                    case .errorText(let value):
                        items.append(makeToolResultObject(toolCallId: part.toolCallId, output: .string(value)))

                    case .errorJson(let value):
                        let jsonString = try encodeJSONValue(value)
                        items.append(makeToolResultObject(toolCallId: part.toolCallId, output: .string(jsonString)))

                    case .content(let contentParts):
                        let converted = contentParts.map { item -> JSONValue in
                            switch item {
                            case .text(let text):
                                return .object([
                                    "type": .string("input_text"),
                                    "text": .string(text)
                                ])
                            case .media(let data, let mediaType):
                                if mediaType.hasPrefix("image/") {
                                    return .object([
                                        "type": .string("input_image"),
                                        "image_url": .string("data:\(mediaType);base64,\(data)")
                                    ])
                                }
                                return .object([
                                    "type": .string("input_file"),
                                    "filename": .string("data"),
                                    "file_data": .string("data:\(mediaType);base64,\(data)")
                                ])
                            }
                        }
                        items.append(makeToolResultObject(toolCallId: part.toolCallId, output: .array(converted)))
                    }
                }
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

    private static func convertUserPart(
        _ part: LanguageModelV3UserMessagePart,
        index: Int,
        prefixes: [String]?
    ) throws -> JSONValue {
        switch part {
        case .text(let textPart):
            return .object([
                "type": .string("input_text"),
                "text": .string(textPart.text)
            ])
        case .file(let filePart):
            return try convertFilePart(part: filePart, index: index, prefixes: prefixes)
        }
    }

    private static func convertFilePart(
        part: LanguageModelV3FilePart,
        index: Int,
        prefixes: [String]?
    ) throws -> JSONValue {
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

        let data = try JSONSerialization.data(withJSONObject: toAny(value), options: [])
        guard let string = String(data: data, encoding: .utf8) else {
            throw UnsupportedFunctionalityError(functionality: "Unable to encode JSON value")
        }
        return string
    }

    private static func makeToolResultObject(toolCallId: String, output: JSONValue) -> JSONValue {
        .object([
            "type": .string("function_call_output"),
            "call_id": .string(toolCallId),
            "output": output
        ])
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
                        "type": .string("input_text"),
                        "text": .string(text)
                    ])
                case .media(let data, let mediaType):
                    if mediaType.hasPrefix("image/") {
                        return .object([
                            "type": .string("input_image"),
                            "image_url": .string("data:\(mediaType);base64,\(data)")
                        ])
                    }
                    return .object([
                        "type": .string("input_file"),
                        "filename": .string("data"),
                        "file_data": .string("data:\(mediaType);base64,\(data)")
                    ])
                }
            })
        }
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

    private static func extractOpenAIItemId(from options: ProviderOptions?) -> String? {
        guard let options,
              let openaiOptions = options["openai"],
              case .string(let itemId) = openaiOptions["itemId"] else {
            return nil
        }
        return itemId
    }
}

private struct ReasoningAccumulator: Sendable {
    let id: String
    var encryptedContent: String?
    var summaryParts: [JSONValue]
    let itemIndex: Int

    func asJSONValue() -> JSONValue {
        var payload: [String: JSONValue] = [
            "type": .string("reasoning"),
            "id": .string(id),
            "summary": .array(summaryParts)
        ]
        if let encryptedContent {
            payload["encrypted_content"] = .string(encryptedContent)
        }
        return .object(payload)
    }
}

private struct OpenAIResponsesReasoningProviderOptions: Sendable, Equatable {
    let itemId: String?
    let reasoningEncryptedContent: String?
}

private let openAIResponsesReasoningProviderOptionsSchema = FlexibleSchema<OpenAIResponsesReasoningProviderOptions>(
    Schema(
        jsonSchemaResolver: {
            .object([
                "type": .string("object"),
                "additionalProperties": .bool(true),
                "properties": .object([
                    "itemId": .object(["type": .array([.string("string"), .string("null")])]),
                    "reasoningEncryptedContent": .object(["type": .array([.string("string"), .string("null")])])
                ])
            ])
        },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(vendor: "openai", issues: "expected object")
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                let itemId = try parseOptionalString(dict, key: "itemId")
                let encrypted = try parseOptionalString(dict, key: "reasoningEncryptedContent")
                return .success(value: OpenAIResponsesReasoningProviderOptions(itemId: itemId, reasoningEncryptedContent: encrypted))
            } catch let error as TypeValidationError {
                return .failure(error: error)
            } catch {
                let wrapped = TypeValidationError.wrap(value: value, cause: error)
                return .failure(error: wrapped)
            }
        }
    )
)

private func parseOptionalString(_ dict: [String: JSONValue], key: String) throws -> String? {
    guard let value = dict[key], value != .null else { return nil }
    guard case .string(let stringValue) = value else {
        let error = SchemaValidationIssuesError(vendor: "openai", issues: "\(key) must be a string")
        throw TypeValidationError.wrap(value: value, cause: error)
    }
    return stringValue
}
