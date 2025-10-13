import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Output part that indicates that a tool approval request has been made.

 The tool approval request can be approved or denied in the next tool message.

 Port of `@ai-sdk/ai/src/generate-text/tool-approval-request-output.ts`.
 */
public struct ToolApprovalRequestOutput: Sendable {
    /// Type discriminator.
    public let type: String = "tool-approval-request"

    /// ID of the tool approval request.
    public let approvalId: String

    /// Tool call that the approval request is for.
    public let toolCall: TypedToolCall

    public init(
        approvalId: String,
        toolCall: TypedToolCall
    ) {
        self.approvalId = approvalId
        self.toolCall = toolCall
    }
}
