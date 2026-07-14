import Foundation
import AISDKProvider

final class OpenAICompatibleImageModelV4Adapter: ImageModelV4, @unchecked Sendable {
    let specificationVersion = "v4"

    private let model: any ImageModelV3

    var provider: String { model.provider }
    var modelId: String { model.modelId }
    var maxImagesPerCall: ImageModelV4MaxImagesPerCall { convertImageModelV3MaxImagesPerCallToV4(model.maxImagesPerCall) }

    init(wrapping model: any ImageModelV3) {
        self.model = model
    }

    func doGenerate(options: ImageModelV4CallOptions) async throws -> ImageModelV4GenerateResult {
        let result = try await model.doGenerate(options: try convertImageModelV4CallOptionsToV3(options))
        return ImageModelV4GenerateResult(
            images: convertImageModelV3GeneratedImagesToV4(result.images),
            warnings: result.warnings.map(convertSharedV3WarningToV4),
            providerMetadata: convertImageModelV3ProviderMetadataToV4(result.providerMetadata),
            response: ImageModelV4ResponseInfo(
                timestamp: result.response.timestamp,
                modelId: result.response.modelId,
                headers: result.response.headers
            ),
            usage: result.usage.map {
                ImageModelV4Usage(
                    inputTokens: $0.inputTokens,
                    outputTokens: $0.outputTokens,
                    totalTokens: $0.totalTokens
                )
            }
        )
    }
}

private func convertImageModelV3MaxImagesPerCallToV4(_ value: ImageModelV3MaxImagesPerCall) -> ImageModelV4MaxImagesPerCall {
    switch value {
    case .value(let count):
        return .value(count)
    case .default:
        return .default
    case .function(let resolver):
        return .function(resolver)
    }
}

private func convertImageModelV4CallOptionsToV3(_ options: ImageModelV4CallOptions) throws -> ImageModelV3CallOptions {
    ImageModelV3CallOptions(
        prompt: options.prompt,
        n: options.n,
        size: options.size,
        aspectRatio: options.aspectRatio,
        seed: options.seed,
        providerOptions: options.providerOptions,
        abortSignal: options.abortSignal,
        headers: options.headers,
        files: try options.files?.map(convertImageModelV4FileToV3),
        mask: try options.mask.map(convertImageModelV4FileToV3)
    )
}

private func convertImageModelV4FileToV3(_ value: ImageModelV4File) throws -> ImageModelV3File {
    switch value {
    case let .file(mediaType, data, providerOptions):
        return .file(mediaType: mediaType, data: convertImageModelV4FileDataToV3(data), providerOptions: providerOptions)
    case let .url(url, providerOptions):
        return .url(url: url, providerOptions: providerOptions)
    }
}

private func convertImageModelV4FileDataToV3(_ value: ImageModelV4FileData) -> ImageModelV3FileData {
    switch value {
    case .base64(let base64):
        return .base64(base64)
    case .binary(let data):
        return .binary(data)
    }
}

private func convertImageModelV3GeneratedImagesToV4(_ value: ImageModelV3GeneratedImages) -> ImageModelV4GeneratedImages {
    switch value {
    case .base64(let images):
        return .base64(images)
    case .binary(let images):
        return .binary(images)
    }
}

private func convertImageModelV3ProviderMetadataToV4(
    _ value: ImageModelV3ProviderMetadata?
) -> ImageModelV4ProviderMetadata? {
    value?.mapValues { ImageModelV4ProviderMetadataValue(images: $0.images, additionalData: $0.additionalData) }
}

private func convertSharedV3WarningToV4(_ value: SharedV3Warning) -> SharedV4Warning {
    switch value {
    case let .unsupported(feature, details):
        return .unsupported(feature: feature, details: details)
    case let .compatibility(feature, details):
        return .compatibility(feature: feature, details: details)
    case .other(let message):
        return .other(message: message)
    }
}
