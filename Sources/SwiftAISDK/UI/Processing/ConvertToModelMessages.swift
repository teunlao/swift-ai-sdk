import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Options controlling the conversion from UI messages to core model messages.
public struct ConvertToModelMessagesOptions: Sendable {
    public var tools: ToolSet?
    public var ignoreIncompleteToolCalls: Bool

    public init(tools: ToolSet? = nil, ignoreIncompleteToolCalls: Bool = false) {
        self.tools = tools
        self.ignoreIncompleteToolCalls = ignoreIncompleteToolCalls
    }
}

/// Converts UI-layer chat messages into core model messages that can be used by
/// `generateText`/`streamText`.
public func convertToModelMessages<Message: UIMessageConvertible>(
    messages: [Message],
    options: ConvertToModelMessagesOptions = ConvertToModelMessagesOptions()
) throws -> [ModelMessage] {
    var workingMessages = messages

    if options.ignoreIncompleteToolCalls {
        workingMessages = workingMessages.map { message in
            let filteredParts = message.parts.filter { part in
                switch part {
                case .tool(let toolPart):
                    return toolPart.state != .inputStreaming && toolPart.state != .inputAvailable
                case .dynamicTool(let dynamicPart):
                    return dynamicPart.state != .inputStreaming && dynamicPart.state != .inputAvailable
                default:
                    return true
                }
            }
            return Message(
                id: message.id,
                role: message.role,
                metadata: message.metadata,
                parts: filteredParts
            )
        }
    }

    var modelMessages: [ModelMessage] = []

    for message in workingMessages {
        switch message.role {
        case .system:
            let textParts = message.parts.compactMap { part -> TextUIPart? in
                if case .text(let text) = part {
                    return text
                }
                return nil
            }

            let aggregatedMetadata = mergeProviderOptions(from: textParts.map { $0.providerMetadata })
            let content = textParts.map { $0.text }.joined()

            modelMessages.append(
                .system(SystemModelMessage(content: content, providerOptions: aggregatedMetadata))
            )

        case .user:
            let contentParts: [UserContentPart] = message.parts.compactMap { part in
                switch part {
                case .text(let textPart):
                    return .text(TextPart(text: textPart.text, providerOptions: textPart.providerMetadata))
                case .file(let filePart):
                    return .file(
                        FilePart(
                            data: .string(filePart.url),
                            mediaType: filePart.mediaType,
                            filename: filePart.filename,
                            providerOptions: filePart.providerMetadata
                        )
                    )
                default:
                    return nil
                }
            }

            modelMessages.append(
                .user(UserModelMessage(content: .parts(contentParts)))
            )

        case .assistant:
            var block: [UIMessagePart] = []

            func processBlock() throws {
                guard !block.isEmpty else { return }

                var assistantParts: [AssistantContentPart] = []

                for part in block {
                    switch part {
                    case .text(let textPart):
                        assistantParts.append(
                            .text(TextPart(text: textPart.text, providerOptions: textPart.providerMetadata))
                        )
                    case .reasoning(let reasoningPart):
                        assistantParts.append(
                            .reasoning(ReasoningPart(text: reasoningPart.text, providerOptions: reasoningPart.providerMetadata))
                        )
                    case .file(let filePart):
                        assistantParts.append(
                            .file(
                                FilePart(
                                    data: .string(filePart.url),
                                    mediaType: filePart.mediaType,
                                    filename: filePart.filename,
                                    providerOptions: filePart.providerMetadata
                                )
                            )
                        )
                    case .dynamicTool(let dynamicPart):
                        if dynamicPart.state != .inputStreaming {
                            assistantParts.append(
                                .toolCall(
                                    ToolCallPart(
                                        toolCallId: dynamicPart.toolCallId,
                                        toolName: dynamicPart.toolName,
                                        input: dynamicPart.input ?? .null,
                                        providerOptions: dynamicPart.callProviderMetadata
                                    )
                                )
                            )
                        }
                    case .tool(let toolPart):
                        if toolPart.state != .inputStreaming {
                            let toolName = getToolName(toolPart)
                            let inputValue: JSONValue
                            if toolPart.state == .outputError {
                                inputValue = toolPart.input ?? toolPart.rawInput ?? .null
                            } else {
                                inputValue = toolPart.input ?? .null
                            }

                            assistantParts.append(
                                .toolCall(
                                    ToolCallPart(
                                        toolCallId: toolPart.toolCallId,
                                        toolName: toolName,
                                        input: inputValue,
                                        providerOptions: toolPart.callProviderMetadata,
                                        providerExecuted: toolPart.providerExecuted
                                    )
                                )
                            )

                            if let approval = toolPart.approval {
                                assistantParts.append(
                                    .toolApprovalRequest(
                                        ToolApprovalRequest(
                                            approvalId: approval.id,
                                            toolCallId: toolPart.toolCallId
                                        )
                                    )
                                )
                            }

                            if toolPart.providerExecuted == true,
                               toolPart.state == .outputAvailable || toolPart.state == .outputError {
                                let tool = options.tools?[toolName]
                                let outputValue: Any?
                                let errorMode: ToolOutputErrorMode
                                if toolPart.state == .outputError {
                                    outputValue = toolPart.errorText
                                    errorMode = .json
                                } else {
                                    outputValue = toolPart.output
                                    errorMode = .none
                                }

                                assistantParts.append(
                                    .toolResult(
                                        ToolResultPart(
                                            toolCallId: toolPart.toolCallId,
                                            toolName: toolName,
                                            output: createToolModelOutput(
                                                output: outputValue,
                                                tool: tool,
                                                errorMode: errorMode
                                            )
                                        )
                                    )
                                )
                            }
                        }
                    case .stepStart:
                        break
                    default:
                        throw makeConversionError(for: message, reason: "Unsupported assistant part: \(part.typeIdentifier)")
                    }
                }

                if !assistantParts.isEmpty {
                    modelMessages.append(
                        .assistant(AssistantModelMessage(content: .parts(assistantParts)))
                    )
                }

                let toolMessageParts = try buildToolMessageParts(from: block, tools: options.tools)
                if !toolMessageParts.isEmpty {
                    modelMessages.append(.tool(ToolModelMessage(content: toolMessageParts)))
                }

                block.removeAll(keepingCapacity: true)
            }

            for part in message.parts {
                switch part {
                case .text, .reasoning, .file, .dynamicTool, .tool:
                    block.append(part)
                case .stepStart:
                    try processBlock()
                default:
                    throw makeConversionError(for: message, reason: "Unsupported assistant part: \(part.typeIdentifier)")
                }
            }

            try processBlock()
        }
    }

    return modelMessages
}

/// Deprecated alias kept for backwards compatibility.
@available(*, deprecated, renamed: "convertToModelMessages")
public func convertToCoreMessages<Message: UIMessageConvertible>(
    messages: [Message],
    options: ConvertToModelMessagesOptions = ConvertToModelMessagesOptions()
) throws -> [ModelMessage] {
    try convertToModelMessages(messages: messages, options: options)
}

// MARK: - Helpers

private func mergeProviderOptions(from metadata: [ProviderMetadata?]) -> ProviderOptions? {
    var merged: ProviderOptions = [:]

    for entry in metadata.compactMap({ $0 }) {
        for (provider, options) in entry {
            var existing = merged[provider] ?? [:]
            existing.merge(options) { _, new in new }
            merged[provider] = existing
        }
    }

    return merged.isEmpty ? nil : merged
}

private func buildToolMessageParts(
    from block: [UIMessagePart],
    tools: ToolSet?
) throws -> [ToolContentPart] {
    var outputs: [ToolContentPart] = []

    for part in block {
        switch part {
        case .tool(let toolPart) where toolPart.providerExecuted != true:
            if let approval = toolPart.approval, let approved = approval.approved {
                outputs.append(.toolApprovalResponse(ToolApprovalResponse(
                    approvalId: approval.id,
                    approved: approved,
                    reason: approval.reason
                )))
            }

            switch toolPart.state {
            case .outputDenied:
                let reason = toolPart.approval?.reason ?? "Tool execution denied."
                outputs.append(.toolResult(ToolResultPart(
                    toolCallId: toolPart.toolCallId,
                    toolName: getToolName(toolPart),
                    output: .errorText(value: reason)
                )))

            case .outputError, .outputAvailable:
                let toolName = getToolName(toolPart)
                let tool = tools?[toolName]
                let outputValue: Any?
                let errorMode: ToolOutputErrorMode

                if toolPart.state == .outputError {
                    outputValue = toolPart.errorText ?? toolPart.output
                    errorMode = .text
                } else {
                    outputValue = toolPart.output
                    errorMode = .none
                }

                outputs.append(.toolResult(ToolResultPart(
                    toolCallId: toolPart.toolCallId,
                    toolName: toolName,
                    output: createToolModelOutput(
                        output: outputValue,
                        tool: tool,
                        errorMode: errorMode
                    )
                )))

            default:
                break
            }

        case .dynamicTool(let dynamicPart):
            switch dynamicPart.state {
            case .outputError, .outputAvailable:
                let tool = tools?[dynamicPart.toolName]
                let outputValue: Any?
                let errorMode: ToolOutputErrorMode

                if dynamicPart.state == .outputError {
                    outputValue = dynamicPart.errorText ?? dynamicPart.output
                    errorMode = .text
                } else {
                    outputValue = dynamicPart.output
                    errorMode = .none
                }

                outputs.append(.toolResult(ToolResultPart(
                    toolCallId: dynamicPart.toolCallId,
                    toolName: dynamicPart.toolName,
                    output: createToolModelOutput(
                        output: outputValue,
                        tool: tool,
                        errorMode: errorMode
                    )
                )))

            default:
                break
            }

        default:
            break
        }
    }

    return outputs
}

private func makeConversionError<Message: UIMessageConvertible>(
    for message: Message,
    reason: String
) -> MessageConversionError {
    MessageConversionError(
        originalMessage: messageDebugRepresentation(message),
        message: reason
    )
}

private func messageDebugRepresentation<Message: UIMessageConvertible>(_ message: Message) -> JSONValue {
    var object: [String: JSONValue] = [
        "id": .string(message.id),
        "role": .string(message.role.rawValue)
    ]
    if let metadata = message.metadata {
        object["metadata"] = metadata
    }
    object["parts"] = .number(Double(message.parts.count))
    return .object(object)
}
