import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/bytedance/src/bytedance-video-model.ts
// Ported from packages/bytedance/src/bytedance-video-settings.ts
// Upstream commit: 73d5c59
//===----------------------------------------------------------------------===//

public struct ByteDanceVideoProviderOptions: Sendable, Equatable {
    public var watermark: Bool?
    public var generateAudio: Bool?
    public var cameraFixed: Bool?
    public var returnLastFrame: Bool?
    public var serviceTier: ServiceTier?
    public var draft: Bool?
    public var lastFrameImage: String?
    public var referenceImages: [String]?
    public var pollIntervalMs: Double?
    public var pollTimeoutMs: Double?

    public init(
        watermark: Bool? = nil,
        generateAudio: Bool? = nil,
        cameraFixed: Bool? = nil,
        returnLastFrame: Bool? = nil,
        serviceTier: ServiceTier? = nil,
        draft: Bool? = nil,
        lastFrameImage: String? = nil,
        referenceImages: [String]? = nil,
        pollIntervalMs: Double? = nil,
        pollTimeoutMs: Double? = nil
    ) {
        self.watermark = watermark
        self.generateAudio = generateAudio
        self.cameraFixed = cameraFixed
        self.returnLastFrame = returnLastFrame
        self.serviceTier = serviceTier
        self.draft = draft
        self.lastFrameImage = lastFrameImage
        self.referenceImages = referenceImages
        self.pollIntervalMs = pollIntervalMs
        self.pollTimeoutMs = pollTimeoutMs
    }

    public enum ServiceTier: String, Sendable, Equatable {
        case `default` = "default"
        case flex = "flex"
    }
}

private let handledProviderOptionKeys: Set<String> = [
    "watermark",
    "generateAudio",
    "cameraFixed",
    "returnLastFrame",
    "serviceTier",
    "draft",
    "lastFrameImage",
    "referenceImages",
    "pollIntervalMs",
    "pollTimeoutMs",
]

private let byteDanceVideoProviderOptionsSchema = FlexibleSchema(
    Schema<ByteDanceVideoProviderOptions>(
        jsonSchemaResolver: {
            .object([
                "type": .string("object"),
                "additionalProperties": .bool(true),
            ])
        },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(vendor: "bytedance", issues: "provider options must be an object")
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                func boolOrNullish(_ key: String) -> Result<Bool?, TypeValidationError> {
                    guard let raw = dict[key], raw != .null else {
                        return .success(nil)
                    }
                    guard case .bool(let value) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "bytedance", issues: "\(key) must be a boolean")
                        return .failure(TypeValidationError.wrap(value: raw, cause: error))
                    }
                    return .success(value)
                }

                func stringOrNullish(_ key: String) -> Result<String?, TypeValidationError> {
                    guard let raw = dict[key], raw != .null else {
                        return .success(nil)
                    }
                    guard case .string(let value) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "bytedance", issues: "\(key) must be a string")
                        return .failure(TypeValidationError.wrap(value: raw, cause: error))
                    }
                    return .success(value)
                }

                func stringArrayOrNullish(_ key: String) -> Result<[String]?, TypeValidationError> {
                    guard let raw = dict[key], raw != .null else {
                        return .success(nil)
                    }
                    guard case .array(let values) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "bytedance", issues: "\(key) must be an array of strings")
                        return .failure(TypeValidationError.wrap(value: raw, cause: error))
                    }
                    var strings: [String] = []
                    strings.reserveCapacity(values.count)
                    for entry in values {
                        guard case .string(let value) = entry else {
                            let error = SchemaValidationIssuesError(vendor: "bytedance", issues: "\(key) must be an array of strings")
                            return .failure(TypeValidationError.wrap(value: entry, cause: error))
                        }
                        strings.append(value)
                    }
                    return .success(strings)
                }

                func positiveNumber(_ key: String) -> Result<Double?, TypeValidationError> {
                    guard let raw = dict[key], raw != .null else {
                        return .success(nil)
                    }
                    guard case .number(let number) = raw, number > 0 else {
                        let error = SchemaValidationIssuesError(vendor: "bytedance", issues: "\(key) must be a positive number")
                        return .failure(TypeValidationError.wrap(value: raw, cause: error))
                    }
                    return .success(number)
                }

                let watermark: Bool?
                switch boolOrNullish("watermark") {
                case .success(let value):
                    watermark = value
                case .failure(let error):
                    return .failure(error: error)
                }

                let generateAudio: Bool?
                switch boolOrNullish("generateAudio") {
                case .success(let value):
                    generateAudio = value
                case .failure(let error):
                    return .failure(error: error)
                }

                let cameraFixed: Bool?
                switch boolOrNullish("cameraFixed") {
                case .success(let value):
                    cameraFixed = value
                case .failure(let error):
                    return .failure(error: error)
                }

                let returnLastFrame: Bool?
                switch boolOrNullish("returnLastFrame") {
                case .success(let value):
                    returnLastFrame = value
                case .failure(let error):
                    return .failure(error: error)
                }

                var serviceTier: ByteDanceVideoProviderOptions.ServiceTier?
                if let raw = dict["serviceTier"], raw != .null {
                    guard case .string(let value) = raw,
                          let parsed = ByteDanceVideoProviderOptions.ServiceTier(rawValue: value) else {
                        let error = SchemaValidationIssuesError(vendor: "bytedance", issues: "serviceTier must be one of 'default' | 'flex'")
                        return .failure(error: TypeValidationError.wrap(value: raw, cause: error))
                    }
                    serviceTier = parsed
                }

                let draft: Bool?
                switch boolOrNullish("draft") {
                case .success(let value):
                    draft = value
                case .failure(let error):
                    return .failure(error: error)
                }

                let lastFrameImage: String?
                switch stringOrNullish("lastFrameImage") {
                case .success(let value):
                    lastFrameImage = value
                case .failure(let error):
                    return .failure(error: error)
                }

                let referenceImages: [String]?
                switch stringArrayOrNullish("referenceImages") {
                case .success(let value):
                    referenceImages = value
                case .failure(let error):
                    return .failure(error: error)
                }

                let pollIntervalMs: Double?
                switch positiveNumber("pollIntervalMs") {
                case .success(let value):
                    pollIntervalMs = value
                case .failure(let error):
                    return .failure(error: error)
                }

                let pollTimeoutMs: Double?
                switch positiveNumber("pollTimeoutMs") {
                case .success(let value):
                    pollTimeoutMs = value
                case .failure(let error):
                    return .failure(error: error)
                }

                return .success(
                    value: ByteDanceVideoProviderOptions(
                        watermark: watermark,
                        generateAudio: generateAudio,
                        cameraFixed: cameraFixed,
                        returnLastFrame: returnLastFrame,
                        serviceTier: serviceTier,
                        draft: draft,
                        lastFrameImage: lastFrameImage,
                        referenceImages: referenceImages,
                        pollIntervalMs: pollIntervalMs,
                        pollTimeoutMs: pollTimeoutMs
                    )
                )
            } catch let error as TypeValidationError {
                return .failure(error: error)
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)

struct ByteDanceVideoModelConfig: Sendable {
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

public final class ByteDanceVideoModel: VideoModelV3 {
    public var specificationVersion: String { "v3" }
    public var maxVideosPerCall: VideoModelV3MaxVideosPerCall { .value(1) }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    private let modelIdentifier: ByteDanceVideoModelId
    private let config: ByteDanceVideoModelConfig

    init(modelId: ByteDanceVideoModelId, config: ByteDanceVideoModelConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public func doGenerate(options: VideoModelV3CallOptions) async throws -> VideoModelV3GenerateResult {
        let currentDate = config.currentDate()
        var warnings: [SharedV3Warning] = []

        let byteDanceOptions = try await parseProviderOptions(
            provider: "bytedance",
            providerOptions: options.providerOptions,
            schema: byteDanceVideoProviderOptionsSchema
        )

        if options.fps != nil {
            warnings.append(.unsupported(
                feature: "fps",
                details: "ByteDance video models do not support custom FPS. Frame rate is fixed at 24 fps."
            ))
        }

        if options.n > 1 {
            warnings.append(.unsupported(
                feature: "n",
                details: "ByteDance video models do not support generating multiple videos per call. Only 1 video will be generated."
            ))
        }

        var content: [JSONValue] = []

        if let prompt = options.prompt {
            content.append(.object([
                "type": .string("text"),
                "text": .string(prompt),
            ]))
        }

        if let image = options.image {
            content.append(.object([
                "type": .string("image_url"),
                "image_url": .object([
                    "url": .string(convertVideoModelFileToDataUri(image)),
                ]),
            ]))
        }

        if let lastFrameImage = byteDanceOptions?.lastFrameImage {
            content.append(.object([
                "type": .string("image_url"),
                "image_url": .object([
                    "url": .string(lastFrameImage),
                ]),
                "role": .string("last_frame"),
            ]))
        }

        if let referenceImages = byteDanceOptions?.referenceImages, !referenceImages.isEmpty {
            for url in referenceImages {
                content.append(.object([
                    "type": .string("image_url"),
                    "image_url": .object([
                        "url": .string(url),
                    ]),
                    "role": .string("reference_image"),
                ]))
            }
        }

        var body: [String: JSONValue] = [
            "model": .string(modelIdentifier.rawValue),
            "content": .array(content),
        ]

        if let aspectRatio = options.aspectRatio {
            body["ratio"] = .string(aspectRatio)
        }

        if let duration = options.duration {
            body["duration"] = .number(Double(duration))
        }

        if let seed = options.seed {
            body["seed"] = .number(Double(seed))
        }

        if let resolution = options.resolution {
            body["resolution"] = .string(byteDanceResolutionMap[resolution] ?? resolution)
        }

        if let byteDanceOptions {
            if let watermark = byteDanceOptions.watermark {
                body["watermark"] = .bool(watermark)
            }
            if let generateAudio = byteDanceOptions.generateAudio {
                body["generate_audio"] = .bool(generateAudio)
            }
            if let cameraFixed = byteDanceOptions.cameraFixed {
                body["camera_fixed"] = .bool(cameraFixed)
            }
            if let returnLastFrame = byteDanceOptions.returnLastFrame {
                body["return_last_frame"] = .bool(returnLastFrame)
            }
            if let serviceTier = byteDanceOptions.serviceTier {
                body["service_tier"] = .string(serviceTier.rawValue)
            }
            if let draft = byteDanceOptions.draft {
                body["draft"] = .bool(draft)
            }
        }

        let rawProviderOptions = options.providerOptions?["bytedance"] ?? [:]
        for (key, value) in rawProviderOptions {
            guard !handledProviderOptionKeys.contains(key) else { continue }
            body[key] = value
        }

        let requestHeaders = combineHeaders(
            try config.headers(),
            options.headers?.mapValues { Optional($0) }
        ).compactMapValues { $0 }

        let createUrl = "\(config.baseURL)/contents/generations/tasks"

        let createResponse: ResponseHandlerResult<ByteDanceTaskResponse>
        do {
            createResponse = try await postJsonToAPI(
                url: createUrl,
                headers: requestHeaders,
                body: JSONValue.object(body),
                failedResponseHandler: byteDanceFailedResponseHandler,
                successfulResponseHandler: createJsonResponseHandler(responseSchema: byteDanceTaskResponseSchema),
                isAborted: options.abortSignal,
                fetch: config.fetch
            )
        } catch {
            if isAbortError(error) {
                throw ByteDanceVideoModelError(
                    name: "BYTEDANCE_VIDEO_GENERATION_ABORTED",
                    message: "Video generation request was aborted",
                    cause: error
                )
            }
            throw error
        }

        let taskId = createResponse.value.id
        if taskId == nil || taskId?.isEmpty == true {
            throw ByteDanceVideoModelError(
                name: "BYTEDANCE_VIDEO_GENERATION_ERROR",
                message: "No task ID returned from API"
            )
        }

        let pollIntervalMs = byteDanceOptions?.pollIntervalMs ?? 3000
        let pollTimeoutMs = byteDanceOptions?.pollTimeoutMs ?? 300000
        let startTime = Date()

        var response: ByteDanceStatusResponse
        var responseHeaders: [String: String]?

        while true {
            let statusUrl = "\(config.baseURL)/contents/generations/tasks/\(taskId!)"

            let statusResult: ResponseHandlerResult<ByteDanceStatusResponse>
            do {
                statusResult = try await getFromAPI(
                    url: statusUrl,
                    headers: requestHeaders,
                    failedResponseHandler: byteDanceFailedResponseHandler,
                    successfulResponseHandler: createJsonResponseHandler(responseSchema: byteDanceStatusResponseSchema),
                    isAborted: options.abortSignal,
                    fetch: config.fetch
                )
            } catch {
                if isAbortError(error) {
                    throw ByteDanceVideoModelError(
                        name: "BYTEDANCE_VIDEO_GENERATION_ABORTED",
                        message: "Video generation request was aborted",
                        cause: error
                    )
                }
                throw error
            }

            if statusResult.value.status == "succeeded" {
                response = statusResult.value
                responseHeaders = statusResult.responseHeaders
                break
            }

            if statusResult.value.status == "failed" {
                throw ByteDanceVideoModelError(
                    name: "BYTEDANCE_VIDEO_GENERATION_FAILED",
                    message: "Video generation failed: \(byteDanceStatusJSONString(from: statusResult.value))"
                )
            }

            let elapsedMs = Date().timeIntervalSince(startTime) * 1000
            if elapsedMs > pollTimeoutMs {
                throw ByteDanceVideoModelError(
                    name: "BYTEDANCE_VIDEO_GENERATION_TIMEOUT",
                    message: "Video generation timed out after \(pollTimeoutMs)ms"
                )
            }

            let pollDelay = max(0, Int(pollIntervalMs.rounded(.towardZero)))
            do {
                try await delay(pollDelay, abortSignal: options.abortSignal)
            } catch {
                if isAbortError(error) {
                    throw ByteDanceVideoModelError(
                        name: "BYTEDANCE_VIDEO_GENERATION_ABORTED",
                        message: "Video generation request was aborted",
                        cause: error
                    )
                }
                throw error
            }
        }

        guard let videoUrl = response.content?.videoUrl, !videoUrl.isEmpty else {
            throw ByteDanceVideoModelError(
                name: "BYTEDANCE_VIDEO_GENERATION_ERROR",
                message: "No video URL in response"
            )
        }

        var bytedanceMetadata: [String: JSONValue] = [
            "taskId": .string(taskId!)
        ]
        if let usage = response.usage {
            let completionTokens: JSONValue
            if let tokens = usage.completionTokens {
                completionTokens = .number(tokens)
            } else {
                completionTokens = .null
            }
            bytedanceMetadata["usage"] = .object([
                "completion_tokens": completionTokens
            ])
        }

        return VideoModelV3GenerateResult(
            videos: [
                .url(url: videoUrl, mediaType: "video/mp4")
            ],
            warnings: warnings,
            providerMetadata: [
                "bytedance": bytedanceMetadata
            ],
            response: VideoModelV3ResponseInfo(
                timestamp: currentDate,
                modelId: modelIdentifier.rawValue,
                headers: responseHeaders
            )
        )
    }
}

// MARK: - API Schemas

private struct ByteDanceTaskResponse: Codable, Sendable {
    let id: String?
}

private let byteDanceTaskResponseSchema = FlexibleSchema(
    Schema<ByteDanceTaskResponse>.codable(
        ByteDanceTaskResponse.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

private struct ByteDanceStatusResponse: Codable, Sendable {
    struct Content: Codable, Sendable {
        let videoUrl: String?

        enum CodingKeys: String, CodingKey {
            case videoUrl = "video_url"
        }
    }

    struct Usage: Codable, Sendable {
        let completionTokens: Double?

        enum CodingKeys: String, CodingKey {
            case completionTokens = "completion_tokens"
        }
    }

    let id: String?
    let model: String?
    let status: String
    let content: Content?
    let usage: Usage?
}

private let byteDanceStatusResponseSchema = FlexibleSchema(
    Schema<ByteDanceStatusResponse>.codable(
        ByteDanceStatusResponse.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

private struct ByteDanceErrorResponse: Codable, Sendable {
    struct ErrorPayload: Codable, Sendable {
        let message: String
        let code: String?
    }

    let error: ErrorPayload?
    let message: String?
}

private let byteDanceErrorResponseSchema = FlexibleSchema(
    Schema<ByteDanceErrorResponse>.codable(
        ByteDanceErrorResponse.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

private let byteDanceFailedResponseHandler = createJsonErrorResponseHandler(
    errorSchema: byteDanceErrorResponseSchema,
    errorToMessage: { data in
        data.error?.message ?? data.message ?? "Unknown error"
    }
)

// MARK: - Helpers

private func convertVideoModelFileToDataUri(_ file: VideoModelV3File) -> String {
    switch file {
    case let .url(url, _):
        return url
    case let .file(mediaType, data, _):
        let base64: String
        switch data {
        case .base64(let value):
            base64 = value
        case .binary(let value):
            base64 = convertDataToBase64(value)
        }
        return "data:\(mediaType);base64,\(base64)"
    }
}

private func byteDanceStatusJSONString(from response: ByteDanceStatusResponse) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    do {
        let data = try encoder.encode(response)
        return String(data: data, encoding: .utf8) ?? "{}"
    } catch {
        return "{}"
    }
}

private struct ByteDanceVideoModelError: AISDKError, Sendable {
    static let errorDomain = "bytedance.video.error"

    let name: String
    let message: String
    let cause: (any Error)?

    init(name: String, message: String, cause: (any Error)? = nil) {
        self.name = name
        self.message = message
        self.cause = cause
    }
}

private let byteDanceResolutionMap: [String: String] = [
    "864x496": "480p",
    "496x864": "480p",
    "752x560": "480p",
    "560x752": "480p",
    "640x640": "480p",
    "992x432": "480p",
    "432x992": "480p",
    "864x480": "480p",
    "480x864": "480p",
    "736x544": "480p",
    "544x736": "480p",
    "960x416": "480p",
    "416x960": "480p",
    "832x480": "480p",
    "480x832": "480p",
    "624x624": "480p",
    "1280x720": "720p",
    "720x1280": "720p",
    "1112x834": "720p",
    "834x1112": "720p",
    "960x960": "720p",
    "1470x630": "720p",
    "630x1470": "720p",
    "1248x704": "720p",
    "704x1248": "720p",
    "1120x832": "720p",
    "832x1120": "720p",
    "1504x640": "720p",
    "640x1504": "720p",
    "1920x1080": "1080p",
    "1080x1920": "1080p",
    "1664x1248": "1080p",
    "1248x1664": "1080p",
    "1440x1440": "1080p",
    "2206x946": "1080p",
    "946x2206": "1080p",
    "1920x1088": "1080p",
    "1088x1920": "1080p",
    "2176x928": "1080p",
    "928x2176": "1080p",
]

