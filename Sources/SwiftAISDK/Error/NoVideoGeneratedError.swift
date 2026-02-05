import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Error thrown when no video could be generated.

 Port of `@ai-sdk/ai/src/error/no-video-generated-error.ts`.
 */
public struct NoVideoGeneratedError: AISDKError, Sendable {
    public static let errorDomain = "ai.error.NoVideoGeneratedError"

    public let name = "AI_NoVideoGeneratedError"
    public let message: String
    public let cause: (any Error)?

    /// The response metadata for each call.
    public let responses: [VideoModelResponseMetadata]?

    public init(
        message: String? = nil,
        cause: (any Error)? = nil,
        responses: [VideoModelResponseMetadata]? = nil
    ) {
        self.message = message ?? "No video generated."
        self.cause = cause
        self.responses = responses
    }

    public static func isInstance(_ error: any Error) -> Bool {
        hasMarker(error, marker: errorDomain)
    }
}

