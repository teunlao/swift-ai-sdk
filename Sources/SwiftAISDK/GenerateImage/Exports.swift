import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Public exports for the generate-image module.

 Port of `@ai-sdk/ai/src/generate-image/index.ts`.
 */
public typealias Experimental_GenerateImageResult = GenerateImageResult

/// Experimental generate image entry point (mirrors upstream export name).
@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func experimental_generateImage(
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
    try await generateImage(
        model: model,
        prompt: prompt,
        n: n,
        maxImagesPerCall: maxImagesPerCall,
        size: size,
        aspectRatio: aspectRatio,
        seed: seed,
        files: files,
        mask: mask,
        providerOptions: providerOptions,
        maxRetries: maxRetries,
        abortSignal: abortSignal,
        headers: headers
    )
}
