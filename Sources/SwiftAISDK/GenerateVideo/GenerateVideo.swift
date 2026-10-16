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
    func normalize() throws -> (prompt: String?, image: VideoModelV4File?) {
        switch self {
        case .text(let text):
            return (prompt: text, image: nil)

        case .imageToVideo(let image, let text):
            return (prompt: text, image: try toVideoModelV4File(image))
        }
    }
}

public struct GenerateVideoInputReference: Sendable {
    public let data: DataContent
    public let mediaType: String?

    public init(data: DataContent, mediaType: String? = nil) {
        self.data = data
        self.mediaType = mediaType
    }

    func normalize() throws -> VideoModelV4File {
        let normalized = try toVideoModelV4File(data, restrictToImages: false)
        guard let mediaType else { return normalized }
        switch normalized {
        case .file(_, let data, let options):
            return .file(mediaType: mediaType, data: data, providerOptions: options)
        case .url(let url, _, let options):
            return .url(url: url, mediaType: mediaType, providerOptions: options)
        }
    }
}

public struct GenerateVideoFrameImage: Sendable {
    public let image: DataContent
    public let frameType: VideoModelV4FrameType

    public init(image: DataContent, frameType: VideoModelV4FrameType) {
        self.image = image
        self.frameType = frameType
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
    frameImages: [GenerateVideoFrameImage]? = nil,
    inputReferences: [DataContent]? = nil,
    generateAudio: Bool? = nil,
    providerOptions: ProviderOptions? = nil,
    maxRetries: Int? = nil,
    abortSignal: (@Sendable () -> Bool)? = nil,
    headers: [String: String]? = nil,
    experimentalDownload download: DownloadFileFunction? = nil,
    poll: GenerateVideoPollOptions? = nil,
    webhook: GenerateVideoWebhookFactory? = nil,
    referenceInputs: [VideoModelV4File]? = nil
) async throws -> DefaultGenerateVideoResult {
    let resolvedModel = try resolveVideoModelV4(model)
    let normalizedPrompt = try prompt.normalize()
    let normalizedFrameImages = try frameImages?.map { frame in
        VideoModelV4FrameImage(
            image: try toVideoModelV4File(frame.image),
            frameType: frame.frameType
        )
    }
    let normalizedInputReferences = try referenceInputs ?? inputReferences?.map { try toVideoModelV4File($0, restrictToImages: false) }
    let hasFrameImages = normalizedFrameImages?.isEmpty == false
    let hasInputReferences = normalizedInputReferences?.isEmpty == false

    let effectiveInputReferences = hasFrameImages ? nil : normalizedInputReferences
    let firstFrameImage = normalizedFrameImages?.first { $0.frameType == .firstFrame }?.image
    let resolvedImage = firstFrameImage ?? normalizedPrompt.image

    var warnings: [VideoGenerationWarning] = []
    if hasFrameImages && hasInputReferences {
        warnings.append(
            .other(
                message: "inputReferences were ignored because frameImages were provided; frameImages and inputReferences cannot be combined."
            )
        )
    }

    if normalizedPrompt.image != nil && firstFrameImage != nil {
        warnings.append(
            .other(
                message: "prompt.image was ignored because a first_frame frameImage was provided; the first_frame frameImage takes precedence as the start image."
            )
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

    let maxVideosPerCallResolved: Int
    if let override = maxVideosPerCall {
        maxVideosPerCallResolved = override
    } else {
        let modelLimit = try await invokeModelMaxVideosPerCall(resolvedModel)
        maxVideosPerCallResolved = modelLimit ?? 1
    }

    guard maxVideosPerCallResolved > 0 else {
        throw InvalidArgumentError(argument: "maxVideosPerCall", message: "maxVideosPerCall must be greater than 0")
    }
    let videoCount = max(n, 0)
    let callCount = videoCount / maxVideosPerCallResolved + (videoCount % maxVideosPerCallResolved == 0 ? 0 : 1)

    let callVideoCounts = (0..<callCount).map { index -> Int in
        let remaining = n - index * maxVideosPerCallResolved
        return min(remaining, maxVideosPerCallResolved)
    }

    let generator = resolvedModel as? any VideoModelV4Generator
    let operations = resolvedModel as? any VideoModelV4Operations
    let useStartStatus = operations != nil && (poll != nil || webhook != nil || generator == nil)
    guard generator != nil || operations != nil else {
        throw VideoGenerationFailure(message: "Video model \(resolvedModel.modelId) does not implement doGenerate or doStart/doStatus.")
    }
    if (poll != nil || webhook != nil) && operations == nil {
        logWarnings([.videoModel(.other(message: "poll/webhook options were provided but the model does not support doStart/doStatus. Falling back to doGenerate."))])
    }

    let results = try await withThrowingTaskGroup(of: (Int, VideoModelV4GenerateResult).self) { group in
        for (index, videosInCall) in callVideoCounts.enumerated() {
            group.addTask {
                var callHeaders = headersWithUserAgent
                if useStartStatus && !callHeaders.keys.contains(where: { $0.lowercased() == "idempotency-key" }) {
                    callHeaders["idempotency-key"] = "aisdk_vid_\(generateID())"
                }
                let options = VideoModelV4CallOptions(
                    prompt: normalizedPrompt.prompt, n: videosInCall,
                    aspectRatio: aspectRatio, resolution: resolution, duration: duration,
                    fps: fps, seed: seed, image: resolvedImage,
                    frameImages: normalizedFrameImages, inputReferences: effectiveInputReferences,
                    generateAudio: generateAudio, providerOptions: providerOptions ?? [:],
                    abortSignal: abortSignal, headers: callHeaders
                )
                let result: VideoModelV4GenerateResult
                if useStartStatus, let operations {
                    result = try await executeVideoOperation(
                        model: operations, options: options, statusHeaders: headersWithUserAgent,
                        poll: poll, webhook: webhook, retries: preparedRetries
                    )
                } else if let generator {
                    result = try await preparedRetries.retry.call { try await generator.doGenerate(options: options) }
                } else {
                    throw VideoGenerationFailure(message: "Video generation capability unavailable.")
                }
                return (index, result)
            }
        }
        var ordered = Array<VideoModelV4GenerateResult?>(repeating: nil, count: callVideoCounts.count)
        for try await (index, result) in group { ordered[index] = result }
        return ordered.compactMap { $0 }
    }

    var videos: [GeneratedFile] = []
    var responses: [VideoModelResponseMetadata] = []
    responses.reserveCapacity(results.count)

    var providerMetadata: VideoModelProviderMetadata = [:]
    let downloadFile = download ?? createDownload()

    for result in results {
        for videoData in result.videos {
            switch videoData {
            case .url(let urlString, let providerMediaType):
                guard let url = URL(string: urlString) else {
                    throw DownloadError(url: urlString, cause: URLError(.badURL))
                }

                let downloadResult = try await downloadFile(
                    DownloadFileRequest(
                        url: url,
                        abortSignal: abortSignal
                    )
                )

                func isUsableMediaType(_ type: String?) -> Bool {
                    guard let type else { return false }
                    return type != "application/octet-stream"
                }

                let mediaType: String
                if isUsableMediaType(providerMediaType) {
                    mediaType = providerMediaType
                } else if isUsableMediaType(downloadResult.mediaType), let downloadedType = downloadResult.mediaType {
                    mediaType = downloadedType
                } else {
                    mediaType = AISDKProviderUtils.detectMediaType(data: downloadResult.data, topLevelType: "video") ?? "video/mp4"
                }

                videos.append(
                    DefaultGeneratedFile(data: downloadResult.data, mediaType: mediaType)
                )

            case .base64(let base64, let mediaType):
                videos.append(
                    DefaultGeneratedFile(base64: base64, mediaType: mediaType.isEmpty ? "video/mp4" : mediaType)
                )

            case .binary(let data, let mediaType):
                let detected = AISDKProviderUtils.detectMediaType(data: data, topLevelType: "video")
                let resolvedMediaType = mediaType.isEmpty ? (detected ?? "video/mp4") : mediaType

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
            mergeVideoProviderMetadata(target: &providerMetadata, source: metadata)
        }
    }

    if videos.isEmpty {
        throw NoVideoGeneratedError(responses: responses)
    }

    if !warnings.isEmpty {
        logWarnings(warnings.map { Warning.videoModel($0) })
    }

    return DefaultGenerateVideoResult(
        videos: videos,
        warnings: warnings,
        responses: responses,
        providerMetadata: providerMetadata
    )
}

func mergeVideoProviderMetadata(
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

private func invokeModelMaxVideosPerCall(_ model: any VideoModelV4) async throws -> Int? {
    switch model.maxVideosPerCall {
    case .value(let value):
        return value
    case .default:
        return nil
    case .function(let fn):
        return try await fn(model.modelId)
    }
}

func toVideoModelV4File(_ dataContent: DataContent, restrictToImages: Bool = true) throws -> VideoModelV4File {
    let topLevelType: String? = restrictToImages ? "image" : nil
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
                    ?? detectMediaType(data: data, topLevelType: topLevelType)
                    ?? "image/png"
                return .file(mediaType: mediaType, data: .binary(data), providerOptions: nil)
            }
        }

        let data = try convertBase64ToData(string)
        let mediaType = detectMediaType(data: data, topLevelType: topLevelType) ?? "image/png"
        return .file(mediaType: mediaType, data: .binary(data), providerOptions: nil)

    case .data(let data):
        let mediaType = detectMediaType(data: data, topLevelType: topLevelType) ?? "image/png"
        return .file(mediaType: mediaType, data: .binary(data), providerOptions: nil)
    }
}
