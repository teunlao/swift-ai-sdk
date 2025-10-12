import Foundation

/**
 Error thrown when no LLM output was generated, e.g. because of errors.

 Port of `@ai-sdk/ai/src/error/no-output-generated-error.ts`.
 */
public struct NoOutputGeneratedError: AISDKError, Sendable {
    public static let errorDomain = "vercel.ai.error.AI_NoOutputGeneratedError"

    public let name = "AI_NoOutputGeneratedError"
    public let message: String
    public let cause: (any Error)?

    public init(
        message: String = "No output generated.",
        cause: (any Error)? = nil
    ) {
        self.message = message
        self.cause = cause
    }

    public static func isInstance(_ error: any Error) -> Bool {
        hasMarker(error, marker: errorDomain)
    }
}
