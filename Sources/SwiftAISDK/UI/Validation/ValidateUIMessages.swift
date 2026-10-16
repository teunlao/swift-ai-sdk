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
public typealias UIToolInputRefinement = @Sendable (JSONValue) async throws -> JSONValue

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
    tools: [String: Tool]? = nil,
    experimentalRefineToolInput: [String: UIToolInputRefinement]? = nil
) async -> SafeValidateUIMessagesResult<Message> {
    guard let messages, !(messages is NSNull) else {
        let error = InvalidArgumentError(
            parameter: "messages",
            value: nil,
            message: "messages parameter must be provided"
        )
        return SafeValidateUIMessagesResult(success: false, error: error)
    }

    do {
        var parsedMessages = try parseMessages(messages, as: Message.self)

        if let metadataSchema {
            try await validateMetadata(for: &parsedMessages, schema: metadataSchema)
        }

        if dataSchemas != nil || tools != nil {
            try await validateMessageParts(
                for: &parsedMessages, dataSchemas: dataSchemas, tools: tools,
                refineToolInput: experimentalRefineToolInput
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
    tools: [String: Tool]? = nil,
    experimentalRefineToolInput: [String: UIToolInputRefinement]? = nil
) async throws -> [Message] {
    let result: SafeValidateUIMessagesResult<Message> = await safeValidateUIMessages(
        messages: messages,
        metadataSchema: metadataSchema,
        dataSchemas: dataSchemas,
        tools: tools,
        experimentalRefineToolInput: experimentalRefineToolInput
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

    if items.isEmpty {
        throw typeValidationError(
            value: rawMessages,
            message: "Messages array must not be empty"
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
        let partsValue = try requireJSONValue(object, key: "parts", context: rawContext)
        let parts = try parseParts(partsValue, in: rawContext)
        try ensure(role == .assistant || !parts.isEmpty, context: rawContext,
                   message: "Message must contain at least one part")

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
                state: state,
                providerMetadata: providerMetadata,
                citations: try object["citations"].map { try parseCitations($0) }
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
                state: state,
                providerMetadata: providerMetadata,
                id: try optionalString(object, key: "id")
            )
            parts.append(.reasoning(part))

        case "custom":
            parts.append(.custom(CustomContentUIPart(
                kind: try requireString(object, key: "kind", context: context),
                providerMetadata: try parseProviderMetadataIfPresent(object, context: context)
            )))

        case "reasoning-file":
            parts.append(.reasoningFile(ReasoningFileUIPart(
                mediaType: try requireString(object, key: "mediaType", context: context),
                url: try requireString(object, key: "url", context: context),
                providerMetadata: try parseProviderMetadataIfPresent(object, context: context)
            )))

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
                providerMetadata: providerMetadata,
                providerReference: try parseProviderReference(object["providerReference"])
            )
            parts.append(.file(part))

        case "step-start":
            parts.append(.stepStart)

        case "dynamic-tool":
            let toolName = try requireString(object, key: "toolName", context: context)
            let toolCallId = try requireString(object, key: "toolCallId", context: context)
            let title = try optionalString(object, key: "title")
            let providerExecuted = try optionalBool(object, key: "providerExecuted")
            let state = try parseRequiredEnum(
                object,
                key: "state",
                context: context,
                as: UIDynamicToolInvocationState.self
            )
            let input = try optionalJSONValue(object, key: "input")
            let output = try optionalJSONValue(object, key: "output")
            let errorText = try optionalString(object, key: "errorText")
            let approval = try parseToolApprovalIfPresent(object, context: context)
            let callProviderMetadata = try parseProviderMetadataIfPresent(object, key: "callProviderMetadata", context: context)
            var resultProviderMetadata: ProviderMetadata?
            var preliminary: Bool?

            switch state {
            case .inputStreaming:
                try ensure(output == nil, context: context, message: "dynamic-tool output must be omitted when state is \"input-streaming\"")
                try ensure(errorText == nil, context: context, message: "dynamic-tool errorText must be omitted when state is \"input-streaming\"")
                try ensure(preliminary == nil, context: context, message: "dynamic-tool preliminary must be omitted when state is \"input-streaming\"")
                try ensure(approval == nil, context: context, message: "dynamic-tool approval must be omitted when state is \"input-streaming\"")
            case .inputAvailable:
                try ensure(input != nil, context: context, message: "dynamic-tool input must be provided when state is \"input-available\"")
                try ensure(output == nil, context: context, message: "dynamic-tool output must be omitted when state is \"input-available\"")
                try ensure(errorText == nil, context: context, message: "dynamic-tool errorText must be omitted when state is \"input-available\"")
                try ensure(preliminary == nil, context: context, message: "dynamic-tool preliminary must be omitted when state is \"input-available\"")
                try ensure(approval == nil, context: context, message: "dynamic-tool approval must be omitted when state is \"input-available\"")
            case .approvalRequested:
                try ensure(input != nil, context: context, message: "dynamic-tool input must be provided when state is \"approval-requested\"")
                let approvalValue = try requireApproval(approval, context: context, message: "dynamic-tool approval must be provided when state is \"approval-requested\"")
                try ensure(approvalValue.approved == nil, context: context, message: "dynamic-tool approval.approved must be omitted when state is \"approval-requested\"")
                try ensure(approvalValue.reason == nil, context: context, message: "dynamic-tool approval.reason must be omitted when state is \"approval-requested\"")
                try ensure(output == nil, context: context, message: "dynamic-tool output must be omitted when state is \"approval-requested\"")
                try ensure(errorText == nil, context: context, message: "dynamic-tool errorText must be omitted when state is \"approval-requested\"")
                try ensure(preliminary == nil, context: context, message: "dynamic-tool preliminary must be omitted when state is \"approval-requested\"")
            case .approvalResponded:
                try ensure(input != nil, context: context, message: "dynamic-tool input must be provided when state is \"approval-responded\"")
                let approvalValue = try requireApproval(approval, context: context, message: "dynamic-tool approval must be provided when state is \"approval-responded\"")
                try ensure(approvalValue.approved != nil, context: context, message: "dynamic-tool approval.approved must be provided when state is \"approval-responded\"")
                try ensure(output == nil, context: context, message: "dynamic-tool output must be omitted when state is \"approval-responded\"")
                try ensure(errorText == nil, context: context, message: "dynamic-tool errorText must be omitted when state is \"approval-responded\"")
                try ensure(preliminary == nil, context: context, message: "dynamic-tool preliminary must be omitted when state is \"approval-responded\"")
            case .outputAvailable:
                try ensure(input != nil, context: context, message: "dynamic-tool input must be provided when state is \"output-available\"")
                try ensure(output != nil, context: context, message: "dynamic-tool output must be provided when state is \"output-available\"")
                try ensure(errorText == nil, context: context, message: "dynamic-tool errorText must be omitted when state is \"output-available\"")
                preliminary = try optionalBool(object, key: "preliminary")
                resultProviderMetadata = try parseProviderMetadataIfPresent(object, key: "resultProviderMetadata", context: context)
                if let approvalValue = approval {
                    try ensure(approvalValue.approved == true, context: context, message: "dynamic-tool approval.approved must be true when provided in \"output-available\" state")
                }
            case .outputError:
                try ensure(output == nil, context: context, message: "dynamic-tool output must be omitted when state is \"output-error\"")
                try ensure(errorText != nil, context: context, message: "dynamic-tool errorText must be provided when state is \"output-error\"")
                try ensure(preliminary == nil, context: context, message: "dynamic-tool preliminary must be omitted when state is \"output-error\"")
                resultProviderMetadata = try parseProviderMetadataIfPresent(object, key: "resultProviderMetadata", context: context)
                if let approvalValue = approval {
                    try ensure(approvalValue.approved == true, context: context, message: "dynamic-tool approval.approved must be true when provided in \"output-error\" state")
                }
            case .outputDenied:
                try ensure(input != nil, context: context, message: "dynamic-tool input must be provided when state is \"output-denied\"")
                try ensure(output == nil, context: context, message: "dynamic-tool output must be omitted when state is \"output-denied\"")
                try ensure(errorText == nil, context: context, message: "dynamic-tool errorText must be omitted when state is \"output-denied\"")
                let approvalValue = try requireApproval(approval, context: context, message: "dynamic-tool approval must be provided when state is \"output-denied\"")
                try ensure(approvalValue.approved == false, context: context, message: "dynamic-tool approval.approved must be false when state is \"output-denied\"")
                try ensure(preliminary == nil, context: context, message: "dynamic-tool preliminary must be omitted when state is \"output-denied\"")
            }

            let part = UIDynamicToolUIPart(
                toolName: toolName,
                toolCallId: toolCallId,
                state: state,
                dynamic: try parseDynamicOrigin(object),
                rawInput: try parseRawInput(object, state: state.rawValue),
                input: input,
                output: output,
                errorText: errorText,
                providerExecuted: providerExecuted,
                callProviderMetadata: callProviderMetadata,
                resultProviderMetadata: resultProviderMetadata,
                preliminary: preliminary,
                approval: approval,
                title: title,
                toolMetadata: try optionalObject(object, key: "toolMetadata"),
                inputEncoding: state == .inputStreaming ? try parseOptionalEnum(object, key: "inputEncoding", context: context, as: UIToolInputEncoding.self) : nil
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
                let title = try optionalString(object, key: "title")
                let state = try parseRequiredEnum(
                    object,
                    key: "state",
                    context: context,
                    as: UIToolInvocationState.self
                )
                let input = try optionalJSONValue(object, key: "input")
                let output = try optionalJSONValue(object, key: "output")
                let errorText = try optionalString(object, key: "errorText")
                let providerExecuted = try optionalBool(object, key: "providerExecuted")
                let approval = try parseToolApprovalIfPresent(object, context: context)
                let callProviderMetadata = try parseProviderMetadataIfPresent(object, key: "callProviderMetadata", context: context)
                var resultProviderMetadata: ProviderMetadata?
                var preliminary: Bool?
                var rawInput: JSONValue?

                switch state {
                case .inputStreaming:
                    try ensure(output == nil, context: context, message: "tool output must be omitted when state is \"input-streaming\"")
                    try ensure(errorText == nil, context: context, message: "tool errorText must be omitted when state is \"input-streaming\"")
                    try ensure(approval == nil, context: context, message: "tool approval must be omitted when state is \"input-streaming\"")
                    rawInput = try parseRawInput(object, state: state.rawValue)
                case .inputAvailable:
                    try ensure(input != nil, context: context, message: "tool input must be provided when state is \"input-available\"")
                    try ensure(output == nil, context: context, message: "tool output must be omitted when state is \"input-available\"")
                    try ensure(errorText == nil, context: context, message: "tool errorText must be omitted when state is \"input-available\"")
                    try ensure(approval == nil, context: context, message: "tool approval must be omitted when state is \"input-available\"")
                    rawInput = nil
                case .approvalRequested:
                    try ensure(input != nil, context: context, message: "tool input must be provided when state is \"approval-requested\"")
                    let approvalValue = try requireApproval(approval, context: context, message: "tool approval must be provided when state is \"approval-requested\"")
                    try ensure(approvalValue.approved == nil, context: context, message: "tool approval.approved must be omitted when state is \"approval-requested\"")
                    try ensure(approvalValue.reason == nil, context: context, message: "tool approval.reason must be omitted when state is \"approval-requested\"")
                    try ensure(output == nil, context: context, message: "tool output must be omitted when state is \"approval-requested\"")
                    try ensure(errorText == nil, context: context, message: "tool errorText must be omitted when state is \"approval-requested\"")
                    rawInput = nil
                case .approvalResponded:
                    try ensure(input != nil, context: context, message: "tool input must be provided when state is \"approval-responded\"")
                    let approvalValue = try requireApproval(approval, context: context, message: "tool approval must be provided when state is \"approval-responded\"")
                    try ensure(approvalValue.approved != nil, context: context, message: "tool approval.approved must be provided when state is \"approval-responded\"")
                    try ensure(output == nil, context: context, message: "tool output must be omitted when state is \"approval-responded\"")
                    try ensure(errorText == nil, context: context, message: "tool errorText must be omitted when state is \"approval-responded\"")
                    rawInput = nil
                case .outputAvailable:
                    try ensure(input != nil, context: context, message: "tool input must be provided when state is \"output-available\"")
                    try ensure(output != nil, context: context, message: "tool output must be provided when state is \"output-available\"")
                    try ensure(errorText == nil, context: context, message: "tool errorText must be omitted when state is \"output-available\"")
                    if let approvalValue = approval {
                        try ensure(approvalValue.approved == true, context: context, message: "tool approval.approved must be true when provided in \"output-available\" state")
                    }
                    resultProviderMetadata = try parseProviderMetadataIfPresent(object, key: "resultProviderMetadata", context: context)
                    preliminary = try optionalBool(object, key: "preliminary")
                    rawInput = nil
                case .outputError:
                    try ensure(output == nil, context: context, message: "tool output must be omitted when state is \"output-error\"")
                    try ensure(errorText != nil, context: context, message: "tool errorText must be provided when state is \"output-error\"")
                    if let approvalValue = approval {
                        try ensure(approvalValue.approved == true, context: context, message: "tool approval.approved must be true when provided in \"output-error\" state")
                    }
                    resultProviderMetadata = try parseProviderMetadataIfPresent(object, key: "resultProviderMetadata", context: context)
                    rawInput = try optionalJSONValue(object, key: "rawInput")
                case .outputDenied:
                    try ensure(input != nil, context: context, message: "tool input must be provided when state is \"output-denied\"")
                    try ensure(output == nil, context: context, message: "tool output must be omitted when state is \"output-denied\"")
                    try ensure(errorText == nil, context: context, message: "tool errorText must be omitted when state is \"output-denied\"")
                    let approvalValue = try requireApproval(approval, context: context, message: "tool approval must be provided when state is \"output-denied\"")
                    try ensure(approvalValue.approved == false, context: context, message: "tool approval.approved must be false when state is \"output-denied\"")
                    rawInput = nil
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
                    resultProviderMetadata: resultProviderMetadata,
                    preliminary: preliminary,
                    approval: approval,
                    title: title,
                    toolMetadata: try optionalObject(object, key: "toolMetadata"),
                    inputEncoding: state == .inputStreaming ? try parseOptionalEnum(object, key: "inputEncoding", context: context, as: UIToolInputEncoding.self) : nil
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
    for messages: inout [Message], schema: FlexibleSchema<JSONValue>
) async throws {
    for index in messages.indices {
        messages[index].metadata = try await validateTypes(ValidateTypesOptions(
            value: messages[index].metadata.map(jsonValueToAny) as Any? ?? NSNull(), schema: schema,
            context: TypeValidationContext(field: "messages[\(index)].metadata", entityId: messages[index].id)
        ))
    }
}

private func validateMessageParts<Message: UIMessageConvertible>(
    for messages: inout [Message], dataSchemas: [String: FlexibleSchema<JSONValue>]?,
    tools: [String: Tool]?, refineToolInput: [String: UIToolInputRefinement]?
) async throws {
    for messageIndex in messages.indices {
        for partIndex in messages[messageIndex].parts.indices {
            if let dataSchemas, case .data(var part) = messages[messageIndex].parts[partIndex] {
                let name = String(part.typeIdentifier.dropFirst(5))
                let context = TypeValidationContext(field: "messages[\(messageIndex)].parts[\(partIndex)].data",
                                                    entityName: name, entityId: part.id)
                guard let schema = dataSchemas[name] else {
                    throw TypeValidationError.wrap(value: jsonValueToAny(part.data),
                        cause: ValidationMessageError(message: "No data schema found for data part \(name)"), context: context)
                }
                part.data = try await validateTypes(ValidateTypesOptions(value: jsonValueToAny(part.data), schema: schema, context: context))
                messages[messageIndex].parts[partIndex] = .data(part)
            }
            guard let tools, case .tool(let part) = messages[messageIndex].parts[partIndex] else { continue }
            let name = part.toolName
            let terminal = part.state == .outputAvailable || part.state == .outputError || part.state == .outputDenied
            let context = TypeValidationContext(field: "messages[\(messageIndex)].parts[\(partIndex)].input",
                                                entityName: name, entityId: part.toolCallId)
            guard let tool = tools[name] else {
                if terminal {
                    messages[messageIndex].parts[partIndex] = .dynamicTool(unavailableTool(part))
                    continue
                }
                throw TypeValidationError.wrap(value: part.input.map(jsonValueToAny) as Any? ?? NSNull(),
                    cause: ValidationMessageError(message: "No tool schema found for tool part \(name)"), context: context)
            }
            var convertToDynamic = false
            let schemaInput = part.approval?.inputSchemaInput
            if part.state != .inputStreaming && (part.state != .outputError || schemaInput != nil || part.input != nil) {
                do {
                    let input = try await validateTypes(ValidateTypesOptions(
                        value: (schemaInput ?? part.input).map(jsonValueToAny) as Any? ?? NSNull(),
                        schema: tool.inputSchema, context: context
                    ))
                    if schemaInput != nil {
                        let reconstructed: JSONValue
                        do {
                            if let refine = refineToolInput?[name] { reconstructed = try await refine(input) }
                            else { reconstructed = input }
                        } catch {
                            throw TypeValidationError.wrap(value: (schemaInput ?? .null), cause: error, context: context)
                        }
                        guard reconstructed == part.input else {
                            throw TypeValidationError.wrap(value: part.input.map(jsonValueToAny) as Any? ?? NSNull(),
                                cause: ValidationMessageError(message: "Tool input does not match the output reconstructed from inputSchemaInput."),
                                context: context)
                        }
                    }
                } catch {
                    if part.state == .outputError || (part.state == .outputAvailable && part.input == .object([:])) {
                        convertToDynamic = true
                    } else { throw error }
                }
            }
            if part.state == .outputAvailable, let schema = tool.outputSchema {
                _ = try await validateTypes(ValidateTypesOptions(
                    value: part.output.map(jsonValueToAny) as Any? ?? NSNull(), schema: schema,
                    context: TypeValidationContext(field: "messages[\(messageIndex)].parts[\(partIndex)].output",
                                                   entityName: name, entityId: part.toolCallId)
                ))
            }
            if convertToDynamic { messages[messageIndex].parts[partIndex] = .dynamicTool(unavailableTool(part)) }
        }
    }
}

private func unavailableTool(_ part: UIToolUIPart) -> UIDynamicToolUIPart {
    UIDynamicToolUIPart(
        toolName: part.toolName, toolCallId: part.toolCallId,
        state: part.state, dynamic: false,
        rawInput: part.rawInput, input: part.input, output: part.output, errorText: part.errorText,
        providerExecuted: part.providerExecuted, callProviderMetadata: part.callProviderMetadata,
        resultProviderMetadata: part.resultProviderMetadata, preliminary: part.preliminary,
        approval: part.approval, title: part.title, toolMetadata: part.toolMetadata, inputEncoding: part.inputEncoding
    )
}

// MARK: - Helpers

private func parseCitations(_ value: JSONValue) throws -> [Citation] {
    do { return try parseUICitations(value) }
    catch { throw typeValidationError(value: jsonValueToAny(value), message: "Invalid citations: \(error)") }
}

private func optionalObject(_ object: JSONObject, key: String) throws -> JSONObject? {
    guard let value = object[key] else { return nil }
    guard case .object(let result) = value else {
        throw typeValidationError(value: jsonValueToAny(value), message: "\"\(key)\" must be an object")
    }
    return result
}

private func parseProviderReference(_ value: JSONValue?) throws -> ProviderReference? {
    guard let value else { return nil }
    guard case .object(let object) = value else {
        throw typeValidationError(value: jsonValueToAny(value), message: "providerReference must be an object")
    }
    var reference: ProviderReference = [:]
    for (key, entry) in object {
        guard case .string(let identifier) = entry else {
            throw typeValidationError(value: jsonValueToAny(value), message: "providerReference values must be strings")
        }
        reference[key] = identifier
    }
    return reference
}

private func parseDynamicOrigin(_ object: JSONObject) throws -> Bool? {
    let value = try optionalBool(object, key: "dynamic")
    try ensure(value != true, context: jsonValueToAny(.object(object)), message: "dynamic must be false when provided")
    return value
}

private func parseRawInput(_ object: JSONObject, state: String) throws -> JSONValue? {
    if state == "output-error" { return object["rawInput"] }
    if state == "input-streaming" { return try optionalString(object, key: "rawInput").map(JSONValue.string) }
    return nil
}

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

    return UIToolApproval(
        id: id, approved: approved, reason: reason,
        descriptor: approvalObject["descriptor"],
        requestReason: try optionalString(approvalObject, key: "requestReason"),
        isAutomatic: try optionalBool(approvalObject, key: "isAutomatic"),
        signature: try optionalString(approvalObject, key: "signature"),
        inputSchemaInput: approvalObject["inputSchemaInput"]
    )
}

@discardableResult
private func ensure(
    _ condition: @autoclosure () -> Bool,
    context: Any,
    message: String
) throws -> Bool {
    guard condition() else {
        throw typeValidationError(value: context, message: message)
    }
    return true
}

private func requireApproval(
    _ approval: UIToolApproval?,
    context: Any,
    message: String
) throws -> UIToolApproval {
    guard let approval else {
        throw typeValidationError(value: context, message: message)
    }
    return approval
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

private struct ValidationMessageError: LocalizedError, CustomStringConvertible, Sendable {
    let message: String

    var description: String { message }
    var errorDescription: String? { message }
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
