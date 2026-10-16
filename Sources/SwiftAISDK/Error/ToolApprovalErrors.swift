import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 A tool approval response references an approval id that has no matching
 tool approval request in the message history.

 Port of `@ai-sdk/ai/src/error/invalid-tool-approval-error.ts`.
 */
public struct InvalidToolApprovalError: AISDKError, Sendable {
    public static let errorDomain = "vercel.ai.error.AI_InvalidToolApprovalError"

    public let name = "AI_InvalidToolApprovalError"
    public let message: String
    public let cause: (any Error)? = nil

    public let approvalId: String

    public init(approvalId: String) {
        self.approvalId = approvalId
        self.message =
            "Tool approval response references unknown approvalId: \"\(approvalId)\". "
            + "No matching tool-approval-request found in message history."
    }

    public static func isInstance(_ error: any Error) -> Bool {
        hasMarker(error, marker: errorDomain)
    }
}

/**
 A signed tool approval failed signature verification.

 Port of `@ai-sdk/ai/src/error/invalid-tool-approval-signature-error.ts`.
 */
public struct InvalidToolApprovalSignatureError: AISDKError, Sendable {
    public static let errorDomain = "vercel.ai.error.AI_InvalidToolApprovalSignatureError"

    public let name = "AI_InvalidToolApprovalSignatureError"
    public let message: String
    public let cause: (any Error)? = nil

    public let approvalId: String
    public let toolCallId: String

    public init(approvalId: String, toolCallId: String, reason: String) {
        self.approvalId = approvalId
        self.toolCallId = toolCallId
        self.message =
            "Tool approval signature verification failed for approval \"\(approvalId)\" (tool call \"\(toolCallId)\"): \(reason)"
    }

    public static func isInstance(_ error: any Error) -> Bool {
        hasMarker(error, marker: errorDomain)
    }
}

/**
 A tool approval request references a tool call that is not in the message
 history.

 Port of `@ai-sdk/ai/src/error/tool-call-not-found-for-approval-error.ts`.
 */
public struct ToolCallNotFoundForApprovalError: AISDKError, Sendable {
    public static let errorDomain = "vercel.ai.error.AI_ToolCallNotFoundForApprovalError"

    public let name = "AI_ToolCallNotFoundForApprovalError"
    public let message: String
    public let cause: (any Error)? = nil

    public let toolCallId: String
    public let approvalId: String

    public init(toolCallId: String, approvalId: String) {
        self.toolCallId = toolCallId
        self.approvalId = approvalId
        self.message = "Tool call \"\(toolCallId)\" not found for approval request \"\(approvalId)\"."
    }

    public static func isInstance(_ error: any Error) -> Bool {
        hasMarker(error, marker: errorDomain)
    }
}

/**
 Tool results are missing for tool calls in the message history.

 Port of `@ai-sdk/ai/src/error/missing-tool-result-error.ts`.
 */
public struct MissingToolResultsError: AISDKError, Sendable {
    public static let errorDomain = "vercel.ai.error.AI_MissingToolResultsError"

    public let name = "AI_MissingToolResultsError"
    public let message: String
    public let cause: (any Error)? = nil

    public let toolCallIds: [String]

    public init(toolCallIds: [String]) {
        self.toolCallIds = toolCallIds
        let plural = toolCallIds.count > 1
        self.message =
            "Tool result\(plural ? "s are" : " is") missing for tool call\(plural ? "s" : "") \(toolCallIds.joined(separator: ", "))."
    }

    public static func isInstance(_ error: any Error) -> Bool {
        hasMarker(error, marker: errorDomain)
    }
}
