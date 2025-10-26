import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/google-vertex/src/google-vertex-image-model.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

struct GoogleVertexImageModelConfig: Sendable {
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

private enum GoogleVertexPersonGeneration: String, Sendable {
    case dontAllow = "dont_allow"
    case allowAdult = "allow_adult"
    case allowAll = "allow_all"
}

private enum GoogleVertexSafetySetting: String, Sendable {
    case blockLowAndAbove = "block_low_and_above"
    case blockMediumAndAbove = "block_medium_and_above"
    case blockOnlyHigh = "block_only_high"
    case blockNone = "block_none"
}

private struct GoogleVertexImageProviderOptions: Sendable, Equatable {
    var negativePrompt: String?
    var personGeneration: GoogleVertexPersonGeneration?
    var safetySetting: GoogleVertexSafetySetting?
    var addWatermark: Bool?
    var storageUri: String?
}

private let googleVertexImageProviderOptionsSchema = FlexibleSchema(
    Schema<GoogleVertexImageProviderOptions>(
        jsonSchemaResolver: {
            .object([
                "type": .string("object"),
                "additionalProperties": .bool(true)
            ])
        },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(
                        vendor: "vertex",
                        issues: "provider options must be an object"
                    )
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                var options = GoogleVertexImageProviderOptions()

                if let negativePrompt = dict["negativePrompt"], negativePrompt != .null {
                    guard case .string(let stringValue) = negativePrompt else {
                        let error = SchemaValidationIssuesError(
                            vendor: "vertex",
                            issues: "negativePrompt must be a string"
                        )
                        return .failure(error: TypeValidationError.wrap(value: negativePrompt, cause: error))
                    }
                    options.negativePrompt = stringValue
                }

                if let personGeneration = dict["personGeneration"], personGeneration != .null {
                    guard case .string(let rawValue) = personGeneration,
                          let parsed = GoogleVertexPersonGeneration(rawValue: rawValue) else {
                        let error = SchemaValidationIssuesError(
                            vendor: "vertex",
                            issues: "personGeneration must be one of 'dont_allow', 'allow_adult', 'allow_all'"
                        )
                        return .failure(error: TypeValidationError.wrap(value: personGeneration, cause: error))
                    }
                    options.personGeneration = parsed
                }

                if let safetySetting = dict["safetySetting"], safetySetting != .null {
                    guard case .string(let rawValue) = safetySetting,
                          let parsed = GoogleVertexSafetySetting(rawValue: rawValue) else {
                        let error = SchemaValidationIssuesError(
                            vendor: "vertex",
                            issues: "safetySetting must be one of 'block_low_and_above', 'block_medium_and_above', 'block_only_high', 'block_none'"
                        )
                        return .failure(error: TypeValidationError.wrap(value: safetySetting, cause: error))
                    }
                    options.safetySetting = parsed
                }

                if let addWatermark = dict["addWatermark"], addWatermark != .null {
                    guard case .bool(let boolValue) = addWatermark else {
                        let error = SchemaValidationIssuesError(
                            vendor: "vertex",
                            issues: "addWatermark must be a boolean"
                        )
                        return .failure(error: TypeValidationError.wrap(value: addWatermark, cause: error))
                    }
                    options.addWatermark = boolValue
                }

                if let storageUri = dict["storageUri"], storageUri != .null {
                    guard case .string(let stringValue) = storageUri else {
                        let error = SchemaValidationIssuesError(
                            vendor: "vertex",
                            issues: "storageUri must be a string"
                        )
                        return .failure(error: TypeValidationError.wrap(value: storageUri, cause: error))
                    }
                    options.storageUri = stringValue
                }

                return .success(value: options)
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)

private struct GoogleVertexImagePrediction: Codable, Sendable {
    let bytesBase64Encoded: String
    let mimeType: String?
    let prompt: String?
}

private struct GoogleVertexImageResponse: Codable, Sendable {
    let predictions: [GoogleVertexImagePrediction]?
}

private let googleVertexImageResponseSchema = FlexibleSchema(
    Schema.codable(
        GoogleVertexImageResponse.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

public final class GoogleVertexImageModel: ImageModelV3 {
    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }
    public var maxImagesPerCall: ImageModelV3MaxImagesPerCall { .value(4) }

    private let modelIdentifier: GoogleVertexImageModelId
    private let config: GoogleVertexImageModelConfig

    init(modelId: GoogleVertexImageModelId, config: GoogleVertexImageModelConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public func doGenerate(options: ImageModelV3CallOptions) async throws -> ImageModelV3GenerateResult {
        var warnings: [ImageModelV3CallWarning] = []

        if options.size != nil {
            warnings.append(
                .unsupportedSetting(
                    setting: "size",
                    details: "This model does not support the `size` option. Use `aspectRatio` instead."
                )
            )
        }

        let vertexOptions = try await parseProviderOptions(
            provider: "vertex",
            providerOptions: options.providerOptions,
            schema: googleVertexImageProviderOptionsSchema
        )

        var parameters: [String: JSONValue] = [
            "sampleCount": .number(Double(options.n))
        ]

        if let aspectRatio = options.aspectRatio {
            parameters["aspectRatio"] = .string(aspectRatio)
        }

        if let seed = options.seed {
            parameters["seed"] = .number(Double(seed))
        }

        if let vertexOptions {
            if let negativePrompt = vertexOptions.negativePrompt {
                parameters["negativePrompt"] = .string(negativePrompt)
            }

            if let personGeneration = vertexOptions.personGeneration {
                parameters["personGeneration"] = .string(personGeneration.rawValue)
            }

            if let safetySetting = vertexOptions.safetySetting {
                parameters["safetySetting"] = .string(safetySetting.rawValue)
            }

            if let addWatermark = vertexOptions.addWatermark {
                parameters["addWatermark"] = .bool(addWatermark)
            }

            if let storageUri = vertexOptions.storageUri {
                parameters["storageUri"] = .string(storageUri)
            }
        }

        let headers = combineHeaders(config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 }

        let response = try await postJsonToAPI(
            url: "\(config.baseURL)/models/\(modelIdentifier.rawValue):predict",
            headers: headers,
            body: JSONValue.object([
                "instances": .array([.object(["prompt": .string(options.prompt)])]),
                "parameters": .object(parameters)
            ]),
            failedResponseHandler: googleVertexFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: googleVertexImageResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let timestamp = config.currentDate()
        let predictions = response.value.predictions ?? []

        let images = predictions.map { $0.bytesBase64Encoded }

        let imageMetadata: [JSONValue] = predictions.map { prediction in
            var metadata: [String: JSONValue] = [:]
            if let revisedPrompt = prediction.prompt {
                metadata["revisedPrompt"] = .string(revisedPrompt)
            }
            return JSONValue.object(metadata)
        }

        let providerMetadata: ImageModelV3ProviderMetadata = [
            "vertex": ImageModelV3ProviderMetadataValue(images: imageMetadata)
        ]

        return ImageModelV3GenerateResult(
            images: .base64(images),
            warnings: warnings,
            providerMetadata: providerMetadata,
            response: ImageModelV3ResponseInfo(
                timestamp: timestamp,
                modelId: modelIdentifier.rawValue,
                headers: response.responseHeaders
            )
        )
    }
}
