import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class OpenAIImageModel: ImageModelV3 {
    private let modelIdentifier: OpenAIImageModelId
    private let config: OpenAIConfig

    public init(modelId: OpenAIImageModelId, config: OpenAIConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    public var maxImagesPerCall: ImageModelV3MaxImagesPerCall {
        if let limit = openAIImageModelMaxImagesPerCall[modelIdentifier] {
            return .value(limit)
        }
        // Upstream TypeScript: return modelMaxImagesPerCall[this.modelId] ?? 1
        return .value(1)
    }

    public func doGenerate(options: ImageModelV3CallOptions) async throws -> ImageModelV3GenerateResult {
        var warnings: [ImageModelV3CallWarning] = []

        if options.aspectRatio != nil {
            warnings.append(.unsupportedSetting(setting: "aspectRatio", details: "This model does not support aspect ratio. Use `size` instead."))
        }

        if options.seed != nil {
            warnings.append(.unsupportedSetting(setting: "seed", details: nil))
        }

        let body = try makeRequestBody(options: options)
        let headers = combineHeaders(config.headers(), options.headers?.mapValues { Optional($0) })
        let normalizedHeaders = headers.compactMapValues { $0 }

        let response = try await postJsonToAPI(
            url: config.url(.init(modelId: modelIdentifier.rawValue, path: "/images/generations")),
            headers: normalizedHeaders,
            body: body,
            failedResponseHandler: openAIFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: openaiImageResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let value = response.value
        let images = value.data.map { $0.b64JSON }

        let metadataValue: ImageModelV3ProviderMetadataValue? = {
            let revisions = value.data.map { item -> JSONValue in
                if let prompt = item.revisedPrompt {
                    return .object(["revisedPrompt": .string(prompt)])
                }
                return .null
            }
            if revisions.allSatisfy({ $0 == .null }) {
                return nil
            }
            return ImageModelV3ProviderMetadataValue(images: revisions, additionalData: nil)
        }()

        let providerMetadata: ImageModelV3ProviderMetadata? = metadataValue.map { ["openai": $0] }

        let timestamp = config._internal?.currentDate?() ?? Date()
        let responseInfo = ImageModelV3ResponseInfo(
            timestamp: timestamp,
            modelId: modelIdentifier.rawValue,
            headers: response.responseHeaders
        )

        return ImageModelV3GenerateResult(
            images: .base64(images),
            warnings: warnings,
            providerMetadata: providerMetadata,
            response: responseInfo
        )
    }

    private func makeRequestBody(options: ImageModelV3CallOptions) throws -> JSONValue {
        var payload: [String: JSONValue] = [
            "model": .string(modelIdentifier.rawValue),
            "prompt": .string(options.prompt)
        ]

        if options.n > 0 {
            payload["n"] = .number(Double(options.n))
        }
        if let size = options.size {
            payload["size"] = .string(size)
        }

        if !openAIImageModelsWithDefaultResponseFormat.contains(modelIdentifier) {
            payload["response_format"] = .string("b64_json")
        }

        if let openaiOptions = options.providerOptions?["openai"], !openaiOptions.isEmpty {
            for (key, value) in openaiOptions {
                payload[key] = value
            }
        }

        return .object(payload)
    }
}
