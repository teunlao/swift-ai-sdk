import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Validates UI messages against optional metadata, data, and tool schemas.

 Port of `@ai-sdk/ai/src/ui/validate-ui-messages.ts`.

 **Adaptations**:
 - TypeScript uses Zod for schema validation. Swift relies on the existing `FlexibleSchema`
   abstraction (`validateTypes`) and manual structural checks to reproduce parity.
 - Provider metadata is validated structurally because Zod schemas are not available.
 */
public struct SafeValidateUIMessagesResult<Message: UIMessageConvertible>: Sendable {
    public let success: Bool
    public let data: [Message]?
    public let error: Error?

    public init(success: Bool, data: [Message]? = nil, error: Error? = nil) {
        self.success = success
        self.data = data
        self.error = error
    }
}

public func safeValidateUIMessages<Message: UIMessageConvertible>(
    messages: Any?,
    metadataSchema: FlexibleSchema<JSONValue>? = nil,
    dataSchemas: [String: FlexibleSchema<JSONValue>]? = nil,
    tools: [String: Tool]? = nil
) async -> SafeValidateUIMessagesResult<Message> {
    guard let messages else {
        let error = InvalidArgumentError(
            parameter: "messages",
            value: nil,
            message: "messages parameter must be provided"
        )
        return SafeValidateUIMessagesResult(success: false, error: error)
    }

    do {
        let parsedMessages = try parseMessages(messages, as: Message.self)

        if let metadataSchema {
            try await validateMetadata(for: parsedMessages, schema: metadataSchema)
        }

        if let dataSchemas {
            try await validateDataParts(
                for: parsedMessages,
                schemas: dataSchemas
            )
        }

        if let tools {
            try await validateToolParts(
                for: parsedMessages,
                tools: tools
            )
        }

        return SafeValidateUIMessagesResult(success: true, data: parsedMessages)
    } catch {
        return SafeValidateUIMessagesResult(success: false, error: error)
    }
}

@discardableResult
public func validateUIMessages<Message: UIMessageConvertible>(
    messages: Any?,
    metadataSchema: FlexibleSchema<JSONValue>? = nil,
    dataSchemas: [String: FlexibleSchema<JSONValue>]? = nil,
    tools: [String: Tool]? = nil
) async throws -> [Message] {
    let result = await safeValidateUIMessages(
        messages: messages,
        metadataSchema: metadataSchema,
        dataSchemas: dataSchemas,
        tools: tools
    )

    if result.success, let data = result.data {
        return data
    }

    throw result.error ?? InvalidArgumentError(
        parameter: "messages",
        value: nil,
        message: "messages parameter must be provided"
    )
}

// MARK: - Parsing

private func parseMessages<Message: UIMessageConvertible>(
    _ rawMessages: Any,
    as _: Message.Type
) throws -> [Message] {
    let json = try jsonValue(from: rawMessages)
    guard case .array(let items) = json else {
        throw typeValidationError(
            value: rawMessages,
            message: "messages must be an array of UI message objects"
        )
    }

    var result: [Message] = []
    result.reserveCapacity(items.count)

    for element in items {
        guard case .object(let object) = element else {
            throw typeValidationError(
                value: jsonValueToAny(element),
                message: "each UI message must be an object"
            )
        }

        let rawContext = jsonValueToAny(element)
        let id = try requireString(object, key: "id", context: rawContext)
        let roleString = try requireString(object, key: "role", context: rawContext)
        guard let role = UIMessageRole(rawValue: roleString) else {
            throw typeValidationError(
                value: rawContext,
                message: "role must be \"system\", \"user\", or \"assistant\""
            )
        }

        let metadata = object["metadata"]
        let partsValue = object["parts"] ?? .array([])
        let parts = try parseParts(partsValue, in: rawContext)

        let message = Message(
            id: id,
            role: role,
            metadata: metadata,
            parts: parts
        )

        result.append(message)
    }

    return result
}

private func parseParts(
    _ value: JSONValue,
    in parentContext: Any
) throws -> [UIMessagePart] {
    guard case .array(let entries) = value else {
        throw typeValidationError(
            value: parentContext,
            message: "message parts must be provided as an array"
        )
    }

    var parts: [UIMessagePart] = []
    parts.reserveCapacity(entries.count)

    for entry in entries {
        guard case .object(let object) = entry else {
            throw typeValidationError(
                value: jsonValueToAny(entry),
                message: "each UI message part must be an object"
            )
        }

        let context = jsonValueToAny(entry)
        let type = try requireString(object, key: "type", context: context)

        switch type {
        case "text":
            let text = try requireString(object, key: "text", context: context)
            let state = try parseOptionalEnum(
                object,
                key: "state",
                context: context,
                as: TextUIPart.State.self
            )
            let providerMetadata = try parseProviderMetadataIfPresent(object, context: context)

            let part = TextUIPart(
                text: text,
                state: state ?? .streaming,
                providerMetadata: providerMetadata
            )
            parts.append(.text(part))

        case "reasoning":
            let text = try requireString(object, key: "text", context: context)
            let state = try parseOptionalEnum(
                object,
                key: "state",
                context: context,
                as: ReasoningUIPart.State.self
            )
            let providerMetadata = try parseProviderMetadataIfPresent(object, context: context)

            let part = ReasoningUIPart(
                text: text,
                state: state ?? .streaming,
                providerMetadata: providerMetadata
            )
            parts.append(.reasoning(part))

        case "source-url":
            let sourceId = try requireString(object, key: "sourceId", context: context)
            let url = try requireString(object, key: "url", context: context)
            let title = try optionalString(object, key: "title")
            let providerMetadata = try parseProviderMetadataIfPresent(object, context: context)

            let part = SourceUrlUIPart(
                sourceId: sourceId,
                url: url,
                title: title,
                providerMetadata: providerMetadata
            )
            parts.append(.sourceURL(part))

        case "source-document":
            let sourceId = try requireString(object, key: "sourceId", context: context)
            let mediaType = try requireString(object, key: "mediaType", context: context)
            let title = try requireString(object, key: "title", context: context)
            let filename = try optionalString(object, key: "filename")
            let providerMetadata = try parseProviderMetadataIfPresent(object, context: context)

            let part = SourceDocumentUIPart(
                sourceId: sourceId,
                mediaType: mediaType,
                title: title,
                filename: filename,
                providerMetadata: providerMetadata
            )
            parts.append(.sourceDocument(part))

        case "file":
            let mediaType = try requireString(object, key: "mediaType", context: context)
            let url = try requireString(object, key: "url", context: context)
            let filename = try optionalString(object, key: "filename")
            let providerMetadata = try parseProviderMetadataIfPresent(object, context: context)

            let part = FileUIPart(
                mediaType: mediaType,
                filename: filename,
                url: url,
                providerMetadata: providerMetadata
            )
            parts.append(.file(part))

        case "step-start":
            parts.append(.stepStart)

        case "dynamic-tool":
            let toolName = try requireString(object, key: "toolName", context: context)
            let toolCallId = try requireString(object, key: "toolCallId", context: context)
            let state = try parseRequiredEnum(
                object,
                key: "state",
                context: context,
                as: UIDynamicToolInvocationState.self
            )
            let input = try optionalJSONValue(object, key: "input")
            let output = try optionalJSONValue(object, key: "output")
            let errorText = try optionalString(object, key: "errorText")
            let callProviderMetadata = try parseProviderMetadataIfPresent(object, key: "callProviderMetadata", context: context)
            let preliminary = try optionalBool(object, key: "preliminary")

            if state == .outputAvailable && output == nil {
                throw typeValidationError(
                    value: context,
                    message: "dynamic-tool output must be provided when state is \"output-available\""
                )
            }

            let part = UIDynamicToolUIPart(
                toolName: toolName,
                toolCallId: toolCallId,
                state: state,
                input: input,
                output: output,
                errorText: errorText,
                callProviderMetadata: callProviderMetadata,
                preliminary: preliminary
            )
            parts.append(.dynamicTool(part))

        default:
            if type.hasPrefix("data-") {
                let data = try requireJSONValue(object, key: "data", context: context)
                let identifier = String(type.dropFirst("data-".count))
                let id = try optionalString(object, key: "id")

                let part = DataUIPart(
                    typeIdentifier: "data-\(identifier)",
                    id: id,
                    data: data
                )
                parts.append(.data(part))
            } else if type.hasPrefix("tool-") {
                let toolName = String(type.dropFirst("tool-".count))
                let toolCallId = try requireString(object, key: "toolCallId", context: context)
                let state = try parseRequiredEnum(
                    object,
                    key: "state",
                    context: context,
                    as: UIToolInvocationState.self
                )
                let input = try optionalJSONValue(object, key: "input")
                let output = try optionalJSONValue(object, key: "output")
                let rawInput = try optionalJSONValue(object, key: "rawInput")
                let errorText = try optionalString(object, key: "errorText")
                let providerExecuted = try optionalBool(object, key: "providerExecuted")
                let callProviderMetadata = try parseProviderMetadataIfPresent(object, key: "callProviderMetadata", context: context)
                let preliminary = try optionalBool(object, key: "preliminary")
                let approval = try parseToolApprovalIfPresent(object, context: context)

                if state == .outputAvailable && output == nil {
                    throw typeValidationError(
                        value: context,
                        message: "tool output must be provided when state is \"output-available\""
                    )
                }

                let part = UIToolUIPart(
                    toolName: toolName,
                    toolCallId: toolCallId,
                    state: state,
                    input: input,
                    output: output,
                    rawInput: rawInput,
                    errorText: errorText,
                    providerExecuted: providerExecuted,
                    callProviderMetadata: callProviderMetadata,
                    preliminary: preliminary,
                    approval: approval
                )
                parts.append(.tool(part))
            } else {
                throw typeValidationError(
                    value: context,
                    message: "unsupported UI message part type \"\(type)\""
                )
            }
        }
    }

    return parts
}

// MARK: - Metadata & Schema Validation

private func validateMetadata<Message: UIMessageConvertible>(
    for messages: [Message],
    schema: FlexibleSchema<JSONValue>
) async throws {
    for message in messages {
        guard let metadata = message.metadata else {
            continue
        }

        try await validateTypes(
            ValidateTypesOptions(
                value: jsonValueToAny(metadata),
                schema: schema
            )
        )
    }
}

private func validateDataParts<Message: UIMessageConvertible>(
    for messages: [Message],
    schemas: [String: FlexibleSchema<JSONValue>]
) async throws {
    for message in messages {
        for part in message.parts {
            guard case .data(let dataPart) = part else { continue }
            let dataName = String(dataPart.typeIdentifier.dropFirst("data-".count))

            guard let schema = schemas[dataName] else {
                throw typeValidationError(
                    value: jsonValueToAny(dataPart.data),
                    message: "No data schema found for data part \(dataName)"
                )
            }

            try await validateTypes(
                ValidateTypesOptions(
                    value: jsonValueToAny(dataPart.data),
                    schema: schema
                )
            )
        }
    }
}

private func validateToolParts<Message: UIMessageConvertible>(
    for messages: [Message],
    tools: [String: Tool]
) async throws {
    for message in messages {
        for part in message.parts {
            guard case .tool(let toolPart) = part else { continue }
            let toolName = toolPart.toolName

            guard let tool = tools[toolName] else {
                throw typeValidationError(
                    value: jsonValueToAny(toolPart.input ?? .null),
                    message: "No tool schema found for tool part \(toolName)"
                )
            }

            switch toolPart.state {
            case .inputStreaming, .inputAvailable, .approvalRequested, .approvalResponded, .outputAvailable, .outputError:
                if let input = toolPart.input {
                    try await validateTypes(
                        ValidateTypesOptions(
                            value: jsonValueToAny(input),
                            schema: tool.inputSchema
                        )
                    )
                }

            case .outputDenied:
                break
            }

            if toolPart.state == .outputAvailable,
               let outputSchema = tool.outputSchema,
               let output = toolPart.output {
                try await validateTypes(
                    ValidateTypesOptions(
                        value: jsonValueToAny(output),
                        schema: outputSchema
                    )
                )
            }
        }
    }
}

// MARK: - Helpers

private func requireString(
    _ object: [String: JSONValue],
    key: String,
    context: Any
) throws -> String {
    guard let raw = object[key], case .string(let stringValue) = raw else {
        throw typeValidationError(
            value: context,
            message: "\"\(key)\" must be a string"
        )
    }

    return stringValue
}

private func optionalString(
    _ object: [String: JSONValue],
    key: String
) throws -> String? {
    guard let raw = object[key] else { return nil }
    guard case .string(let stringValue) = raw else {
        throw typeValidationError(
            value: jsonValueToAny(raw),
            message: "\"\(key)\" must be a string"
        )
    }
    return stringValue
}

private func optionalBool(
    _ object: [String: JSONValue],
    key: String
) throws -> Bool? {
    guard let raw = object[key] else { return nil }
    guard case .bool(let boolValue) = raw else {
        throw typeValidationError(
            value: jsonValueToAny(raw),
            message: "\"\(key)\" must be a boolean"
        )
    }
    return boolValue
}

private func optionalJSONValue(
    _ object: [String: JSONValue],
    key: String
) throws -> JSONValue? {
    guard let raw = object[key] else { return nil }
    return raw
}

private func requireJSONValue(
    _ object: [String: JSONValue],
    key: String,
    context: Any
) throws -> JSONValue {
    guard let raw = object[key] else {
        throw typeValidationError(
            value: context,
            message: "\"\(key)\" must be provided"
        )
    }
    return raw
}

private func parseOptionalEnum<Value: RawRepresentable>(
    _ object: [String: JSONValue],
    key: String,
    context: Any,
    as type: Value.Type
) throws -> Value? where Value.RawValue == String {
    guard let raw = object[key] else {
        return nil
    }

    guard case .string(let rawValue) = raw else {
        throw typeValidationError(
            value: context,
            message: "\"\(key)\" must be a string"
        )
    }

    guard let value = Value(rawValue: rawValue) else {
        throw typeValidationError(
            value: context,
            message: "\"\(key)\" has unsupported value \"\(rawValue)\""
        )
    }

    return value
}

private func parseRequiredEnum<Value: RawRepresentable>(
    _ object: [String: JSONValue],
    key: String,
    context: Any,
    as type: Value.Type
) throws -> Value where Value.RawValue == String {
    guard let value = try parseOptionalEnum(object, key: key, context: context, as: type) else {
        throw typeValidationError(
            value: context,
            message: "\"\(key)\" must be provided"
        )
    }
    return value
}

private func parseProviderMetadataIfPresent(
    _ object: [String: JSONValue],
    key: String = "providerMetadata",
    context: Any
) throws -> ProviderMetadata? {
    guard let metadata = object[key] else {
        return nil
    }

    return try parseProviderMetadata(metadata, context: context, field: key)
}

private func parseProviderMetadata(
    _ value: JSONValue,
    context: Any,
    field: String
) throws -> ProviderMetadata {
    guard case .object(let providers) = value else {
        throw typeValidationError(
            value: context,
            message: "\"\(field)\" must be an object"
        )
    }

    var result: ProviderMetadata = [:]
    result.reserveCapacity(providers.count)

    for (provider, entry) in providers {
        guard case .object(let metadata) = entry else {
            throw typeValidationError(
                value: context,
                message: "\"\(field).\(provider)\" must be an object"
            )
        }
        result[provider] = metadata
    }

    return result
}

private func parseToolApprovalIfPresent(
    _ object: [String: JSONValue],
    context: Any
) throws -> UIToolApproval? {
    guard let approvalValue = object["approval"] else {
        return nil
    }

    guard case .object(let approvalObject) = approvalValue else {
        throw typeValidationError(
            value: context,
            message: "\"approval\" must be an object"
        )
    }

    let id = try requireString(approvalObject, key: "id", context: context)
    let approved = try optionalBool(approvalObject, key: "approved")
    let reason = try optionalString(approvalObject, key: "reason")

    return UIToolApproval(id: id, approved: approved, reason: reason)
}

private func typeValidationError(
    value: Any,
    message: String
) -> TypeValidationError {
    TypeValidationError.wrap(
        value: value,
        cause: ValidationMessageError(message: message)
    )
}

private struct ValidationMessageError: Error, CustomStringConvertible, Sendable {
    let message: String

    var description: String { message }
}

private func jsonValueToAny(_ value: JSONValue) -> Any {
    switch value {
    case .null: return NSNull()
    case .bool(let bool): return bool
    case .number(let number): return number
    case .string(let string): return string
    case .array(let array):
        return array.map { jsonValueToAny($0) }
    case .object(let dictionary):
        var result: [String: Any] = [:]
        result.reserveCapacity(dictionary.count)
        for (key, entry) in dictionary {
            result[key] = jsonValueToAny(entry)
        }
        return result
    }
}
