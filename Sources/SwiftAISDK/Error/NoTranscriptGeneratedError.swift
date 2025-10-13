import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Error thrown when no transcript was generated.

 Port of `@ai-sdk/ai/src/error/no-transcript-generated-error.ts`.
 */
public struct NoTranscriptGeneratedError: AISDKError, Sendable {
    /// General AI SDK error domain (no specialized marker for this error type)
    public static let errorDomain = "vercel.ai.error"

    public let name = "AI_NoTranscriptGeneratedError"
    public let message = "No transcript generated."
    public let cause: (any Error)? = nil

    /// The response metadata for each call
    public let responses: [TranscriptionModelResponseMetadata]

    public init(responses: [TranscriptionModelResponseMetadata]) {
        self.responses = responses
    }
}
