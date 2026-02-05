import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Generates videos using a video model.

 Port of `@ai-sdk/ai/src/generate-video/generate-video.ts`.
 */

public enum GenerateVideoPrompt: Sendable {
    case text(String)
    case imageToVideo(image: DataContent, text: String?)
}

extension GenerateVideoPrompt {
    func normalize() throws -> (prompt: String?, image: VideoModelV3File?) {
        switch self {
        case .text(let text):
            return (prompt: text, image: nil)

        case .imageToVideo(let image, let text):
            return (prompt: text, image: try toVideoModelV3File(image))
        }
    }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
func generateVideo(
    model: VideoModel,
    prompt: GenerateVideoPrompt,
    n: Int = 1,
    maxVideosPerCall: Int? = nil,
    aspectRatio: String? = nil,
    resolution: String? = nil,
    duration: Int? = nil,
    fps: Int? = nil,
    seed: Int? = nil,
    providerOptions: ProviderOptions? = nil,
    maxRetries: Int? = nil,
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil
) async throws -> DefaultGenerateVideoResult {
    let normalizedPrompt = try prompt.normalize()

    let headersWithUserAgent = withUserAgentSuffix(
        headers ?? [:],
        "ai/\(VERSION)"
    )

    let preparedRetries = try prepareRetries(
        maxRetries: maxRetries,
        abortSignal: abortSignal
    )

    let maxVideosPerCallResolved: Int
    if let override = maxVideosPerCall {
        maxVideosPerCallResolved = override
    } else {
        let modelLimit = try await invokeModelMaxVideosPerCall(model)
        maxVideosPerCallResolved = modelLimit ?? 1
    }

    let callCount = Int(
        ceil(Double(n) / Double(maxVideosPerCallResolved))
    )

    let callVideoCounts = (0..<callCount).map { index -> Int in
        let remaining = n - index * maxVideosPerCallResolved
        return min(remaining, maxVideosPerCallResolved)
    }

    var results: [VideoModelV3GenerateResult] = []
    results.reserveCapacity(callVideoCounts.count)

    for videosInCall in callVideoCounts {
        let result = try await preparedRetries.retry.call {
            try await model.doGenerate(
                options: VideoModelV3CallOptions(
                    prompt: normalizedPrompt.prompt,
                    n: videosInCall,
                    aspectRatio: aspectRatio,
                    resolution: resolution,
                    duration: duration,
                    fps: fps,
                    seed: seed,
                    image: normalizedPrompt.image,
                    providerOptions: providerOptions ?? [:],
                    abortSignal: abortSignal,
                    headers: headersWithUserAgent
                )
            )
        }

        results.append(result)
    }

    var videos: [GeneratedFile] = []
    var warnings: [VideoGenerationWarning] = []
    var responses: [VideoModelResponseMetadata] = []
    responses.reserveCapacity(results.count)

    var providerMetadata: VideoModelProviderMetadata = [:]

    for result in results {
        for videoData in result.videos {
            switch videoData {
            case .url(let urlString, let providerMediaType):
                guard let url = URL(string: urlString) else {
                    throw DownloadError(url: urlString, cause: URLError(.badURL))
                }

                let (data, downloadedMediaType) = try await download(url: url)

                func isUsableMediaType(_ type: String?) -> Bool {
                    guard let type else { return false }
                    return type != "application/octet-stream"
                }

                let mediaType =
                    (isUsableMediaType(providerMediaType) ? providerMediaType : nil)
                    ?? (isUsableMediaType(downloadedMediaType) ? downloadedMediaType : nil)
                    ?? detectMediaType(data: data, signatures: videoMediaTypeSignatures)
                    ?? "video/mp4"

                videos.append(
                    DefaultGeneratedFile(data: data, mediaType: mediaType)
                )

            case .base64(let base64, let mediaType):
                videos.append(
                    DefaultGeneratedFile(base64: base64, mediaType: mediaType ?? "video/mp4")
                )

            case .binary(let data, let mediaType):
                let resolvedMediaType =
                    mediaType
                    ?? detectMediaType(data: data, signatures: videoMediaTypeSignatures)
                    ?? "video/mp4"

                videos.append(
                    DefaultGeneratedFile(data: data, mediaType: resolvedMediaType)
                )
            }
        }

        warnings.append(contentsOf: result.warnings)

        responses.append(
            VideoModelResponseMetadata(
                timestamp: result.response.timestamp,
                modelId: result.response.modelId,
                headers: result.response.headers,
                providerMetadata: result.providerMetadata
            )
        )

        if let metadata = result.providerMetadata {
            mergeProviderMetadata(target: &providerMetadata, source: metadata)
        }
    }

    logWarnings(warnings.map { Warning.videoModel($0) })

    if videos.isEmpty {
        throw NoVideoGeneratedError(responses: responses)
    }

    return DefaultGenerateVideoResult(
        videos: videos,
        warnings: warnings,
        responses: responses,
        providerMetadata: providerMetadata
    )
}

private func mergeProviderMetadata(
    target: inout VideoModelProviderMetadata,
    source: VideoModelProviderMetadata
) {
    for (providerName, metadata) in source {
        if let existingMetadata = target[providerName] {
            var merged = existingMetadata

            // Merge object keys (last write wins).
            for (key, value) in metadata {
                merged[key] = value
            }

            // Merge `videos` arrays if present in both.
            if case .some(.array(let existingVideos)) = existingMetadata["videos"],
               case .some(.array(let newVideos)) = metadata["videos"] {
                merged["videos"] = .array(existingVideos + newVideos)
            }

            target[providerName] = merged
        } else {
            target[providerName] = metadata
        }
    }
}

private func invokeModelMaxVideosPerCall(_ model: VideoModel) async throws -> Int? {
    switch model.maxVideosPerCall {
    case .value(let value):
        return value
    case .default:
        return nil
    case .function(let fn):
        return try await fn(model.modelId)
    }
}

private func toVideoModelV3File(_ dataContent: DataContent) throws -> VideoModelV3File {
    switch dataContent {
    case .string(let string):
        if string.hasPrefix("http://") || string.hasPrefix("https://") {
            return .url(url: string, providerOptions: nil)
        }

        if string.hasPrefix("data:") {
            let (dataUrlMediaType, base64Content) = splitDataUrl(string)

            if let base64Content {
                let data = try convertBase64ToData(base64Content)
                let mediaType = dataUrlMediaType
                    ?? detectMediaType(data: data, signatures: imageMediaTypeSignatures)
                    ?? "image/png"
                return .file(mediaType: mediaType, data: .binary(data), providerOptions: nil)
            }
        }

        let data = try convertBase64ToData(string)
        let mediaType = detectMediaType(data: data, signatures: imageMediaTypeSignatures) ?? "image/png"
        return .file(mediaType: mediaType, data: .binary(data), providerOptions: nil)

    case .data(let data):
        let mediaType = detectMediaType(data: data, signatures: imageMediaTypeSignatures) ?? "image/png"
        return .file(mediaType: mediaType, data: .binary(data), providerOptions: nil)
    }
}
