import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/togetherai/src/togetherai-image-model.ts
// Upstream commit: f3a72bc2a
//===----------------------------------------------------------------------===//

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
                        guard case .number = steps else {
                            let error = SchemaValidationIssuesError(
                                vendor: "togetherai",
                                issues: "steps must be a number"
                            )
                            return .failure(error: TypeValidationError.wrap(value: steps, cause: error))
                        }
                    }

                    if let guidance = dict["guidance"], guidance != .null {
                        guard case .number = guidance else {
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

public final class TogetherAIImageModel: ImageModelV3 {
    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }
    public var maxImagesPerCall: ImageModelV3MaxImagesPerCall { .value(1) }

    private let modelIdentifier: TogetherAIImageModelId
    private let config: TogetherAIImageModelConfig

    init(modelId: TogetherAIImageModelId, config: TogetherAIImageModelConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public func doGenerate(options: ImageModelV3CallOptions) async throws -> ImageModelV3GenerateResult {
        var warnings: [SharedV3Warning] = []

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

        let togetheraiOptions = try await parseProviderOptions(
            provider: "togetherai",
            providerOptions: options.providerOptions,
            schema: togetheraiImageProviderOptionsSchema
        )

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

        if let seed = options.seed {
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

        return ImageModelV3GenerateResult(
            images: .base64(images),
            warnings: warnings,
            providerMetadata: nil,
            response: ImageModelV3ResponseInfo(
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

private func convertImageFileToDataURI(_ file: ImageModelV3File) throws -> String {
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

