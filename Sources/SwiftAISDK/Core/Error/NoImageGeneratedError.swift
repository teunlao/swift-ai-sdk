import Foundation

/**
 Error thrown when no image could be generated.

 Port of `@ai-sdk/ai/src/error/no-image-generated-error.ts`.

 This can have multiple causes:
 - The model failed to generate a response.
 - The model generated a response that could not be parsed.
 */
public struct NoImageGeneratedError: AISDKError, Sendable {
    public static let errorDomain = "ai.error.NoImageGeneratedError"

    public let name = "AI_NoImageGeneratedError"
    public let message: String
    public let cause: (any Error)?

    /// The response metadata for each call.
    public let responses: [ImageModelResponseMetadata]?

    public init(
        message: String? = nil,
        cause: (any Error)? = nil,
        responses: [ImageModelResponseMetadata]? = nil
    ) {
        self.message = message ?? "No image generated."
        self.cause = cause
        self.responses = responses
    }

    public static func isInstance(_ error: any Error) -> Bool {
        SwiftAISDK.hasMarker(error, marker: errorDomain)
    }
}
