/**
 Options for `VideoModelV4.doGenerate`.

 Port of `@ai-sdk/provider/src/video-model/v4/video-model-v4-call-options.ts`.
 */
public struct VideoModelV4CallOptions: Sendable {
    public let prompt: String?
    public let n: Int
    public let aspectRatio: String?
    public let resolution: String?
    public let duration: Int?
    public let fps: Int?
    public let seed: Int?
    public let image: VideoModelV4File?
    public let frameImages: [VideoModelV4FrameImage]?
    public let inputReferences: [VideoModelV4File]?
    public let generateAudio: Bool?
    public let providerOptions: SharedV4ProviderOptions?
    public let abortSignal: (@Sendable () -> Bool)?
    public let headers: SharedV4Headers?

    public init(
        prompt: String? = nil,
        n: Int,
        aspectRatio: String? = nil,
        resolution: String? = nil,
        duration: Int? = nil,
        fps: Int? = nil,
        seed: Int? = nil,
        image: VideoModelV4File? = nil,
        frameImages: [VideoModelV4FrameImage]? = nil,
        inputReferences: [VideoModelV4File]? = nil,
        generateAudio: Bool? = nil,
        providerOptions: SharedV4ProviderOptions? = nil,
        abortSignal: (@Sendable () -> Bool)? = nil,
        headers: SharedV4Headers? = nil
    ) {
        self.prompt = prompt
        self.n = n
        self.aspectRatio = aspectRatio
        self.resolution = resolution
        self.duration = duration
        self.fps = fps
        self.seed = seed
        self.image = image
        self.frameImages = frameImages
        self.inputReferences = inputReferences
        self.generateAudio = generateAudio
        self.providerOptions = providerOptions
        self.abortSignal = abortSignal
        self.headers = headers
    }
}
