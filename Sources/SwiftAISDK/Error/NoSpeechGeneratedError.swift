import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Error thrown when no speech audio was generated.

 Port of `@ai-sdk/ai/src/error/no-speech-generated-error.ts`.
 */
public struct NoSpeechGeneratedError: AISDKError, Sendable {
    /// General AI SDK error domain (no specialized marker for this error type)
    public static let errorDomain = "vercel.ai.error"

    public let name = "AI_NoSpeechGeneratedError"
    public let message = "No speech audio generated."
    public let cause: (any Error)? = nil

    /// The response metadata for each call
    public let responses: [SpeechModelResponseMetadata]

    public init(responses: [SpeechModelResponseMetadata]) {
        self.responses = responses
    }
}
