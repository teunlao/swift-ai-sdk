import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Output part that indicates that a tool approval request has been made.

 The tool approval request can be approved or denied in the next tool message.

 Port of `@ai-sdk/ai/src/generate-text/tool-approval-request-output.ts`.
 */
public struct ToolApprovalRequestOutput: Sendable {
    public let type: String = "tool-approval-request"

    /// ID of the tool approval.
    public let approvalId: String

    /// Tool call that the approval request is for.
    public let toolCall: TypedToolCall

    /// Optional reason for the approval request.
    public let reason: String?

    /// Whether the approval was decided automatically by the tool approval configuration.
    public let isAutomatic: Bool?

    /// HMAC signature of the approval request, when a tool approval secret is configured.
    public let signature: String?

    public init(
        approvalId: String,
        toolCall: TypedToolCall,
        reason: String? = nil,
        isAutomatic: Bool? = nil,
        signature: String? = nil
    ) {
        self.approvalId = approvalId
        self.toolCall = toolCall
        self.reason = reason
        self.isAutomatic = isAutomatic
        self.signature = signature
    }
}

/**
 Output part that indicates that a tool approval has been resolved.

 Port of `@ai-sdk/ai/src/generate-text/tool-approval-response-output.ts`.
 */
public struct ToolApprovalResponseOutput: Sendable {
    public let type: String = "tool-approval-response"

    /// ID of the tool approval.
    public let approvalId: String

    /// Tool call that the approval response is for.
    public let toolCall: TypedToolCall

    /// Whether the tool call was approved.
    public let approved: Bool

    /// Optional reason for the approval or denial.
    public let reason: String?

    /// Whether the tool call is executed by the provider.
    public let providerExecuted: Bool?

    public init(
        approvalId: String,
        toolCall: TypedToolCall,
        approved: Bool,
        reason: String? = nil,
        providerExecuted: Bool? = nil
    ) {
        self.approvalId = approvalId
        self.toolCall = toolCall
        self.approved = approved
        self.reason = reason
        self.providerExecuted = providerExecuted
    }
}
