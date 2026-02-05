import Foundation

/**
 Options for VideoModelV3 doGenerate call.

 Port of `@ai-sdk/provider/src/video-model/v3/video-model-v3-call-options.ts`.
 */
public struct VideoModelV3CallOptions: Sendable {
    /// Text prompt for the video generation.
    public let prompt: String?

    /// Number of videos to generate.
    public let n: Int

    /// Aspect ratio of the videos to generate (format: "{width}:{height}").
    public let aspectRatio: String?

    /// Resolution of the video to generate (format: "{width}x{height}").
    public let resolution: String?

    /// Duration of the video in seconds.
    public let duration: Int?

    /// Frames per second (FPS) for the video.
    public let fps: Int?

    /// Seed for deterministic video generation.
    public let seed: Int?

    /// Input image for image-to-video generation.
    public let image: VideoModelV3File?

    /// Additional provider-specific options.
    public let providerOptions: SharedV3ProviderOptions?

    /// Abort signal for cancelling the operation.
    public let abortSignal: (@Sendable () -> Bool)?

    /// Additional HTTP headers (HTTP-based providers only).
    public let headers: [String: String]?

    public init(
        prompt: String? = nil,
        n: Int,
        aspectRatio: String? = nil,
        resolution: String? = nil,
        duration: Int? = nil,
        fps: Int? = nil,
        seed: Int? = nil,
        image: VideoModelV3File? = nil,
        providerOptions: SharedV3ProviderOptions? = nil,
        abortSignal: (@Sendable () -> Bool)? = nil,
        headers: [String: String]? = nil
    ) {
        self.prompt = prompt
        self.n = n
        self.aspectRatio = aspectRatio
        self.resolution = resolution
        self.duration = duration
        self.fps = fps
        self.seed = seed
        self.image = image
        self.providerOptions = providerOptions
        self.abortSignal = abortSignal
        self.headers = headers
    }
}

