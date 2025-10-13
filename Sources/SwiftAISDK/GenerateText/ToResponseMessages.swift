/**
 Convert generation content parts into assistant/tool response messages.

 Port of `@ai-sdk/ai/src/generate-text/to-response-messages.ts`.
 */
import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Convert generated content parts to response messages for assistant and tool roles.

 Port of `@ai-sdk/ai/src/generate-text/to-response-messages.ts`.
 */
public func toResponseMessages(
    content inputContent: [ContentPart],
    tools: ToolSet?
) -> [ModelMessage] {
    var messages: [ModelMessage] = []

    let assistantParts: [AssistantContentPart] = inputContent
        .filter { part in
            if case .source = part { return false }
            return true
        }
        .filter { part in
            switch part {
            case .toolResult(let result, _):
                return result.providerExecuted == true
            case .toolError(let error, _):
                return error.providerExecuted == true
            default:
                return true
            }
        }
        .compactMap { part in
            assistantContentPart(from: part, tools: tools)
        }

    if !assistantParts.isEmpty {
        messages.append(
            .assistant(
                AssistantModelMessage(content: .parts(assistantParts))
            )
        )
    }

    let toolParts: [ToolContentPart] = inputContent.compactMap { part in
        switch part {
        case .toolResult(let result, _):
            guard result.providerExecuted != true else { return nil }
            let output = createToolModelOutput(
                output: jsonValueToAny(result.output),
                tool: tools?[result.toolName],
                errorMode: .none
            )
            let part = ToolResultPart(
                toolCallId: result.toolCallId,
                toolName: result.toolName,
                output: output
            )
            return .toolResult(part)

        case .toolError(let error, _):
            guard error.providerExecuted != true else { return nil }
            let errorMessage = AISDKProvider.getErrorMessage(error.error)
            let output = createToolModelOutput(
                output: errorMessage,
                tool: tools?[error.toolName],
                errorMode: .text
            )
            let part = ToolResultPart(
                toolCallId: error.toolCallId,
                toolName: error.toolName,
                output: output
            )
            return .toolResult(part)

        default:
            return nil
        }
    }

    if !toolParts.isEmpty {
        messages.append(.tool(ToolModelMessage(content: toolParts)))
    }

    return messages
}

// MARK: - Helpers

private func assistantContentPart(
    from part: ContentPart,
    tools: ToolSet?
) -> AssistantContentPart? {
    switch part {
    case .text(let text, let providerMetadata):
        guard !text.isEmpty else { return nil }
        let textPart = TextPart(text: text, providerOptions: providerMetadata)
        return .text(textPart)

    case .reasoning(let reasoning):
        let reasoningPart = ReasoningPart(
            text: reasoning.text,
            providerOptions: reasoning.providerMetadata
        )
        return .reasoning(reasoningPart)

    case .file(let file, let providerMetadata):
        let filePart = FilePart(
            data: .string(file.base64),
            mediaType: file.mediaType,
            providerOptions: providerMetadata
        )
        return .file(filePart)

    case .toolCall(let toolCall, let providerMetadata):
        let toolCallPart = ToolCallPart(
            toolCallId: toolCall.toolCallId,
            toolName: toolCall.toolName,
            input: toolCall.input,
            providerOptions: providerMetadata,
            providerExecuted: toolCall.providerExecuted
        )
        return .toolCall(toolCallPart)

    case .toolResult(let result, let providerMetadata):
        guard result.providerExecuted == true else { return nil }
        let output = createToolModelOutput(
            output: jsonValueToAny(result.output),
            tool: tools?[result.toolName],
            errorMode: .none
        )
        let resultPart = ToolResultPart(
            toolCallId: result.toolCallId,
            toolName: result.toolName,
            output: output,
            providerOptions: providerMetadata
        )
        return .toolResult(resultPart)

    case .toolError(let error, let providerMetadata):
        guard error.providerExecuted == true else { return nil }
        let errorMessage = AISDKProvider.getErrorMessage(error.error)
        let output = createToolModelOutput(
            output: errorMessage,
            tool: tools?[error.toolName],
            errorMode: .json
        )
        let resultPart = ToolResultPart(
            toolCallId: error.toolCallId,
            toolName: error.toolName,
            output: output,
            providerOptions: providerMetadata
        )
        return .toolResult(resultPart)

    case .toolApprovalRequest(let approval):
        let request = ToolApprovalRequest(
            approvalId: approval.approvalId,
            toolCallId: approval.toolCall.toolCallId
        )
        return .toolApprovalRequest(request)

    case .source:
        return nil
    }
}

private func jsonValueToAny(_ value: JSONValue) -> Any {
    switch value {
    case .string(let string):
        return string
    case .number(let number):
        return number
    case .bool(let bool):
        return bool
    case .null:
        return NSNull()
    case .array(let array):
        return array.map { jsonValueToAny($0) }
    case .object(let dictionary):
        var result: [String: Any] = [:]
        for (key, entry) in dictionary {
            result[key] = jsonValueToAny(entry)
        }
        return result
    }
}
