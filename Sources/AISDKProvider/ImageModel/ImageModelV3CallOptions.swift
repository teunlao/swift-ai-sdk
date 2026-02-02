/**
 Options for ImageModelV3 doGenerate call.

 Port of `@ai-sdk/provider/src/image-model/v3/image-model-v3-call-options.ts`.
 */
public struct ImageModelV3CallOptions: Sendable {
    /// Prompt for the image generation
    public let prompt: String

    /// Number of images to generate
    public let n: Int

    /// Size of the images to generate
    /// Must have the format "{width}x{height}"
    /// `nil` will use the provider's default size
    public let size: String?

    /// Aspect ratio of the images to generate
    /// Must have the format "{width}:{height}"
    /// `nil` will use the provider's default aspect ratio
    public let aspectRatio: String?

    /// Seed for the image generation
    /// `nil` will use the provider's default seed
    public let seed: Int?

    /// Array of images for image editing or variation generation.
    /// Port of `files?: ImageModelV3File[]`.
    public let files: [ImageModelV3File]?

    /// Mask image for inpainting operations.
    /// Port of `mask?: ImageModelV3File`.
    public let mask: ImageModelV3File?

    /// Additional provider-specific options
    public let providerOptions: SharedV3ProviderOptions?

    /// Abort signal for cancelling the operation
    public let abortSignal: (@Sendable () -> Bool)?

    /// Additional HTTP headers to be sent with the request (only applicable for HTTP-based providers)
    public let headers: [String: String]?

    public init(
        prompt: String,
        n: Int,
        size: String? = nil,
        aspectRatio: String? = nil,
        seed: Int? = nil,
        files: [ImageModelV3File]? = nil,
        mask: ImageModelV3File? = nil,
        providerOptions: SharedV3ProviderOptions? = nil,
        abortSignal: (@Sendable () -> Bool)? = nil,
        headers: [String: String]? = nil
    ) {
        self.prompt = prompt
        self.n = n
        self.size = size
        self.aspectRatio = aspectRatio
        self.seed = seed
        self.files = files
        self.mask = mask
        self.providerOptions = providerOptions
        self.abortSignal = abortSignal
        self.headers = headers
    }

    /// Backwards-compatible initializer (pre `files`/`mask`).
    public init(
        prompt: String,
        n: Int,
        size: String? = nil,
        aspectRatio: String? = nil,
        seed: Int? = nil,
        providerOptions: SharedV3ProviderOptions? = nil,
        abortSignal: (@Sendable () -> Bool)? = nil,
        headers: [String: String]? = nil
    ) {
        self.init(
            prompt: prompt,
            n: n,
            size: size,
            aspectRatio: aspectRatio,
            seed: seed,
            files: nil,
            mask: nil,
            providerOptions: providerOptions,
            abortSignal: abortSignal,
            headers: headers
        )
    }
}
