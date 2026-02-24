import Foundation
import AISDKProvider
import AISDKProviderUtils
import GoogleProvider

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/google-vertex/src/google-vertex-image-model.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

struct GoogleVertexImageModelConfig: Sendable {
    let provider: String
    let baseURL: String
    let headers: @Sendable () throws -> [String: String?]
    let fetch: FetchFunction?
    let generateId: @Sendable () -> String
    let currentDate: @Sendable () -> Date

    init(
        provider: String,
        baseURL: String,
        headers: @escaping @Sendable () throws -> [String: String?],
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

private let googleVertexGeminiHTTPRegex: NSRegularExpression = {
    try! NSRegularExpression(
        pattern: "^https?:\\/\\/.*$",
        options: [.caseInsensitive]
    )
}()

private let googleVertexGeminiGCSRegex: NSRegularExpression = {
    try! NSRegularExpression(
        pattern: "^gs:\\/\\/.*$",
        options: [.caseInsensitive]
    )
}()

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

private enum GoogleVertexSampleImageSize: String, Sendable {
    case k1 = "1K"
    case k2 = "2K"
}

private enum GoogleVertexImageEditMode: String, Sendable {
    case inpaintInsertion = "EDIT_MODE_INPAINT_INSERTION"
    case inpaintRemoval = "EDIT_MODE_INPAINT_REMOVAL"
    case outpaint = "EDIT_MODE_OUTPAINT"
    case controlledEditing = "EDIT_MODE_CONTROLLED_EDITING"
    case productImage = "EDIT_MODE_PRODUCT_IMAGE"
    case backgroundSwap = "EDIT_MODE_BGSWAP"
}

private enum GoogleVertexImageMaskMode: String, Sendable {
    case `default` = "MASK_MODE_DEFAULT"
    case userProvided = "MASK_MODE_USER_PROVIDED"
    case detectionBox = "MASK_MODE_DETECTION_BOX"
    case clothingArea = "MASK_MODE_CLOTHING_AREA"
    case parsedPerson = "MASK_MODE_PARSED_PERSON"
}

private struct GoogleVertexImageEditProviderOptions: Sendable, Equatable {
    var baseSteps: Double?
    var mode: GoogleVertexImageEditMode?
    var maskMode: GoogleVertexImageMaskMode?
    var maskDilation: Double?
}

private struct GoogleVertexImageProviderOptions: Sendable, Equatable {
    var negativePrompt: String?
    var personGeneration: GoogleVertexPersonGeneration?
    var safetySetting: GoogleVertexSafetySetting?
    var addWatermark: Bool?
    var storageUri: String?
    var sampleImageSize: GoogleVertexSampleImageSize?
    var edit: GoogleVertexImageEditProviderOptions?
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

                if let sampleImageSize = dict["sampleImageSize"], sampleImageSize != .null {
                    guard case .string(let rawValue) = sampleImageSize,
                          let parsed = GoogleVertexSampleImageSize(rawValue: rawValue) else {
                        let error = SchemaValidationIssuesError(
                            vendor: "vertex",
                            issues: "sampleImageSize must be one of '1K', '2K'"
                        )
                        return .failure(error: TypeValidationError.wrap(value: sampleImageSize, cause: error))
                    }
                    options.sampleImageSize = parsed
                }

                if let editValue = dict["edit"], editValue != .null {
                    guard case .object(let editDict) = editValue else {
                        let error = SchemaValidationIssuesError(
                            vendor: "vertex",
                            issues: "edit must be an object"
                        )
                        return .failure(error: TypeValidationError.wrap(value: editValue, cause: error))
                    }

                    var editOptions = GoogleVertexImageEditProviderOptions()

                    if let baseStepsValue = editDict["baseSteps"], baseStepsValue != .null {
                        guard case .number(let number) = baseStepsValue else {
                            let error = SchemaValidationIssuesError(
                                vendor: "vertex",
                                issues: "edit.baseSteps must be a number"
                            )
                            return .failure(error: TypeValidationError.wrap(value: baseStepsValue, cause: error))
                        }
                        editOptions.baseSteps = number
                    }

                    if let modeValue = editDict["mode"], modeValue != .null {
                        guard case .string(let rawValue) = modeValue,
                              let parsed = GoogleVertexImageEditMode(rawValue: rawValue) else {
                            let error = SchemaValidationIssuesError(
                                vendor: "vertex",
                                issues: "edit.mode must be a valid enum value"
                            )
                            return .failure(error: TypeValidationError.wrap(value: modeValue, cause: error))
                        }
                        editOptions.mode = parsed
                    }

                    if let maskModeValue = editDict["maskMode"], maskModeValue != .null {
                        guard case .string(let rawValue) = maskModeValue,
                              let parsed = GoogleVertexImageMaskMode(rawValue: rawValue) else {
                            let error = SchemaValidationIssuesError(
                                vendor: "vertex",
                                issues: "edit.maskMode must be a valid enum value"
                            )
                            return .failure(error: TypeValidationError.wrap(value: maskModeValue, cause: error))
                        }
                        editOptions.maskMode = parsed
                    }

                    if let maskDilationValue = editDict["maskDilation"], maskDilationValue != .null {
                        guard case .number(let number) = maskDilationValue else {
                            let error = SchemaValidationIssuesError(
                                vendor: "vertex",
                                issues: "edit.maskDilation must be a number"
                            )
                            return .failure(error: TypeValidationError.wrap(value: maskDilationValue, cause: error))
                        }
                        editOptions.maskDilation = number
                    }

                    options.edit = editOptions
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

private func base64Data(from file: ImageModelV3File) throws -> String {
    switch file {
    case .url:
        throw InvalidArgumentError(
            argument: "files",
            message: "URL-based images are not supported for Google Vertex image editing. Please provide the image data directly."
        )
    case let .file(_, data, _):
        switch data {
        case .base64(let base64):
            return base64
        case .binary(let data):
            return convertDataToBase64(data)
        }
    }
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
    public var maxImagesPerCall: ImageModelV3MaxImagesPerCall {
        isGeminiModel(modelIdentifier.rawValue) ? .value(10) : .value(4)
    }

    private let modelIdentifier: GoogleVertexImageModelId
    private let config: GoogleVertexImageModelConfig

    init(modelId: GoogleVertexImageModelId, config: GoogleVertexImageModelConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public func doGenerate(options: ImageModelV3CallOptions) async throws -> ImageModelV3GenerateResult {
        if isGeminiModel(modelIdentifier.rawValue) {
            return try await doGenerateGemini(options: options)
        }
        return try await doGenerateImagen(options: options)
    }

    private func doGenerateImagen(options: ImageModelV3CallOptions) async throws -> ImageModelV3GenerateResult {
        var warnings: [SharedV3Warning] = []

        if options.size != nil {
            warnings.append(
                .unsupported(
                    feature: "size",
                    details: "This model does not support the `size` option. Use `aspectRatio` instead."
                    )
            )
        }

        let vertexOptions = try await parseProviderOptions(
            provider: "vertex",
            providerOptions: options.providerOptions,
            schema: googleVertexImageProviderOptionsSchema
        )

        let editOptions = vertexOptions?.edit
        let isEditMode = options.files?.isEmpty == false
        let files = options.files ?? []

        var parameters: [String: JSONValue] = ["sampleCount": .number(Double(options.n))]
        if let aspectRatio = options.aspectRatio { parameters["aspectRatio"] = .string(aspectRatio) }
        if let seed = options.seed { parameters["seed"] = .number(Double(seed)) }

        if let vertexOptions {
            if let negativePrompt = vertexOptions.negativePrompt { parameters["negativePrompt"] = .string(negativePrompt) }
            if let personGeneration = vertexOptions.personGeneration { parameters["personGeneration"] = .string(personGeneration.rawValue) }
            if let safetySetting = vertexOptions.safetySetting { parameters["safetySetting"] = .string(safetySetting.rawValue) }
            if let addWatermark = vertexOptions.addWatermark { parameters["addWatermark"] = .bool(addWatermark) }
            if let storageUri = vertexOptions.storageUri { parameters["storageUri"] = .string(storageUri) }
            if let sampleImageSize = vertexOptions.sampleImageSize { parameters["sampleImageSize"] = .string(sampleImageSize.rawValue) }
        }

        if isEditMode {
            parameters["editMode"] = .string(editOptions?.mode?.rawValue ?? GoogleVertexImageEditMode.inpaintInsertion.rawValue)
            if let baseSteps = editOptions?.baseSteps {
                parameters["editConfig"] = .object(["baseSteps": .number(baseSteps)])
            }
        }

        var instances: [JSONValue] = []
        if isEditMode {
            var referenceImages: [JSONValue] = []

            for (index, file) in files.enumerated() {
                referenceImages.append(
                    .object([
                        "referenceType": .string("REFERENCE_TYPE_RAW"),
                        "referenceId": .number(Double(index + 1)),
                        "referenceImage": .object([
                            "bytesBase64Encoded": .string(try base64Data(from: file))
                        ])
                    ])
                )
            }

            if let mask = options.mask {
                var maskConfig: [String: JSONValue] = [
                    "maskMode": .string(editOptions?.maskMode?.rawValue ?? GoogleVertexImageMaskMode.userProvided.rawValue)
                ]
                if let dilation = editOptions?.maskDilation {
                    maskConfig["dilation"] = .number(dilation)
                }

                referenceImages.append(
                    .object([
                        "referenceType": .string("REFERENCE_TYPE_MASK"),
                        "referenceId": .number(Double(files.count + 1)),
                        "referenceImage": .object([
                            "bytesBase64Encoded": .string(try base64Data(from: mask))
                        ]),
                        "maskImageConfig": .object(maskConfig)
                    ])
                )
            }

            var instance: [String: JSONValue] = [
                "referenceImages": .array(referenceImages)
            ]
            if let prompt = options.prompt {
                instance["prompt"] = .string(prompt)
            }
            instances = [.object(instance)]
        } else {
            var instance: [String: JSONValue] = [:]
            if let prompt = options.prompt {
                instance["prompt"] = .string(prompt)
            }
            instances = [.object(instance)]
        }

        let headers = combineHeaders(try config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 }

        let response = try await postJsonToAPI(
            url: "\(config.baseURL)/models/\(modelIdentifier.rawValue):predict",
            headers: headers,
            body: JSONValue.object(["instances": .array(instances), "parameters": .object(parameters)]),
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

        let mergedVertexOptions = mergeVertexLanguageModelOptions(
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
                supportedUrls: {
                    ["*": [googleVertexGeminiHTTPRegex, googleVertexGeminiGCSRegex]]
                }
            )
        )

        let result = try await languageModel.doGenerate(options: .init(
            prompt: languageModelPrompt,
            seed: options.seed,
            abortSignal: options.abortSignal,
            headers: options.headers,
            providerOptions: ["vertex": mergedVertexOptions]
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
                "vertex": ImageModelV3ProviderMetadataValue(images: metadataImages)
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

private func mergeVertexLanguageModelOptions(
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

    if let optionsObject = providerOptions?["vertex"] {
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
