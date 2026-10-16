import Foundation
import AISDKProvider
import AISDKProviderUtils

public enum ConvertedDataPart: Sendable, Equatable {
    case text(TextPart)
    case file(FilePart)
}

/// Options controlling the conversion from UI messages to core model messages.
public struct ConvertToModelMessagesOptions: Sendable {
    public var tools: ToolSet?
    public var ignoreIncompleteToolCalls: Bool

    public var convertDataPart: (@Sendable (DataUIPart) -> ConvertedDataPart?)?

    public init(
        tools: ToolSet? = nil,
        ignoreIncompleteToolCalls: Bool = false,
        convertDataPart: (@Sendable (DataUIPart) -> ConvertedDataPart?)? = nil
    ) {
        self.tools = tools
        self.ignoreIncompleteToolCalls = ignoreIncompleteToolCalls
        self.convertDataPart = convertDataPart
    }
}

/// Converts UI-layer chat messages into core model messages that can be used by
/// `generateText`/`streamText`.
public func convertToModelMessages<Message: UIMessageConvertible>(
    messages: [Message],
    options: ConvertToModelMessagesOptions = ConvertToModelMessagesOptions()
) async throws -> [ModelMessage] {
    var workingMessages = messages

    let lastUserIndex = messages.lastIndex { $0.role == .user } ?? -1
    if options.ignoreIncompleteToolCalls || lastUserIndex > 0 {
        workingMessages = workingMessages.enumerated().map { messageIndex, message in
            let filteredParts = message.parts.filter { part in
                switch part {
                case .tool(let toolPart):
                    return (toolPart.state != .approvalRequested || messageIndex >= lastUserIndex)
                        && (!options.ignoreIncompleteToolCalls || toolPart.state == .approvalResponded
                            || (toolPart.state == .outputAvailable && toolPart.preliminary != true)
                            || toolPart.state == .outputError || toolPart.state == .outputDenied)
                case .dynamicTool(let dynamicPart):
                    return (dynamicPart.state != .approvalRequested || messageIndex >= lastUserIndex)
                        && (!options.ignoreIncompleteToolCalls || dynamicPart.state == .approvalResponded
                            || (dynamicPart.state == .outputAvailable && dynamicPart.preliminary != true)
                            || dynamicPart.state == .outputError || dynamicPart.state == .outputDenied)
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
            let contentParts: [UserContentPart] = try message.parts.compactMap { part in
                switch part {
                case .text(let textPart):
                    return .text(TextPart(text: textPart.text, providerOptions: textPart.providerMetadata))
                case .file(let filePart):
                    return .file(
                        FilePart(
                            data: try fileData(filePart),
                            mediaType: filePart.mediaType,
                            filename: filePart.filename,
                            providerOptions: filePart.providerMetadata
                        )
                    )
                case .data(let dataPart):
                    switch options.convertDataPart?(dataPart) {
                    case .text(let part): return .text(part)
                    case .file(let part): return .file(part)
                    case nil: return nil
                    }
                default:
                    return nil
                }
            }

            modelMessages.append(
                .user(UserModelMessage(content: .parts(contentParts)))
            )

        case .assistant:
            var block: [UIMessagePart] = []

            func processBlock() async throws {
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
                                    data: try fileData(filePart),
                                    mediaType: filePart.mediaType,
                                    filename: filePart.filename,
                                    providerOptions: filePart.providerMetadata
                                )
                            )
                        )
                    case .custom(let part):
                        assistantParts.append(.custom(CustomPart(kind: part.kind, providerOptions: part.providerMetadata)))
                    case .reasoningFile(let part):
                        assistantParts.append(.reasoningFile(ReasoningFilePart(
                            data: try urlData(part.url), mediaType: part.mediaType, providerOptions: part.providerMetadata
                        )))
                    case .data(let part):
                        switch options.convertDataPart?(part) {
                        case .text(let converted): assistantParts.append(.text(converted))
                        case .file(let converted): assistantParts.append(.file(converted))
                        case nil: break
                        }
                    case .dynamicTool(let dynamicPart):
                        if dynamicPart.state != .inputStreaming {
                            assistantParts.append(
                                .toolCall(
                                    ToolCallPart(
                                        toolCallId: dynamicPart.toolCallId,
                                        toolName: dynamicPart.toolName,
                                        input: dynamicPart.input ?? dynamicPart.rawInput ?? .null,
                                        providerOptions: dynamicPart.callProviderMetadata ?? (dynamicPart.state == .outputError ? dynamicPart.resultProviderMetadata : nil),
                                        providerExecuted: dynamicPart.providerExecuted
                                    )
                                )
                            )

                            if let approval = dynamicPart.approval {
                                assistantParts.append(
                                    .toolApprovalRequest(
                                        ToolApprovalRequest(
                                            approvalId: approval.id,
                                            toolCallId: dynamicPart.toolCallId,
                                            reason: approval.requestReason,
                                            isAutomatic: approval.isAutomatic,
                                            signature: approval.signature,
                                            inputSchemaInput: approval.inputSchemaInput
                                        )
                                    )
                                )
                            }

                            if dynamicPart.providerExecuted == true,
                               dynamicPart.state == .outputAvailable || dynamicPart.state == .outputError {
                                let tool = options.tools?[dynamicPart.toolName]
                                let outputValue: Any?
                                let errorMode: ToolOutputErrorMode
                                let providerOptions = dynamicPart.resultProviderMetadata ?? dynamicPart.callProviderMetadata

                                if dynamicPart.state == .outputError {
                                    outputValue = dynamicPart.errorText
                                    errorMode = .json
                                } else {
                                    outputValue = dynamicPart.output
                                    errorMode = .none
                                }

                                assistantParts.append(
                                    .toolResult(
                                        ToolResultPart(
                                            toolCallId: dynamicPart.toolCallId,
                                            toolName: dynamicPart.toolName,
                                            output: try await modelOutput(toolCallId: dynamicPart.toolCallId, input: dynamicPart.input,
                                                                output: outputValue, tool: tool, errorMode: errorMode,
                                                                unavailable: dynamicPart.dynamic == false),
                                            providerOptions: providerOptions
                                        )
                                    )
                                )
                            }
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
                                        providerOptions: toolPart.callProviderMetadata ?? (toolPart.state == .outputError ? toolPart.resultProviderMetadata : nil),
                                        providerExecuted: toolPart.providerExecuted
                                    )
                                )
                            )

                            if let approval = toolPart.approval {
                                assistantParts.append(
                                    .toolApprovalRequest(
                                        ToolApprovalRequest(
                                            approvalId: approval.id,
                                            toolCallId: toolPart.toolCallId,
                                            reason: approval.requestReason,
                                            isAutomatic: approval.isAutomatic,
                                            signature: approval.signature,
                                            inputSchemaInput: approval.inputSchemaInput
                                        )
                                    )
                                )
                            }

                            if toolPart.providerExecuted == true,
                               toolPart.state == .outputAvailable || toolPart.state == .outputError {
                                let tool = options.tools?[toolName]
                                let outputValue: Any?
                                let errorMode: ToolOutputErrorMode
                                let providerOptions = toolPart.resultProviderMetadata ?? toolPart.callProviderMetadata
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
                                            output: try await modelOutput(
                                                toolCallId: toolPart.toolCallId, input: toolPart.input,
                                                output: outputValue,
                                                tool: tool,
                                                errorMode: errorMode
                                            ),
                                            providerOptions: providerOptions
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

                let toolMessageParts = try await buildToolMessageParts(from: block, tools: options.tools)
                if !toolMessageParts.isEmpty {
                    modelMessages.append(.tool(ToolModelMessage(content: toolMessageParts)))
                }

                block.removeAll(keepingCapacity: true)
            }

            for part in message.parts {
                switch part {
                case .text, .custom, .reasoning, .reasoningFile, .file, .dynamicTool, .tool, .data:
                    block.append(part)
                case .stepStart:
                    try await processBlock()
                default:
                    break
                }
            }

            try await processBlock()
        }
    }

    return modelMessages
}

/// Deprecated alias kept for backwards compatibility.
@available(*, deprecated, renamed: "convertToModelMessages")
public func convertToCoreMessages<Message: UIMessageConvertible>(
    messages: [Message],
    options: ConvertToModelMessagesOptions = ConvertToModelMessagesOptions()
) async throws -> [ModelMessage] {
    try await convertToModelMessages(messages: messages, options: options)
}

// MARK: - Helpers

private func fileData(_ part: FileUIPart) throws -> DataContentOrURL {
    if let reference = part.providerReference { return .reference(reference) }
    return try urlData(part.url)
}

private func urlData(_ string: String) throws -> DataContentOrURL {
    guard let url = URL(string: string), url.scheme != nil else {
        throw InvalidArgumentError(parameter: "url", value: .string(string), message: "Invalid URL")
    }
    return .url(url)
}

private func modelOutput(
    toolCallId: String, input: JSONValue?, output: Any?, tool: Tool?, errorMode: ToolOutputErrorMode, unavailable: Bool = false
) async throws -> LanguageModelV3ToolResultOutput {
    if errorMode == .none, tool == nil, unavailable {
        return .text(value: "Tool output omitted because the tool is no longer available.")
    }
    return createToolModelOutput(output: output, tool: tool, errorMode: errorMode)
}

private func mergeProviderOptions(from metadata: [ProviderMetadata?]) -> ProviderOptions? {
    var merged: ProviderOptions = [:]

    for entry in metadata.compactMap({ $0 }) {
        for (provider, options) in entry {
            merged[provider] = options
        }
    }

    return merged.isEmpty ? nil : merged
}

private func buildToolMessageParts(
    from block: [UIMessagePart],
    tools: ToolSet?
) async throws -> [ToolContentPart] {
    var outputs: [ToolContentPart] = []

    for part in block {
        switch part {
        case .tool(let toolPart):
            if let approval = toolPart.approval, let approved = approval.approved {
                outputs.append(.toolApprovalResponse(ToolApprovalResponse(
                    approvalId: approval.id,
                    approved: approved,
                    reason: approval.reason,
                    providerExecuted: toolPart.providerExecuted
                )))
            }

            if toolPart.state == .approvalResponded, toolPart.approval?.approved == false {
                outputs.append(.toolResult(ToolResultPart(
                    toolCallId: toolPart.toolCallId, toolName: toolPart.toolName,
                    output: .executionDenied(reason: toolPart.approval?.reason),
                    providerOptions: toolPart.callProviderMetadata
                )))
            }

            if toolPart.providerExecuted == true {
                break
            }

            switch toolPart.state {
            case .outputDenied:
                let reason = toolPart.approval?.reason ?? "Tool call execution denied."
                outputs.append(.toolResult(ToolResultPart(
                    toolCallId: toolPart.toolCallId,
                    toolName: getToolName(toolPart),
                    output: .errorText(value: reason),
                    providerOptions: toolPart.callProviderMetadata
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
                    output: try await modelOutput(
                        toolCallId: toolPart.toolCallId, input: toolPart.input,
                        output: outputValue,
                        tool: tool,
                        errorMode: errorMode
                    ),
                    providerOptions: toolPart.callProviderMetadata
                )))

            default:
                break
            }

        case .dynamicTool(let dynamicPart):
            if let approval = dynamicPart.approval, let approved = approval.approved {
                outputs.append(.toolApprovalResponse(ToolApprovalResponse(
                    approvalId: approval.id,
                    approved: approved,
                    reason: approval.reason,
                    providerExecuted: dynamicPart.providerExecuted
                )))
            }

            if dynamicPart.state == .approvalResponded, dynamicPart.approval?.approved == false {
                outputs.append(.toolResult(ToolResultPart(
                    toolCallId: dynamicPart.toolCallId, toolName: dynamicPart.toolName,
                    output: .executionDenied(reason: dynamicPart.approval?.reason),
                    providerOptions: dynamicPart.callProviderMetadata
                )))
            }

            if dynamicPart.providerExecuted == true {
                break
            }

            switch dynamicPart.state {
            case .outputDenied:
                let reason = dynamicPart.approval?.reason ?? "Tool call execution denied."
                outputs.append(.toolResult(ToolResultPart(
                    toolCallId: dynamicPart.toolCallId,
                    toolName: dynamicPart.toolName,
                    output: .errorText(value: reason),
                    providerOptions: dynamicPart.callProviderMetadata
                )))

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
                    output: try await modelOutput(toolCallId: dynamicPart.toolCallId, input: dynamicPart.input,
                                        output: outputValue, tool: tool, errorMode: errorMode,
                                        unavailable: dynamicPart.dynamic == false),
                    providerOptions: dynamicPart.callProviderMetadata
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
