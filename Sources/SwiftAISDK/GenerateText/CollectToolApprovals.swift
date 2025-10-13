/**
 Collect approved and denied tool approvals from conversation messages.

 Port of `@ai-sdk/ai/src/generate-text/collect-tool-approvals.ts`.
 */
import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Collect tool approvals from model messages when the last message comes from a tool.

 Port of `@ai-sdk/ai/src/generate-text/collect-tool-approvals.ts`.
 */
public func collectToolApprovals(
    messages: [ModelMessage]
) -> (
    approvedToolApprovals: [CollectedToolApproval],
    deniedToolApprovals: [CollectedToolApproval]
) {
    guard
        let lastMessage = messages.last,
        case .tool(let toolMessage) = lastMessage
    else {
        return (approvedToolApprovals: [], deniedToolApprovals: [])
    }

    var toolCallsById: [String: TypedToolCall] = [:]
    var approvalRequestsById: [String: ToolApprovalRequest] = [:]

    for message in messages {
        guard case .assistant(let assistantMessage) = message else { continue }

        switch assistantMessage.content {
        case .text:
            continue

        case .parts(let parts):
            for part in parts {
                switch part {
                case let .toolCall(toolCallPart):
                    let typedCall = TypedToolCall.static(
                        StaticToolCall(
                            toolCallId: toolCallPart.toolCallId,
                            toolName: toolCallPart.toolName,
                            input: toolCallPart.input,
                            providerExecuted: toolCallPart.providerExecuted,
                            providerMetadata: toolCallPart.providerOptions
                        )
                    )
                    toolCallsById[toolCallPart.toolCallId] = typedCall

                case let .toolApprovalRequest(approvalRequest):
                    approvalRequestsById[approvalRequest.approvalId] = approvalRequest

                default:
                    break
                }
            }
        }
    }

    var toolResultsByCallId: Set<String> = []
    for part in toolMessage.content {
        if case .toolResult(let resultPart) = part {
            toolResultsByCallId.insert(resultPart.toolCallId)
        }
    }

    var approved: [CollectedToolApproval] = []
    var denied: [CollectedToolApproval] = []

    for part in toolMessage.content {
        guard case .toolApprovalResponse(let response) = part else { continue }
        guard let approvalRequest = approvalRequestsById[response.approvalId] else {
            continue
        }

        if toolResultsByCallId.contains(approvalRequest.toolCallId) {
            continue
        }

        guard let toolCall = toolCallsById[approvalRequest.toolCallId] else {
            continue
        }

        let collected = CollectedToolApproval(
            approvalRequest: approvalRequest,
            approvalResponse: response,
            toolCall: toolCall
        )

        if response.approved {
            approved.append(collected)
        } else {
            denied.append(collected)
        }
    }

    return (approvedToolApprovals: approved, deniedToolApprovals: denied)
}

/// Collected tool approval (request, response, and associated tool call).
public struct CollectedToolApproval: Sendable {
    public let approvalRequest: ToolApprovalRequest
    public let approvalResponse: ToolApprovalResponse
    public let toolCall: TypedToolCall

    public init(
        approvalRequest: ToolApprovalRequest,
        approvalResponse: ToolApprovalResponse,
        toolCall: TypedToolCall
    ) {
        self.approvalRequest = approvalRequest
        self.approvalResponse = approvalResponse
        self.toolCall = toolCall
    }
}
