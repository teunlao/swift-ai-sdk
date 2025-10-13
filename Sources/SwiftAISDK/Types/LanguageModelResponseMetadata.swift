import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Response metadata for language model calls.

 Port of `@ai-sdk/ai/src/types/language-model-response-metadata.ts`.

 Contains information about the generated response including ID, timestamp,
 model ID, and optional HTTP headers.
 */
public struct LanguageModelResponseMetadata: Sendable, Equatable, Codable {
    /// ID for the generated response.
    public let id: String

    /// Timestamp for the start of the generated response.
    public let timestamp: Date

    /// The ID of the response model that was used to generate the response.
    public let modelId: String

    /// Response headers (available only for providers that use HTTP requests).
    public let headers: [String: String]?

    public init(
        id: String,
        timestamp: Date,
        modelId: String,
        headers: [String: String]? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.modelId = modelId
        self.headers = headers
    }
}
