/**
 Tests for collectToolApprovals helper.

 Port of `@ai-sdk/ai/src/generate-text/collect-tool-approvals.test.ts`.
 */
import Testing
import AISDKProvider
import AISDKProviderUtils
@testable import SwiftAISDK

@Suite("Collect Tool Approvals")
struct CollectToolApprovalsTests {
    @Test("should not return approvals when last message is not tool")
    func noApprovalsWhenLastMessageNotTool() {
        let messages: [ModelMessage] = [
            .user(UserModelMessage(content: .text("Hello, world!")))
        ]

        let result = collectToolApprovals(messages: messages)

        #expect(result.approvedToolApprovals.isEmpty)
        #expect(result.deniedToolApprovals.isEmpty)
    }

    @Test("should ignore approval request without response")
    func ignoreApprovalWithoutResponse() {
        let toolCall = makeStaticToolCall(id: "call-1", name: "tool1")
        let toolCallPart = makeToolCallPart(toolCall)
        let approvalRequestPart = ToolApprovalRequest(approvalId: "approval-id-1", toolCallId: "call-1")

        let messages: [ModelMessage] = [
            .assistant(
                AssistantModelMessage(
                    content: .parts([
                        .toolCall(toolCallPart),
                        .toolApprovalRequest(approvalRequestPart)
                    ])
                )
            ),
            .tool(ToolModelMessage(content: []))
        ]

        let result = collectToolApprovals(messages: messages)

        #expect(result.approvedToolApprovals.isEmpty)
        #expect(result.deniedToolApprovals.isEmpty)
    }

    @Test("should return approved approval with approved response")
    func approvedApprovalWithResponse() {
        let toolCall = makeStaticToolCall(id: "call-1", name: "tool1")
        let toolCallPart = makeToolCallPart(toolCall)
        let approvalRequestPart = ToolApprovalRequest(approvalId: "approval-id-1", toolCallId: "call-1")

        let messages: [ModelMessage] = [
            .assistant(
                AssistantModelMessage(
                    content: .parts([
                        .toolCall(toolCallPart),
                        .toolApprovalRequest(approvalRequestPart)
                    ])
                )
            ),
            .tool(
                ToolModelMessage(
                    content: [
                        .toolApprovalResponse(
                            ToolApprovalResponse(approvalId: "approval-id-1", approved: true)
                        )
                    ]
                )
            )
        ]

        let result = collectToolApprovals(messages: messages)

        #expect(result.approvedToolApprovals.count == 1)
        let approval = result.approvedToolApprovals.first!
        #expect(approval.approvalRequest.approvalId == "approval-id-1")
        #expect(approval.approvalResponse.approved)
        #expect(approval.toolCall.toolCallId == "call-1")
        #expect(result.deniedToolApprovals.isEmpty)
    }

    @Test("should ignore approval when tool result exists")
    func skipApprovalWhenToolResultPresent() {
        let toolCall = makeStaticToolCall(id: "call-1", name: "tool1")
        let toolCallPart = makeToolCallPart(toolCall)
        let approvalRequestPart = ToolApprovalRequest(approvalId: "approval-id-1", toolCallId: "call-1")

        let messages: [ModelMessage] = [
            .assistant(
                AssistantModelMessage(
                    content: .parts([
                        .toolCall(toolCallPart),
                        .toolApprovalRequest(approvalRequestPart)
                    ])
                )
            ),
            .tool(
                ToolModelMessage(
                    content: [
                        .toolApprovalResponse(
                            ToolApprovalResponse(approvalId: "approval-id-1", approved: true)
                        ),
                        .toolResult(
                            ToolResultPart(
                                toolCallId: "call-1",
                                toolName: "tool1",
                                output: .text(value: "test-output")
                            )
                        )
                    ]
                )
            )
        ]

        let result = collectToolApprovals(messages: messages)

        #expect(result.approvedToolApprovals.isEmpty)
        #expect(result.deniedToolApprovals.isEmpty)
    }

    @Test("should return denied approval with denied response")
    func deniedApproval() {
        let toolCall = makeStaticToolCall(id: "call-1", name: "tool1")
        let toolCallPart = makeToolCallPart(toolCall)
        let approvalRequestPart = ToolApprovalRequest(approvalId: "approval-id-1", toolCallId: "call-1")

        let messages: [ModelMessage] = [
            .assistant(
                AssistantModelMessage(
                    content: .parts([
                        .toolCall(toolCallPart),
                        .toolApprovalRequest(approvalRequestPart)
                    ])
                )
            ),
            .tool(
                ToolModelMessage(
                    content: [
                        .toolApprovalResponse(
                            ToolApprovalResponse(approvalId: "approval-id-1", approved: false, reason: "test-reason")
                        )
                    ]
                )
            )
        ]

        let result = collectToolApprovals(messages: messages)

        #expect(result.approvedToolApprovals.isEmpty)
        #expect(result.deniedToolApprovals.count == 1)
        let denial = result.deniedToolApprovals.first!
        #expect(denial.approvalResponse.reason == "test-reason")
        #expect(denial.toolCall.toolCallId == "call-1")
    }

    @Test("should ignore denied response when tool result exists")
    func denyApprovalWithResult() {
        let toolCall = makeStaticToolCall(id: "call-1", name: "tool1")
        let toolCallPart = makeToolCallPart(toolCall)
        let approvalRequestPart = ToolApprovalRequest(approvalId: "approval-id-1", toolCallId: "call-1")

        let messages: [ModelMessage] = [
            .assistant(
                AssistantModelMessage(
                    content: .parts([
                        .toolCall(toolCallPart),
                        .toolApprovalRequest(approvalRequestPart)
                    ])
                )
            ),
            .tool(
                ToolModelMessage(
                    content: [
                        .toolApprovalResponse(
                            ToolApprovalResponse(approvalId: "approval-id-1", approved: false, reason: "test-reason")
                        ),
                        .toolResult(
                            ToolResultPart(
                                toolCallId: "call-1",
                                toolName: "tool1",
                                output: .errorText(value: "denied")
                            )
                        )
                    ]
                )
            )
        ]

        let result = collectToolApprovals(messages: messages)

        #expect(result.approvedToolApprovals.isEmpty)
        #expect(result.deniedToolApprovals.isEmpty)
    }

    @Test("should handle multiple approvals and denials")
    func multipleApprovalsAndDenials() {
        var assistantParts: [AssistantContentPart] = []
        var toolContent: [ToolContentPart] = []

        for index in 1...6 {
            let id = "call-approval-\(index)"
            let toolCall = makeStaticToolCall(id: id, name: "tool1", input: .object(["value": .string("test-input-\(index)")]))
            let toolCallPart = makeToolCallPart(toolCall)
            let approvalId = "approval-id-\(index)"
            assistantParts.append(.toolCall(toolCallPart))
            assistantParts.append(.toolApprovalRequest(ToolApprovalRequest(approvalId: approvalId, toolCallId: id)))

            if index <= 6 {
                switch index {
                case 1, 2:
                    toolContent.append(.toolApprovalResponse(ToolApprovalResponse(approvalId: approvalId, approved: true)))
                case 3:
                    toolContent.append(.toolApprovalResponse(ToolApprovalResponse(approvalId: approvalId, approved: false, reason: "test-reason")))
                case 4:
                    toolContent.append(.toolApprovalResponse(ToolApprovalResponse(approvalId: approvalId, approved: false)))
                case 5:
                    toolContent.append(.toolApprovalResponse(ToolApprovalResponse(approvalId: approvalId, approved: true)))
                    toolContent.append(.toolResult(ToolResultPart(toolCallId: id, toolName: "tool1", output: .text(value: "test-output-5"))))
                case 6:
                    toolContent.append(.toolApprovalResponse(ToolApprovalResponse(approvalId: approvalId, approved: false)))
                    toolContent.append(.toolResult(ToolResultPart(toolCallId: id, toolName: "tool1", output: .errorText(value: "execution-denied"))))
                default:
                    break
                }
            }
        }

        let messages: [ModelMessage] = [
            .assistant(AssistantModelMessage(content: .parts(assistantParts))),
            .tool(ToolModelMessage(content: toolContent))
        ]

        let result = collectToolApprovals(messages: messages)

        #expect(result.approvedToolApprovals.count == 2)
        #expect(result.approvedToolApprovals.map { $0.approvalRequest.approvalId }.sorted() == ["approval-id-1", "approval-id-2"])
        #expect(result.deniedToolApprovals.count == 2)
        #expect(result.deniedToolApprovals.map { $0.approvalRequest.approvalId }.sorted() == ["approval-id-3", "approval-id-4"])
    }

    private func makeStaticToolCall(
        id: String,
        name: String,
        input: JSONValue = .object([:])
    ) -> TypedToolCall {
        .static(
            StaticToolCall(
                toolCallId: id,
                toolName: name,
                input: input
            )
        )
    }

    private func makeToolCallPart(_ call: TypedToolCall) -> ToolCallPart {
        switch call {
        case .static(let value):
            return ToolCallPart(
                toolCallId: value.toolCallId,
                toolName: value.toolName,
                input: value.input,
                providerOptions: value.providerMetadata,
                providerExecuted: value.providerExecuted
            )
        case .dynamic(let value):
            return ToolCallPart(
                toolCallId: value.toolCallId,
                toolName: value.toolName,
                input: value.input,
                providerOptions: value.providerMetadata,
                providerExecuted: value.providerExecuted
            )
        }
    }
}
