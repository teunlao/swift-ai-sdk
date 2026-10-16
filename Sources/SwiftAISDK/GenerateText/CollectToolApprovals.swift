import Foundation
import AISDKProvider
import AISDKProviderUtils

/// A tool approval found in the message history: the request, the response, and the tool call.
public struct CollectedToolApproval: Sendable {
    public let approvalRequest: ToolApprovalRequest
    public let approvalResponse: ToolApprovalResponse
    public let toolCall: TypedToolCall
    /// A tool result for the call that is already in the last tool message (an earlier denial).
    public let existingToolResult: ToolResultPart?

    public init(
        approvalRequest: ToolApprovalRequest,
        approvalResponse: ToolApprovalResponse,
        toolCall: TypedToolCall,
        existingToolResult: ToolResultPart? = nil
    ) {
        self.approvalRequest = approvalRequest
        self.approvalResponse = approvalResponse
        self.toolCall = toolCall
        self.existingToolResult = existingToolResult
    }

    func with(approvalResponse: ToolApprovalResponse) -> CollectedToolApproval {
        CollectedToolApproval(
            approvalRequest: approvalRequest,
            approvalResponse: approvalResponse,
            toolCall: toolCall,
            existingToolResult: existingToolResult
        )
    }
}

/**
 Collects the tool approval responses of the last message when it is a tool message.

 Port of `@ai-sdk/ai/src/generate-text/collect-tool-approvals.ts`. Approved
 approvals are sorted by the order of their tool calls in the history.

 - Throws: `InvalidToolApprovalError` when a response references an unknown
   approval, `ToolCallNotFoundForApprovalError` when the approved call is missing.
 */
public func collectToolApprovals(
    messages: [ModelMessage]
) throws -> (
    approvedToolApprovals: [CollectedToolApproval],
    deniedToolApprovals: [CollectedToolApproval]
) {
    guard let lastMessage = messages.last, case .tool(let toolMessage) = lastMessage else {
        return (approvedToolApprovals: [], deniedToolApprovals: [])
    }

    var toolCallsById: [String: TypedToolCall] = [:]
    var toolCallOrder: [String: Int] = [:]
    var approvalRequestsById: [String: ToolApprovalRequest] = [:]

    for message in messages {
        guard case .assistant(let assistantMessage) = message,
              case .parts(let parts) = assistantMessage.content else { continue }

        for part in parts {
            switch part {
            case .toolCall(let toolCallPart):
                toolCallsById[toolCallPart.toolCallId] = .static(StaticToolCall(
                    toolCallId: toolCallPart.toolCallId,
                    toolName: toolCallPart.toolName,
                    input: toolCallPart.input,
                    providerExecuted: toolCallPart.providerExecuted
                ))
                toolCallOrder[toolCallPart.toolCallId] = toolCallOrder.count
            case .toolApprovalRequest(let approvalRequest):
                approvalRequestsById[approvalRequest.approvalId] = approvalRequest
            default:
                break
            }
        }
    }

    var toolResults: [String: ToolResultPart] = [:]
    for part in toolMessage.content {
        if case .toolResult(let resultPart) = part {
            toolResults[resultPart.toolCallId] = resultPart
        }
    }

    var approved: [CollectedToolApproval] = []
    var denied: [CollectedToolApproval] = []

    for part in toolMessage.content {
        guard case .toolApprovalResponse(let response) = part else { continue }

        guard let approvalRequest = approvalRequestsById[response.approvalId] else {
            throw InvalidToolApprovalError(approvalId: response.approvalId)
        }

        let existingToolResult = toolResults[approvalRequest.toolCallId]
        if let existingToolResult {
            let isDeniedResult: Bool
            if case .executionDenied = existingToolResult.output { isDeniedResult = true } else { isDeniedResult = false }
            if response.approved || !isDeniedResult {
                continue
            }
        }

        guard let toolCall = toolCallsById[approvalRequest.toolCallId] else {
            throw ToolCallNotFoundForApprovalError(
                toolCallId: approvalRequest.toolCallId,
                approvalId: approvalRequest.approvalId
            )
        }

        let collected = CollectedToolApproval(
            approvalRequest: approvalRequest,
            approvalResponse: response,
            toolCall: toolCall,
            existingToolResult: existingToolResult
        )

        if response.approved {
            approved.append(collected)
        } else {
            denied.append(collected)
        }
    }

    approved.sort {
        (toolCallOrder[$0.toolCall.toolCallId] ?? 0) < (toolCallOrder[$1.toolCall.toolCallId] ?? 0)
    }

    return (approvedToolApprovals: approved, deniedToolApprovals: denied)
}
