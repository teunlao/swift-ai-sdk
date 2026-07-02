/**
 Options for `ImageModelV4.doGenerate`.

 Port of `@ai-sdk/provider/src/image-model/v4/image-model-v4-call-options.ts`.
 */
public struct ImageModelV4CallOptions: Sendable {
    public let prompt: String?
    public let n: Int
    public let size: String?
    public let aspectRatio: String?
    public let seed: Int?
    public let files: [ImageModelV4File]?
    public let mask: ImageModelV4File?
    public let providerOptions: SharedV4ProviderOptions?
    public let abortSignal: (@Sendable () -> Bool)?
    public let headers: SharedV4Headers?

    public init(
        prompt: String? = nil,
        n: Int,
        size: String? = nil,
        aspectRatio: String? = nil,
        seed: Int? = nil,
        files: [ImageModelV4File]? = nil,
        mask: ImageModelV4File? = nil,
        providerOptions: SharedV4ProviderOptions? = nil,
        abortSignal: (@Sendable () -> Bool)? = nil,
        headers: SharedV4Headers? = nil
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
}
