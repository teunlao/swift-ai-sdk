import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Result of a video generation call.

 Port of `@ai-sdk/ai/src/generate-video/generate-video-result.ts`.
 */
public protocol GenerateVideoResult: Sendable {
    /// The first generated video.
    var video: GeneratedFile { get }

    /// All generated videos.
    var videos: [GeneratedFile] { get }

    /// Provider warnings collected during generation.
    var warnings: [VideoGenerationWarning] { get }

    /// Response metadata for every model call.
    var responses: [VideoModelResponseMetadata] { get }

    /// Provider-specific metadata aggregated across calls.
    var providerMetadata: VideoModelProviderMetadata { get }
}

/**
 Default implementation of `GenerateVideoResult`.
 */
public final class DefaultGenerateVideoResult: GenerateVideoResult {
    public let videos: [GeneratedFile]
    public let warnings: [VideoGenerationWarning]
    public let responses: [VideoModelResponseMetadata]
    public let providerMetadata: VideoModelProviderMetadata

    public init(
        videos: [GeneratedFile],
        warnings: [VideoGenerationWarning],
        responses: [VideoModelResponseMetadata],
        providerMetadata: VideoModelProviderMetadata
    ) {
        self.videos = videos
        self.warnings = warnings
        self.responses = responses
        self.providerMetadata = providerMetadata
    }

    public var video: GeneratedFile {
        videos[0]
    }
}

