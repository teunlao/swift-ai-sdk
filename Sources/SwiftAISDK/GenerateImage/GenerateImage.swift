import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Generates images using an image model.

 Port of `@ai-sdk/ai/src/generate-image/generate-image.ts`.

 Handles retry logic, user-agent headers, media type detection, provider metadata
 aggregation, and warning logging while supporting multiple model calls when more
 images are requested than a single call can return.
 */
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func generateImage(
    model: ImageModel,
    prompt: String,
    n: Int = 1,
    maxImagesPerCall: Int? = nil,
    size: String? = nil,
    aspectRatio: String? = nil,
    seed: Int? = nil,
    files: [ImageModelV3File]? = nil,
    mask: ImageModelV3File? = nil,
    providerOptions: ProviderOptions? = nil,
    maxRetries: Int? = nil,
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil
) async throws -> DefaultGenerateImageResult {
    guard model.specificationVersion == "v3" else {
        throw UnsupportedModelVersionError(
            version: model.specificationVersion,
            provider: model.provider,
            modelId: model.modelId
        )
    }

    let headersWithUserAgent = withUserAgentSuffix(
        headers ?? [:],
        "ai/\(VERSION)"
    )

    let preparedRetries = try prepareRetries(
        maxRetries: maxRetries,
        abortSignal: abortSignal
    )

    let maxImagesPerCallResolved: Int
    if let override = maxImagesPerCall {
        maxImagesPerCallResolved = override
    } else {
        let modelLimit = try await invokeModelMaxImagesPerCall(model)
        maxImagesPerCallResolved = modelLimit ?? 1
    }

    let callCount = Int(
        ceil(Double(n) / Double(maxImagesPerCallResolved))
    )

    let callImageCounts = (0..<callCount).map { index -> Int in
        if index < callCount - 1 {
            return maxImagesPerCallResolved
        }

        let remainder = n % maxImagesPerCallResolved
        return remainder == 0 ? maxImagesPerCallResolved : remainder
    }

    var results: [ImageModelV3GenerateResult] = []
    results.reserveCapacity(callImageCounts.count)

    for imagesInCall in callImageCounts {
        let result = try await preparedRetries.retry.call {
            try await model.doGenerate(
                options: ImageModelV3CallOptions(
                    prompt: prompt,
                    n: imagesInCall,
                    size: size,
                    aspectRatio: aspectRatio,
                    seed: seed,
                    providerOptions: providerOptions ?? [:],
                    abortSignal: abortSignal,
                    headers: headersWithUserAgent,
                    files: files,
                    mask: mask
                )
            )
        }
        results.append(result)
    }

    var generatedImages: [GeneratedFile] = []
    generatedImages.reserveCapacity(n)

    var warnings: [ImageGenerationWarning] = []
    var responses: [ImageModelResponseMetadata] = []
    responses.reserveCapacity(results.count)

    var providerMetadata: ImageModelProviderMetadata = [:]

    for result in results {
        switch result.images {
        case .base64(let base64Images):
            for base64 in base64Images {
                let mediaType = detectMediaType(
                    data: base64,
                    signatures: imageMediaTypeSignatures
                ) ?? "image/png"
                generatedImages.append(
                    DefaultGeneratedFile(base64: base64, mediaType: mediaType)
                )
            }

        case .binary(let dataImages):
            for data in dataImages {
                let mediaType = detectMediaType(
                    data: data,
                    signatures: imageMediaTypeSignatures
                ) ?? "image/png"
                generatedImages.append(
                    DefaultGeneratedFile(data: data, mediaType: mediaType)
                )
            }
        }

        warnings.append(contentsOf: result.warnings)
        if let metadata = result.providerMetadata {
            mergeProviderMetadata(
                target: &providerMetadata,
                source: metadata
            )
        }

        responses.append(
            ImageModelResponseMetadata(
                timestamp: result.response.timestamp,
                modelId: result.response.modelId,
                headers: result.response.headers
            )
        )
    }

    logWarnings(warnings.map { Warning.imageModel($0) })

    if generatedImages.isEmpty {
        throw NoImageGeneratedError(responses: responses)
    }

    return DefaultGenerateImageResult(
        images: generatedImages,
        warnings: warnings,
        responses: responses,
        providerMetadata: providerMetadata
    )
}

private func mergeProviderMetadata(
    target: inout ImageModelV3ProviderMetadata,
    source: ImageModelV3ProviderMetadata
) {
    for (providerName, value) in source {
        if let existing = target[providerName] {
            let combinedImages = existing.images + value.images
            let additionalData = existing.additionalData ?? value.additionalData
            target[providerName] = ImageModelV3ProviderMetadataValue(
                images: combinedImages,
                additionalData: additionalData
            )
        } else {
            target[providerName] = value
        }
    }
}

private func invokeModelMaxImagesPerCall(_ model: ImageModel) async throws -> Int? {
    switch model.maxImagesPerCall {
    case .value(let value):
        return value
    case .default:
        return nil
    case .function(let fn):
        return try await fn(model.modelId)
    }
}
