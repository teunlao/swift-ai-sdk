import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct ProdiaImageModelOptions: Sendable, Equatable, Codable {
    public var steps: Int?
    public var width: Int?
    public var height: Int?
    public var stylePreset: String?
    public var loras: [String]?
    public var progressive: Bool?
    public init(steps: Int? = nil, width: Int? = nil, height: Int? = nil, stylePreset: String? = nil, loras: [String]? = nil, progressive: Bool? = nil) {
        self.steps = steps
        self.width = width
        self.height = height
        self.stylePreset = stylePreset
        self.loras = loras
        self.progressive = progressive
    }
}

private let prodiaImageOptionsSchema = FlexibleSchema(jsonSchema(.object([
    "type": .string("object"), "properties": .object([
        "steps": .object(["type": .string("integer"), "minimum": .number(1), "maximum": .number(4)]),
        "width": .object(["type": .string("integer"), "minimum": .number(256), "maximum": .number(1920)]),
        "height": .object(["type": .string("integer"), "minimum": .number(256), "maximum": .number(1920)]),
        "stylePreset": .object(["enum": .array(["3d-model", "analog-film", "anime", "cinematic", "comic-book", "digital-art", "enhance", "fantasy-art", "isometric", "line-art", "low-poly", "neon-punk", "origami", "photographic", "pixel-art", "texture", "craft-clay"].map(JSONValue.string))]),
        "loras": .object(["type": .string("array"), "maxItems": .number(3), "items": .object(["type": .string("string")])]),
        "progressive": .object(["type": .string("boolean")])
    ])
])))

public final class ProdiaImageModel: ImageModelV4 {
    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }
    public var maxImagesPerCall: ImageModelV4MaxImagesPerCall { .value(1) }
    public var supportsFileInputs: Bool? { ["inference.flux-fast.schnell.txt2img.v2", "inference.flux.schnell.txt2img.v2"].contains(modelId) ? false : nil }
    public var supportsMaskInputs: Bool? { supportsFileInputs == false ? false : nil }
    private let modelIdentifier: ProdiaImageModelId
    private let config: ProdiaModelConfig

    init(modelId: ProdiaImageModelId, config: ProdiaModelConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public func doGenerate(options: ImageModelV4CallOptions) async throws -> ImageModelV4GenerateResult {
        let parsed = try await parseProviderOptions(provider: "prodia", providerOptions: options.providerOptions, schema: prodiaImageOptionsSchema)
        var providerOptions: [String: JSONValue] = [:]
        if case .object(let values) = parsed { providerOptions = values }
        var warnings: [SharedV4Warning] = []
        if let aspect = options.aspectRatio, !aspect.isEmpty { warnings.append(.unsupported(feature: "aspectRatio", details: "This provider does not support aspect ratio. Use `size` instead.")) }
        var job: [String: JSONValue] = [:]
        if let size = options.size, !size.isEmpty {
            let parts = size.components(separatedBy: "x")
            let width = parts.first.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : Double($0) }
            let height = parts.count > 1 ? (parts[1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : Double(parts[1])) : nil
            if let width, let height, width.isFinite, height.isFinite {
                job["width"] = .number(width)
                job["height"] = .number(height)
            } else { warnings.append(.unsupported(feature: "size", details: "Invalid size format: \(size). Expected format: WIDTHxHEIGHT (e.g., 1024x1024)")) }
        }
        if let prompt = options.prompt { job["prompt"] = .string(prompt) }
        if let seed = options.seed { job["seed"] = .number(Double(seed)) }
        for key in ["width", "height", "steps", "loras", "progressive"] { if let value = providerOptions[key] { job[key] = value } }
        job["style_preset"] = providerOptions["stylePreset"]
        let timestamp = config.currentDate()
        var headers = combineHeaders(try await config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 }
        headers["Accept"] = "multipart/form-data; image/png"
        let response = try await postJsonToAPI(
            url: "\(config.baseURL)/job?price=true", headers: headers,
            body: JSONValue.object(["type": .string(modelId), "config": .object(job)]),
            failedResponseHandler: prodiaFailedResponseHandler, successfulResponseHandler: prodiaMultipartResponseHandler,
            isAborted: options.abortSignal, fetch: config.fetch
        )
        guard let image = response.value.parts.last(where: { $0.disposition.contains("name=\"output\"") || (!$0.disposition.contains("name=\"job\"") && $0.mediaType.hasPrefix("image/")) }) else {
            throw InvalidResponseDataError(data: nil, message: "Prodia multipart response missing output image")
        }
        return .init(images: .binary([image.body]), warnings: warnings, providerMetadata: ["prodia": .init(images: [.object(response.value.job.metadata)])], response: .init(timestamp: timestamp, modelId: modelId, headers: response.responseHeaders))
    }
}
