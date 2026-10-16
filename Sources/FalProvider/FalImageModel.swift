import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/fal/src/fal-image-model.ts
// Upstream commit: 8a5233b15b1e69573d63faee6cd0014559252ee4
//===----------------------------------------------------------------------===//

struct FalImageModelConfig: Sendable {
    let provider: String
    let baseURL: String
    let headers: @Sendable () throws -> [String: String?]
    let fetch: FetchFunction?
    let currentDate: @Sendable () -> Date

    init(
        provider: String,
        baseURL: String,
        headers: @escaping @Sendable () throws -> [String: String?],
        fetch: FetchFunction?,
        currentDate: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.provider = provider
        self.baseURL = baseURL
        self.headers = headers
        self.fetch = fetch
        self.currentDate = currentDate
    }
}

public final class FalImageModel: ImageModelV4 {
    public var specificationVersion: String { "v4" }

    public var supportsFileInputs: Bool? {
        if [
            "fal-ai/flux-2/edit", "fal-ai/flux-pro/kontext", "fal-ai/flux-pro/kontext/max",
            "fal-ai/flux-general/image-to-image", "fal-ai/flux-general/inpainting",
            "fal-ai/flux-lora/image-to-image", "fal-ai/flux-lora/inpainting",
            "fal-ai/flux/dev/image-to-image", "fal-ai/flux/krea/image-to-image",
            "fal-ai/recraft/v3/image-to-image",
        ].contains(modelId) {
            return true
        }
        return [
            "bria/text-to-image/3.2", "fal-ai/bria/text-to-image/base",
            "fal-ai/bria/text-to-image/fast", "fal-ai/bria/text-to-image/hd",
            "fal-ai/bytedance/dreamina/v3.1/text-to-image",
            "fal-ai/flux-kontext-lora/text-to-image", "fal-ai/recraft/v3/text-to-image",
            "fal-ai/wan/v2.2-5b/text-to-image", "fal-ai/wan/v2.2-a14b/text-to-image",
        ].contains(modelId) ? false : nil
    }

    public var supportsMaskInputs: Bool? {
        if ["fal-ai/flux-general/inpainting", "fal-ai/flux-lora/inpainting"].contains(modelId) {
            return true
        }
        return supportsFileInputs == nil ? nil : false
    }
    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }
    public var maxImagesPerCall: ImageModelV4MaxImagesPerCall { .value(1) }

    private let modelIdentifier: FalImageModelId
    private let config: FalImageModelConfig

    init(modelId: FalImageModelId, config: FalImageModelConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public func doGenerate(options: ImageModelV4CallOptions) async throws -> ImageModelV4GenerateResult {
        let prepared = try await prepareRequest(options: options)

        let headers = combineHeaders(
            try config.headers(),
            options.headers?.mapValues { Optional($0) }
        ).compactMapValues { $0 }

        let now = config.currentDate()

        let response = try await postJsonToAPI(
            url: "\(config.baseURL)/\(modelIdentifier.rawValue)",
            headers: headers,
            body: JSONValue.object(prepared.body),
            failedResponseHandler: falImageFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: falImageResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let parsed = response.value

        let imagesData = try await withThrowingTaskGroup(of: (Int, Data).self) { group in
            for (index, image) in parsed.images.enumerated() {
                group.addTask { [config] in
                    let result = try await getFromAPI(
                        url: image.url,
                        headers: nil,
                        failedResponseHandler: createStatusCodeErrorResponseHandler(),
                        successfulResponseHandler: createBinaryResponseHandler(),
                        isAborted: options.abortSignal,
                        fetch: config.fetch,
                        validateUrl: true,
                        trustedOrigin: config.baseURL
                    )
                    return (index, result.value)
                }
            }
            var images = Array(repeating: Data(), count: parsed.images.count)
            for try await (index, data) in group { images[index] = data }
            return images
        }

        let imageMetadata: [JSONValue] = parsed.images.enumerated().map { index, image in
            var metadata = image.metadata
            let nsfw = parsed.nsfwConcepts.flatMap { index < $0.count ? $0[index] : nil }
                ?? parsed.nsfwDetected.flatMap { index < $0.count ? $0[index] : nil }
            if let nsfw { metadata["nsfw"] = .bool(nsfw) }
            return .object(metadata)
        }

        let additionalMetadata = parsed.additionalMetadata.isEmpty ? nil : JSONValue.object(parsed.additionalMetadata)

        return ImageModelV4GenerateResult(
            images: .binary(imagesData),
            warnings: prepared.warnings,
            providerMetadata: [
                "fal": ImageModelV4ProviderMetadataValue(
                    images: imageMetadata,
                    additionalData: additionalMetadata
                )
            ],
            response: ImageModelV4ResponseInfo(
                timestamp: now,
                modelId: modelIdentifier.rawValue,
                headers: response.responseHeaders
            )
        )
    }

    private struct PreparedRequest: Sendable {
        let body: [String: JSONValue]
        let warnings: [SharedV4Warning]
    }

    private func prepareRequest(options: ImageModelV4CallOptions) async throws -> PreparedRequest {
        var warnings: [SharedV4Warning] = []
        var body: [String: JSONValue] = [
            "num_images": .number(Double(options.n))
        ]

        if let prompt = options.prompt {
            body["prompt"] = .string(prompt)
        }

        if let seed = options.seed {
            body["seed"] = .number(Double(seed))
        }

        if let sizeValue = makeImageSize(size: options.size, aspectRatio: options.aspectRatio) {
            body["image_size"] = sizeValue
        }

        let falOptions = try await parseProviderOptions(
            provider: "fal",
            providerOptions: options.providerOptions,
            schema: falImageModelOptionsSchema
        )
        let useMultipleImages = falOptions?.useMultipleImages == true

        if let files = options.files, !files.isEmpty {
            if useMultipleImages {
                body["image_urls"] = .array(try files.map { file in
                    .string(try convertImageFileToDataURI(file))
                })
            } else {
                body["image_url"] = .string(try convertImageFileToDataURI(files[0]))

                if files.count > 1 {
                    warnings.append(.other(
                        message: "Multiple input images provided but useMultipleImages is not enabled. Only the first image will be used. Set providerOptions.fal.useMultipleImages to true for models that support multiple images (e.g., fal-ai/flux-2/edit)."
                    ))
                }
            }
        }

        if let mask = options.mask {
            body["mask_url"] = .string(try convertImageFileToDataURI(mask))
        }

        if let falOptions, !falOptions.deprecatedKeys.isEmpty {
            let mappedKeys = falOptions.deprecatedKeys.map { key in
                "'\(key)' (use '\(snakeToCamelCase(key))')"
            }.joined(separator: ", ")

            warnings.append(.other(
                message: "The following provider options use deprecated snake_case and will be removed in @ai-sdk/fal v2.0. Please use camelCase instead: \(mappedKeys)"
            ))
        }

        if let falOptions {
            for (key, value) in falOptions.options {
                if key == "useMultipleImages" || key == "__deprecatedKeys" { continue }
                let apiKey = camelToAPIFieldMapping[key] ?? key
                body[apiKey] = value
            }
        }

        return PreparedRequest(body: body, warnings: warnings)
    }
}

// MARK: - Helpers

private func makeImageSize(size: String?, aspectRatio: String?) -> JSONValue? {
    if let size, !size.isEmpty {
        let parts = size.split(separator: "x", omittingEmptySubsequences: false)
        var dimensions: [String: JSONValue] = [:]
        for (key, part) in zip(["width", "height"], parts) {
            let value = part.trimmingCharacters(in: .whitespacesAndNewlines)
            let number = value.isEmpty ? 0 : Double(value)
            dimensions[key] = number.flatMap { $0.isFinite ? .number($0) : nil } ?? .null
        }
        return .object(dimensions)
    }

    guard let aspectRatio else {
        return nil
    }

    switch aspectRatio {
    case "1:1":
        return .string("square_hd")
    case "16:9":
        return .string("landscape_16_9")
    case "9:16":
        return .string("portrait_16_9")
    case "4:3":
        return .string("landscape_4_3")
    case "3:4":
        return .string("portrait_4_3")
    case "16:10":
        return .object([
            "width": .number(1280),
            "height": .number(800)
        ])
    case "10:16":
        return .object([
            "width": .number(800),
            "height": .number(1280)
        ])
    case "21:9":
        return .object([
            "width": .number(2560),
            "height": .number(1080)
        ])
    case "9:21":
        return .object([
            "width": .number(1080),
            "height": .number(2560)
        ])
    default:
        return nil
    }
}

private let camelToAPIFieldMapping: [String: String] = [
    "imageUrl": "image_url",
    "maskUrl": "mask_url",
    "guidanceScale": "guidance_scale",
    "numInferenceSteps": "num_inference_steps",
    "enableSafetyChecker": "enable_safety_checker",
    "outputFormat": "output_format",
    "syncMode": "sync_mode",
    "safetyTolerance": "safety_tolerance"
]

private func snakeToCamelCase(_ snakeKey: String) -> String {
    var result = ""
    result.reserveCapacity(snakeKey.count)

    var shouldCapitalizeNext = false
    for character in snakeKey {
        if character == "_" {
            shouldCapitalizeNext = true
            continue
        }

        if shouldCapitalizeNext {
            result.append(contentsOf: String(character).uppercased())
            shouldCapitalizeNext = false
        } else {
            result.append(character)
        }
    }

    return result
}

private func convertImageFileToDataURI(_ file: ImageModelV4File) throws -> String {
    switch file {
    case .url(let url, _):
        return url

    case let .file(mediaType, data, _):
        let base64: String
        switch data {
        case .base64(let string):
            base64 = string
        case .binary(let binary):
            base64 = binary.base64EncodedString()
        }

        return "data:\(mediaType);base64,\(base64)"
    }
}

private struct FalImageResponse: Decodable, Sendable {
    struct Image: Decodable, Sendable {
        let url: String
        let metadata: [String: JSONValue]
        let fields: [String: JSONValue]

        enum CodingKeys: String, CodingKey {
            case url, width, height
            case contentType = "content_type", fileName = "file_name", fileData = "file_data", fileSize = "file_size"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            url = try container.decode(String.self, forKey: .url)
            _ = try container.decodeIfPresent(Double.self, forKey: .width)
            _ = try container.decodeIfPresent(Double.self, forKey: .height)
            _ = try container.decodeIfPresent(Double.self, forKey: .fileSize)
            _ = try container.decodeIfPresent(String.self, forKey: .contentType)
            _ = try container.decodeIfPresent(String.self, forKey: .fileName)
            if container.contains(.fileData) { _ = try container.decode(String.self, forKey: .fileData) }
            let mapping: [CodingKeys: String] = [.width: "width", .height: "height", .contentType: "contentType",
                                                .fileName: "fileName", .fileData: "fileData", .fileSize: "fileSize"]
            var fields: [String: JSONValue] = ["url": .string(url)]
            var metadata: [String: JSONValue] = [:]
            for (key, name) in mapping where container.contains(key) {
                let value = try container.decode(JSONValue.self, forKey: key)
                fields[key.rawValue] = value
                metadata[name] = value
            }
            self.fields = fields
            self.metadata = metadata
        }
    }

    let images: [Image]
    let nsfwConcepts: [Bool]?
    let nsfwDetected: [Bool]?
    let additionalMetadata: [String: JSONValue]

    enum CodingKeys: String, CodingKey {
        case images, image, timings, seed, prompt
        case nsfwConcepts = "has_nsfw_concepts", nsfwDetected = "nsfw_content_detected"
        case inferenceSteps = "num_inference_steps", debugLatents = "debug_latents", debugPerPassLatents = "debug_per_pass_latents"
    }
    struct Timings: Decodable {
        let inference: Double?
        enum CodingKeys: String, CodingKey { case inference }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            inference = container.contains(.inference) ? try container.decode(Double.self, forKey: .inference) : nil
        }
    }
    struct LoraFile: Decodable {
        enum CodingKeys: String, CodingKey { case url, contentType = "content_type", fileName = "file_name", fileData = "file_data", fileSize = "file_size" }
        let fields: [String: JSONValue]
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            _ = try container.decode(String.self, forKey: .url)
            for key in [CodingKeys.contentType, .fileData] where container.contains(key) { _ = try container.decode(String.self, forKey: key) }
            _ = try container.decodeIfPresent(String.self, forKey: .fileName)
            _ = try container.decodeIfPresent(Double.self, forKey: .fileSize)
            fields = try Dictionary(uniqueKeysWithValues: container.allKeys.map { ($0.rawValue, try container.decode(JSONValue.self, forKey: $0)) })
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var root = try decoder.singleValueContainer().decode([String: JSONValue].self)
        if let array = try? container.decode([Image].self, forKey: .images) {
            images = array
        } else {
            let image = try container.decode(Image.self, forKey: .image)
            images = [image]
            root["image"] = .object(image.fields)
        }
        nsfwConcepts = container.contains(.nsfwConcepts) ? try container.decode([Bool].self, forKey: .nsfwConcepts) : nil
        nsfwDetected = container.contains(.nsfwDetected) ? try container.decode([Bool].self, forKey: .nsfwDetected) : nil
        for key in [CodingKeys.seed, .inferenceSteps] where container.contains(key) { _ = try container.decode(Double.self, forKey: key) }
        if container.contains(.prompt) { _ = try container.decode(String.self, forKey: .prompt) }
        if container.contains(.timings) {
            let timings = try container.decode(Timings.self, forKey: .timings)
            root["timings"] = .object(timings.inference.map { ["inference": .number($0)] } ?? [:])
        }
        for key in [CodingKeys.debugLatents, .debugPerPassLatents] where container.contains(key) {
            root[key.rawValue] = .object(try container.decode(LoraFile.self, forKey: key).fields)
        }
        for key in ["images", "prompt", "has_nsfw_concepts", "nsfw_content_detected"] { root.removeValue(forKey: key) }
        additionalMetadata = root
    }
}

private let falImageResponseSchema = FlexibleSchema(
    Schema<FalImageResponse>.codable(FalImageResponse.self, jsonSchema: .object(["type": .string("object")]))
)

private enum FalImageErrorData: Decodable, Sendable {
    case validation(FalImageValidationError)
    case http(FalImageHttpError)

    init(from decoder: Decoder) throws {
        if let value = try? FalImageValidationError(from: decoder) {
            self = .validation(value)
            return
        }

        if let value = try? FalImageHttpError(from: decoder) {
            self = .http(value)
            return
        }

        throw DecodingError.dataCorrupted(.init(
            codingPath: [],
            debugDescription: "Unsupported fal image error response"
        ))
    }
}

private struct FalImageValidationError: Decodable, Sendable {
    struct Detail: Decodable, Sendable {
        let loc: [String]
        let msg: String
        let type: String
    }

    let detail: [Detail]
}

private struct FalImageHttpError: Decodable, Sendable {
    let message: String
}

private let falImageErrorSchema = FlexibleSchema(
    Schema<FalImageErrorData>.codable(
        FalImageErrorData.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

private let falImageFailedResponseHandler: ResponseHandler<APICallError> = createJsonErrorResponseHandler(
    errorSchema: falImageErrorSchema,
    errorToMessage: { error in
        switch error {
        case .validation(let validation):
            return validation.detail
                .map { "\($0.loc.joined(separator: ".")): \($0.msg)" }
                .joined(separator: "\n")
        case .http(let http):
            return http.message
        }
    }
)
