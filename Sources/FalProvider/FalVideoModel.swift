import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class FalVideoModel: VideoModelV4Operations, VideoModelV4WebhookHandler {
    public var specificationVersion: String { "v4" }
    public var maxVideosPerCall: VideoModelV4MaxVideosPerCall { .value(1) }
    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    private let modelIdentifier: FalVideoModelId
    private let config: FalConfig

    private var normalizedModelId: String {
        var value = modelId
        if value.hasPrefix("fal-ai/") { value.removeFirst("fal-ai/".count) }
        if value.hasPrefix("fal/") { value.removeFirst("fal/".count) }
        return value
    }

    init(modelId: FalVideoModelId, config: FalConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public func handleWebhookOption(
        webhook: @escaping @Sendable () async throws -> VideoModelV4Webhook
    ) async throws -> VideoModelV4WebhookRegistration {
        let value = try await webhook()
        return .init(webhookUrl: value.url, received: value.received)
    }

    public func doStart(
        options: VideoModelV4CallOptions,
        webhookUrl: String? = nil
    ) async throws -> VideoModelV4OperationStartResult {
        let now = config.currentDate()
        let body = try await buildRequestBody(options: options)
        var path = "https://queue.fal.run/fal-ai/\(normalizedModelId)"
        if let webhookUrl, !webhookUrl.isEmpty {
            let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
            path += "?fal_webhook=\(webhookUrl.addingPercentEncoding(withAllowedCharacters: allowed) ?? webhookUrl)"
        }
        let submitUrl = config.url(.init(modelId: modelId, path: path))
        let queue = try await postJsonToAPI(
            url: submitUrl,
            headers: combineHeaders(try config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 },
            body: JSONValue.object(body),
            failedResponseHandler: falFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: falJobResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )
        guard let responseUrl = queue.value.responseUrl, !responseUrl.isEmpty else {
            throw FalVideoModelError(message: "No response URL returned from queue endpoint")
        }
        return .init(
            operation: .object(["responseUrl": .string(responseUrl), "submitUrl": .string(submitUrl)]),
            warnings: [],
            response: .init(timestamp: now, modelId: modelId)
        )
    }

    public func doStatus(options: VideoModelV4StatusCallOptions) async throws -> VideoModelV4OperationStatusResult {
        let now = config.currentDate()
        guard case .object(let operation) = options.operation,
              case .string(let responseUrl) = operation["responseUrl"],
              case .string(let submitUrl) = operation["submitUrl"] else {
            throw InvalidArgumentError(argument: "operation", message: "Invalid fal video operation")
        }
        let statusUrl = config.url(.init(modelId: modelId, path: responseUrl))
        do {
            let response = try await getFromAPI(
                url: statusUrl,
                headers: combineHeaders(try config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 },
                failedResponseHandler: falVideoStatusFailedResponseHandler,
                successfulResponseHandler: createJsonResponseHandler(responseSchema: falVideoResponseSchema),
                isAborted: options.abortSignal,
                fetch: config.fetch,
                validateUrl: true,
                credentialedOrigin: submitUrl,
                trustedOrigin: submitUrl
            )
            return try buildResult(response: response.value, headers: response.responseHeaders, now: now)
        } catch let error as APICallError {
            if error.message == "Request is still in progress" {
                return .pending(warnings: nil, providerMetadata: nil, response: .init(timestamp: now, modelId: modelId))
            }
            return .error(
                error: error.message,
                providerMetadata: nil,
                response: .init(timestamp: now, modelId: modelId, headers: error.responseHeaders)
            )
        }
    }

    private func buildRequestBody(options: VideoModelV4CallOptions) async throws -> [String: JSONValue] {
        let falOptions = try await parseProviderOptions(
            provider: "fal",
            providerOptions: options.providerOptions,
            schema: falVideoModelOptionsSchema
        )
        var body: [String: JSONValue] = [:]
        if let prompt = options.prompt { body["prompt"] = .string(prompt) }
        if let image = options.image {
            switch image {
            case .url(let url, _, _):
                body["image_url"] = .string(url)
            case .file(let mediaType, let data, _):
                let base64: String
                switch data {
                case .base64(let value): base64 = value
                case .binary(let value): base64 = value.base64EncodedString()
                }
                body["image_url"] = .string("data:\(mediaType);base64,\(base64)")
            }
        }
        if let aspectRatio = options.aspectRatio, !aspectRatio.isEmpty { body["aspect_ratio"] = .string(aspectRatio) }
        if let duration = options.duration, duration != 0 { body["duration"] = .string("\(duration)s") }
        if let seed = options.seed, seed != 0 { body["seed"] = .number(Double(seed)) }
        let mapping = ["loop": "loop", "motionStrength": "motion_strength", "resolution": "resolution",
                       "negativePrompt": "negative_prompt", "promptOptimizer": "prompt_optimizer"]
        for (key, value) in falOptions?.options ?? [:] {
            if let apiKey = mapping[key] {
                if value != .null { body[apiKey] = value }
            } else {
                body[key] = value
            }
        }
        return body
    }

    private func buildResult(
        response: FalVideoResponse,
        headers: [String: String],
        now: Date
    ) throws -> VideoModelV4OperationStatusResult {
        guard let video = response.video, !video.url.isEmpty else {
            throw FalVideoModelError(message: "No video URL in response")
        }
        var videoMetadata: [String: JSONValue] = ["url": .string(video.url)]
        for key in ["width", "height", "duration", "fps"] {
            if let value = video.values[key] { videoMetadata[key] = value }
        }
        if let value = video.values["content_type"] { videoMetadata["contentType"] = value }
        var metadata: [String: JSONValue] = ["videos": .array([.object(videoMetadata)])]
        if let value = response.values["seed"] { metadata["seed"] = value }
        if let value = response.values["timings"], value != .null { metadata["timings"] = value }
        if let value = response.values["has_nsfw_concepts"] { metadata["has_nsfw_concepts"] = value }
        if case .string(let prompt) = response.values["prompt"], !prompt.isEmpty { metadata["prompt"] = .string(prompt) }
        let contentType: String
        if case .string(let value) = video.values["content_type"], !value.isEmpty {
            contentType = value
        } else {
            contentType = "video/mp4"
        }
        return .completed(
            videos: [.url(url: video.url, mediaType: contentType)],
            warnings: [],
            providerMetadata: ["fal": metadata],
            response: .init(timestamp: now, modelId: modelId, headers: headers)
        )
    }
}

public struct FalVideoModelOptions: Decodable, Sendable {
    public let options: [String: JSONValue]

    public init(options: [String: JSONValue] = [:]) throws {
        for key in ["loop", "promptOptimizer"] {
            guard let value = options[key] else { continue }
            switch value {
            case .bool, .null: break
            default:
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Expected '\(key)' to be a boolean"))
            }
        }
        for key in ["resolution", "negativePrompt"] {
            guard let value = options[key] else { continue }
            switch value {
            case .string, .null: break
            default:
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Expected '\(key)' to be a string"))
            }
        }
        if let value = options["motionStrength"], value != .null {
            guard case .number(let number) = value, (0...1).contains(number) else {
                throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "motionStrength must be between 0 and 1"))
            }
        }
        self.options = options
    }

    public init(from decoder: Decoder) throws {
        try self.init(options: decoder.singleValueContainer().decode([String: JSONValue].self))
    }
}

private let falVideoModelOptionsSchema = FlexibleSchema(
    Schema<FalVideoModelOptions>.codable(FalVideoModelOptions.self, jsonSchema: .object(["type": .string("object")]))
)

private struct FalJobResponse: Decodable, Sendable {
    let requestId: String?
    let responseUrl: String?
    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case responseUrl = "response_url"
    }
}

private let falJobResponseSchema = FlexibleSchema(
    Schema<FalJobResponse>.codable(FalJobResponse.self, jsonSchema: .object(["type": .string("object")]))
)

private struct FalVideoResponse: Decodable, Sendable {
    struct Video: Decodable, Sendable {
        let url: String
        let values: [String: JSONValue]
        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode([String: JSONValue].self)
            guard case .string(let url) = raw["url"] else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Missing video URL"))
            }
            self.url = url
            var values: [String: JSONValue] = [:]
            for key in ["width", "height", "duration", "fps", "content_type"] {
                guard let value = raw[key] else { continue }
                if key == "content_type" {
                    switch value {
                    case .null, .string: break
                    default:
                        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid video content_type"))
                    }
                } else if value != .null {
                    guard case .number = value else {
                        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid video \(key)"))
                    }
                }
                values[key] = value
            }
            self.values = values
        }
    }
    let video: Video?
    let values: [String: JSONValue]

    enum CodingKeys: String, CodingKey { case video, seed, timings, hasNSFW = "has_nsfw_concepts", prompt }
    struct Timings: Decodable { let inference: Double? }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        video = try container.decodeIfPresent(Video.self, forKey: .video)
        _ = try container.decodeIfPresent(Double.self, forKey: .seed)
        _ = try container.decodeIfPresent(Timings.self, forKey: .timings)
        _ = try container.decodeIfPresent([Bool].self, forKey: .hasNSFW)
        _ = try container.decodeIfPresent(String.self, forKey: .prompt)
        var values: [String: JSONValue] = [:]
        for key in [CodingKeys.seed, .timings, .hasNSFW, .prompt] {
            if container.contains(key) { values[key.rawValue] = try container.decode(JSONValue.self, forKey: key) }
        }
        if case .object(let timings) = values["timings"] {
            values["timings"] = .object(timings.filter { $0.key == "inference" })
        }
        self.values = values
    }
}

private let falVideoResponseSchema = FlexibleSchema(
    Schema<FalVideoResponse>.codable(FalVideoResponse.self, jsonSchema: .object(["type": .string("object")]))
)

private let falVideoStatusFailedResponseHandler: ResponseHandler<APICallError> = { input in
    let response = input.response
    let data = try await response.body.collectData()
    if let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
       object["detail"] as? String == "Request is still in progress" {
        return ResponseHandlerResult(
            value: APICallError(message: "Request is still in progress", url: input.url, requestBodyValues: input.requestBodyValues),
            rawValue: object,
            responseHeaders: [:]
        )
    }
    return try await falFailedResponseHandler(.init(
        url: input.url,
        requestBodyValues: input.requestBodyValues,
        response: .init(url: response.url, httpResponse: response.httpResponse, body: .data(data))
    ))
}

private struct FalVideoModelError: AISDKError, Sendable {
    static let errorDomain = "fal.video.error"
    let name = "FAL_VIDEO_GENERATION_ERROR"
    let message: String
    let cause: (any Error)? = nil
}
