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
    prompt: GenerateImagePrompt,
    n: Int = 1,
    maxImagesPerCall: Int? = nil,
    size: String? = nil,
    aspectRatio: String? = nil,
    seed: Int? = nil,
    providerOptions: ProviderOptions? = nil,
    maxRetries: Int? = nil,
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil
) async throws -> DefaultGenerateImageResult {
    let normalized = try prompt.normalize()
    return try await generateImageInternal(
        model: model,
        prompt: normalized.prompt,
        n: n,
        maxImagesPerCall: maxImagesPerCall,
        size: size,
        aspectRatio: aspectRatio,
        seed: seed,
        files: normalized.files,
        mask: normalized.mask,
        providerOptions: providerOptions,
        maxRetries: maxRetries,
        abortSignal: abortSignal,
        headers: headers
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func generateImage(
    model: ImageModel,
    prompt: String,
    n: Int = 1,
    maxImagesPerCall: Int? = nil,
    size: String? = nil,
    aspectRatio: String? = nil,
    seed: Int? = nil,
    files: [ImageModelV4File]? = nil,
    mask: ImageModelV4File? = nil,
    providerOptions: ProviderOptions? = nil,
    maxRetries: Int? = nil,
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil
) async throws -> DefaultGenerateImageResult {
    try await generateImageInternal(
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

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func generateImage(
    model: any ImageModelV4,
    prompt: GenerateImagePrompt,
    n: Int = 1,
    maxImagesPerCall: Int? = nil,
    size: String? = nil,
    aspectRatio: String? = nil,
    seed: Int? = nil,
    providerOptions: ProviderOptions? = nil,
    maxRetries: Int? = nil,
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil
) async throws -> DefaultGenerateImageResult {
    try await generateImage(
        model: .v4(model),
        prompt: prompt,
        n: n,
        maxImagesPerCall: maxImagesPerCall,
        size: size,
        aspectRatio: aspectRatio,
        seed: seed,
        providerOptions: providerOptions,
        maxRetries: maxRetries,
        abortSignal: abortSignal,
        headers: headers
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func generateImage(
    model: any ImageModelV3,
    prompt: GenerateImagePrompt,
    n: Int = 1,
    maxImagesPerCall: Int? = nil,
    size: String? = nil,
    aspectRatio: String? = nil,
    seed: Int? = nil,
    providerOptions: ProviderOptions? = nil,
    maxRetries: Int? = nil,
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil
) async throws -> DefaultGenerateImageResult {
    try await generateImage(
        model: .v3(model),
        prompt: prompt,
        n: n,
        maxImagesPerCall: maxImagesPerCall,
        size: size,
        aspectRatio: aspectRatio,
        seed: seed,
        providerOptions: providerOptions,
        maxRetries: maxRetries,
        abortSignal: abortSignal,
        headers: headers
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func generateImage(
    model: any ImageModelV4,
    prompt: String,
    n: Int = 1,
    maxImagesPerCall: Int? = nil,
    size: String? = nil,
    aspectRatio: String? = nil,
    seed: Int? = nil,
    files: [ImageModelV4File]? = nil,
    mask: ImageModelV4File? = nil,
    providerOptions: ProviderOptions? = nil,
    maxRetries: Int? = nil,
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil
) async throws -> DefaultGenerateImageResult {
    try await generateImage(
        model: .v4(model),
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

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func generateImage(
    model: any ImageModelV3,
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
        model: .v3(model),
        prompt: prompt,
        n: n,
        maxImagesPerCall: maxImagesPerCall,
        size: size,
        aspectRatio: aspectRatio,
        seed: seed,
        files: try files?.map(convertImageModelV3FileToV4),
        mask: try mask.map(convertImageModelV3FileToV4),
        providerOptions: providerOptions,
        maxRetries: maxRetries,
        abortSignal: abortSignal,
        headers: headers
    )
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private func generateImageInternal(
    model: ImageModel,
    prompt: String?,
    n: Int,
    maxImagesPerCall: Int?,
    size: String?,
    aspectRatio: String?,
    seed: Int?,
    files: [ImageModelV4File]?,
    mask: ImageModelV4File?,
    providerOptions: ProviderOptions?,
    maxRetries: Int?,
    abortSignal: (@Sendable () -> Bool)?,
    headers: [String: String]?
) async throws -> DefaultGenerateImageResult {
    let model = try resolveImageModelV4(model)

    let headersWithUserAgent = withUserAgentSuffix(
        headers ?? [:],
        "ai/\(VERSION)"
    )

    let preparedRetries = try prepareRetries(
        maxRetries: maxRetries,
        abortSignal: abortSignal,
        additionalRetryableError: { $0 is RetryableNoImageResultError }
    )

    let maxImagesPerCallResolved: Int
    if let override = maxImagesPerCall {
        maxImagesPerCallResolved = override
    } else {
        let modelLimit = try await invokeModelMaxImagesPerCall(model)
        maxImagesPerCallResolved = modelLimit ?? 1
    }

    guard maxImagesPerCallResolved > 0 else {
        throw InvalidArgumentError(argument: "maxImagesPerCall", message: "maxImagesPerCall must be greater than 0")
    }
    let imageCount = max(n, 0)
    let callCount = imageCount / maxImagesPerCallResolved + (imageCount % maxImagesPerCallResolved == 0 ? 0 : 1)

    let callImageCounts = (0..<callCount).map { index -> Int in
        if index < callCount - 1 {
            return maxImagesPerCallResolved
        }

        let remainder = n % maxImagesPerCallResolved
        return remainder == 0 ? maxImagesPerCallResolved : remainder
    }

    let resultGroups = try await withThrowingTaskGroup(of: (Int, [ImageModelV4GenerateResult]).self) { group in
        for (index, imagesInCall) in callImageCounts.enumerated() {
            group.addTask {
                let attempts = ImageCallAttempts()
                do {
                    _ = try await preparedRetries.retry.call {
                        let result = try await model.doGenerate(
                            options: ImageModelV4CallOptions(
                                prompt: prompt,
                                n: imagesInCall,
                                size: size,
                                aspectRatio: aspectRatio,
                                seed: seed,
                                files: files,
                                mask: mask,
                                providerOptions: providerOptions ?? [:],
                                abortSignal: abortSignal,
                                headers: headersWithUserAgent
                            )
                        )
                        await attempts.append(result)
                        if result.images.isEmpty && result.isRetryable != false {
                            throw RetryableNoImageResultError()
                        }
                        return result
                    }
                } catch {
                    guard error is RetryableNoImageResultError
                        || (error as? RetryError)?.lastError is RetryableNoImageResultError else {
                        throw error
                    }
                }
                return (index, await attempts.results)
            }
        }
        var ordered = Array(repeating: [ImageModelV4GenerateResult](), count: callImageCounts.count)
        for try await (index, results) in group { ordered[index] = results }
        return ordered
    }
    let results = resultGroups.flatMap { $0 }

    var generatedImages: [GeneratedFile] = []
    generatedImages.reserveCapacity(imageCount)

    var calls: [GenerateImageCall] = []
    var warnings: [ImageGenerationWarning] = []
    var responses: [ImageModelResponseMetadata] = []
    responses.reserveCapacity(results.count)

    var providerMetadata: ImageModelProviderMetadata = [:]
    var usage: ImageModelUsage = .init()

    for result in results {
        let firstImageIndex = generatedImages.count
        switch result.images {
        case .base64(let base64Images):
            for (imageIndex, base64) in base64Images.enumerated() {
                let mediaType = detectMediaType(
                    data: base64,
                    topLevelType: "image"
                ) ?? "image/png"
                generatedImages.append(
                    DefaultGeneratedFile(base64: base64, mediaType: mediaType, providerMetadata: imageProviderMetadata(result.providerMetadata, index: imageIndex))
                )
            }

        case .binary(let dataImages):
            for (imageIndex, data) in dataImages.enumerated() {
                let mediaType = detectMediaType(
                    data: data,
                    topLevelType: "image"
                ) ?? "image/png"
                generatedImages.append(
                    DefaultGeneratedFile(data: data, mediaType: mediaType, providerMetadata: imageProviderMetadata(result.providerMetadata, index: imageIndex))
                )
            }
        }

        warnings.append(contentsOf: result.warnings)

        if let resultUsage = result.usage {
            usage = addImageModelUsage(usage, resultUsage)
        }

        if let metadata = result.providerMetadata {
            mergeProviderMetadata(
                target: &providerMetadata,
                source: metadata
            )
        }

        let response = ImageModelResponseMetadata(
            timestamp: result.response.timestamp,
            modelId: result.response.modelId,
            headers: result.response.headers
        )
        responses.append(response)
        calls.append(GenerateImageCall(
            images: Array(generatedImages.dropFirst(firstImageIndex)),
            providerMetadata: result.providerMetadata,
            response: response,
            warnings: result.warnings,
            usage: result.usage
        ))
    }

    logWarnings(warnings.map { Warning.imageModel($0) })

    if generatedImages.isEmpty {
        throw NoImageGeneratedError(responses: responses, calls: calls)
    }

    return DefaultGenerateImageResult(
        images: generatedImages,
        calls: calls,
        warnings: warnings,
        responses: responses,
        providerMetadata: providerMetadata,
        usage: usage
    )
}

private func mergeProviderMetadata(
    target: inout ImageModelV4ProviderMetadata,
    source: ImageModelV4ProviderMetadata
) {
    for (providerName, value) in source {
        if providerName == "gateway" {
            let existing = target[providerName]
            target[providerName] = ImageModelV4ProviderMetadataValue(
                images: value.images.isEmpty ? (existing?.images ?? []) : value.images,
                additionalData: mergeGatewayAdditionalData(
                    existing?.additionalData,
                    value.additionalData
                )
            )
            continue
        }

        target[providerName] = ImageModelV4ProviderMetadataValue(
            images: (target[providerName]?.images ?? []) + value.images
        )
    }
}

private func mergeGatewayAdditionalData(_ existing: JSONValue?, _ incoming: JSONValue?) -> JSONValue? {
    switch (existing, incoming) {
    case let (.object(lhs)?, .object(rhs)?):
        var merged = lhs.merging(rhs) { _, new in new }
        for key in ["cost", "gatewayCost", "inferenceCost", "inputInferenceCost", "marketCost", "outputInferenceCost", "surchargeCost"] {
            if case .string(let a)? = lhs[key], case .string(let b)? = rhs[key],
               let sum = addDecimalStrings(a, b) {
                merged[key] = .string(sum)
            }
        }
        return .object(merged)
    case (_, let incoming?):
        return incoming
    case (let existing?, nil):
        return existing
    case (nil, nil):
        return nil
    }
}

private func addDecimalStrings(_ lhs: String, _ rhs: String) -> String? {
    func parts(_ value: String) -> (String, String)? {
        let segments = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(segments.count), segments.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }) else { return nil }
        return (String(segments[0]), segments.count == 2 ? String(segments[1]) : "")
    }
    guard let a = parts(lhs), let b = parts(rhs) else { return nil }
    let precision = max(a.1.count, b.1.count)
    let left = Array((a.0 + a.1 + String(repeating: "0", count: precision - a.1.count)).utf8.reversed())
    let right = Array((b.0 + b.1 + String(repeating: "0", count: precision - b.1.count)).utf8.reversed())
    var digits: [UInt8] = []
    var carry = 0
    for index in 0..<max(left.count, right.count) {
        let sum = (index < left.count ? Int(left[index]) - 48 : 0)
            + (index < right.count ? Int(right[index]) - 48 : 0) + carry
        digits.append(UInt8(sum % 10) + 48)
        carry = sum / 10
    }
    if carry != 0 { digits.append(UInt8(carry) + 48) }
    while digits.count > max(precision + 1, 1), digits.last == 48 { digits.removeLast() }
    var result = String(decoding: digits.reversed(), as: UTF8.self)
    if precision > 0 {
        result.insert(".", at: result.index(result.endIndex, offsetBy: -precision))
        while result.last == "0" { result.removeLast() }
        if result.last == "." { result.removeLast() }
    }
    return result
}

private func convertImageModelV3FileToV4(_ value: ImageModelV3File) throws -> ImageModelV4File {
    switch value {
    case let .file(mediaType, data, providerOptions):
        return .file(
            mediaType: mediaType,
            data: convertImageModelV3FileDataToV4(data),
            providerOptions: providerOptions
        )
    case let .url(url, providerOptions):
        return .url(url: url, providerOptions: providerOptions)
    }
}

private func convertImageModelV3FileDataToV4(_ value: ImageModelV3FileData) -> ImageModelV4FileData {
    switch value {
    case .base64(let base64):
        return .base64(base64)
    case .binary(let data):
        return .binary(data)
    }
}

private func imageProviderMetadata(_ metadata: ImageModelProviderMetadata?, index: Int) -> ProviderMetadata? {
    var result: ProviderMetadata = [:]
    for (provider, value) in metadata ?? [:] {
        if value.images.indices.contains(index), case .object(let object) = value.images[index] {
            result[provider] = object
        }
    }
    return result.isEmpty ? nil : result
}

private struct RetryableNoImageResultError: Error, LocalizedError {
    var errorDescription: String? { "No image generated." }
}

private actor ImageCallAttempts {
    private(set) var results: [ImageModelV4GenerateResult] = []
    func append(_ result: ImageModelV4GenerateResult) { results.append(result) }
}

private extension ImageModelV4GeneratedImages {
    var isEmpty: Bool {
        switch self {
        case .base64(let images): images.isEmpty
        case .binary(let images): images.isEmpty
        }
    }
}

private func invokeModelMaxImagesPerCall(_ model: any ImageModelV4) async throws -> Int? {
    switch model.maxImagesPerCall {
    case .value(let value):
        return value
    case .default:
        return nil
    case .function(let fn):
        return try await fn(model.modelId)
    }
}
