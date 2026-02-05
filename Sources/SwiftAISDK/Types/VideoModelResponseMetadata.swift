import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Response metadata for a video model call.

 Port of `@ai-sdk/ai/src/types/video-model-response-metadata.ts`.
 */
public struct VideoModelResponseMetadata: Sendable, Equatable, Codable {
    /// Timestamp for the start of the generated response.
    public let timestamp: Date

    /// The ID of the response model that was used to generate the response.
    public let modelId: String

    /// Response headers.
    public let headers: [String: String]?

    /// Provider-specific metadata for this call.
    public let providerMetadata: VideoModelProviderMetadata?

    public init(
        timestamp: Date,
        modelId: String,
        headers: [String: String]? = nil,
        providerMetadata: VideoModelProviderMetadata? = nil
    ) {
        self.timestamp = timestamp
        self.modelId = modelId
        self.headers = headers
        self.providerMetadata = providerMetadata
    }
}

