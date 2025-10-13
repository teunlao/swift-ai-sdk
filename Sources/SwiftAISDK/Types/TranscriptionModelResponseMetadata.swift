import Foundation

/**
 Metadata for transcription model responses.

 Port of `@ai-sdk/ai/src/types/transcription-model-response-metadata.ts`.
 */
public struct TranscriptionModelResponseMetadata: Sendable {
    /// Timestamp for the start of the generated response
    public let timestamp: Date

    /// The ID of the response model that was used to generate the response
    public let modelId: String

    /// Response headers
    public let headers: [String: String]?

    public init(
        timestamp: Date,
        modelId: String,
        headers: [String: String]? = nil
    ) {
        self.timestamp = timestamp
        self.modelId = modelId
        self.headers = headers
    }
}
