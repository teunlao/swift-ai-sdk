import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/amazon-bedrock/src/bedrock-image-model.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

struct BedrockImageModelConfig: Sendable {
    let baseURL: @Sendable () -> String
    let headers: @Sendable () -> [String: String?]
    let fetch: FetchFunction?
    let currentDate: @Sendable () -> Date
}

private struct BedrockImageResponse: Codable, Sendable {
    let images: [String]
}

private let bedrockImageResponseSchema = FlexibleSchema(
    Schema<BedrockImageResponse>.codable(
        BedrockImageResponse.self,
        jsonSchema: .object([
            "type": .string("object")
        ])
    )
)

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
        if let limit = bedrockModelMaxImagesPerCall[modelIdentifier] {
            return .value(limit)
        }
        return .value(1)
    }

    public func doGenerate(options: ImageModelV3CallOptions) async throws -> ImageModelV3GenerateResult {
        var warnings: [ImageModelV3CallWarning] = []

        if options.aspectRatio != nil {
            warnings.append(.unsupportedSetting(
                setting: "aspectRatio",
                details: "This model does not support aspect ratio. Use `size` instead."
            ))
        }

        let overrides: [String: JSONValue] = options.providerOptions?["bedrock"] ?? [:]

        var textToImageParams: [String: JSONValue] = [
            "text": .string(options.prompt ?? "")
        ]

        if let negativeTextValue = overrides["negativeText"],
           case .string(let negativeText) = negativeTextValue {
            textToImageParams["negativeText"] = .string(negativeText)
        }
        if let styleValue = overrides["style"],
           case .string(let style) = styleValue {
            textToImageParams["style"] = .string(style)
        }

        var imageConfig: [String: JSONValue] = [:]

        if let size = options.size {
            let components = size.split(separator: "x").compactMap { Int($0) }
            if components.count == 2 {
                imageConfig["width"] = .number(Double(components[0]))
                imageConfig["height"] = .number(Double(components[1]))
            }
        }

        if let seed = options.seed {
            imageConfig["seed"] = .number(Double(seed))
        }

        imageConfig["numberOfImages"] = .number(Double(options.n))

        if let qualityValue = overrides["quality"],
           case .string(let quality) = qualityValue {
            imageConfig["quality"] = .string(quality)
        }

        if let cfgScaleValue = overrides["cfgScale"],
           case .number(let cfgScale) = cfgScaleValue {
            imageConfig["cfgScale"] = .number(cfgScale)
        } else if let cfgScaleValue = overrides["cfgScale"],
                  case .number(let cfgScaleNumber) = cfgScaleValue,
                  cfgScaleNumber == Double(Int(cfgScaleNumber)) {
            let cfgScale = Int(cfgScaleNumber)
            imageConfig["cfgScale"] = .number(Double(cfgScale))
        }

        let body: [String: JSONValue] = [
            "taskType": .string("TEXT_IMAGE"),
            "textToImageParams": .object(textToImageParams),
            "imageGenerationConfig": .object(imageConfig)
        ]

        let url = "\(config.baseURL())/model/\(encodeModelId(modelIdentifier.rawValue))/invoke"
        let headers = mergeHeaders(base: config.headers(), overrides: options.headers)

        let response = try await postJsonToAPI(
            url: url,
            headers: headers,
            body: JSONValue.object(body),
            failedResponseHandler: bedrockFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: bedrockImageResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let timestamp = config.currentDate()

        return ImageModelV3GenerateResult(
            images: .base64(response.value.images),
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
        id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
    }
}
