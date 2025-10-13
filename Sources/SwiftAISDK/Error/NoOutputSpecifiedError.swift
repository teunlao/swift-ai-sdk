import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Error thrown when no output type is specified and output-related methods are called.

 Port of `@ai-sdk/ai/src/error/no-output-specified-error.ts`.
 */
public struct NoOutputSpecifiedError: AISDKError, Sendable {
    public static let errorDomain = "vercel.ai.error.AI_NoOutputSpecifiedError"

    public let name = "AI_NoOutputSpecifiedError"
    public let message: String
    public let cause: (any Error)? = nil

    public init(message: String = "No output specified.") {
        self.message = message
    }

    public static func isInstance(_ error: any Error) -> Bool {
        hasMarker(error, marker: errorDomain)
    }
}
