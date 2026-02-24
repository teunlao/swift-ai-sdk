import Foundation
import AISDKProvider
import AISDKProviderUtils

struct GoogleGenerativeAIImageModelConfig: Sendable {
    let provider: String
    let baseURL: String
    let headers: @Sendable () -> [String: String?]
    let fetch: FetchFunction?
    let generateId: @Sendable () -> String
    let currentDate: @Sendable () -> Date

    init(
        provider: String,
        baseURL: String,
        headers: @escaping @Sendable () -> [String: String?],
        fetch: FetchFunction?,
        generateId: @escaping @Sendable () -> String = generateID,
        currentDate: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.provider = provider
        self.baseURL = baseURL
        self.headers = headers
        self.fetch = fetch
        self.generateId = generateId
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
        if isGeminiModel(modelIdentifier.rawValue) {
            return .value(10)
        }
        return .value(4)
    }

    public func doGenerate(options: ImageModelV3CallOptions) async throws -> ImageModelV3GenerateResult {
        if isGeminiModel(modelIdentifier.rawValue) {
            return try await doGenerateGemini(options: options)
        }
        return try await doGenerateImagen(options: options)
    }

    private func doGenerateImagen(options: ImageModelV3CallOptions) async throws -> ImageModelV3GenerateResult {
        var warnings: [SharedV3Warning] = []

        // Default aspectRatio to '1:1' matching upstream
        let defaultAspectRatio = "1:1"

        if let files = options.files, !files.isEmpty {
            throw UnsupportedFunctionalityError(
                functionality: "image editing",
                message: "Google Generative AI does not support image editing with Imagen models. Use Google Vertex AI (@ai-sdk/google-vertex) for image editing capabilities."
            )
        }

        if options.mask != nil {
            throw UnsupportedFunctionalityError(
                functionality: "image editing with masks",
                message: "Google Generative AI does not support image editing with masks. Use Google Vertex AI (@ai-sdk/google-vertex) for image editing capabilities."
            )
        }

        if options.size != nil {
            warnings.append(
                .unsupported(
                    feature: "size",
                    details: "This model does not support the `size` option. Use `aspectRatio` instead."
                )
            )
        }

        if options.seed != nil {
            warnings.append(
                .unsupported(
                    feature: "seed",
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

        var instance: [String: JSONValue] = [:]
        if let prompt = options.prompt {
            instance["prompt"] = .string(prompt)
        }
        let body = JSONValue.object([
            "instances": .array([.object(instance)]),
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
        let metadataImages = response.value.predictions.map { _ in JSONValue.object([:]) }
        let providerMetadata: ImageModelV3ProviderMetadata = [
            "google": ImageModelV3ProviderMetadataValue(images: metadataImages)
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

    private func doGenerateGemini(options: ImageModelV3CallOptions) async throws -> ImageModelV3GenerateResult {
        var warnings: [SharedV3Warning] = []

        if options.mask != nil {
            throw InvalidArgumentError(
                argument: "mask",
                message: "Gemini image models do not support mask-based image editing."
            )
        }

        if options.n > 1 {
            throw InvalidArgumentError(
                argument: "n",
                message: "Gemini image models do not support generating a set number of images per call. Use n=1 or omit the n parameter."
            )
        }

        if options.size != nil {
            warnings.append(
                .unsupported(
                    feature: "size",
                    details: "This model does not support the `size` option. Use `aspectRatio` instead."
                )
            )
        }

        var userContent: [LanguageModelV3UserMessagePart] = []

        if let prompt = options.prompt {
            userContent.append(.text(.init(text: prompt)))
        }

        if let files = options.files, !files.isEmpty {
            for file in files {
                switch file {
                case .url(let url, _):
                    guard let parsedURL = parseAbsoluteURL(url) else {
                        throw InvalidArgumentError(
                            argument: "files",
                            message: "Invalid file URL: \(url)"
                        )
                    }
                    userContent.append(
                        .file(
                            .init(
                                data: .url(parsedURL),
                                mediaType: "image/*"
                            )
                        )
                    )

                case let .file(mediaType, data, _):
                    let contentData: LanguageModelV3DataContent
                    switch data {
                    case .base64(let base64):
                        contentData = .base64(base64)
                    case .binary(let binary):
                        contentData = .data(binary)
                    }

                    userContent.append(
                        .file(
                            .init(
                                data: contentData,
                                mediaType: mediaType
                            )
                        )
                    )
                }
            }
        }

        let languageModelPrompt: LanguageModelV3Prompt = [
            .user(content: userContent, providerOptions: nil)
        ]

        let mergedGoogleOptions = mergeGoogleLanguageModelOptions(
            providerOptions: options.providerOptions,
            aspectRatio: options.aspectRatio
        )

        let languageModel = GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: modelIdentifier.rawValue),
            config: .init(
                provider: config.provider,
                baseURL: config.baseURL,
                headers: config.headers,
                fetch: config.fetch,
                generateId: config.generateId,
                supportedUrls: { [:] }
            )
        )

        let result = try await languageModel.doGenerate(options: .init(
            prompt: languageModelPrompt,
            seed: options.seed,
            abortSignal: options.abortSignal,
            headers: options.headers,
            providerOptions: ["google": mergedGoogleOptions]
        ))

        var images: [String] = []
        for content in result.content {
            guard case let .file(file) = content, file.mediaType.hasPrefix("image/") else {
                continue
            }

            switch file.data {
            case .base64(let base64):
                images.append(convertToBase64(.string(base64)))
            case .binary(let binary):
                images.append(convertToBase64(.data(binary)))
            }
        }

        let metadataImages = images.map { _ in JSONValue.object([:]) }
        let hasUsage = result.usage.inputTokens.total != nil || result.usage.outputTokens.total != nil || result.usage.raw != nil
        let usage = hasUsage
            ? ImageModelV3Usage(
                inputTokens: result.usage.inputTokens.total,
                outputTokens: result.usage.outputTokens.total,
                totalTokens: (result.usage.inputTokens.total ?? 0) + (result.usage.outputTokens.total ?? 0)
            )
            : nil

        return ImageModelV3GenerateResult(
            images: .base64(images),
            warnings: warnings,
            providerMetadata: [
                "google": ImageModelV3ProviderMetadataValue(images: metadataImages)
            ],
            response: ImageModelV3ResponseInfo(
                timestamp: config.currentDate(),
                modelId: modelIdentifier.rawValue,
                headers: result.response?.headers
            ),
            usage: usage
        )
    }
}

private func isGeminiModel(_ modelId: String) -> Bool {
    modelId.hasPrefix("gemini-")
}

private func mergeGoogleLanguageModelOptions(
    providerOptions: SharedV3ProviderOptions?,
    aspectRatio: String?
) -> [String: JSONValue] {
    var merged: [String: JSONValue] = [
        "responseModalities": .array([.string(GoogleGenerativeAIResponseModality.image.rawValue)])
    ]

    if let aspectRatio {
        merged["imageConfig"] = .object([
            "aspectRatio": .string(aspectRatio)
        ])
    }

    if let optionsObject = providerOptions?["google"] {
        for (key, value) in optionsObject {
            merged[key] = value
        }
    }

    return merged
}

private func parseAbsoluteURL(_ rawValue: String) -> URL? {
    guard let url = URL(string: rawValue), url.scheme != nil else {
        return nil
    }
    return url
}
