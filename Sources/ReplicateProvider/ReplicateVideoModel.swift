import Foundation
import AISDKProvider
import AISDKProviderUtils

// MARK: - Config

struct ReplicateVideoModelConfig: Sendable {
    let provider: String
    let baseURL: String
    let headers: @Sendable () -> [String: String?]
    let fetch: FetchFunction?
    let currentDate: @Sendable () -> Date

    init(
        provider: String,
        baseURL: String,
        headers: @escaping @Sendable () -> [String: String?],
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

// MARK: - Provider Options

/// Provider options for Replicate video generation.
/// Mirrors `packages/replicate/src/replicate-video-model.ts`.
public struct ReplicateVideoProviderOptions: Sendable, Equatable {
    // Polling configuration
    public var pollIntervalMs: Double?
    public var pollTimeoutMs: Double?
    public var maxWaitTimeInSeconds: Double?

    // Common video generation options
    public var guidanceScale: Double?
    public var numInferenceSteps: Double?

    // Stable Video Diffusion specific
    public var motionBucketId: Double?
    public var condAug: Double?
    public var decodingT: Double?
    public var videoLength: String?
    public var sizingStrategy: String?
    public var framesPerSecond: Double?

    // MiniMax specific
    public var promptOptimizer: Bool?

    public init() {}
}

private let replicateVideoProviderOptionsSchemaJSON: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(true)
])

private let replicateVideoProviderOptionsSchema = FlexibleSchema(
    Schema<ReplicateVideoProviderOptions>(
        jsonSchemaResolver: { replicateVideoProviderOptionsSchemaJSON },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(vendor: "replicate", issues: "provider options must be an object")
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                func positiveNumber(_ value: JSONValue, key: String) -> Result<Double?, TypeValidationError> {
                    guard value != .null else { return .success(nil) }
                    guard case .number(let number) = value else {
                        let error = SchemaValidationIssuesError(vendor: "replicate", issues: "\(key) must be a positive number")
                        return .failure(TypeValidationError.wrap(value: value, cause: error))
                    }
                    guard number > 0 else {
                        let error = SchemaValidationIssuesError(vendor: "replicate", issues: "\(key) must be a positive number")
                        return .failure(TypeValidationError.wrap(value: value, cause: error))
                    }
                    return .success(number)
                }

                func number(_ value: JSONValue, key: String) -> Result<Double?, TypeValidationError> {
                    guard value != .null else { return .success(nil) }
                    guard case .number(let number) = value else {
                        let error = SchemaValidationIssuesError(vendor: "replicate", issues: "\(key) must be a number")
                        return .failure(TypeValidationError.wrap(value: value, cause: error))
                    }
                    return .success(number)
                }

                func string(_ value: JSONValue, key: String) -> Result<String?, TypeValidationError> {
                    guard value != .null else { return .success(nil) }
                    guard case .string(let string) = value else {
                        let error = SchemaValidationIssuesError(vendor: "replicate", issues: "\(key) must be a string")
                        return .failure(TypeValidationError.wrap(value: value, cause: error))
                    }
                    return .success(string)
                }

                func bool(_ value: JSONValue, key: String) -> Result<Bool?, TypeValidationError> {
                    guard value != .null else { return .success(nil) }
                    guard case .bool(let bool) = value else {
                        let error = SchemaValidationIssuesError(vendor: "replicate", issues: "\(key) must be a boolean")
                        return .failure(TypeValidationError.wrap(value: value, cause: error))
                    }
                    return .success(bool)
                }

                var options = ReplicateVideoProviderOptions()

                if let v = dict["pollIntervalMs"] {
                    switch positiveNumber(v, key: "pollIntervalMs") {
                    case .success(let number): options.pollIntervalMs = number
                    case .failure(let error): return .failure(error: error)
                    }
                }

                if let v = dict["pollTimeoutMs"] {
                    switch positiveNumber(v, key: "pollTimeoutMs") {
                    case .success(let number): options.pollTimeoutMs = number
                    case .failure(let error): return .failure(error: error)
                    }
                }

                if let v = dict["maxWaitTimeInSeconds"] {
                    switch positiveNumber(v, key: "maxWaitTimeInSeconds") {
                    case .success(let number): options.maxWaitTimeInSeconds = number
                    case .failure(let error): return .failure(error: error)
                    }
                }

                if let v = dict["guidance_scale"] {
                    switch number(v, key: "guidance_scale") {
                    case .success(let number): options.guidanceScale = number
                    case .failure(let error): return .failure(error: error)
                    }
                }

                if let v = dict["num_inference_steps"] {
                    switch number(v, key: "num_inference_steps") {
                    case .success(let number): options.numInferenceSteps = number
                    case .failure(let error): return .failure(error: error)
                    }
                }

                if let v = dict["motion_bucket_id"] {
                    switch number(v, key: "motion_bucket_id") {
                    case .success(let number): options.motionBucketId = number
                    case .failure(let error): return .failure(error: error)
                    }
                }

                if let v = dict["cond_aug"] {
                    switch number(v, key: "cond_aug") {
                    case .success(let number): options.condAug = number
                    case .failure(let error): return .failure(error: error)
                    }
                }

                if let v = dict["decoding_t"] {
                    switch number(v, key: "decoding_t") {
                    case .success(let number): options.decodingT = number
                    case .failure(let error): return .failure(error: error)
                    }
                }

                if let v = dict["video_length"] {
                    switch string(v, key: "video_length") {
                    case .success(let string): options.videoLength = string
                    case .failure(let error): return .failure(error: error)
                    }
                }

                if let v = dict["sizing_strategy"] {
                    switch string(v, key: "sizing_strategy") {
                    case .success(let string): options.sizingStrategy = string
                    case .failure(let error): return .failure(error: error)
                    }
                }

                if let v = dict["frames_per_second"] {
                    switch number(v, key: "frames_per_second") {
                    case .success(let number): options.framesPerSecond = number
                    case .failure(let error): return .failure(error: error)
                    }
                }

                if let v = dict["prompt_optimizer"] {
                    switch bool(v, key: "prompt_optimizer") {
                    case .success(let bool): options.promptOptimizer = bool
                    case .failure(let error): return .failure(error: error)
                    }
                }

                return .success(value: options)
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)

// MARK: - Prediction schema

private struct ReplicatePrediction: Codable, Sendable, Equatable {
    enum Status: String, Codable, Sendable, Equatable {
        case starting
        case processing
        case succeeded
        case failed
        case canceled
    }

    struct URLs: Codable, Sendable, Equatable {
        let get: String
    }

    struct Metrics: Codable, Sendable, Equatable {
        let predictTime: Double?
    }

    let id: String
    let status: Status
    let output: String?
    let error: String?
    let urls: URLs
    let metrics: Metrics?
}

private let replicatePredictionSchema = FlexibleSchema(
    Schema<ReplicatePrediction>.codable(
        ReplicatePrediction.self,
        jsonSchema: .object(["type": .string("object")]),
        configureDecoder: { decoder in
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return decoder
        }
    )
)

// MARK: - Video Model

/// Replicate video generation model.
/// Mirrors `packages/replicate/src/replicate-video-model.ts`.
public final class ReplicateVideoModel: VideoModelV3 {
    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }
    public var maxVideosPerCall: VideoModelV3MaxVideosPerCall { .value(1) }

    private let modelIdentifier: ReplicateVideoModelId
    private let config: ReplicateVideoModelConfig

    init(_ modelId: ReplicateVideoModelId, config: ReplicateVideoModelConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public func doGenerate(options: VideoModelV3CallOptions) async throws -> VideoModelV3GenerateResult {
        let now = config.currentDate()
        let warnings: [SharedV3Warning] = []

        let replicateOptions = try await parseProviderOptions(
            provider: "replicate",
            providerOptions: options.providerOptions,
            schema: replicateVideoProviderOptionsSchema
        )

        let parts = modelIdentifier.rawValue.split(separator: ":", omittingEmptySubsequences: true)
        let modelPart = String(parts.first ?? Substring(modelIdentifier.rawValue))
        let versionPart: String? = parts.count >= 2 ? String(parts[1]) : nil

        var input: [String: JSONValue] = [:]

        if let prompt = options.prompt {
            input["prompt"] = .string(prompt)
        }

        if let image = options.image {
            switch image {
            case .url(let url, _):
                input["image"] = .string(url)
            case .file(let mediaType, let data, _):
                input["image"] = .string(convertFileToDataUri(mediaType: mediaType, data: data))
            }
        }

        if let aspectRatio = options.aspectRatio {
            input["aspect_ratio"] = .string(aspectRatio)
        }

        if let resolution = options.resolution {
            input["size"] = .string(resolution)
        }

        if let duration = options.duration {
            input["duration"] = .number(Double(duration))
        }

        if let fps = options.fps {
            input["fps"] = .number(Double(fps))
        }

        if let seed = options.seed {
            input["seed"] = .number(Double(seed))
        }

        if let replicateOptions {
            if let value = replicateOptions.guidanceScale {
                input["guidance_scale"] = .number(value)
            }
            if let value = replicateOptions.numInferenceSteps {
                input["num_inference_steps"] = .number(value)
            }
            if let value = replicateOptions.motionBucketId {
                input["motion_bucket_id"] = .number(value)
            }
            if let value = replicateOptions.condAug {
                input["cond_aug"] = .number(value)
            }
            if let value = replicateOptions.decodingT {
                input["decoding_t"] = .number(value)
            }
            if let value = replicateOptions.videoLength {
                input["video_length"] = .string(value)
            }
            if let value = replicateOptions.sizingStrategy {
                input["sizing_strategy"] = .string(value)
            }
            if let value = replicateOptions.framesPerSecond {
                input["frames_per_second"] = .number(value)
            }
            if let value = replicateOptions.promptOptimizer {
                input["prompt_optimizer"] = .bool(value)
            }
        }

        let excludedKeys: Set<String> = [
            "pollIntervalMs",
            "pollTimeoutMs",
            "maxWaitTimeInSeconds",
            "guidance_scale",
            "num_inference_steps",
            "motion_bucket_id",
            "cond_aug",
            "decoding_t",
            "video_length",
            "sizing_strategy",
            "frames_per_second",
            "prompt_optimizer",
        ]

        let rawReplicateOptions = options.providerOptions?["replicate"] ?? [:]
        for (key, value) in rawReplicateOptions {
            guard !excludedKeys.contains(key) else { continue }
            input[key] = value
        }

        let preferValue: String = {
            guard let maxWait = replicateOptions?.maxWaitTimeInSeconds else { return "wait" }
            return "wait=\(jsNumberString(maxWait))"
        }()

        let preferHeader: [String: String?] = ["prefer": preferValue]

        let predictionUrl: String = {
            if versionPart != nil {
                return "\(config.baseURL)/predictions"
            }
            return "\(config.baseURL)/models/\(modelPart)/predictions"
        }()

        var requestBody: [String: JSONValue] = [
            "input": .object(input),
        ]

        if let version = versionPart {
            requestBody["version"] = .string(version)
        }

        let resolvedHeaders = await resolve(config.headers)
        let requestHeaders = combineHeaders(
            resolvedHeaders,
            options.headers?.mapValues { Optional($0) },
            preferHeader
        ).compactMapValues { $0 }

        let postResult = try await postJsonToAPI(
            url: predictionUrl,
            headers: requestHeaders,
            body: JSONValue.object(requestBody),
            failedResponseHandler: replicateFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: replicatePredictionSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        var finalPrediction = postResult.value

        if finalPrediction.status == .starting || finalPrediction.status == .processing {
            let pollIntervalMs = Int((replicateOptions?.pollIntervalMs ?? 2000).rounded(.towardZero))
            let pollTimeoutMs = Int((replicateOptions?.pollTimeoutMs ?? 300_000).rounded(.towardZero))

            let start = Date()

            while finalPrediction.status == .starting || finalPrediction.status == .processing {
                let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)
                if elapsedMs > pollTimeoutMs {
                    throw ReplicateVideoModelError(
                        name: "REPLICATE_VIDEO_GENERATION_TIMEOUT",
                        message: "Video generation timed out after \(pollTimeoutMs)ms"
                    )
                }

                try await delay(pollIntervalMs)

                if options.abortSignal?() == true {
                    throw ReplicateVideoModelError(
                        name: "REPLICATE_VIDEO_GENERATION_ABORTED",
                        message: "Video generation request was aborted"
                    )
                }

                let pollHeaders = await resolve(config.headers)
                do {
                    let pollResult = try await getFromAPI(
                        url: finalPrediction.urls.get,
                        headers: pollHeaders.compactMapValues { $0 },
                        failedResponseHandler: replicateFailedResponseHandler,
                        successfulResponseHandler: createJsonResponseHandler(responseSchema: replicatePredictionSchema),
                        isAborted: options.abortSignal,
                        fetch: config.fetch
                    )

                    finalPrediction = pollResult.value
                } catch {
                    if isAbortError(error), options.abortSignal?() == true {
                        throw ReplicateVideoModelError(
                            name: "REPLICATE_VIDEO_GENERATION_ABORTED",
                            message: "Video generation request was aborted"
                        )
                    }
                    throw error
                }
            }
        }

        if finalPrediction.status == .failed {
            let errorMessage = finalPrediction.error ?? "Unknown error"
            throw ReplicateVideoModelError(
                name: "REPLICATE_VIDEO_GENERATION_FAILED",
                message: "Video generation failed: \(errorMessage)"
            )
        }

        if finalPrediction.status == .canceled {
            throw ReplicateVideoModelError(
                name: "REPLICATE_VIDEO_GENERATION_CANCELED",
                message: "Video generation was canceled"
            )
        }

        guard let videoUrl = finalPrediction.output, !videoUrl.isEmpty else {
            throw ReplicateVideoModelError(
                name: "REPLICATE_VIDEO_GENERATION_ERROR",
                message: "No video URL in response"
            )
        }

        let replicateMetadata: [String: JSONValue] = [
            "videos": .array([.object(["url": .string(videoUrl)])]),
            "predictionId": .string(finalPrediction.id),
            "metrics": {
                guard let metrics = finalPrediction.metrics else { return .null }
                var object: [String: JSONValue] = [:]
                if let predictTime = metrics.predictTime {
                    object["predict_time"] = .number(predictTime)
                } else {
                    object["predict_time"] = .null
                }
                return .object(object)
            }()
        ]

        return VideoModelV3GenerateResult(
            videos: [
                .url(url: videoUrl, mediaType: "video/mp4")
            ],
            warnings: warnings,
            providerMetadata: [
                "replicate": replicateMetadata
            ],
            response: VideoModelV3ResponseInfo(
                timestamp: now,
                modelId: modelIdentifier.rawValue,
                headers: postResult.responseHeaders
            )
        )
    }
}

// MARK: - Utilities

private func convertFileToDataUri(mediaType: String, data: VideoModelV3FileData) -> String {
    let base64: String
    switch data {
    case .base64(let value):
        base64 = value
    case .binary(let value):
        base64 = convertDataToBase64(value)
    }

    return "data:\(mediaType);base64,\(base64)"
}

private func jsNumberString(_ value: Double) -> String {
    if value.isFinite, value.rounded(.towardZero) == value {
        return String(Int(value))
    }
    return String(value)
}

private struct ReplicateVideoModelError: AISDKError, Sendable {
    static let errorDomain = "replicate.video.error"

    let name: String
    let message: String
    let cause: (any Error)? = nil
}
