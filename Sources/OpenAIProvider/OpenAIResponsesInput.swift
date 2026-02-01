import Foundation
import AISDKProvider
import AISDKProviderUtils

struct OpenAIResponsesInputBuilder {
    static func makeInput(
        prompt: LanguageModelV3Prompt,
        providerOptionsName: String = "openai",
        toolNameMapping: OpenAIToolNameMapping = .init(),
        systemMessageMode: OpenAIResponsesSystemMessageMode = .system,
        fileIdPrefixes: [String]? = ["file-"],
        store: Bool = true,
        hasConversation: Bool = false,
        hasLocalShellTool: Bool = false,
        hasShellTool: Bool = false,
        hasApplyPatchTool: Bool = false
    ) async throws -> (input: OpenAIResponsesInput, warnings: [LanguageModelV3CallWarning]) {
        var items: [JSONValue] = []
        var warnings: [LanguageModelV3CallWarning] = []
        var reasoningReferences: Set<String> = []
        var processedApprovalIds: Set<String> = []

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
                    try convertUserPart(
                        part,
                        index: index,
                        prefixes: fileIdPrefixes,
                        providerOptionsName: providerOptionsName
                    )
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
                        let itemId = extractOpenAIItemId(from: textPart.providerOptions, providerOptionsName: providerOptionsName)

                        if hasConversation, itemId != nil {
                            continue
                        }

                        if store, let itemId {
                            items.append(.object([
                                "type": .string("item_reference"),
                                "id": .string(itemId)
                            ]))
                            continue
                        }

                        var payload: [String: JSONValue] = [
                            "role": .string("assistant"),
                            "content": .array([
                                .object([
                                    "type": .string("output_text"),
                                    "text": .string(textPart.text)
                                ])
                            ])
                        ]

                        if let itemId {
                            payload["id"] = .string(itemId)
                        }

                        items.append(.object(payload))

                    case .toolCall(let callPart):
                        let itemId =
                            extractOpenAIItemId(from: callPart.providerOptions, providerOptionsName: providerOptionsName)
                            ?? extractOpenAIItemId(from: callPart.providerMetadata, providerOptionsName: providerOptionsName)

                        if hasConversation, itemId != nil {
                            continue
                        }

                        if callPart.providerExecuted == true {
                            if store, let itemId {
                                items.append(.object([
                                    "type": .string("item_reference"),
                                    "id": .string(itemId)
                                ]))
                            }
                            continue
                        }

                        if store, let itemId {
                            items.append(.object([
                                "type": .string("item_reference"),
                                "id": .string(itemId)
                            ]))
                            continue
                        }

                        let resolvedToolName = toolNameMapping.toProviderToolName(callPart.toolName)

                        if hasLocalShellTool, resolvedToolName == "local_shell" {
                            let parsed = try await validateTypes(
                                ValidateTypesOptions(value: jsonValueToFoundation(callPart.input), schema: openaiLocalShellInputSchema)
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

                            if let itemId {
                                payload["id"] = .string(itemId)
                            }

                            items.append(.object(payload))
                            continue
                        }

                        if hasShellTool, resolvedToolName == "shell" {
                            let parsed = try await validateTypes(
                                ValidateTypesOptions(value: jsonValueToFoundation(callPart.input), schema: openaiShellInputSchema)
                            )

                            var action: [String: JSONValue] = [
                                "commands": .array(parsed.action.commands.map(JSONValue.string))
                            ]
                            if let timeout = parsed.action.timeoutMs {
                                action["timeout_ms"] = .number(timeout)
                            }
                            if let maxOutputLength = parsed.action.maxOutputLength {
                                action["max_output_length"] = .number(maxOutputLength)
                            }

                            var payload: [String: JSONValue] = [
                                "type": .string("shell_call"),
                                "call_id": .string(callPart.toolCallId),
                                "status": .string("completed"),
                                "action": .object(action)
                            ]

                            if let itemId {
                                payload["id"] = .string(itemId)
                            }

                            items.append(.object(payload))
                            continue
                        }

                        if hasApplyPatchTool, resolvedToolName == "apply_patch" {
                            let parsed = try await validateTypes(
                                ValidateTypesOptions(value: jsonValueToFoundation(callPart.input), schema: openaiApplyPatchInputSchema)
                            )

                            let operation: JSONValue = switch parsed.operation {
                            case let .createFile(path, diff):
                                .object([
                                    "type": .string("create_file"),
                                    "path": .string(path),
                                    "diff": .string(diff)
                                ])
                            case let .deleteFile(path):
                                .object([
                                    "type": .string("delete_file"),
                                    "path": .string(path)
                                ])
                            case let .updateFile(path, diff):
                                .object([
                                    "type": .string("update_file"),
                                    "path": .string(path),
                                    "diff": .string(diff)
                                ])
                            }

                            var payload: [String: JSONValue] = [
                                "type": .string("apply_patch_call"),
                                "call_id": .string(parsed.callId),
                                "status": .string("completed"),
                                "operation": operation
                            ]

                            if let itemId {
                                payload["id"] = .string(itemId)
                            }

                            items.append(.object(payload))
                            continue
                        }

                        let arguments = try encodeJSONValue(callPart.input)
                        var payload: [String: JSONValue] = [
                            "type": .string("function_call"),
                            "call_id": .string(callPart.toolCallId),
                            "name": .string(resolvedToolName),
                            "arguments": .string(arguments)
                        ]
                        if let itemId {
                            payload["id"] = .string(itemId)
                        }
                        items.append(.object(payload))

                    case .toolResult(let resultPart):
                        if case .executionDenied = resultPart.output {
                            continue
                        }

                        if case .json(let value, _) = resultPart.output,
                           case .object(let object) = value,
                           object["type"] == .string("execution-denied") {
                            continue
                        }

                        if hasConversation {
                            continue
                        }

	                        if store {
	                            let itemId =
	                                extractOpenAIItemId(from: resultPart.providerMetadata, providerOptionsName: providerOptionsName)
	                                ?? resultPart.toolCallId
	                            items.append(.object([
	                                "type": .string("item_reference"),
	                                "id": .string(itemId)
	                            ]))
	                        } else {
                            warnings.append(.other(message: "Results for OpenAI tool \(resultPart.toolName) are not sent to the API when store is false"))
                        }

                    case .reasoning(let reasoningPart):
                        let providerOptions = try await parseProviderOptions(
                            provider: providerOptionsName,
                            providerOptions: reasoningPart.providerOptions,
                            schema: openAIResponsesReasoningProviderOptionsSchema
                        )

                        guard let reasoningId = providerOptions?.itemId else {
                            let partDescription = stringifyReasoningPart(reasoningPart)
                            warnings.append(.other(message: "Non-OpenAI reasoning parts are not supported. Skipping reasoning part: \(partDescription)."))
                            continue
                        }

                        if hasConversation {
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
                        let isFirstPart = accumulator == nil

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
                        } else if !isFirstPart {
                            // Only warn when appending empty text to existing sequence
                            let partDescription = stringifyReasoningPart(reasoningPart)
                            warnings.append(.other(message: "Cannot append empty reasoning part to existing reasoning sequence. Skipping reasoning part: \(partDescription)."))
                        }
                        // For first part with empty text, we already added the accumulator with empty summary - no warning needed

                    case .file:
                        continue
                    }
                }

            case let .tool(parts, _):
                for part in parts {
                    switch part {
                    case .toolApprovalResponse(let approvalResponse):
                        if processedApprovalIds.contains(approvalResponse.approvalId) {
                            continue
                        }
                        processedApprovalIds.insert(approvalResponse.approvalId)

                        if store {
                            items.append(.object([
                                "type": .string("item_reference"),
                                "id": .string(approvalResponse.approvalId)
                            ]))
                        }

                        items.append(.object([
                            "type": .string("mcp_approval_response"),
                            "approval_request_id": .string(approvalResponse.approvalId),
                            "approve": .bool(approvalResponse.approved)
                        ]))

                    case .toolResult(let toolResult):
                        // Skip execution-denied with approvalId - already handled via tool-approval-response
                        if case .executionDenied(_, let providerOptions) = toolResult.output,
                           extractOpenAIStringOption(from: providerOptions, providerOptionsName: "openai", key: "approvalId") != nil {
                            continue
                        }

                        let resolvedToolName = toolNameMapping.toProviderToolName(toolResult.toolName)

                        switch toolResult.output {
                        case .json(let value, _):
                            if hasLocalShellTool, resolvedToolName == "local_shell" {
                                let parsed = try await validateTypes(
                                    ValidateTypesOptions(value: jsonValueToFoundation(value), schema: openaiLocalShellOutputSchema)
                                )

                                items.append(.object([
                                    "type": .string("local_shell_call_output"),
                                    "call_id": .string(toolResult.toolCallId),
                                    "output": .string(parsed.output)
                                ]))
                                continue
                            }

                            if hasShellTool, resolvedToolName == "shell" {
                                let parsed = try await validateTypes(
                                    ValidateTypesOptions(value: jsonValueToFoundation(value), schema: openaiShellOutputSchema)
                                )

                                let output: JSONValue = .array(parsed.output.map { item in
                                    let outcome: JSONValue = switch item.outcome {
                                    case .timeout:
                                        .object(["type": .string("timeout")])
                                    case .exit(let exitCode):
                                        .object([
                                            "type": .string("exit"),
                                            "exit_code": .number(exitCode)
                                        ])
                                    }

                                    return .object([
                                        "stdout": .string(item.stdout),
                                        "stderr": .string(item.stderr),
                                        "outcome": outcome
                                    ])
                                })

                                items.append(.object([
                                    "type": .string("shell_call_output"),
                                    "call_id": .string(toolResult.toolCallId),
                                    "output": output
                                ]))
                                continue
                            }

                            if hasApplyPatchTool, resolvedToolName == "apply_patch" {
                                let parsed = try await validateTypes(
                                    ValidateTypesOptions(value: jsonValueToFoundation(value), schema: openaiApplyPatchOutputSchema)
                                )

                                var payload: [String: JSONValue] = [
                                    "type": .string("apply_patch_call_output"),
                                    "call_id": .string(toolResult.toolCallId),
                                    "status": .string(parsed.status)
                                ]
                                if let output = parsed.output {
                                    payload["output"] = .string(output)
                                }

                                items.append(.object(payload))
                                continue
                            }

                            let jsonString = try encodeJSONValue(value)
                            items.append(makeToolResultObject(toolCallId: toolResult.toolCallId, output: .string(jsonString)))

                        case .text(let value, _):
                            items.append(makeToolResultObject(toolCallId: toolResult.toolCallId, output: .string(value)))

                        case .executionDenied(let reason, _):
                            let message = reason ?? "Tool execution denied."
                            items.append(makeToolResultObject(toolCallId: toolResult.toolCallId, output: .string(message)))

                        case .errorText(let value, _):
                            items.append(makeToolResultObject(toolCallId: toolResult.toolCallId, output: .string(value)))

                        case .errorJson(let value, _):
                            let jsonString = try encodeJSONValue(value)
                            items.append(makeToolResultObject(toolCallId: toolResult.toolCallId, output: .string(jsonString)))

                        case .content(let contentParts, _):
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
                            items.append(makeToolResultObject(toolCallId: toolResult.toolCallId, output: .array(converted)))
                        }
                    }
                }
            }
        }

        return (items, warnings)
    }

    private static func systemItem(role: String, content: String) -> JSONValue {
        .object([
            "role": .string(role),
            "content": .string(content)
        ])
    }

    private static func convertUserPart(
        _ part: LanguageModelV3UserMessagePart,
        index: Int,
        prefixes: [String]?,
        providerOptionsName: String
    ) throws -> JSONValue {
        switch part {
        case .text(let textPart):
            return .object([
                "type": .string("input_text"),
                "text": .string(textPart.text)
            ])
        case .file(let filePart):
            return try convertFilePart(
                part: filePart,
                index: index,
                prefixes: prefixes,
                providerOptionsName: providerOptionsName
            )
        }
    }

    private static func convertFilePart(
        part: LanguageModelV3FilePart,
        index: Int,
        prefixes: [String]?,
        providerOptionsName: String
    ) throws -> JSONValue {
        if part.mediaType.hasPrefix("image/") {
            let mediaType = part.mediaType == "image/*" ? "image/jpeg" : part.mediaType
            let detail = extractOpenAIStringOption(
                from: part.providerOptions,
                providerOptionsName: providerOptionsName,
                key: "imageDetail"
            )
            switch part.data {
            case .url(let url):
                var payload: [String: JSONValue] = [
                    "type": .string("input_image"),
                    "image_url": .string(url.absoluteString)
                ]
                if let detail {
                    payload["detail"] = .string(detail)
                }
                return .object(payload)
            case .base64(let value):
                if isFileId(value, prefixes: prefixes) {
                    var payload: [String: JSONValue] = [
                        "type": .string("input_image"),
                        "file_id": .string(value)
                    ]
                    if let detail {
                        payload["detail"] = .string(detail)
                    }
                    return .object(payload)
                }
                var payload: [String: JSONValue] = [
                    "type": .string("input_image"),
                    "image_url": .string("data:\(mediaType);base64,\(value)")
                ]
                if let detail {
                    payload["detail"] = .string(detail)
                }
                return .object(payload)
            case .data(let data):
                let base64 = convertDataToBase64(data)
                var payload: [String: JSONValue] = [
                    "type": .string("input_image"),
                    "image_url": .string("data:\(mediaType);base64,\(base64)")
                ]
                if let detail {
                    payload["detail"] = .string(detail)
                }
                return .object(payload)
            }
        }

        if part.mediaType.hasPrefix("audio/") {
            let format: String
            switch part.mediaType {
            case "audio/wav":
                format = "wav"
            case "audio/mp3", "audio/mpeg":
                format = "mp3"
            default:
                throw UnsupportedFunctionalityError(functionality: "audio content parts with media type \(part.mediaType)")
            }

            switch part.data {
            case .url:
                throw UnsupportedFunctionalityError(functionality: "audio file parts with URLs")
            case .data(let data):
                let base64 = convertDataToBase64(data)
                return .object([
                    "type": .string("input_audio"),
                    "input_audio": .object([
                        "data": .string(base64),
                        "format": .string(format)
                    ])
                ])
            case .base64(let value):
                if isFileId(value, prefixes: prefixes) {
                    return .object([
                        "type": .string("input_audio"),
                        "file_id": .string(value)
                    ])
                }
                return .object([
                    "type": .string("input_audio"),
                    "input_audio": .object([
                        "data": .string(value),
                        "format": .string(format)
                    ])
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

        // JSONSerialization requires top-level object to be Array or Dictionary
        // For primitive values, we need to handle them specially
        let anyValue = toAny(value)
        let data: Data

        if anyValue is [Any] || anyValue is [String: Any] {
            data = try JSONSerialization.data(withJSONObject: anyValue, options: [])
        } else {
            // For primitives (number, string, bool, null), encode them directly
            switch value {
            case .null:
                return "null"
            case .bool(let bool):
                return bool ? "true" : "false"
            case .number(let number):
                // Handle integer vs decimal
                if number.truncatingRemainder(dividingBy: 1) == 0 {
                    return String(format: "%.0f", number)
                } else {
                    return String(number)
                }
            case .string(let string):
                // Need to properly escape the string as JSON
                data = try JSONSerialization.data(withJSONObject: [string], options: [])
                guard let arrayString = String(data: data, encoding: .utf8),
                      arrayString.hasPrefix("[\""),
                      arrayString.hasSuffix("\"]") else {
                    throw UnsupportedFunctionalityError(functionality: "Unable to encode JSON string")
                }
                return String(arrayString.dropFirst(2).dropLast(2))
            case .array, .object:
                // Should not reach here due to earlier check
                data = try JSONSerialization.data(withJSONObject: anyValue, options: [])
            }
        }

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



    private static func extractOpenAIStringOption(
        from options: ProviderOptions?,
        providerOptionsName: String,
        key: String
    ) -> String? {
        guard let options,
              let openaiOptions = options[providerOptionsName],
              let value = openaiOptions[key],
              case .string(let stringValue) = value else {
            return nil
        }
        return stringValue
    }

    private static func stringifyReasoningPart(_ part: LanguageModelV3ReasoningPart) -> String {
        let encoder = JSONEncoder()
        var segments: [String] = []

        if let typeData = try? encoder.encode("reasoning"),
           let typeJSON = String(data: typeData, encoding: .utf8) {
            segments.append("\"type\":\(typeJSON)")
        }

        if let textData = try? encoder.encode(part.text),
           let textJSON = String(data: textData, encoding: .utf8) {
            segments.append("\"text\":\(textJSON)")
        }

        if let providerOptions = part.providerOptions,
           let providerData = try? encoder.encode(providerOptions),
           let providerJSON = String(data: providerData, encoding: .utf8) {
            segments.append("\"providerOptions\":\(providerJSON)")
        }

        if segments.isEmpty {
            return part.text
        }

        return "{\(segments.joined(separator: ","))}"
    }

    private static func extractOpenAIItemId(from options: ProviderOptions?, providerOptionsName: String) -> String? {
        guard let options,
              let openaiOptions = options[providerOptionsName],
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
