import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/fal/src/fal-image-model.ts
// Upstream commit: f3a72bc2a0433fda9506b7c7ac1b28b4adafcfc9
//===----------------------------------------------------------------------===//

struct FalImageModelConfig: Sendable {
    let provider: String
    let baseURL: String
    let headers: @Sendable () -> [String: String?]
    let fetch: FetchFunction?
    let currentDate: @Sendable () -> Date

    init(
        provider: String,
        baseURL: String,
        headers: @escaping @Sendable () -> [String: String?],
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

public final class FalImageModel: ImageModelV3 {
    public var specificationVersion: String { "v3" }
    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }
    public var maxImagesPerCall: ImageModelV3MaxImagesPerCall { .value(1) }

    private let modelIdentifier: FalImageModelId
    private let config: FalImageModelConfig

    init(modelId: FalImageModelId, config: FalImageModelConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public func doGenerate(options: ImageModelV3CallOptions) async throws -> ImageModelV3GenerateResult {
        let prepared = try await prepareRequest(options: options)

        let headers = combineHeaders(
            config.headers(),
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

        let parsed = try FalImageResponse.parse(from: response.value)

        var imagesData: [Data] = []
        imagesData.reserveCapacity(parsed.images.count)

        for image in parsed.images {
            let result = try await getFromAPI(
                url: image.url,
                headers: nil,
                failedResponseHandler: createStatusCodeErrorResponseHandler(),
                successfulResponseHandler: createBinaryResponseHandler(),
                isAborted: options.abortSignal,
                fetch: config.fetch
            )
            imagesData.append(result.value)
        }

        let imageMetadata: [JSONValue] = parsed.images.enumerated().map { index, image in
            var metadata = image.metadata
            if let nsfw = image.nsfw {
                metadata["nsfw"] = .bool(nsfw)
            }
            return .object(metadata)
        }

        let additionalMetadata = parsed.additionalMetadata.isEmpty ? nil : JSONValue.object(parsed.additionalMetadata)

        return ImageModelV3GenerateResult(
            images: .binary(imagesData),
            warnings: prepared.warnings,
            providerMetadata: [
                "fal": ImageModelV3ProviderMetadataValue(
                    images: imageMetadata,
                    additionalData: additionalMetadata
                )
            ],
            response: ImageModelV3ResponseInfo(
                timestamp: now,
                modelId: modelIdentifier.rawValue,
                headers: response.responseHeaders
            )
        )
    }

    private struct PreparedRequest: Sendable {
        let body: [String: JSONValue]
        let warnings: [SharedV3Warning]
    }

    private func prepareRequest(options: ImageModelV3CallOptions) async throws -> PreparedRequest {
        var warnings: [SharedV3Warning] = []
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
            schema: falImageProviderOptionsSchema
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
                if key == "useMultipleImages" { continue }
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
        let parts = size.split(separator: "x", omittingEmptySubsequences: true)
        if parts.count == 2, let width = Int(parts[0]), let height = Int(parts[1]) {
            return .object([
                "width": .number(Double(width)),
                "height": .number(Double(height))
            ])
        }
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

private func convertImageFileToDataURI(_ file: ImageModelV3File) throws -> String {
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

private struct FalImageResponse {
    struct Image {
        let url: String
        let metadata: [String: JSONValue]
        let nsfw: Bool?
    }

    let images: [Image]
    let additionalMetadata: [String: JSONValue]

    static func parse(from value: JSONValue) throws -> FalImageResponse {
        guard case .object(var root) = value else {
            throw APICallError(message: "Invalid fal image response", url: "", requestBodyValues: nil)
        }

        var imagesValue: [JSONValue] = []
        if let imagesJSON = root.removeValue(forKey: "images"), case .array(let array) = imagesJSON {
            imagesValue = array
        } else if let imageJSON = root.removeValue(forKey: "image"), case .object = imageJSON {
            imagesValue = [imageJSON]
        }

        guard !imagesValue.isEmpty else {
            throw APICallError(message: "fal image response missing images", url: "", requestBodyValues: nil)
        }

        let nsfwConcepts = extractBoolArray(root.removeValue(forKey: "has_nsfw_concepts"))
        let nsfwDetected = extractBoolArray(root.removeValue(forKey: "nsfw_content_detected"))
        _ = root.removeValue(forKey: "prompt")

        var images: [Image] = []
        images.reserveCapacity(imagesValue.count)

        for (index, imageJSON) in imagesValue.enumerated() {
            guard case .object(var imageDict) = imageJSON, let urlValue = imageDict.removeValue(forKey: "url"), case .string(let url) = urlValue else {
                throw APICallError(message: "fal image entry missing url", url: "", requestBodyValues: nil)
            }

            let contentType = imageDict.removeValue(forKey: "content_type")
            let fileName = imageDict.removeValue(forKey: "file_name")
            let fileData = imageDict.removeValue(forKey: "file_data")
            let fileSize = imageDict.removeValue(forKey: "file_size")

            var metadata = imageDict
            if let contentType { metadata["contentType"] = contentType }
            if let fileName { metadata["fileName"] = fileName }
            if let fileData { metadata["fileData"] = fileData }
            if let fileSize { metadata["fileSize"] = fileSize }

            let nsfw = nsfwConcepts?[index] ?? nsfwDetected?[index]

            images.append(Image(url: url, metadata: metadata, nsfw: nsfw))
        }

        let additionalMetadata = root

        return FalImageResponse(images: images, additionalMetadata: additionalMetadata)
    }

    private static func extractBoolArray(_ value: JSONValue?) -> [Bool]? {
        guard let value, case .array(let array) = value else {
            return nil
        }
        var result: [Bool] = []
        result.reserveCapacity(array.count)
        for entry in array {
            guard case .bool(let flag) = entry else { return nil }
            result.append(flag)
        }
        return result
    }
}

private let falImageResponseSchema = FlexibleSchema(
    Schema<JSONValue>.codable(
        JSONValue.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

private enum FalImageErrorData: Decodable, Sendable {
    case validation(FalImageValidationError)
    case fal(FalErrorPayload)
    case http(FalImageHttpError)

    init(from decoder: Decoder) throws {
        if let value = try? FalImageValidationError(from: decoder) {
            self = .validation(value)
            return
        }

        if let value = try? FalErrorPayload(from: decoder) {
            self = .fal(value)
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
        case .fal(let fal):
            return fal.error.message
        case .http(let http):
            return http.message
        }
    }
)
