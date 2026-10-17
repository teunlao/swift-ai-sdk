import Foundation
import AISDKProvider
import AISDKProviderUtils

struct AlibabaVideoModelConfig: Sendable {
    let provider: String
    let baseURL: String
    let headers: @Sendable () throws -> [String: String?]
    let fetch: FetchFunction?
    let currentDate: @Sendable () -> Date

    init(
        provider: String,
        baseURL: String,
        headers: @escaping @Sendable () throws -> [String: String?],
        fetch: FetchFunction?,
        currentDate: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.provider = provider
        self.baseURL = baseURL
        self.headers = headers
        self.fetch = fetch
        self.currentDate = currentDate
    }
}

public final class AlibabaVideoModel: VideoModelV4Operations {
    public var maxVideosPerCall: VideoModelV4MaxVideosPerCall { .value(1) }
    public var provider: String { config.provider }
    public var modelId: String { identifier.rawValue }
    private let identifier: AlibabaVideoModelId
    private let config: AlibabaVideoModelConfig

    init(modelId: AlibabaVideoModelId, config: AlibabaVideoModelConfig) {
        identifier = modelId
        self.config = config
    }

    public func doStart(options: VideoModelV4CallOptions, webhookUrl: String? = nil) async throws -> VideoModelV4OperationStartResult {
        let now = config.currentDate()
        let (body, warnings) = try await buildRequest(options)
        let response = try await postJsonToAPI(
            url: "\(config.baseURL)/api/v1/services/aigc/video-generation/video-synthesis",
            headers: combineHeaders(try config.headers(), options.headers?.mapValues(Optional.some), ["X-DashScope-Async": "enable"]).compactMapValues { $0 },
            body: JSONValue.object(body),
            failedResponseHandler: videoFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: videoCreateTaskSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )
        guard let taskId = response.value.output?.taskId, !taskId.isEmpty else {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.withoutEscapingSlashes]
            let json = String(decoding: try encoder.encode(response.value.raw), as: UTF8.self)
            throw VideoGenerationError(message: "No task_id returned from Alibaba API. Response: \(json)")
        }
        return .init(operation: ["taskId": .string(taskId)], warnings: warnings,
                     response: .init(timestamp: now, modelId: modelId, headers: response.responseHeaders))
    }

    public func doStatus(options: VideoModelV4StatusCallOptions) async throws -> VideoModelV4OperationStatusResult {
        let now = config.currentDate()
        guard case .object(let operation) = options.operation, case .string(let taskId) = operation["taskId"] else {
            throw InvalidArgumentError(argument: "operation", message: "Invalid Alibaba video operation")
        }
        let response = try await getFromAPI(
            url: "\(config.baseURL)/api/v1/tasks/\(taskId)",
            headers: combineHeaders(try config.headers(), options.headers?.mapValues(Optional.some)).compactMapValues { $0 },
            failedResponseHandler: videoFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: videoTaskStatusSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch,
            validateUrl: false
        )
        let info = VideoModelV4ResponseInfo(timestamp: now, modelId: modelId, headers: response.responseHeaders)
        let status = response.value
        if status.output?.taskStatus == "SUCCEEDED" {
            guard let output = status.output, let videoUrl = output.videoUrl, !videoUrl.isEmpty else {
                throw VideoGenerationError(message: "No video URL in response. Task ID: \(status.output?.taskId ?? "undefined")")
            }
            var metadata: JSONObject = ["taskId": .string(output.taskId), "videoUrl": .string(videoUrl)]
            if let prompt = output.actualPrompt, !prompt.isEmpty { metadata["actualPrompt"] = .string(prompt) }
            if let usage = status.usage {
                var values: JSONObject = [:]
                for (wire, field) in [("duration", "duration"), ("output_video_duration", "outputVideoDuration"), ("SR", "resolution"), ("size", "size")] {
                    values[field] = usage.fields[wire]
                }
                for (wire, field) in [("input_video_duration", "inputVideoDuration"), ("fps", "fps"), ("ratio", "ratio")] {
                    if let value = usage.fields[wire], value != .null { values[field] = value }
                }
                metadata["usage"] = .object(values)
            }
            return .completed(videos: [.url(url: videoUrl, mediaType: "video/mp4")], warnings: [],
                              providerMetadata: ["alibaba": metadata], response: info)
        }
        if let taskStatus = status.output?.taskStatus, taskStatus == "FAILED" || taskStatus == "CANCELED" {
            let error = "Video generation \(taskStatus.lowercased()). Task ID: \(taskId). \(status.output?.message ?? "")"
            return .error(error: error.trimmingCharacters(in: videoWhitespace), providerMetadata: nil, response: info)
        }
        return .pending(warnings: nil, providerMetadata: nil, response: info)
    }

    private func buildRequest(_ options: VideoModelV4CallOptions) async throws -> (JSONObject, [SharedV4Warning]) {
        let settings = try await parseProviderOptions(provider: "alibaba", providerOptions: options.providerOptions, schema: alibabaVideoModelOptionsSchema)
        let mode = VideoMode(modelId)
        let wire = VideoProtocol(modelId)
        let tiered = wire != .sizeAndReferences
        let supportsRatio = wire == .allInOneMedia || (wire == .tieredMedia && mode != .i2v)
        let firstFrame = options.frameImages?.first { $0.frameType == .firstFrame }?.image
        let lastFrame = options.frameImages?.first { $0.frameType == .lastFrame }?.image
        let startImage = firstFrame ?? options.image
        var warnings: [SharedV4Warning] = []
        var input: JSONObject = [:]
        if let prompt = options.prompt { input["prompt"] = .string(prompt) }
        if let prompt = settings?.negativePrompt { input["negative_prompt"] = .string(prompt) }
        if let url = settings?.audioUrl { input["audio_url"] = .string(url) }
        if wire != .allInOneMedia, mode == .i2v, let startImage {
            input["img_url"] = .string(imageString(startImage))
        }
        if wire == .allInOneMedia {
            if let media = resolveMedia(options, settings, first: startImage, last: lastFrame, warnings: &warnings) { input["media"] = .array(media) }
        } else if mode == .r2v {
            if wire == .tieredMedia {
                if let media = resolveMedia(options, settings, first: firstFrame, last: nil, warnings: &warnings) { input["media"] = .array(media) }
            } else if let references = resolveReferenceUrls(options, settings, warnings: &warnings), !references.isEmpty {
                input["reference_urls"] = .array(references.map(JSONValue.string))
            }
        }
        if lastFrame != nil, wire != .allInOneMedia {
            warnings.append(.unsupported(feature: "frameImages", details: "This model does not support last_frame. The last frame image was ignored."))
        }
        if options.inputReferences?.isEmpty == false, mode != .r2v, wire != .allInOneMedia {
            warnings.append(.unsupported(feature: "inputReferences", details: "Alibaba only supports inputReferences (reference-to-video) on reference-to-video models. The reference images were ignored."))
        }
        var parameters: JSONObject = [:]
        if let duration = options.duration { parameters["duration"] = .number(Double(duration)) }
        if let seed = options.seed { parameters["seed"] = .number(Double(seed)) }
        if let resolution = options.resolution {
            if mode == .i2v || tiered {
                let tier = resolutionTiers[resolution] ?? resolution
                let supported = wire == .allInOneMedia ? ["480P", "720P", "1080P"] : ["720P", "1080P"]
                if tiered, !supported.contains(tier) {
                    let name = wire == .allInOneMedia ? "wan3" : "wan2.7"
                    warnings.append(.unsupported(feature: "resolution", details: "\(name) models only support the \(supported.joined(separator: ", ")) resolution tiers. The resolution \"\(resolution)\" was ignored."))
                } else { parameters["resolution"] = .string(tier) }
            } else {
                var size = resolution
                if let range = size.range(of: "x") { size.replaceSubrange(range, with: "*") }
                parameters["size"] = .string(size)
            }
        }
        if supportsRatio, let ratio = settings?.ratio?.rawValue ?? options.aspectRatio ?? options.resolution.flatMap(deriveRatio) {
            parameters["ratio"] = .string(ratio)
        }
        if let extend = settings?.promptExtend { parameters["prompt_extend"] = .bool(extend) }
        if let shot = settings?.shotType {
            if tiered {
                let name = wire == .allInOneMedia ? "wan3" : "wan2.7"
                warnings.append(.unsupported(feature: "shotType", details: "\(name) models do not support the shotType option. Describe the shot structure in the prompt instead."))
            } else { parameters["shot_type"] = .string(shot.rawValue) }
        }
        if let watermark = settings?.watermark { parameters["watermark"] = .bool(watermark) }
        if let audio = options.generateAudio ?? settings?.audio {
            if wire == .tieredMedia {
                warnings.append(.unsupported(feature: "generateAudio", details: "wan2.7 models always generate audio. The audio option was ignored."))
            } else { parameters["audio"] = .bool(audio) }
        }
        if let ratio = options.aspectRatio, !ratio.isEmpty, !supportsRatio {
            warnings.append(.unsupported(feature: "aspectRatio", details: "Alibaba video models use explicit size/resolution dimensions. Use the resolution option or providerOptions.alibaba for size control."))
        }
        if let fps = options.fps, fps != 0 {
            warnings.append(.unsupported(feature: "fps", details: "Alibaba video models do not support custom FPS."))
        }
        if options.n > 1 {
            warnings.append(.unsupported(feature: "n", details: "Alibaba video models only support generating 1 video per call."))
        }
        return (["model": .string(modelId), "input": .object(input), "parameters": .object(parameters)], warnings)
    }
}

private enum VideoMode {
    case t2v, i2v, r2v
    init(_ id: String) {
        self = id.contains("-i2v") ? .i2v : id.contains("-r2v") ? .r2v : .t2v
    }
}

private enum VideoProtocol {
    case sizeAndReferences, tieredMedia, allInOneMedia
    private static let version = try! NSRegularExpression(pattern: "^wanx?(\\d+)(?:\\.(\\d+))?(?=[.-]|$)")
    init(_ id: String) {
        guard let match = Self.version.firstMatch(in: id, range: NSRange(id.startIndex..., in: id)),
              let majorRange = Range(match.range(at: 1), in: id), let major = Double(id[majorRange]) else {
            self = .allInOneMedia; return
        }
        let minor = Range(match.range(at: 2), in: id).flatMap { Double(id[$0]) } ?? 0
        self = major < 2 || (major == 2 && minor < 7) ? .sizeAndReferences : major == 2 ? .tieredMedia : .allInOneMedia
    }
}

private let resolutionTiers = [
    "1280x720": "720P", "720x1280": "720P", "960x960": "720P", "1088x832": "720P", "832x1088": "720P",
    "1920x1080": "1080P", "1080x1920": "1080P", "1440x1440": "1080P", "1632x1248": "1080P", "1248x1632": "1080P",
    "832x480": "480P", "480x832": "480P", "624x624": "480P"
]

private func deriveRatio(_ resolution: String) -> String? {
    let parts = resolution.components(separatedBy: "x")
    guard parts.count >= 2,
          let width = Double(parts[0].trimmingCharacters(in: videoWhitespace)),
          let height = Double(parts[1].trimmingCharacters(in: videoWhitespace)),
          width.isFinite, height.isFinite, width.rounded() == width, height.rounded() == height, width > 0, height > 0 else { return nil }
    var a = width
    var b = height
    while b != 0 { (a, b) = (b, a.truncatingRemainder(dividingBy: b)) }
    let numerator = width / a
    let denominator = height / a
    for (left, right, ratio) in [(16.0, 9.0, "16:9"), (9, 16, "9:16"), (1, 1, "1:1"), (4, 3, "4:3"), (3, 4, "3:4")] {
        if numerator == left, denominator == right { return ratio }
    }
    return nil
}

private func imageString(_ file: VideoModelV4File) -> String {
    switch file {
    case .url(let url, _, _): url
    case .file(_, .base64(let value), _): value
    case .file(_, .binary(let value), _): value.base64EncodedString()
    }
}

private func imageDataURI(_ file: VideoModelV4File) -> String {
    let image: ImageModelV4File
    switch file {
    case .url(let url, _, let options): image = .url(url: url, providerOptions: options)
    case .file(let type, .base64(let data), let options): image = .file(mediaType: type, data: .base64(data), providerOptions: options)
    case .file(let type, .binary(let data), let options): image = .file(mediaType: type, data: .binary(data), providerOptions: options)
    }
    return convertImageModelFileToDataURI(image)
}

private let videoURLPattern = try! NSRegularExpression(pattern: "\\.(mp4|mov)([?#]|$)", options: .caseInsensitive)

private func resolveMedia(
    _ options: VideoModelV4CallOptions,
    _ settings: AlibabaVideoModelOptions?,
    first: VideoModelV4File?, last: VideoModelV4File?, warnings: inout [SharedV4Warning]
) -> [JSONValue]? {
    if let media = settings?.media, !media.isEmpty {
        return media.map { item in
            var result: JSONObject = ["type": .string(item.type.rawValue), "url": .string(item.url)]
            if let voice = item.referenceVoice { result["reference_voice"] = .string(voice) }
            return .object(result)
        }
    }
    var media: [JSONValue] = []
    for reference in options.inputReferences ?? [] {
        switch reference {
        case .url(let url, _, _):
            let isVideo = videoURLPattern.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)) != nil
            media.append(["type": .string(isVideo ? "reference_video" : "reference_image"), "url": .string(url)])
        case .file(let type, _, _) where type.hasPrefix("image/"):
            media.append(["type": "reference_image", "url": .string(imageDataURI(reference))])
        default:
            warnings.append(.unsupported(feature: "inputReferences", details: "Alibaba reference-to-video requires URL references for videos. Non-URL video reference was skipped."))
        }
    }
    if let first { media.append(["type": "first_frame", "url": .string(imageDataURI(first))]) }
    if let last { media.append(["type": "last_frame", "url": .string(imageDataURI(last))]) }
    return media.isEmpty ? nil : media
}

private func resolveReferenceUrls(
    _ options: VideoModelV4CallOptions, _ settings: AlibabaVideoModelOptions?, warnings: inout [SharedV4Warning]
) -> [String]? {
    if options.frameImages?.isEmpty == false { return nil }
    if let references = options.inputReferences, !references.isEmpty {
        var urls: [String] = []
        for reference in references {
            if case .url(let url, _, _) = reference { urls.append(url) }
            else { warnings.append(.unsupported(feature: "inputReferences", details: "Alibaba reference-to-video requires URL references. Non-URL reference was skipped.")) }
        }
        return urls.isEmpty ? nil : urls
    }
    return settings?.referenceUrls
}

private let videoWhitespace = CharacterSet(charactersIn: "\u{0009}\u{000A}\u{000B}\u{000C}\u{000D}\u{0020}\u{00A0}\u{1680}\u{2000}\u{2001}\u{2002}\u{2003}\u{2004}\u{2005}\u{2006}\u{2007}\u{2008}\u{2009}\u{200A}\u{2028}\u{2029}\u{202F}\u{205F}\u{3000}\u{FEFF}")
