import Foundation
import AISDKProvider
import AISDKProviderUtils

struct GoogleGenerativeAIImageModelConfig: Sendable {
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

private struct GoogleImagePrediction: Codable, Sendable {
    let bytesBase64Encoded: String
}

private struct GoogleImageResponse: Codable, Sendable {
    let predictions: [GoogleImagePrediction]
}

private let googleImageResponseSchema = FlexibleSchema(
    Schema.codable(
        GoogleImageResponse.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

final class GoogleGenerativeAIImageModel: ImageModelV3 {
    private let modelIdentifier: GoogleGenerativeAIImageModelId
    private let settings: GoogleGenerativeAIImageSettings
    private let config: GoogleGenerativeAIImageModelConfig

    init(
        modelId: GoogleGenerativeAIImageModelId,
        settings: GoogleGenerativeAIImageSettings,
        config: GoogleGenerativeAIImageModelConfig
    ) {
        self.modelIdentifier = modelId
        self.settings = settings
        self.config = config
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    public var maxImagesPerCall: ImageModelV3MaxImagesPerCall {
        if let maxImages = settings.maxImagesPerCall {
            return .value(maxImages)
        }
        return .value(4)
    }

    public func doGenerate(options: ImageModelV3CallOptions) async throws -> ImageModelV3GenerateResult {
        var warnings: [ImageModelV3CallWarning] = []

        // Default aspectRatio to '1:1' matching upstream
        let defaultAspectRatio = "1:1"

        if options.size != nil {
            warnings.append(
                .unsupportedSetting(
                    setting: "size",
                    details: "This model does not support the `size` option. Use `aspectRatio` instead."
                )
            )
        }

        if options.seed != nil {
            warnings.append(
                .unsupportedSetting(
                    setting: "seed",
                    details: "This model does not support the `seed` option through this provider."
                )
            )
        }

        let providerOptions = try await parseProviderOptions(
            provider: "google",
            providerOptions: options.providerOptions,
            schema: googleImageProviderOptionsSchema
        )

        var parameters: [String: JSONValue] = [
            "sampleCount": .number(Double(options.n))
        ]

        // Use aspectRatio with default '1:1' (ignore size completely)
        let aspectRatio = options.aspectRatio ?? defaultAspectRatio
        parameters["aspectRatio"] = .string(aspectRatio)

        // Allow providerOptions to override aspectRatio (Object.assign behavior)
        if let providerOptions {
            let dict = providerOptions.toDictionary()
            for (k, v) in dict {
                parameters[k] = v  // Overwrite any existing values including aspectRatio
            }
        }

        let headers = combineHeaders(config.headers(), options.headers?.mapValues { Optional($0) })
        let normalizedHeaders = headers.compactMapValues { $0 }

        let body = JSONValue.object([
            "instances": .array([.object(["prompt": .string(options.prompt)])]),
            "parameters": .object(parameters)
        ])

        let response = try await postJsonToAPI(
            url: "\(config.baseURL)/models/\(modelIdentifier.rawValue):predict",
            headers: normalizedHeaders,
            body: body,
            failedResponseHandler: googleFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: googleImageResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let timestamp = config.currentDate()

        let images = response.value.predictions.map { $0.bytesBase64Encoded }

        return ImageModelV3GenerateResult(
            images: .base64(images),
            warnings: warnings,
            providerMetadata: [
                "google": ImageModelV3ProviderMetadataValue(images: [])
            ],
            response: ImageModelV3ResponseInfo(
                timestamp: timestamp,
                modelId: modelIdentifier.rawValue,
                headers: response.responseHeaders
            )
        )
    }
}
