import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/amazon-bedrock/src/bedrock-image-model.ts
// Upstream commit: 73d5c5920
//===----------------------------------------------------------------------===//

struct BedrockImageModelConfig: Sendable {
    let baseURL: @Sendable () -> String
    let headers: @Sendable () -> [String: String?]
    let fetch: FetchFunction?
    let currentDate: @Sendable () -> Date
}

private let bedrockImageResponseSchema = FlexibleSchema(
    Schema<JSONValue>.codable(
        JSONValue.self,
        jsonSchema: .object([
            "type": .string("object")
        ])
    )
)

private struct BedrockImageModelError: LocalizedError, Sendable {
    let message: String

    var errorDescription: String? { message }
}

public final class BedrockImageModel: ImageModelV3 {
    private let modelIdentifier: BedrockImageModelId
    private let config: BedrockImageModelConfig

    init(modelId: BedrockImageModelId, config: BedrockImageModelConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var specificationVersion: String { "v3" }
    public var provider: String { "amazon-bedrock" }
    public var modelId: String { modelIdentifier.rawValue }

    public var maxImagesPerCall: ImageModelV3MaxImagesPerCall {
        .value(bedrockModelMaxImagesPerCall[modelIdentifier] ?? 1)
    }

    public func doGenerate(options: ImageModelV3CallOptions) async throws -> ImageModelV3GenerateResult {
        var warnings: [SharedV3Warning] = []

        if options.aspectRatio != nil {
            warnings.append(.unsupported(
                feature: "aspectRatio",
                details: "This model does not support aspect ratio. Use `size` instead."
            ))
        }

        let overrides: [String: JSONValue] = options.providerOptions?["bedrock"] ?? [:]
        let imageGenerationConfig = buildImageGenerationConfig(options: options, overrides: overrides)

        let args: JSONValue
        if let files = options.files, !files.isEmpty {
            let hasMask = options.mask != nil
            let maskPrompt = stringValue(overrides["maskPrompt"])
            let hasMaskPrompt = maskPrompt != nil

            let taskType = stringValue(overrides["taskType"])
                ?? ((hasMask || hasMaskPrompt) ? "INPAINTING" : "IMAGE_VARIATION")

            let sourceImageBase64 = try getBase64Data(files[0])

            switch taskType {
            case "INPAINTING":
                var inPaintingParams: [String: JSONValue] = [
                    "image": .string(sourceImageBase64)
                ]

                if let prompt = options.prompt, !prompt.isEmpty {
                    inPaintingParams["text"] = .string(prompt)
                }
                if let negativeText = nonEmptyString(overrides["negativeText"]) {
                    inPaintingParams["negativeText"] = .string(negativeText)
                }

                if let mask = options.mask {
                    inPaintingParams["maskImage"] = .string(try getBase64Data(mask))
                } else if let maskPrompt {
                    inPaintingParams["maskPrompt"] = .string(maskPrompt)
                }

                args = .object([
                    "taskType": .string("INPAINTING"),
                    "inPaintingParams": .object(inPaintingParams),
                    "imageGenerationConfig": .object(imageGenerationConfig),
                ])

            case "OUTPAINTING":
                var outPaintingParams: [String: JSONValue] = [
                    "image": .string(sourceImageBase64)
                ]

                if let prompt = options.prompt, !prompt.isEmpty {
                    outPaintingParams["text"] = .string(prompt)
                }
                if let negativeText = nonEmptyString(overrides["negativeText"]) {
                    outPaintingParams["negativeText"] = .string(negativeText)
                }
                if let outPaintingMode = nonEmptyString(overrides["outPaintingMode"]) {
                    outPaintingParams["outPaintingMode"] = .string(outPaintingMode)
                }

                if let mask = options.mask {
                    outPaintingParams["maskImage"] = .string(try getBase64Data(mask))
                } else if let maskPrompt {
                    outPaintingParams["maskPrompt"] = .string(maskPrompt)
                }

                args = .object([
                    "taskType": .string("OUTPAINTING"),
                    "outPaintingParams": .object(outPaintingParams),
                    "imageGenerationConfig": .object(imageGenerationConfig),
                ])

            case "BACKGROUND_REMOVAL":
                args = .object([
                    "taskType": .string("BACKGROUND_REMOVAL"),
                    "backgroundRemovalParams": .object([
                        "image": .string(sourceImageBase64)
                    ]),
                ])

            case "IMAGE_VARIATION":
                let images = try files.map(getBase64Data)

                var imageVariationParams: [String: JSONValue] = [
                    "images": .array(images.map { .string($0) })
                ]

                if let prompt = options.prompt, !prompt.isEmpty {
                    imageVariationParams["text"] = .string(prompt)
                }
                if let negativeText = nonEmptyString(overrides["negativeText"]) {
                    imageVariationParams["negativeText"] = .string(negativeText)
                }
                if let similarityStrength = numberValue(overrides["similarityStrength"]) {
                    imageVariationParams["similarityStrength"] = .number(similarityStrength)
                }

                args = .object([
                    "taskType": .string("IMAGE_VARIATION"),
                    "imageVariationParams": .object(imageVariationParams),
                    "imageGenerationConfig": .object(imageGenerationConfig),
                ])

            default:
                throw BedrockImageModelError(message: "Unsupported task type: \(taskType)")
            }
        } else {
            var textToImageParams: [String: JSONValue] = [
                "text": .string(options.prompt ?? "")
            ]

            if let negativeText = nonEmptyString(overrides["negativeText"]) {
                textToImageParams["negativeText"] = .string(negativeText)
            }
            if let style = nonEmptyString(overrides["style"]) {
                textToImageParams["style"] = .string(style)
            }

            args = .object([
                "taskType": .string("TEXT_IMAGE"),
                "textToImageParams": .object(textToImageParams),
                "imageGenerationConfig": .object(imageGenerationConfig),
            ])
        }

        let url = "\(config.baseURL())/model/\(encodeModelId(modelIdentifier.rawValue))/invoke"
        let headers = mergeHeaders(base: config.headers(), overrides: options.headers)
        let timestamp = config.currentDate()

        let response = try await postJsonToAPI(
            url: url,
            headers: headers,
            body: args,
            failedResponseHandler: bedrockFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: bedrockImageResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let images = try extractImages(from: response.value)

        return ImageModelV3GenerateResult(
            images: .base64(images),
            warnings: warnings,
            providerMetadata: nil,
            response: ImageModelV3ResponseInfo(
                timestamp: timestamp,
                modelId: modelIdentifier.rawValue,
                headers: response.responseHeaders
            )
        )
    }

    private func mergeHeaders(base: [String: String?], overrides: [String: String]?) -> [String: String] {
        let merged = combineHeaders(
            base,
            overrides?.mapValues { Optional($0) }
        )
        return merged.compactMapValues { $0 }
    }

    private func encodeModelId(_ id: String) -> String {
        bedrockEncodeURIComponent(id)
    }
}

private func buildImageGenerationConfig(
    options: ImageModelV3CallOptions,
    overrides: [String: JSONValue]
) -> [String: JSONValue] {
    var config: [String: JSONValue] = [:]

    if let size = options.size {
        let components = size.split(separator: "x").compactMap { Int($0) }
        if components.count == 2, components[0] > 0, components[1] > 0 {
            config["width"] = .number(Double(components[0]))
            config["height"] = .number(Double(components[1]))
        }
    }

    if let seed = options.seed, seed != 0 {
        config["seed"] = .number(Double(seed))
    }

    if options.n > 0 {
        config["numberOfImages"] = .number(Double(options.n))
    }

    if let quality = nonEmptyString(overrides["quality"]) {
        config["quality"] = .string(quality)
    }

    if let cfgScale = numberValue(overrides["cfgScale"]), cfgScale != 0 {
        config["cfgScale"] = .number(cfgScale)
    }

    return config
}

private func extractImages(from value: JSONValue) throws -> [String] {
    let foundationValue = jsonValueToFoundation(value)

    guard case .object(let dict) = value else {
        throw TypeValidationError.wrap(
            value: foundationValue,
            cause: BedrockImageModelError(message: "Expected object image response.")
        )
    }

    if case .string(let status)? = dict["status"], status == "Request Moderated" {
        var reasons: [String] = ["Unknown"]

        if case .object(let details)? = dict["details"],
           let reasonsValue = details["Moderation Reasons"],
           case .array(let array) = reasonsValue {
            let parsed = array.compactMap { element -> String? in
                if case .string(let text) = element { return text }
                return nil
            }
            if !parsed.isEmpty {
                reasons = parsed
            }
        }

        throw BedrockImageModelError(
            message: "Amazon Bedrock request was moderated: \(reasons.joined(separator: ", "))"
        )
    }

    guard let imagesValue = dict["images"],
          case .array(let imagesArray) = imagesValue
    else {
        var message = "Amazon Bedrock returned no images. "
        if case .string(let status)? = dict["status"] {
            message += "Status: \(status)"
        }
        throw BedrockImageModelError(message: message)
    }

    let images = imagesArray.compactMap { element -> String? in
        if case .string(let text) = element { return text }
        return nil
    }

    if images.isEmpty {
        var message = "Amazon Bedrock returned no images. "
        if case .string(let status)? = dict["status"] {
            message += "Status: \(status)"
        }
        throw BedrockImageModelError(message: message)
    }

    return images
}

private func stringValue(_ value: JSONValue?) -> String? {
    guard case .string(let text)? = value else {
        return nil
    }
    return text
}

private func nonEmptyString(_ value: JSONValue?) -> String? {
    guard let text = stringValue(value), !text.isEmpty else {
        return nil
    }
    return text
}

private func numberValue(_ value: JSONValue?) -> Double? {
    guard case .number(let number)? = value else {
        return nil
    }
    return number
}

private func getBase64Data(_ file: ImageModelV3File) throws -> String {
    switch file {
    case .url:
        throw BedrockImageModelError(
            message: "URL-based images are not supported for Amazon Bedrock image editing. Please provide the image data directly."
        )
    case let .file(_, data, _):
        switch data {
        case .binary(let binary):
            return binary.base64EncodedString()
        case .base64(let base64):
            return base64
        }
    }
}
