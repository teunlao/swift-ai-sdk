import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/alibaba/src/alibaba-video-model.ts
// Upstream commit: 73d5c59
//===----------------------------------------------------------------------===//

public struct AlibabaVideoModelOptions: Sendable, Equatable {
    /// Negative prompt to specify what to avoid (max 500 chars).
    public var negativePrompt: String?

    /// URL to audio file for audio-video sync (WAV/MP3, 3-30s, max 15MB).
    public var audioUrl: String?

    /// Enable prompt extension/rewriting for better generation. Defaults to true.
    public var promptExtend: Bool?

    /// Shot type: 'single' for single-shot or 'multi' for multi-shot narrative.
    public var shotType: ShotType?

    /// Whether to add watermark to generated video. Defaults to false.
    public var watermark: Bool?

    /// Enable audio generation (for I2V/R2V models).
    public var audio: Bool?

    /// Reference URLs for reference-to-video mode.
    public var referenceUrls: [String]?

    /// Polling interval in milliseconds. Defaults to 5000 (5 seconds).
    public var pollIntervalMs: Double?

    /// Maximum wait time in milliseconds for video generation. Defaults to 600000 (10 minutes).
    public var pollTimeoutMs: Double?

    public init(
        negativePrompt: String? = nil,
        audioUrl: String? = nil,
        promptExtend: Bool? = nil,
        shotType: ShotType? = nil,
        watermark: Bool? = nil,
        audio: Bool? = nil,
        referenceUrls: [String]? = nil,
        pollIntervalMs: Double? = nil,
        pollTimeoutMs: Double? = nil
    ) {
        self.negativePrompt = negativePrompt
        self.audioUrl = audioUrl
        self.promptExtend = promptExtend
        self.shotType = shotType
        self.watermark = watermark
        self.audio = audio
        self.referenceUrls = referenceUrls
        self.pollIntervalMs = pollIntervalMs
        self.pollTimeoutMs = pollTimeoutMs
    }

    public enum ShotType: String, Sendable, Equatable {
        case single
        case multi
    }
}

private let alibabaVideoModelOptionsSchema = FlexibleSchema(
    Schema<AlibabaVideoModelOptions>(
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
                    let error = SchemaValidationIssuesError(vendor: "alibaba", issues: "provider options must be an object")
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                func stringNullish(_ key: String) -> Result<String?, TypeValidationError> {
                    guard let raw = dict[key], raw != .null else { return .success(nil) }
                    guard case .string(let value) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "alibaba", issues: "\(key) must be a string")
                        return .failure(TypeValidationError.wrap(value: raw, cause: error))
                    }
                    return .success(value)
                }

                func boolNullish(_ key: String) -> Result<Bool?, TypeValidationError> {
                    guard let raw = dict[key], raw != .null else { return .success(nil) }
                    guard case .bool(let value) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "alibaba", issues: "\(key) must be a boolean")
                        return .failure(TypeValidationError.wrap(value: raw, cause: error))
                    }
                    return .success(value)
                }

                func stringArrayNullish(_ key: String) -> Result<[String]?, TypeValidationError> {
                    guard let raw = dict[key], raw != .null else { return .success(nil) }
                    guard case .array(let values) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "alibaba", issues: "\(key) must be an array of strings")
                        return .failure(TypeValidationError.wrap(value: raw, cause: error))
                    }
                    var strings: [String] = []
                    strings.reserveCapacity(values.count)
                    for value in values {
                        guard case .string(let entry) = value else {
                            let error = SchemaValidationIssuesError(vendor: "alibaba", issues: "\(key) must be an array of strings")
                            return .failure(TypeValidationError.wrap(value: value, cause: error))
                        }
                        strings.append(entry)
                    }
                    return .success(strings)
                }

                func positiveNumberNullish(_ key: String) -> Result<Double?, TypeValidationError> {
                    guard let raw = dict[key], raw != .null else { return .success(nil) }
                    guard case .number(let value) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "alibaba", issues: "\(key) must be a positive number")
                        return .failure(TypeValidationError.wrap(value: raw, cause: error))
                    }
                    guard value > 0 else {
                        let error = SchemaValidationIssuesError(vendor: "alibaba", issues: "\(key) must be a positive number")
                        return .failure(TypeValidationError.wrap(value: raw, cause: error))
                    }
                    return .success(value)
                }

                func shotTypeNullish(_ key: String) -> Result<AlibabaVideoModelOptions.ShotType?, TypeValidationError> {
                    guard let raw = dict[key], raw != .null else { return .success(nil) }
                    guard case .string(let value) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "alibaba", issues: "\(key) must be 'single' or 'multi'")
                        return .failure(TypeValidationError.wrap(value: raw, cause: error))
                    }
                    guard let shotType = AlibabaVideoModelOptions.ShotType(rawValue: value) else {
                        let error = SchemaValidationIssuesError(vendor: "alibaba", issues: "\(key) must be 'single' or 'multi'")
                        return .failure(TypeValidationError.wrap(value: raw, cause: error))
                    }
                    return .success(shotType)
                }

                return .success(value: AlibabaVideoModelOptions(
                    negativePrompt: try stringNullish("negativePrompt").get(),
                    audioUrl: try stringNullish("audioUrl").get(),
                    promptExtend: try boolNullish("promptExtend").get(),
                    shotType: try shotTypeNullish("shotType").get(),
                    watermark: try boolNullish("watermark").get(),
                    audio: try boolNullish("audio").get(),
                    referenceUrls: try stringArrayNullish("referenceUrls").get(),
                    pollIntervalMs: try positiveNumberNullish("pollIntervalMs").get(),
                    pollTimeoutMs: try positiveNumberNullish("pollTimeoutMs").get()
                ))
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)

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

// DashScope native API error format (different from OpenAI-compatible endpoint)
private struct AlibabaVideoErrorData: Codable {
    let code: String?
    let message: String
    let requestId: String?

    private enum CodingKeys: String, CodingKey {
        case code
        case message
        case requestId = "request_id"
    }
}

private let genericJSONObjectSchema: JSONValue = .object(["type": .string("object")])

private let alibabaVideoErrorSchema = FlexibleSchema(
    Schema<AlibabaVideoErrorData>.codable(
        AlibabaVideoErrorData.self,
        jsonSchema: genericJSONObjectSchema
    )
)

private let alibabaVideoFailedResponseHandler: ResponseHandler<APICallError> = createJsonErrorResponseHandler(
    errorSchema: alibabaVideoErrorSchema,
    errorToMessage: { $0.message }
)

private struct AlibabaVideoCreateTaskResponse: Codable {
    struct Output: Codable {
        let taskStatus: String?
        let taskId: String?

        private enum CodingKeys: String, CodingKey {
            case taskStatus = "task_status"
            case taskId = "task_id"
        }
    }

    let output: Output?
    let requestId: String?

    private enum CodingKeys: String, CodingKey {
        case output
        case requestId = "request_id"
    }
}

private let alibabaVideoCreateTaskResponseSchema = FlexibleSchema(
    Schema<AlibabaVideoCreateTaskResponse>.codable(
        AlibabaVideoCreateTaskResponse.self,
        jsonSchema: genericJSONObjectSchema
    )
)

private struct AlibabaVideoTaskStatusResponse: Codable {
    struct Output: Codable {
        let taskId: String?
        let taskStatus: String?
        let videoUrl: String?
        let submitTime: String?
        let scheduledTime: String?
        let endTime: String?
        let origPrompt: String?
        let actualPrompt: String?
        let code: String?
        let message: String?

        private enum CodingKeys: String, CodingKey {
            case taskId = "task_id"
            case taskStatus = "task_status"
            case videoUrl = "video_url"
            case submitTime = "submit_time"
            case scheduledTime = "scheduled_time"
            case endTime = "end_time"
            case origPrompt = "orig_prompt"
            case actualPrompt = "actual_prompt"
            case code
            case message
        }
    }

    struct Usage: Codable {
        let duration: Double?
        let outputVideoDuration: Double?
        let resolution: Double?
        let size: String?

        private enum CodingKeys: String, CodingKey {
            case duration
            case outputVideoDuration = "output_video_duration"
            case resolution = "SR"
            case size
        }
    }

    let output: Output?
    let usage: Usage?
    let requestId: String?

    private enum CodingKeys: String, CodingKey {
        case output
        case usage
        case requestId = "request_id"
    }
}

private let alibabaVideoTaskStatusResponseSchema = FlexibleSchema(
    Schema<AlibabaVideoTaskStatusResponse>.codable(
        AlibabaVideoTaskStatusResponse.self,
        jsonSchema: genericJSONObjectSchema
    )
)

private func detectMode(modelId: String) -> String {
    if modelId.contains("-i2v") { return "i2v" }
    if modelId.contains("-r2v") { return "r2v" }
    return "t2v"
}

public final class AlibabaVideoModel: VideoModelV3 {
    public var specificationVersion: String { "v3" }
    public var maxVideosPerCall: VideoModelV3MaxVideosPerCall { .value(1) }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    private let modelIdentifier: AlibabaVideoModelId
    private let config: AlibabaVideoModelConfig

    init(modelId: AlibabaVideoModelId, config: AlibabaVideoModelConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public func doGenerate(options: VideoModelV3CallOptions) async throws -> VideoModelV3GenerateResult {
        let currentDate = config.currentDate()
        var warnings: [SharedV3Warning] = []
        let mode = detectMode(modelId: modelIdentifier.rawValue)

        let alibabaOptions = try await parseProviderOptions(
            provider: "alibaba",
            providerOptions: options.providerOptions,
            schema: alibabaVideoModelOptionsSchema
        )

        // Build input object
        var input: [String: JSONValue] = [:]

        if let prompt = options.prompt {
            input["prompt"] = .string(prompt)
        }

        if let negativePrompt = alibabaOptions?.negativePrompt {
            input["negative_prompt"] = .string(negativePrompt)
        }

        if let audioUrl = alibabaOptions?.audioUrl {
            input["audio_url"] = .string(audioUrl)
        }

        // Handle image input for I2V mode
        if mode == "i2v", let image = options.image {
            switch image {
            case .url(let url, _):
                input["img_url"] = .string(url)
            case .file(_, let data, _):
                switch data {
                case .base64(let base64):
                    input["img_url"] = .string(base64)
                case .binary(let bytes):
                    input["img_url"] = .string(convertToBase64(.data(bytes)))
                }
            }
        }

        // Handle reference URLs for R2V mode
        if mode == "r2v", let referenceUrls = alibabaOptions?.referenceUrls {
            input["reference_urls"] = .array(referenceUrls.map { JSONValue.string($0) })
        }

        // Build parameters object
        var parameters: [String: JSONValue] = [:]

        if let duration = options.duration {
            parameters["duration"] = .number(Double(duration))
        }

        if let seed = options.seed {
            parameters["seed"] = .number(Double(seed))
        }

        if let resolution = options.resolution {
            if mode == "i2v" {
                let resolutionMap: [String: String] = [
                    "1280x720": "720P",
                    "720x1280": "720P",
                    "960x960": "720P",
                    "1088x832": "720P",
                    "832x1088": "720P",
                    "1920x1080": "1080P",
                    "1080x1920": "1080P",
                    "1440x1440": "1080P",
                    "1632x1248": "1080P",
                    "1248x1632": "1080P",
                    "832x480": "480P",
                    "480x832": "480P",
                    "624x624": "480P",
                ]
                parameters["resolution"] = .string(resolutionMap[resolution] ?? resolution)
            } else {
                parameters["size"] = .string(resolution.replacingOccurrences(of: "x", with: "*"))
            }
        }

        if let promptExtend = alibabaOptions?.promptExtend {
            parameters["prompt_extend"] = .bool(promptExtend)
        }
        if let shotType = alibabaOptions?.shotType {
            parameters["shot_type"] = .string(shotType.rawValue)
        }
        if let watermark = alibabaOptions?.watermark {
            parameters["watermark"] = .bool(watermark)
        }
        if let audio = alibabaOptions?.audio {
            parameters["audio"] = .bool(audio)
        }

        // Warn about unsupported standard options
        if options.aspectRatio != nil {
            warnings.append(.unsupported(
                feature: "aspectRatio",
                details: "Alibaba video models use explicit size/resolution dimensions. Use the resolution option or providerOptions.alibaba for size control."
            ))
        }
        if options.fps != nil {
            warnings.append(.unsupported(
                feature: "fps",
                details: "Alibaba video models do not support custom FPS."
            ))
        }
        if options.n > 1 {
            warnings.append(.unsupported(
                feature: "n",
                details: "Alibaba video models only support generating 1 video per call."
            ))
        }

        // Step 1: Create task
        let createURL = "\(config.baseURL)/api/v1/services/aigc/video-generation/video-synthesis"
        let createHeaders = combineHeaders(
            try config.headers(),
            options.headers?.mapValues { Optional($0) },
            ["X-DashScope-Async": "enable"]
        ).compactMapValues { $0 }

        let createBody: [String: JSONValue] = [
            "model": .string(modelIdentifier.rawValue),
            "input": .object(input),
            "parameters": .object(parameters),
        ]

        let createResponse = try await postJsonToAPI(
            url: createURL,
            headers: createHeaders,
            body: JSONValue.object(createBody),
            failedResponseHandler: alibabaVideoFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: alibabaVideoCreateTaskResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        guard let taskId = createResponse.value.output?.taskId, !taskId.isEmpty else {
            throw AlibabaVideoModelError(
                name: "ALIBABA_VIDEO_GENERATION_ERROR",
                message: "No task_id returned from Alibaba API. Response: \(encodeJSONString(createResponse.value))"
            )
        }

        // Step 2: Poll for task completion
        let pollIntervalMs = alibabaOptions?.pollIntervalMs ?? 5000
        let pollTimeoutMs = alibabaOptions?.pollTimeoutMs ?? 600000
        let startTime = Date()

        var finalResponse: AlibabaVideoTaskStatusResponse? = nil
        var responseHeaders: [String: String]? = nil

        while true {
            try await delay(Int(pollIntervalMs.rounded(.towardZero)), abortSignal: options.abortSignal)

            let elapsedMs = Date().timeIntervalSince(startTime) * 1000
            if elapsedMs > pollTimeoutMs {
                throw AlibabaVideoModelError(
                    name: "ALIBABA_VIDEO_GENERATION_TIMEOUT",
                    message: "Video generation timed out after \(pollTimeoutMs)ms"
                )
            }

            let statusURL = "\(config.baseURL)/api/v1/tasks/\(taskId)"
            let statusHeaders = combineHeaders(
                try config.headers(),
                options.headers?.mapValues { Optional($0) }
            ).compactMapValues { $0 }

            let statusResponse = try await getFromAPI(
                url: statusURL,
                headers: statusHeaders,
                failedResponseHandler: alibabaVideoFailedResponseHandler,
                successfulResponseHandler: createJsonResponseHandler(responseSchema: alibabaVideoTaskStatusResponseSchema),
                isAborted: options.abortSignal,
                fetch: config.fetch
            )

            responseHeaders = statusResponse.responseHeaders
            let taskStatus = statusResponse.value.output?.taskStatus

            if taskStatus == "SUCCEEDED" {
                finalResponse = statusResponse.value
                break
            }

            if taskStatus == "FAILED" || taskStatus == "CANCELED" {
                let message = statusResponse.value.output?.message ?? ""
                throw AlibabaVideoModelError(
                    name: "ALIBABA_VIDEO_GENERATION_FAILED",
                    message: "Video generation \(taskStatus?.lowercased() ?? "failed"). Task ID: \(taskId). \(message)"
                )
            }

            // Continue polling for PENDING, RUNNING, UNKNOWN statuses
        }

        guard let videoUrl = finalResponse?.output?.videoUrl, !videoUrl.isEmpty else {
            throw AlibabaVideoModelError(
                name: "ALIBABA_VIDEO_GENERATION_ERROR",
                message: "No video URL in response. Task ID: \(taskId)"
            )
        }

        var alibabaMetadata: [String: JSONValue] = [
            "taskId": .string(taskId),
            "videoUrl": .string(videoUrl),
        ]

        if let actualPrompt = finalResponse?.output?.actualPrompt, !actualPrompt.isEmpty {
            alibabaMetadata["actualPrompt"] = .string(actualPrompt)
        }

        if let usage = finalResponse?.usage {
            alibabaMetadata["usage"] = .object([
                "duration": usage.duration.map(JSONValue.number) ?? .null,
                "outputVideoDuration": usage.outputVideoDuration.map(JSONValue.number) ?? .null,
                "resolution": usage.resolution.map(JSONValue.number) ?? .null,
                "size": usage.size.map(JSONValue.string) ?? .null,
            ])
        }

        return VideoModelV3GenerateResult(
            videos: [
                .url(url: videoUrl, mediaType: "video/mp4")
            ],
            warnings: warnings,
            providerMetadata: [
                "alibaba": alibabaMetadata
            ],
            response: VideoModelV3ResponseInfo(
                timestamp: currentDate,
                modelId: modelIdentifier.rawValue,
                headers: responseHeaders
            )
        )
    }
}

private struct AlibabaVideoModelError: AISDKError, Sendable {
    static let errorDomain = "alibaba.video.error"

    let name: String
    let message: String
    let cause: (any Error)?

    init(name: String, message: String, cause: (any Error)? = nil) {
        self.name = name
        self.message = message
        self.cause = cause
    }
}

private func encodeJSONString<T: Encodable>(_ value: T) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    do {
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    } catch {
        return "{}"
    }
}
