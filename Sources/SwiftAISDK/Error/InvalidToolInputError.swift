import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Error thrown when a tool receives invalid input.

 Port of `@ai-sdk/ai/src/error/invalid-tool-input-error.ts`.
 */
public struct InvalidToolInputError: AISDKError, Sendable {
    public static let errorDomain = "vercel.ai.error.AI_InvalidToolInputError"

    public let name = "AI_InvalidToolInputError"
    public let message: String
    public let cause: (any Error)?

    /// The name of the tool
    public let toolName: String

    /// The invalid input string
    public let toolInput: String

    public init(
        toolName: String,
        toolInput: String,
        cause: (any Error)?,
        message: String? = nil
    ) {
        self.toolName = toolName
        self.toolInput = toolInput
        self.cause = cause

        if let message = message {
            self.message = message
        } else {
            self.message = "Invalid input for tool \(toolName): \(AISDKProvider.getErrorMessage(cause))"
        }
    }

    public static func isInstance(_ error: any Error) -> Bool {
        hasMarker(error, marker: errorDomain)
    }
}
