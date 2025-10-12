import Foundation

/**
 Metadata for speech model responses.

 Port of `@ai-sdk/ai/src/types/speech-model-response-metadata.ts`.
 */
public struct SpeechModelResponseMetadata: @unchecked Sendable {
    /// Timestamp for the start of the generated response
    public let timestamp: Date

    /// The ID of the response model that was used to generate the response
    public let modelId: String

    /// Response headers
    public let headers: [String: String]?

    /// Response body (opaque data, marked @unchecked Sendable to match TypeScript's unknown)
    public let body: Any?

    public init(
        timestamp: Date,
        modelId: String,
        headers: [String: String]? = nil,
        body: Any? = nil
    ) {
        self.timestamp = timestamp
        self.modelId = modelId
        self.headers = headers
        self.body = body
    }
}
