import Foundation

/**
 Response metadata for image generation model calls.

 Port of `@ai-sdk/ai/src/types/image-model-response-metadata.ts`.

 Contains information about the image generation response including timestamp,
 model ID, and optional HTTP headers.
 */
public struct ImageModelResponseMetadata: Sendable, Equatable, Codable {
    /// Timestamp for the start of the generated response.
    public let timestamp: Date

    /// The ID of the response model that was used to generate the response.
    public let modelId: String

    /// Response headers.
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
