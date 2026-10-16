import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct ByteDanceVideoModelOptions: Decodable, Sendable {
    public enum ServiceTier: String, Decodable, Sendable { case `default`, flex }
    public let watermark: Bool?
    public let generateAudio: Bool?
    public let cameraFixed: Bool?
    public let returnLastFrame: Bool?
    public let serviceTier: ServiceTier?
    public let draft: Bool?
    public let lastFrameImage: String?
    public let referenceImages: [String]?
    public let referenceVideos: [String]?
    public let referenceAudio: [String]?
    public let pollIntervalMs: Double?
    public let pollTimeoutMs: Double?
    public let additionalOptions: JSONObject

    public init(
        watermark: Bool? = nil, generateAudio: Bool? = nil, cameraFixed: Bool? = nil,
        returnLastFrame: Bool? = nil, serviceTier: ServiceTier? = nil, draft: Bool? = nil,
        lastFrameImage: String? = nil, referenceImages: [String]? = nil, referenceVideos: [String]? = nil,
        referenceAudio: [String]? = nil, pollIntervalMs: Double? = nil, pollTimeoutMs: Double? = nil,
        additionalOptions: JSONObject = [:]
    ) throws {
        for value in [pollIntervalMs, pollTimeoutMs].compactMap({ $0 }) where value <= 0 || !value.isFinite {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Poll interval and timeout must be positive numbers"))
        }
        self.watermark = watermark
        self.generateAudio = generateAudio
        self.cameraFixed = cameraFixed
        self.returnLastFrame = returnLastFrame
        self.serviceTier = serviceTier
        self.draft = draft
        self.lastFrameImage = lastFrameImage
        self.referenceImages = referenceImages
        self.referenceVideos = referenceVideos
        self.referenceAudio = referenceAudio
        self.pollIntervalMs = pollIntervalMs
        self.pollTimeoutMs = pollTimeoutMs
        self.additionalOptions = additionalOptions
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case watermark, generateAudio, cameraFixed, returnLastFrame, serviceTier, draft, lastFrameImage
        case referenceImages, referenceVideos, referenceAudio, pollIntervalMs, pollTimeoutMs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try decoder.singleValueContainer().decode(JSONObject.self)
        let known = Set(CodingKeys.allCases.map(\.rawValue))
        try self.init(
            watermark: container.decodeIfPresent(Bool.self, forKey: .watermark),
            generateAudio: container.decodeIfPresent(Bool.self, forKey: .generateAudio),
            cameraFixed: container.decodeIfPresent(Bool.self, forKey: .cameraFixed),
            returnLastFrame: container.decodeIfPresent(Bool.self, forKey: .returnLastFrame),
            serviceTier: container.decodeIfPresent(ServiceTier.self, forKey: .serviceTier),
            draft: container.decodeIfPresent(Bool.self, forKey: .draft),
            lastFrameImage: container.decodeIfPresent(String.self, forKey: .lastFrameImage),
            referenceImages: container.decodeIfPresent([String].self, forKey: .referenceImages),
            referenceVideos: container.decodeIfPresent([String].self, forKey: .referenceVideos),
            referenceAudio: container.decodeIfPresent([String].self, forKey: .referenceAudio),
            pollIntervalMs: container.decodeIfPresent(Double.self, forKey: .pollIntervalMs),
            pollTimeoutMs: container.decodeIfPresent(Double.self, forKey: .pollTimeoutMs),
            additionalOptions: raw.filter { !known.contains($0.key) }
        )
    }
}

private let byteDanceVideoModelOptionsSchema = FlexibleSchema(
    Schema<ByteDanceVideoModelOptions>.codable(ByteDanceVideoModelOptions.self, jsonSchema: .object(["type": .string("object")]))
)

public final class ByteDanceVideoModel: VideoModelV4Operations {
    public var specificationVersion: String { "v4" }
    public var maxVideosPerCall: VideoModelV4MaxVideosPerCall { .value(1) }
    public var provider: String { config.provider }
    public var modelId: String { identifier.rawValue }
    private let identifier: ByteDanceVideoModelId
    private let config: ByteDanceConfig

    init(modelId: ByteDanceVideoModelId, config: ByteDanceConfig) {
        self.identifier = modelId
        self.config = config
    }

    public func doStart(
        options: VideoModelV4CallOptions,
        webhookUrl: String? = nil
    ) async throws -> VideoModelV4OperationStartResult {
        let now = config.currentDate()
        let (requestBody, warnings) = try await buildRequestBody(options)
        var body = requestBody
        if let webhookUrl { body["callback_url"] = .string(webhookUrl) }
        let response = try await postJsonToAPI(
            url: "\(config.baseURL)/contents/generations/tasks",
            headers: combineHeaders(try await config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 },
            body: JSONValue.object(body),
            failedResponseHandler: byteDanceFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: byteDanceTaskResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )
        guard let taskId = response.value.id, !taskId.isEmpty else {
            throw ByteDanceVideoModelError(message: "No task ID returned from API")
        }
        return .init(operation: .object(["taskId": .string(taskId)]), warnings: warnings,
                     response: .init(timestamp: now, modelId: modelId, headers: response.responseHeaders))
    }

    public func doStatus(options: VideoModelV4StatusCallOptions) async throws -> VideoModelV4OperationStatusResult {
        let now = config.currentDate()
        guard case .object(let operation) = options.operation, case .string(let taskId) = operation["taskId"] else {
            throw InvalidArgumentError(argument: "operation", message: "Invalid ByteDance video operation")
        }
        let response = try await getFromAPI(
            url: "\(config.baseURL)/contents/generations/tasks/\(taskId)",
            headers: combineHeaders(try await config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 },
            failedResponseHandler: byteDanceFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: byteDanceStatusResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch,
            validateUrl: true,
            trustedOrigin: config.baseURL
        )
        let info = VideoModelV4ResponseInfo(timestamp: now, modelId: modelId, headers: response.responseHeaders)
        let status = response.value
        if status.status == "succeeded" {
            guard let url = status.content?.videoUrl, !url.isEmpty else {
                throw ByteDanceVideoModelError(message: "No video URL in response. Task ID: \(taskId)")
            }
            var metadata: JSONObject = ["taskId": .string(taskId)]
            if let usage = status.fields["usage"] { metadata["usage"] = usage }
            if let lastFrame = status.content?.lastFrameUrl { metadata["lastFrameUrl"] = .string(lastFrame) }
            return .completed(videos: [.url(url: url, mediaType: "video/mp4")], warnings: [],
                              providerMetadata: ["bytedance": metadata], response: info)
        }
        if ["failed", "expired", "cancelled", "canceled"].contains(status.status) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            let fallback = String(decoding: try encoder.encode(JSONValue.object(status.fields)), as: UTF8.self)
            let reason = status.error?.message ?? status.error?.code ?? fallback
            return .error(error: "Video generation \(status.status). Task ID: \(taskId). \(reason)", providerMetadata: nil, response: info)
        }
        return .pending(warnings: nil, providerMetadata: nil, response: info)
    }

    private func buildRequestBody(_ options: VideoModelV4CallOptions) async throws -> (JSONObject, [SharedV4Warning]) {
        let parsed = try await parseProviderOptions(provider: "bytedance", providerOptions: options.providerOptions,
                                                  schema: byteDanceVideoModelOptionsSchema)
        var warnings: [SharedV4Warning] = []
        for (setting, value) in [("pollIntervalMs", parsed?.pollIntervalMs), ("pollTimeoutMs", parsed?.pollTimeoutMs)] where value != nil {
            warnings.append(.deprecated(setting: setting, message: "`\(setting)` is ignored. Polling is orchestrated by the AI SDK: pass `poll: { intervalMs, timeoutMs }` to `generateVideo` instead."))
        }
        if let fps = options.fps, fps != 0 {
            warnings.append(.unsupported(feature: "fps", details: "ByteDance video models do not support custom FPS. Frame rate is fixed at 24 fps."))
        }
        if options.n > 1 {
            warnings.append(.unsupported(feature: "n", details: "ByteDance video models do not support generating multiple videos per call. Only 1 video will be generated."))
        }
        var content: [JSONValue] = []
        if let prompt = options.prompt { content.append(.object(["type": .string("text"), "text": .string(prompt)])) }
        let startImage = options.frameImages?.first { $0.frameType == .firstFrame }?.image ?? options.image
        let lastFrameUrl = options.frameImages?.first { $0.frameType == .lastFrame }.map { dataURI($0.image) } ?? parsed?.lastFrameImage
        var references: [JSONValue] = []
        if options.frameImages?.isEmpty != false {
            if let inputReferences = options.inputReferences, !inputReferences.isEmpty {
                for reference in inputReferences {
                    let mediaType: String?
                    switch reference {
                    case .file(let type, _, _): mediaType = type
                    case .url(_, let type, _):
                        mediaType = type
                        if type == nil {
                            warnings.append(.unsupported(feature: "inputReferences", details: "ByteDance requires an explicit mediaType to route URL references as video or image. Pass { data: url, mediaType: \"video/mp4\" } for video references. The reference was treated as an image."))
                        }
                    }
                    let type = mediaType.map { getTopLevelMediaType($0) == "video" } == true ? "video" : "image"
                    references.append(mediaContent(type: type, url: dataURI(reference), role: "reference_\(type)"))
                }
            } else {
                references += (parsed?.referenceImages ?? []).map { mediaContent(type: "image", url: $0, role: "reference_image") }
                references += (parsed?.referenceVideos ?? []).map { mediaContent(type: "video", url: $0, role: "reference_video") }
            }
        }
        if let startImage {
            let role = lastFrameUrl != nil ? "first_frame" : references.isEmpty ? nil : "reference_image"
            content.append(mediaContent(type: "image", url: dataURI(startImage), role: role))
        }
        if let lastFrameUrl { content.append(mediaContent(type: "image", url: lastFrameUrl, role: "last_frame")) }
        content += references
        content += (parsed?.referenceAudio ?? []).map { mediaContent(type: "audio", url: $0, role: "reference_audio") }
        var body: JSONObject = ["model": .string(modelId), "content": .array(content)]
        if let ratio = options.aspectRatio, !ratio.isEmpty { body["ratio"] = .string(ratio) }
        if let duration = options.duration, duration != 0 { body["duration"] = .number(Double(duration)) }
        if let seed = options.seed, seed != 0 { body["seed"] = .number(Double(seed)) }
        if let resolution = options.resolution, !resolution.isEmpty { body["resolution"] = .string(byteDanceResolutionMap[resolution] ?? resolution) }
        if let audio = options.generateAudio ?? parsed?.generateAudio { body["generate_audio"] = .bool(audio) }
        if let watermark = parsed?.watermark { body["watermark"] = .bool(watermark) }
        if let cameraFixed = parsed?.cameraFixed { body["camera_fixed"] = .bool(cameraFixed) }
        if let returnLastFrame = parsed?.returnLastFrame { body["return_last_frame"] = .bool(returnLastFrame) }
        if let serviceTier = parsed?.serviceTier { body["service_tier"] = .string(serviceTier.rawValue) }
        if let draft = parsed?.draft { body["draft"] = .bool(draft) }
        for (key, value) in parsed?.additionalOptions ?? [:] { body[key] = value }
        return (body, warnings)
    }
}

private func mediaContent(type: String, url: String, role: String?) -> JSONValue {
    var content: JSONObject = ["type": .string("\(type)_url"), "\(type)_url": .object(["url": .string(url)])]
    if let role { content["role"] = .string(role) }
    return .object(content)
}

private func dataURI(_ file: VideoModelV4File) -> String {
    switch file {
    case .url(let url, _, _): return url
    case .file(let mediaType, let data, _):
        let base64: String
        switch data {
        case .base64(let value): base64 = value
        case .binary(let value): base64 = value.base64EncodedString()
        }
        return "data:\(mediaType);base64,\(base64)"
    }
}

private struct ByteDanceTaskResponse: Decodable, Sendable { let id: String? }
private let byteDanceTaskResponseSchema = FlexibleSchema(
    Schema<ByteDanceTaskResponse>.codable(ByteDanceTaskResponse.self, jsonSchema: .object(["type": .string("object")]))
)

private struct ByteDanceStatusResponse: Decodable, Sendable {
    struct Content: Decodable, Sendable {
        let videoUrl: String?
        let lastFrameUrl: String?
        enum CodingKeys: String, CodingKey { case videoUrl = "video_url", lastFrameUrl = "last_frame_url" }
    }
    struct Usage: Decodable { let completion_tokens: Double? }
    struct Failure: Decodable, Sendable { let code: String?; let message: String? }
    let status: String
    let content: Content?
    let error: Failure?
    let fields: JSONObject
    enum CodingKeys: String, CodingKey, CaseIterable { case id, model, status, content, usage, error }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _ = try container.decodeIfPresent(String.self, forKey: .id)
        _ = try container.decodeIfPresent(String.self, forKey: .model)
        status = try container.decode(String.self, forKey: .status)
        content = try container.decodeIfPresent(Content.self, forKey: .content)
        _ = try container.decodeIfPresent(Usage.self, forKey: .usage)
        error = try container.decodeIfPresent(Failure.self, forKey: .error)
        var fields: JSONObject = [:]
        for key in CodingKeys.allCases where container.contains(key) { fields[key.rawValue] = try container.decode(JSONValue.self, forKey: key) }
        for (key, allowed) in [("content", ["video_url", "last_frame_url"]), ("usage", ["completion_tokens"]), ("error", ["code", "message"])] {
            if case .object(let object) = fields[key] { fields[key] = .object(object.filter { allowed.contains($0.key) }) }
        }
        self.fields = fields
    }
}

private let byteDanceStatusResponseSchema = FlexibleSchema(
    Schema<ByteDanceStatusResponse>.codable(ByteDanceStatusResponse.self, jsonSchema: .object(["type": .string("object")]))
)

private struct ByteDanceVideoModelError: AISDKError, Sendable {
    static let errorDomain = "bytedance.video.error"
    let name = "BYTEDANCE_VIDEO_GENERATION_ERROR"
    let message: String
    let cause: (any Error)? = nil
}

private let byteDanceResolutionMap: [String: String] = [
    "864x496": "480p", "496x864": "480p", "752x560": "480p", "560x752": "480p", "640x640": "480p",
    "992x432": "480p", "432x992": "480p", "864x480": "480p", "480x864": "480p", "736x544": "480p",
    "544x736": "480p", "960x416": "480p", "416x960": "480p", "832x480": "480p", "480x832": "480p", "624x624": "480p",
    "1280x720": "720p", "720x1280": "720p", "1112x834": "720p", "834x1112": "720p", "960x960": "720p",
    "1470x630": "720p", "630x1470": "720p", "1248x704": "720p", "704x1248": "720p", "1120x832": "720p",
    "832x1120": "720p", "1504x640": "720p", "640x1504": "720p", "1920x1080": "1080p", "1080x1920": "1080p",
    "1664x1248": "1080p", "1248x1664": "1080p", "1440x1440": "1080p", "2206x946": "1080p", "946x2206": "1080p",
    "1920x1088": "1080p", "1088x1920": "1080p", "2176x928": "1080p", "928x2176": "1080p",
]
