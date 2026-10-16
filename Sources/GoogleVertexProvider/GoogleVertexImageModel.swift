import Foundation
import AISDKProvider
import AISDKProviderUtils
import GoogleProvider

struct GoogleVertexImageModelConfig: Sendable {
    let provider: String
    let baseURL: @Sendable () throws -> String
    let headers: @Sendable () throws -> [String: String?]
    let fetch: FetchFunction?
    let generateId: @Sendable () -> String
    let currentDate: @Sendable () -> Date
}

public typealias GoogleVertexImageModelOptions = GoogleLanguageModelOptions

public final class GoogleVertexImageModel: ImageModelV4 {
    private let modelIdentifier: GoogleVertexImageModelId
    private let config: GoogleVertexImageModelConfig

    init(modelId: GoogleVertexImageModelId, config: GoogleVertexImageModelConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }
    public var maxImagesPerCall: ImageModelV4MaxImagesPerCall { .value(1) }
    public var supportsFileInputs: Bool? {
        get async throws {
            ["gemini-2.5-flash-image", "gemini-3-pro-image-preview", "gemini-3.1-flash-image-preview", "gemini-nano-banana-2.1"].contains(modelId) ? true : nil
        }
    }
    public var supportsMaskInputs: Bool? { get async throws { try await supportsFileInputs == true ? false : nil } }

    public func doGenerate(options: ImageModelV4CallOptions) async throws -> ImageModelV4GenerateResult {
        guard modelId.hasPrefix("gemini-") else {
            throw UnsupportedFunctionalityError(functionality: "Google image models other than Gemini; use a model ID that starts with `gemini-`.")
        }
        if options.mask != nil {
            throw InvalidArgumentError(argument: "mask", message: "Gemini image models do not support mask-based image editing.")
        }
        var warnings: [SharedV4Warning] = []
        if options.size != nil {
            warnings.append(.unsupported(feature: "size", details: "This model does not support the `size` option. Use `aspectRatio` instead."))
        }
        var content: [LanguageModelV4UserMessagePart] = []
        if let prompt = options.prompt { content.append(.text(.init(text: prompt))) }
        for file in options.files ?? [] {
            switch file {
            case .url(let rawURL, _):
                guard let url = URL(string: rawURL), url.scheme != nil else {
                    throw InvalidArgumentError(argument: "files", message: "Invalid file URL: \(rawURL)")
                }
                content.append(.file(.init(data: .url(url, originalUrl: rawURL), mediaType: "image/*")))
            case .file(let mediaType, let data, _):
                switch data {
                case .base64(let value): content.append(.file(.init(data: .base64(value), mediaType: mediaType)))
                case .binary(let value): content.append(.file(.init(data: .data(value), mediaType: mediaType)))
                }
            }
        }
        var vertexOptions = options.providerOptions?["googleVertex"] ?? options.providerOptions?["vertex"] ?? [:]
        vertexOptions["responseModalities"] = .array([.string("IMAGE")])
        var imageConfig: JSONObject = [:]
        if case .object(let value) = vertexOptions["imageConfig"] { imageConfig = value }
        if let aspectRatio = options.aspectRatio { imageConfig["aspectRatio"] = .string(aspectRatio) }
        if !imageConfig.isEmpty { vertexOptions["imageConfig"] = .object(imageConfig) }
        let languageModel = GoogleLanguageModel(
            modelId: GoogleModelId(rawValue: modelId),
            config: .init(
                provider: provider, baseURL: try config.baseURL(), headers: config.headers,
                fetch: config.fetch, generateId: config.generateId,
                supportedUrls: { ["*": [googleVertexHTTPRegex, googleVertexGCSRegex]] }
            )
        )
        let result = try await languageModel.doGenerate(options: .init(
            prompt: [.user(content: content, providerOptions: nil)], seed: options.seed,
            abortSignal: options.abortSignal, headers: options.headers,
            providerOptions: ["googleVertex": vertexOptions, "vertex": vertexOptions]
        ))
        let images = result.content.compactMap { part -> String? in
            guard case .file(let file) = part, file.mediaType.hasPrefix("image/") else { return nil }
            switch file.data {
            case .base64(let value): return value
            case .data(let value): return value.base64EncodedString()
            case .url: return nil
            }
        }
        let payload = ImageModelV4ProviderMetadataValue(images: images.map { _ in .object([:]) })
        return ImageModelV4GenerateResult(
            images: .base64(images), isRetryable: result.finishReason.unified == .contentFilter ? false : nil,
            warnings: warnings, providerMetadata: ["googleVertex": payload, "vertex": payload],
            response: .init(timestamp: config.currentDate(), modelId: modelId, headers: result.response?.headers),
            usage: .init(
                inputTokens: result.usage.inputTokens.total, outputTokens: result.usage.outputTokens.total,
                totalTokens: (result.usage.inputTokens.total ?? 0) + (result.usage.outputTokens.total ?? 0)
            )
        )
    }
}
