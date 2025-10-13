import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Union type for the original error in ToolCallRepairError.

 Port of TypeScript union: `NoSuchToolError | InvalidToolInputError`
 */
public enum ToolCallOriginalError: Sendable {
    case noSuchTool(NoSuchToolError)
    case invalidToolInput(InvalidToolInputError)
}

/**
 Error thrown when an attempt to repair a tool call fails.

 Port of `@ai-sdk/ai/src/error/tool-call-repair-error.ts`.
 */
public struct ToolCallRepairError: AISDKError, Sendable {
    public static let errorDomain = "vercel.ai.error.AI_ToolCallRepairError"

    public let name = "AI_ToolCallRepairError"
    public let message: String
    public let cause: (any Error)?

    /// The original error that triggered the repair attempt
    public let originalError: ToolCallOriginalError

    public init(
        originalError: ToolCallOriginalError,
        cause: (any Error)?,
        message: String? = nil
    ) {
        self.originalError = originalError
        self.cause = cause

        if let message = message {
            self.message = message
        } else {
            self.message = "Error repairing tool call: \(AISDKProvider.getErrorMessage(cause))"
        }
    }

    public static func isInstance(_ error: any Error) -> Bool {
        hasMarker(error, marker: errorDomain)
    }
}
