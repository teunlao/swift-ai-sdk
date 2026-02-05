import Foundation

/**
 Video generation model specification version 3.

 Port of `@ai-sdk/provider/src/video-model/v3/video-model-v3.ts`.
 */
public protocol VideoModelV3: Sendable {
    /**
     The video model must specify which video model interface
     version it implements. This will allow us to evolve the video
     model interface and retain backwards compatibility.
     */
    var specificationVersion: String { get }

    /**
     Name of the provider for logging purposes.
     */
    var provider: String { get }

    /**
     Provider-specific model ID for logging purposes.
     */
    var modelId: String { get }

    /**
     Limit of how many videos can be generated in a single API call.
     */
    var maxVideosPerCall: VideoModelV3MaxVideosPerCall { get }

    /**
     Generates an array of videos.

     - Parameter options: Call options for video generation
     - Returns: Result containing generated videos, warnings, and metadata
     - Throws: Errors during video generation
     */
    func doGenerate(options: VideoModelV3CallOptions) async throws -> VideoModelV3GenerateResult
}

extension VideoModelV3 {
    /// Default implementation returns "v3"
    public var specificationVersion: String { "v3" }
}

// MARK: - Supporting Types

/// Maximum videos per call configuration
public enum VideoModelV3MaxVideosPerCall: Sendable {
    /// Fixed limit
    case value(Int)

    /// Use global/default limit
    case `default`

    /// Function that returns limit (can be sync or async)
    case function(@Sendable (String) async throws -> Int?)
}

/**
 Generated video data.

 Port of `VideoModelV3VideoData` from upstream.
 */
public enum VideoModelV3VideoData: Sendable, Equatable {
    /// Video available as a URL.
    case url(url: String, mediaType: String?)

    /// Video as base64-encoded string.
    case base64(data: String, mediaType: String?)

    /// Video as binary data.
    case binary(data: Data, mediaType: String?)
}

/// Result from VideoModelV3 doGenerate call
public struct VideoModelV3GenerateResult: Sendable {
    /// Generated videos as URLs, base64 strings, or binary data.
    public let videos: [VideoModelV3VideoData]

    /// Warnings for the call, e.g. unsupported features.
    public let warnings: [SharedV3Warning]

    /// Additional provider-specific metadata.
    public let providerMetadata: SharedV3ProviderMetadata?

    /// Response information for telemetry and debugging purposes.
    public let response: VideoModelV3ResponseInfo

    public init(
        videos: [VideoModelV3VideoData],
        warnings: [SharedV3Warning] = [],
        providerMetadata: SharedV3ProviderMetadata? = nil,
        response: VideoModelV3ResponseInfo
    ) {
        self.videos = videos
        self.warnings = warnings
        self.providerMetadata = providerMetadata
        self.response = response
    }
}

/// Response information for telemetry and debugging
public struct VideoModelV3ResponseInfo: Sendable {
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

