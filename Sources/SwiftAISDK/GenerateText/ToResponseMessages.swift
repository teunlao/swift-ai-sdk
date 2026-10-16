import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Converts the content of a `generateText` or `streamText` step to response messages.

 Port of `@ai-sdk/ai/src/generate-text/to-response-messages.ts`: an assistant
 message with the model content (and provider-executed tool results), then a
 tool message with approval responses and client tool results sorted by tool
 call order.
 */
public func toResponseMessages(
    content inputContent: [ContentPart],
    tools: ToolSet?
) async throws -> [ResponseMessage] {
    var responseMessages: [ResponseMessage] = []
    var toolCallOrder: [String: Int] = [:]
    var assistantParts: [AssistantContentPart] = []

    for part in inputContent {
        switch part {
        case .source:
            continue

        case .text(let text, _, let providerMetadata):
            guard !text.isEmpty else { continue }
            assistantParts.append(.text(TextPart(text: text, providerOptions: providerMetadata)))

        case .custom(let kind, let providerMetadata):
            assistantParts.append(.custom(CustomPart(kind: kind, providerOptions: providerMetadata)))

        case .reasoning(let reasoning):
            assistantParts.append(.reasoning(ReasoningPart(
                text: reasoning.text,
                providerOptions: reasoning.providerMetadata
            )))

        case .file(let file, let providerMetadata):
            assistantParts.append(.file(FilePart(
                data: .string(file.base64),
                mediaType: file.mediaType,
                providerOptions: providerMetadata
            )))

        case .reasoningFile(let file, let providerMetadata):
            assistantParts.append(.reasoningFile(ReasoningFilePart(
                data: .string(file.base64),
                mediaType: file.mediaType,
                providerOptions: providerMetadata
            )))

        case .toolCall(let toolCall, let providerMetadata):
            if toolCallOrder[toolCall.toolCallId] == nil {
                toolCallOrder[toolCall.toolCallId] = toolCallOrder.count
            }
            let input: JSONValue
            if toolCall.invalid == true, !toolCall.input.isJavaScriptObject {
                input = .object([:])
            } else {
                input = toolCall.input
            }
            assistantParts.append(.toolCall(ToolCallPart(
                toolCallId: toolCall.toolCallId,
                toolName: toolCall.toolName,
                input: input,
                providerOptions: providerMetadata,
                providerExecuted: toolCall.providerExecuted
            )))

        case .toolResult(let result, let providerMetadata):
            guard result.providerExecuted == true else { continue }
            let output = try await createToolModelOutput(
                toolCallId: result.toolCallId,
                input: result.input,
                output: result.output,
                tool: tools?[result.toolName],
                errorMode: .none
            )
            assistantParts.append(.toolResult(ToolResultPart(
                toolCallId: result.toolCallId,
                toolName: result.toolName,
                output: output,
                providerOptions: providerMetadata
            )))

        case .toolError(let error, let providerMetadata):
            guard error.providerExecuted == true else { continue }
            let output = try await createToolModelOutput(
                toolCallId: error.toolCallId,
                input: error.input,
                output: toolErrorValue(error.error),
                tool: tools?[error.toolName],
                errorMode: .json
            )
            assistantParts.append(.toolResult(ToolResultPart(
                toolCallId: error.toolCallId,
                toolName: error.toolName,
                output: output,
                providerOptions: providerMetadata
            )))

        case .toolApprovalRequest(let approval):
            let inputSchemaInput = approval.toolCall.inputSchemaInput
            assistantParts.append(.toolApprovalRequest(ToolApprovalRequest(
                approvalId: approval.approvalId,
                toolCallId: approval.toolCall.toolCallId,
                reason: approval.reason,
                isAutomatic: approval.isAutomatic,
                signature: approval.signature,
                inputSchemaInput: inputSchemaInput != approval.toolCall.input ? inputSchemaInput : nil
            )))

        case .toolApprovalResponse:
            continue
        }
    }

    if !assistantParts.isEmpty {
        responseMessages.append(.assistant(AssistantModelMessage(content: .parts(assistantParts))))
    }

    var toolContent: [ToolContentPart] = []
    for part in inputContent {
        switch part {
        case .toolApprovalResponse(let response):
            toolContent.append(.toolApprovalResponse(ToolApprovalResponse(
                approvalId: response.approvalId,
                approved: response.approved,
                reason: response.reason,
                providerExecuted: response.providerExecuted
            )))
            if !response.approved {
                toolContent.append(.toolResult(ToolResultPart(
                    toolCallId: response.toolCall.toolCallId,
                    toolName: response.toolCall.toolName,
                    output: .executionDenied(reason: response.reason)
                )))
            }

        case .toolResult(let result, _):
            guard result.providerExecuted != true else { continue }
            let output = try await createToolModelOutput(
                toolCallId: result.toolCallId,
                input: result.input,
                output: result.output,
                tool: tools?[result.toolName],
                errorMode: .none
            )
            toolContent.append(.toolResult(ToolResultPart(
                toolCallId: result.toolCallId,
                toolName: result.toolName,
                output: output,
                providerOptions: result.providerMetadata
            )))

        case .toolError(let error, _):
            guard error.providerExecuted != true else { continue }
            let output = try await createToolModelOutput(
                toolCallId: error.toolCallId,
                input: error.input,
                output: toolErrorValue(error.error),
                tool: tools?[error.toolName],
                errorMode: .text
            )
            toolContent.append(.toolResult(ToolResultPart(
                toolCallId: error.toolCallId,
                toolName: error.toolName,
                output: output,
                providerOptions: error.providerMetadata
            )))

        default:
            continue
        }
    }

    if !toolContent.isEmpty {
        responseMessages.append(.tool(ToolModelMessage(
            content: sortToolResultsByToolCallOrder(toolContent, toolCallOrder: toolCallOrder)
        )))
    }

    return responseMessages
}

/// The error value as the model sees it: provider error payloads stay JSON.
private func toolErrorValue(_ error: any Error) -> Any {
    if let providerError = error as? ProviderToolExecutionError {
        return providerError.value
    }
    return error
}

private func sortToolResultsByToolCallOrder(
    _ content: [ToolContentPart],
    toolCallOrder: [String: Int]
) -> [ToolContentPart] {
    let toolResults = content.enumerated().compactMap { index, part -> (index: Int, part: ToolContentPart, toolCallId: String)? in
        if case .toolResult(let result) = part { return (index, part, result.toolCallId) }
        return nil
    }

    let sorted = toolResults.sorted { lhs, rhs in
        switch (toolCallOrder[lhs.toolCallId], toolCallOrder[rhs.toolCallId]) {
        case (nil, nil): return lhs.index < rhs.index
        case (nil, _): return false
        case (_, nil): return true
        case (let left?, let right?): return left == right ? lhs.index < rhs.index : left < right
        }
    }

    var next = sorted.makeIterator()
    return content.map { part in
        if case .toolResult = part { return next.next()!.part }
        return part
    }
}

extension JSONValue {
    /// Whether JavaScript's `typeof` reports `'object'` for the value (objects, arrays, null).
    var isJavaScriptObject: Bool {
        switch self {
        case .object, .array, .null: return true
        default: return false
        }
    }
}
