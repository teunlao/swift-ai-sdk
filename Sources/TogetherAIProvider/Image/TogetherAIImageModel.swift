import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/togetherai/src/togetherai-image-model.ts
// Upstream commit: f3a72bc2a
//===----------------------------------------------------------------------===//

public struct TogetherAIImageModelOptions: Codable, Sendable, Equatable {
    public var steps: Double?
    public var guidance: Double?
    public var negative_prompt: String?
    public var disable_safety_checker: Bool?
    public init(steps: Double? = nil, guidance: Double? = nil, negative_prompt: String? = nil, disable_safety_checker: Bool? = nil) {
        self.steps = steps; self.guidance = guidance
        self.negative_prompt = negative_prompt; self.disable_safety_checker = disable_safety_checker
    }
}

struct TogetherAIImageModelConfig: Sendable {
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

private struct TogetherAIImageResponse: Codable, Sendable {
    struct Item: Codable, Sendable {
        let b64JSON: String

        private enum CodingKeys: String, CodingKey {
            case b64JSON = "b64_json"
        }
    }

    let data: [Item]
}

private let togetherAIImageResponseSchema = FlexibleSchema(
    Schema.codable(
        TogetherAIImageResponse.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

private struct TogetherAIErrorEnvelope: Codable, Sendable {
    struct ErrorInfo: Codable, Sendable {
        let message: String
    }

    let error: ErrorInfo
}

private let togetherAIErrorSchema = FlexibleSchema(
    Schema.codable(
        TogetherAIErrorEnvelope.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

private let togetheraiImageProviderOptionsSchema: FlexibleSchema<[String: JSONValue]> = {
    let schemaJSON: JSONValue = .object([
        "type": .string("object"),
        "additionalProperties": .bool(true),
    ])

    return FlexibleSchema(
        Schema<[String: JSONValue]>(
            jsonSchemaResolver: { schemaJSON },
            validator: { value in
                do {
                    let json = try jsonValue(from: value)
                    guard case .object(let dict) = json else {
                        let error = SchemaValidationIssuesError(
                            vendor: "togetherai",
                            issues: "provider options must be an object"
                        )
                        return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                    }

                    if let steps = dict["steps"], steps != .null {
                        guard case .number(let number) = steps, number.isFinite else {
                            let error = SchemaValidationIssuesError(
                                vendor: "togetherai",
                                issues: "steps must be a number"
                            )
                            return .failure(error: TypeValidationError.wrap(value: steps, cause: error))
                        }
                    }

                    if let guidance = dict["guidance"], guidance != .null {
                        guard case .number(let number) = guidance, number.isFinite else {
                            let error = SchemaValidationIssuesError(
                                vendor: "togetherai",
                                issues: "guidance must be a number"
                            )
                            return .failure(error: TypeValidationError.wrap(value: guidance, cause: error))
                        }
                    }

                    if let negativePrompt = dict["negative_prompt"], negativePrompt != .null {
                        guard case .string = negativePrompt else {
                            let error = SchemaValidationIssuesError(
                                vendor: "togetherai",
                                issues: "negative_prompt must be a string"
                            )
                            return .failure(error: TypeValidationError.wrap(value: negativePrompt, cause: error))
                        }
                    }

                    if let disableSafetyChecker = dict["disable_safety_checker"], disableSafetyChecker != .null {
                        guard case .bool = disableSafetyChecker else {
                            let error = SchemaValidationIssuesError(
                                vendor: "togetherai",
                                issues: "disable_safety_checker must be a boolean"
                            )
                            return .failure(error: TypeValidationError.wrap(value: disableSafetyChecker, cause: error))
                        }
                    }

                    return .success(value: dict)
                } catch {
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }
            }
        )
    )
}()

public final class TogetherAIImageModel: ImageModelV4 {
    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }
    public var maxImagesPerCall: ImageModelV4MaxImagesPerCall { .value(1) }
    public var supportsFileInputs: Bool? {
        get async throws {
            if ["black-forest-labs/FLUX.1-kontext-pro", "black-forest-labs/FLUX.1-kontext-max", "black-forest-labs/FLUX.1-kontext-dev",
                "black-forest-labs/FLUX.1-canny", "black-forest-labs/FLUX.1-depth", "black-forest-labs/FLUX.1-redux",
                "black-forest-labs/FLUX.2-pro", "black-forest-labs/FLUX.2-flex"].contains(modelId) { return true }
            return ["stabilityai/stable-diffusion-xl-base-1.0", "black-forest-labs/FLUX.1-dev", "black-forest-labs/FLUX.1-dev-lora",
                    "black-forest-labs/FLUX.1-schnell", "black-forest-labs/FLUX.1.1-pro", "black-forest-labs/FLUX.1-pro",
                    "black-forest-labs/FLUX.1-schnell-Free", "black-forest-labs/FLUX.2-dev", "google/gemini-3-pro-image"].contains(modelId) ? false : nil
        }
    }
    public var supportsMaskInputs: Bool? { get async throws { try await supportsFileInputs == nil ? nil : false } }

    private let modelIdentifier: TogetherAIImageModelId
    private let config: TogetherAIImageModelConfig

    init(modelId: TogetherAIImageModelId, config: TogetherAIImageModelConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public func doGenerate(options: ImageModelV4CallOptions) async throws -> ImageModelV4GenerateResult {
        var warnings: [SharedV4Warning] = []

        if options.mask != nil {
            throw UnsupportedFunctionalityError(
                functionality: "mask-based image editing",
                message: "Together AI does not support mask-based image editing. " +
                    "Use FLUX Kontext models (e.g., black-forest-labs/FLUX.1-kontext-pro) " +
                    "with a reference image and descriptive prompt instead."
            )
        }

        // NOTE: Matches upstream implementation (which checks `size`).
        if options.size != nil {
            warnings.append(
                .unsupported(
                    feature: "aspectRatio",
                    details: "This model does not support the `aspectRatio` option. Use `size` instead."
                )
            )
        }

        var togetheraiOptions = try await parseProviderOptions(
            provider: "togetherai",
            providerOptions: options.providerOptions,
            schema: togetheraiImageProviderOptionsSchema
        )

        let nonDiffusion = modelId == "google/gemini-3-pro-image"
        if nonDiffusion {
            for key in ["steps", "guidance", "negative_prompt", "disable_safety_checker"] { togetheraiOptions?.removeValue(forKey: key) }
            if options.seed != nil { warnings.append(.unsupported(feature: "seed", details: "The \(modelId) model does not support the `seed` option.")) }
        }

        // Handle image input from files
        var imageURL: String?
        if let files = options.files, let first = files.first {
            imageURL = try convertImageFileToDataURI(first)

            if files.count > 1 {
                warnings.append(
                    .other(
                        message: "Together AI only supports a single input image. Additional images are ignored."
                    )
                )
            }
        }

        var body: [String: JSONValue] = [
            "model": .string(modelIdentifier.rawValue),
            "response_format": .string("base64"),
        ]

        if let prompt = options.prompt {
            body["prompt"] = .string(prompt)
        }

        if let seed = options.seed, !nonDiffusion {
            body["seed"] = .number(Double(seed))
        }

        if options.n > 1 {
            body["n"] = .number(Double(options.n))
        }

        if let size = options.size, let (width, height) = parseSize(size) {
            body["width"] = .number(Double(width))
            body["height"] = .number(Double(height))
        }

        if let imageURL {
            body["image_url"] = .string(imageURL)
        }

        if let togetheraiOptions {
            for (key, value) in togetheraiOptions {
                body[key] = value
            }
        }

        let combinedHeaders = combineHeaders(
            config.headers(),
            options.headers?.mapValues { Optional($0) }
        ).compactMapValues { $0 }

        let response = try await postJsonToAPI(
            url: "\(config.baseURL)/images/generations",
            headers: combinedHeaders,
            body: JSONValue.object(body),
            failedResponseHandler: createJsonErrorResponseHandler(
                errorSchema: togetherAIErrorSchema,
                errorToMessage: { $0.error.message }
            ),
            successfulResponseHandler: createJsonResponseHandler(responseSchema: togetherAIImageResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let images = response.value.data.map { $0.b64JSON }

        return ImageModelV4GenerateResult(
            images: .base64(images),
            warnings: warnings,
            providerMetadata: nil,
            response: ImageModelV4ResponseInfo(
                timestamp: config.currentDate(),
                modelId: modelIdentifier.rawValue,
                headers: response.responseHeaders
            )
        )
    }
}

private func parseSize(_ size: String) -> (width: Int, height: Int)? {
    let parts = size.split(separator: "x", maxSplits: 1).map(String.init)
    guard parts.count == 2, let width = Int(parts[0]), let height = Int(parts[1]) else {
        return nil
    }
    return (width, height)
}

private func convertImageFileToDataURI(_ file: ImageModelV4File) throws -> String {
    switch file {
    case .url(let url, _):
        return url

    case let .file(mediaType, data, _):
        let base64: String
        switch data {
        case .base64(let value):
            base64 = value
        case .binary(let value):
            base64 = value.base64EncodedString()
        }
        return "data:\(mediaType);base64,\(base64)"
    }
}

