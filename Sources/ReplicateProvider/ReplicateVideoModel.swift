import Foundation
import AISDKProvider
import AISDKProviderUtils

struct ReplicateVideoModelConfig: Sendable {
    let provider: String
    let baseURL: String
    let headers: @Sendable () throws -> [String: String?]
    let fetch: FetchFunction?
    var currentDate: @Sendable () -> Date = { Date() }
}

public struct ReplicateVideoModelOptions: Sendable, Codable, Equatable {
    public var pollIntervalMs: Double?
    public var pollTimeoutMs: Double?
    public var maxWaitTimeInSeconds: Double?
    public var guidance_scale: Double?
    public var num_inference_steps: Double?
    public var motion_bucket_id: Double?
    public var cond_aug: Double?
    public var decoding_t: Double?
    public var video_length: String?
    public var sizing_strategy: String?
    public var frames_per_second: Double?
    public var prompt_optimizer: Bool?
    public init() {}
}

private let replicateVideoOptionsSchema: FlexibleSchema<JSONValue> = {
    var properties: [String: JSONValue] = [:]
    for key in ["pollIntervalMs", "pollTimeoutMs", "maxWaitTimeInSeconds"] {
        properties[key] = .object(["type": .array([.string("number"), .string("null")]), "exclusiveMinimum": .number(0)])
    }
    for key in ["guidance_scale", "num_inference_steps", "motion_bucket_id", "cond_aug", "decoding_t", "frames_per_second"] {
        properties[key] = .object(["type": .array([.string("number"), .string("null")])])
    }
    for key in ["video_length", "sizing_strategy"] {
        properties[key] = .object(["type": .array([.string("string"), .string("null")])])
    }
    properties["prompt_optimizer"] = .object(["type": .array([.string("boolean"), .string("null")])])
    return FlexibleSchema(jsonSchema(.object(["type": .string("object"), "properties": .object(properties), "additionalProperties": .bool(true)])))
}()

private struct ReplicatePrediction: Decodable, Sendable {
    enum Status: String, Decodable, Sendable { case starting, processing, succeeded, failed, canceled }
    struct URLs: Decodable, Sendable { let get: String }
    struct Metrics: Decodable, Sendable { let predict_time: Double? }
    let id: String
    let status: Status
    let output: String?
    let error: String?
    let urls: URLs
    let metrics: Metrics?
}

private let replicatePredictionSchema = FlexibleSchema(Schema<ReplicatePrediction>.codable(
    ReplicatePrediction.self, jsonSchema: .object(["type": .string("object")])
))

public final class ReplicateVideoModel: VideoModelV4Operations, VideoModelV4WebhookHandler {
    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }
    public var maxVideosPerCall: VideoModelV4MaxVideosPerCall { .value(1) }
    private let modelIdentifier: ReplicateVideoModelId
    private let config: ReplicateVideoModelConfig

    init(_ modelId: ReplicateVideoModelId, config: ReplicateVideoModelConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public func handleWebhookOption(webhook: @escaping @Sendable () async throws -> VideoModelV4Webhook) async throws -> VideoModelV4WebhookRegistration {
        let value = try await webhook()
        return .init(webhookUrl: value.url, received: value.received)
    }

    public func doStart(options: VideoModelV4CallOptions, webhookUrl: String? = nil) async throws -> VideoModelV4OperationStartResult {
        let timestamp = config.currentDate()
        let parsed = try await parseProviderOptions(provider: "replicate", providerOptions: options.providerOptions, schema: replicateVideoOptionsSchema)
        var input: [String: JSONValue] = [:]
        if let prompt = options.prompt { input["prompt"] = .string(prompt) }
        if let image = options.image {
            switch image {
            case .url(let url, _, _): input["image"] = .string(url)
            case .file(let mediaType, let data, _):
                let base64: String
                switch data {
                case .base64(let value): base64 = value
                case .binary(let value): base64 = value.base64EncodedString()
                }
                input["image"] = .string("data:\(mediaType);base64,\(base64)")
            }
        }
        if let value = options.aspectRatio, !value.isEmpty { input["aspect_ratio"] = .string(value) }
        if let value = options.resolution, !value.isEmpty { input["size"] = .string(value) }
        if let value = options.duration, value != 0 { input["duration"] = .number(Double(value)) }
        if let value = options.fps, value != 0 { input["fps"] = .number(Double(value)) }
        if let value = options.seed, value != 0 { input["seed"] = .number(Double(value)) }
        if case .object(let values) = parsed {
            let controls: Set<String> = ["pollIntervalMs", "pollTimeoutMs", "maxWaitTimeInSeconds"]
            let known: Set<String> = ["guidance_scale", "num_inference_steps", "motion_bucket_id", "cond_aug", "decoding_t", "video_length", "sizing_strategy", "frames_per_second", "prompt_optimizer"]
            for (key, value) in values where !controls.contains(key) {
                if known.contains(key), value == .null { continue }
                input[key] = value
            }
        }
        let parts = modelId.split(separator: ":", omittingEmptySubsequences: false)
        var body: [String: JSONValue] = ["input": .object(input)]
        if parts.count > 1 { body["version"] = .string(String(parts[1])) }
        if let webhookUrl {
            body["webhook"] = .string(webhookUrl)
            body["webhook_events_filter"] = .array([.string("completed")])
        }
        let result = try await postJsonToAPI(
            url: parts.count > 1 ? "\(config.baseURL)/predictions" : "\(config.baseURL)/models/\(parts[0])/predictions",
            headers: combineHeaders(try config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 },
            body: JSONValue.object(body),
            failedResponseHandler: replicateFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: replicatePredictionSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )
        return .init(operation: .object(["getUrl": .string(result.value.urls.get)]), response: .init(timestamp: timestamp, modelId: modelId, headers: result.responseHeaders))
    }

    public func doStatus(options: VideoModelV4StatusCallOptions) async throws -> VideoModelV4OperationStatusResult {
        let timestamp = config.currentDate()
        guard case .object(let operation) = options.operation, case .string(let getUrl) = operation["getUrl"] else {
            throw InvalidArgumentError(parameter: "operation", value: options.operation, message: "Replicate operation must contain getUrl")
        }
        let result = try await getFromAPI(
            url: getUrl,
            headers: combineHeaders(try config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 },
            failedResponseHandler: replicateFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: replicatePredictionSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch,
            validateUrl: true,
            credentialedOrigin: config.baseURL,
            trustedOrigin: config.baseURL
        )
        let prediction = result.value
        let response = VideoModelV4ResponseInfo(timestamp: timestamp, modelId: modelId, headers: result.responseHeaders)
        switch prediction.status {
        case .failed:
            return .error(error: "Video generation failed: \(prediction.error ?? "Unknown error")", providerMetadata: nil, response: response)
        case .canceled:
            return .error(error: "Video generation was canceled", providerMetadata: nil, response: response)
        case .starting, .processing:
            return .pending(warnings: nil, providerMetadata: nil, response: response)
        case .succeeded:
            guard let url = prediction.output, !url.isEmpty else { throw ReplicateVideoModelError() }
            let metrics: JSONValue = prediction.metrics.map { .object(["predict_time": $0.predict_time.map(JSONValue.number) ?? .null]) } ?? .null
            return .completed(
                videos: [.url(url: url, mediaType: "video/mp4")],
                warnings: [],
                providerMetadata: ["replicate": ["videos": .array([.object(["url": .string(url)])]), "predictionId": .string(prediction.id), "metrics": metrics]],
                response: response
            )
        }
    }
}

private struct ReplicateVideoModelError: AISDKError, Sendable {
    static let errorDomain = "replicate.video.error"
    let name = "REPLICATE_VIDEO_GENERATION_ERROR"
    let message = "No video URL in response"
    let cause: (any Error)? = nil
}
