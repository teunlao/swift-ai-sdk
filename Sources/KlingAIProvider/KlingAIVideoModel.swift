import Foundation
import AISDKProvider
import AISDKProviderUtils

struct KlingAIVideoModelConfig: Sendable {
    let provider: String
    let baseURL: String
    let headers: @Sendable () async throws -> [String: String?]
    let fetch: FetchFunction?
    var currentDate: @Sendable () -> Date = { Date() }
}

private struct KlingAIResponse: Codable, Sendable {
    struct TaskInfo: Codable, Sendable { let external_task_id: String? }
    struct Watermark: Codable, Sendable { let enabled: Bool? }
    struct Video: Codable, Sendable {
        let id: String?
        let url: String?
        let watermark_url: String?
        let duration: String?
    }
    struct TaskResult: Codable, Sendable { let videos: [Video]? }
    struct TaskData: Codable, Sendable {
        let task_id: String
        let task_status: String?
        let task_status_msg: String?
        let task_info: TaskInfo?
        let watermark_info: Watermark?
        let final_unit_deduction: String?
        let created_at: Double?
        let updated_at: Double?
        let task_result: TaskResult?
    }
    let code: Double
    let message: String
    let request_id: String?
    let data: TaskData?
}

private let klingaiCreateSchema = FlexibleSchema(Schema<KlingAIResponse>.codable(KlingAIResponse.self, jsonSchema: .object(["type": .string("object")])))
private let klingaiStatusSchema = FlexibleSchema(Schema<KlingAIResponse>(jsonSchemaResolver: { .object(["type": .string("object")]) }, validator: { value in
    do {
        let response = try JSONDecoder().decode(KlingAIResponse.self, from: JSONEncoder().encode(jsonValue(from: value)))
        if let data = response.data, data.task_status == nil { throw InvalidResponseDataError(data: value, message: "Missing task_status") }
        return .success(value: response)
    } catch { return .failure(error: TypeValidationError.wrap(value: value, cause: error)) }
}))

public final class KlingAIVideoModel: VideoModelV4Operations {
    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }
    public var maxVideosPerCall: VideoModelV4MaxVideosPerCall { .value(1) }
    private let modelIdentifier: KlingAIVideoModelId
    private let config: KlingAIVideoModelConfig

    init(modelId: KlingAIVideoModelId, config: KlingAIVideoModelConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public func doStart(options: VideoModelV4CallOptions, webhookUrl: String? = nil) async throws -> VideoModelV4OperationStartResult {
        let timestamp = config.currentDate()
        let mode: String
        if modelId.hasSuffix("-t2v") { mode = "t2v" }
        else if modelId.hasSuffix("-i2v") { mode = "i2v" }
        else if modelId.hasSuffix("-motion-control") { mode = "motion-control" }
        else { throw NoSuchModelError(modelId: modelId, modelType: .videoModel) }
        let providerOptions = try await klingaiOptions(options.providerOptions)
        var warnings: [SharedV4Warning] = []
        var references: [VideoModelV4File] = []
        if options.frameImages?.isEmpty ?? true {
            for file in options.inputReferences ?? [] {
                if isVideo(file) { warnings.append(.unsupported(feature: "inputReferences", details: "KlingAI does not support video reference inputs; the video reference was ignored.")) }
                else { references.append(file) }
            }
        }
        let effectiveMode = mode == "i2v" && !references.isEmpty ? "mi2v" : mode
        let endpoint = ["t2v": "/v1/videos/text2video", "i2v": "/v1/videos/image2video", "mi2v": "/v1/videos/multi-image2video", "motion-control": "/v1/videos/motion-control"][effectiveMode]!
        let suffix = mode == "motion-control" ? "-motion-control" : "-\(mode)"
        var name = String(modelId.dropLast(suffix.count))
        if name.hasSuffix(".0") { name.removeLast(2) }
        name = name.replacingOccurrences(of: ".", with: "-")
        var body: [String: JSONValue] = ["model_name": .string(name)]
        if let prompt = options.prompt { body["prompt"] = .string(prompt) }
        func add(_ key: String, _ field: String) {
            if let value = providerOptions[key], value != .null { body[field] = value }
        }
        func firstImage() -> VideoModelV4File? {
            guard let file = options.frameImages?.first(where: { $0.frameType == .firstFrame })?.image ?? options.image else { return nil }
            if isVideo(file) {
                warnings.append(.unsupported(feature: "frameImages", details: "KlingAI does not accept video as a frame image; it was ignored."))
                return nil
            }
            return file
        }
        func lastImage() -> String? {
            if let file = options.frameImages?.first(where: { $0.frameType == .lastFrame })?.image {
                if isVideo(file) {
                    warnings.append(.unsupported(feature: "frameImages", details: "KlingAI does not accept video as a frame image; it was ignored."))
                    return nil
                }
                return imageString(file)
            }
            if case .string(let value) = providerOptions["imageTail"] { return value }
            return nil
        }
        switch effectiveMode {
        case "motion-control":
            guard case .string(let videoURL) = providerOptions["videoUrl"], !videoURL.isEmpty,
                  case .string(let orientation) = providerOptions["characterOrientation"],
                  case .string(let quality) = providerOptions["mode"] else {
                throw KlingAIVideoModelError(name: "KLINGAI_VIDEO_MISSING_OPTIONS", message: "KlingAI Motion Control requires providerOptions.klingai with videoUrl, characterOrientation, and mode.")
            }
            body["video_url"] = .string(videoURL)
            body["character_orientation"] = .string(orientation)
            body["mode"] = .string(quality)
            if let image = firstImage() { body["image_url"] = .string(imageString(image)) }
            add("keepOriginalSound", "keep_original_sound")
            add("elementList", "element_list")
            if let aspect = options.aspectRatio, !aspect.isEmpty { warnings.append(.unsupported(feature: "aspectRatio", details: "KlingAI Motion Control does not support aspectRatio. The output dimensions are determined by the reference image/video.")) }
            if let duration = options.duration, duration != 0 { warnings.append(.unsupported(feature: "duration", details: "KlingAI Motion Control does not support custom duration. The output duration matches the reference video duration.")) }
        default:
            add("negativePrompt", "negative_prompt")
            add("cfgScale", "cfg_scale")
            add("mode", "mode")
            if let duration = options.duration { body["duration"] = .string(String(duration)) }
            if effectiveMode == "mi2v" {
                body["image_list"] = .array(references.map { .object(["image": .string(imageString($0))]) })
                if let aspect = options.aspectRatio { body["aspect_ratio"] = .string(aspect) }
                if firstImage() != nil { warnings.append(.unsupported(feature: "image", details: "KlingAI reference-to-video does not support a separate start frame. Provide all guidance images via inputReferences instead.")) }
                if lastImage() != nil { warnings.append(.unsupported(feature: "frameImages", details: "KlingAI reference-to-video does not support a last frame (image_tail). Provide all guidance images via inputReferences instead.")) }
            } else {
                if let audio = options.generateAudio { body["sound"] = .string(audio ? "on" : "off") } else { add("sound", "sound") }
                add("cameraControl", "camera_control")
                add("multiShot", "multi_shot")
                add("shotType", "shot_type")
                add("multiPrompt", "multi_prompt")
                add("voiceList", "voice_list")
                if effectiveMode == "t2v" {
                    if let aspect = options.aspectRatio { body["aspect_ratio"] = .string(aspect) }
                    if firstImage() != nil { warnings.append(.unsupported(feature: "image", details: "KlingAI text-to-video does not support image input. Use an image-to-video model instead.")) }
                } else {
                    if let image = firstImage() { body["image"] = .string(imageString(image)) }
                    if let image = lastImage() { body["image_tail"] = .string(image) }
                    add("staticMask", "static_mask")
                    add("dynamicMasks", "dynamic_masks")
                    add("elementList", "element_list")
                    if options.aspectRatio != nil { warnings.append(.unsupported(feature: "aspectRatio", details: "KlingAI image-to-video does not support aspectRatio. The output dimensions are determined by the input image.")) }
                }
            }
        }
        if let enabled = providerOptions["watermarkEnabled"], enabled != .null { body["watermark_info"] = .object(["enabled": enabled]) }
        for (key, value) in providerOptions where !klingaiHandledOptions.contains(key) { body[key] = value }
        if !references.isEmpty, effectiveMode != "mi2v" { warnings.append(.unsupported(feature: "inputReferences", details: "KlingAI only supports inputReferences (reference-to-video) on image-to-video models. The reference images were ignored.")) }
        if let webhookUrl { body["callback_url"] = .string(webhookUrl) }
        if let value = options.resolution, !value.isEmpty { warnings.append(.unsupported(feature: "resolution", details: "KlingAI video models do not support the resolution option.")) }
        if let value = options.seed, value != 0 { warnings.append(.unsupported(feature: "seed", details: "KlingAI video models do not support seed for deterministic generation.")) }
        if let value = options.fps, value != 0 { warnings.append(.unsupported(feature: "fps", details: "KlingAI video models do not support custom FPS.")) }
        if options.n > 1 { warnings.append(.unsupported(feature: "n", details: "KlingAI video models do not support generating multiple videos per call. Only 1 video will be generated.")) }
        let result = try await postJsonToAPI(
            url: "\(config.baseURL)\(endpoint)", headers: combineHeaders(try await config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 }, body: JSONValue.object(body),
            failedResponseHandler: klingaiFailedResponseHandler, successfulResponseHandler: createJsonResponseHandler(responseSchema: klingaiCreateSchema), isAborted: options.abortSignal, fetch: config.fetch
        )
        guard let id = result.value.data?.task_id, !id.isEmpty else { throw KlingAIVideoModelError(name: "KLINGAI_VIDEO_GENERATION_ERROR", message: "No task_id returned from KlingAI API. Response: \(responseJSON(result.value))") }
        return .init(operation: .object(["taskId": .string(id), "endpointPath": .string(endpoint)]), warnings: warnings, response: .init(timestamp: timestamp, modelId: modelId, headers: result.responseHeaders))
    }

    public func doStatus(options: VideoModelV4StatusCallOptions) async throws -> VideoModelV4OperationStatusResult {
        let timestamp = config.currentDate()
        guard case .object(let operation) = options.operation, case .string(let id) = operation["taskId"], case .string(let endpoint) = operation["endpointPath"] else { throw InvalidArgumentError(argument: "operation", message: "Invalid KlingAI video operation") }
        let result = try await getFromAPI(
            url: "\(config.baseURL)\(endpoint)/\(id)", headers: combineHeaders(try await config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 },
            failedResponseHandler: klingaiFailedResponseHandler, successfulResponseHandler: createJsonResponseHandler(responseSchema: klingaiStatusSchema), isAborted: options.abortSignal, fetch: config.fetch, validateUrl: true, trustedOrigin: config.baseURL
        )
        let response = VideoModelV4ResponseInfo(timestamp: timestamp, modelId: modelId, headers: result.responseHeaders)
        if result.value.data?.task_status == "failed" { return .error(error: "Video generation failed: \(result.value.data?.task_status_msg ?? "Unknown error")", providerMetadata: nil, response: response) }
        guard result.value.data?.task_status == "succeed" else { return .pending(warnings: nil, providerMetadata: nil, response: response) }
        guard let output = result.value.data?.task_result?.videos, !output.isEmpty else { throw KlingAIVideoModelError(name: "KLINGAI_VIDEO_GENERATION_ERROR", message: "No videos in response. Response: \(responseJSON(result.value))") }
        var videos: [VideoModelV4VideoData] = []
        var metadata: [JSONValue] = []
        for video in output {
            guard let url = video.url, !url.isEmpty else { continue }
            videos.append(.url(url: url, mediaType: "video/mp4"))
            var value: [String: JSONValue] = ["id": .string(video.id ?? ""), "url": .string(url)]
            if let watermark = video.watermark_url, !watermark.isEmpty { value["watermarkUrl"] = .string(watermark) }
            if let duration = video.duration, !duration.isEmpty { value["duration"] = .string(duration) }
            metadata.append(.object(value))
        }
        guard !videos.isEmpty else { throw KlingAIVideoModelError(name: "KLINGAI_VIDEO_GENERATION_ERROR", message: "No valid video URLs in response") }
        return .completed(videos: videos, warnings: [], providerMetadata: ["klingai": ["taskId": .string(id), "videos": .array(metadata)]], response: response)
    }

    private func isVideo(_ file: VideoModelV4File) -> Bool {
        switch file {
        case .url(_, let type, _): return type?.components(separatedBy: "/").first == "video"
        case .file(let type, _, _): return type.components(separatedBy: "/").first == "video"
        }
    }
    private func imageString(_ file: VideoModelV4File) -> String {
        switch file {
        case .url(let url, _, _): return url
        case .file(_, let data, _):
            switch data {
            case .base64(let value): return value
            case .binary(let value): return value.base64EncodedString()
            }
        }
    }
    private func responseJSON(_ response: KlingAIResponse) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? String(data: encoder.encode(response), encoding: .utf8)) ?? "{}"
    }
}

private struct KlingAIVideoModelError: AISDKError, Sendable {
    static let errorDomain = "klingai.video.error"
    let name: String
    let message: String
    let cause: (any Error)? = nil
}
