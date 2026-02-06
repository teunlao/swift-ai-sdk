import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/fal/src/fal-video-model.ts
// Upstream commit: f3a72bc2
//===----------------------------------------------------------------------===//

public final class FalVideoModel: VideoModelV3 {
    public var specificationVersion: String { "v3" }
    public var maxVideosPerCall: VideoModelV3MaxVideosPerCall { .value(1) }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    private let modelIdentifier: FalVideoModelId
    private let config: FalConfig

    private var normalizedModelId: String {
        var value = modelIdentifier.rawValue
        if value.hasPrefix("fal-ai/") {
            value.removeFirst("fal-ai/".count)
        }
        if value.hasPrefix("fal/") {
            value.removeFirst("fal/".count)
        }
        return value
    }

    init(modelId: FalVideoModelId, config: FalConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public func doGenerate(options: VideoModelV3CallOptions) async throws -> VideoModelV3GenerateResult {
        let now = config.currentDate()
        let warnings: [SharedV3Warning] = []

        let parsedOptions = try await parseProviderOptions(
            provider: "fal",
            providerOptions: options.providerOptions,
            schema: falVideoProviderOptionsSchema
        )

        var body: [String: JSONValue] = [:]

        if let prompt = options.prompt {
            body["prompt"] = .string(prompt)
        }

        if let image = options.image {
            switch image {
            case .url(let url, _):
                body["image_url"] = .string(url)
            case .file(let mediaType, let data, _):
                body["image_url"] = .string(convertFileToDataUri(mediaType: mediaType, data: data))
            }
        }

        if let aspectRatio = options.aspectRatio {
            body["aspect_ratio"] = .string(aspectRatio)
        }

        if let duration = options.duration {
            body["duration"] = .string("\(duration)s")
        }

        if let seed = options.seed {
            body["seed"] = .number(Double(seed))
        }

        let rawFalOptions = options.providerOptions?["fal"] ?? [:]

        if let loop = parsedOptions?.loop {
            body["loop"] = .bool(loop)
        }

        if let motionStrength = parsedOptions?.motionStrength {
            body["motion_strength"] = .number(motionStrength)
        }

        if let resolution = parsedOptions?.resolution {
            body["resolution"] = .string(resolution)
        }

        if let negativePrompt = parsedOptions?.negativePrompt {
            body["negative_prompt"] = .string(negativePrompt)
        }

        if let promptOptimizer = parsedOptions?.promptOptimizer {
            body["prompt_optimizer"] = .bool(promptOptimizer)
        }

        let excludedKeys: Set<String> = [
            "loop",
            "motionStrength",
            "pollIntervalMs",
            "pollTimeoutMs",
            "resolution",
            "negativePrompt",
            "promptOptimizer",
        ]

        for (key, value) in rawFalOptions {
            guard !excludedKeys.contains(key) else { continue }
            body[key] = value
        }

        let headers = combineHeaders(config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 }

        let queueResponse = try await postJsonToAPI(
            url: config.url(.init(
                modelId: modelIdentifier.rawValue,
                path: "https://queue.fal.run/fal-ai/\(normalizedModelId)"
            )),
            headers: headers,
            body: JSONValue.object(body),
            failedResponseHandler: falFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: falJobResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        guard let responseUrl = queueResponse.value.responseUrl, !responseUrl.isEmpty else {
            throw FalVideoModelError(
                name: "FAL_VIDEO_GENERATION_ERROR",
                message: "No response URL returned from queue endpoint"
            )
        }

        let pollIntervalMs = parsedOptions?.pollIntervalMs ?? 2000
        let pollTimeoutMs = parsedOptions?.pollTimeoutMs ?? 300_000
        let start = Date()

        var response: FalVideoStatusResponse
        var responseHeaders: [String: String]?

        while true {
            do {
                let status = try await getFromAPI(
                    url: config.url(.init(modelId: modelIdentifier.rawValue, path: responseUrl)),
                    headers: headers,
                    failedResponseHandler: falPollingFailedResponseHandler,
                    successfulResponseHandler: createJsonResponseHandler(responseSchema: falVideoStatusResponseSchema),
                    isAborted: options.abortSignal,
                    fetch: config.fetch
                )
                response = status.value
                responseHeaders = status.responseHeaders
                break
            } catch let error as APICallError {
                if error.message == FalVideoPollingConstants.inProgressDetail {
                    // Continue polling.
                } else {
                    throw error
                }
            }

            let elapsedMs = Int(start.timeIntervalSinceNow * -1000)
            if elapsedMs > pollTimeoutMs {
                throw FalVideoModelError(
                    name: "FAL_VIDEO_GENERATION_TIMEOUT",
                    message: "Video generation request timed out after \(pollTimeoutMs)ms"
                )
            }

            try await delay(pollIntervalMs)

            if options.abortSignal?() == true {
                throw FalVideoModelError(
                    name: "FAL_VIDEO_GENERATION_ABORTED",
                    message: "Video generation request was aborted"
                )
            }
        }

        guard let video = response.video, !video.url.isEmpty else {
            throw FalVideoModelError(
                name: "FAL_VIDEO_GENERATION_ERROR",
                message: "No video URL in response"
            )
        }

        let videoUrl = video.url
        let mediaType = video.contentType ?? "video/mp4"

        var videoMetadata: [String: JSONValue] = ["url": .string(videoUrl)]
        if let contentType = video.contentType {
            videoMetadata["contentType"] = .string(contentType)
        }

        if let width = video.width {
            videoMetadata["width"] = .number(width)
        }
        if let height = video.height {
            videoMetadata["height"] = .number(height)
        }
        if let duration = video.duration {
            videoMetadata["duration"] = .number(duration)
        }
        if let fps = video.fps {
            videoMetadata["fps"] = .number(fps)
        }

        var falMetadata: [String: JSONValue] = [
            "videos": .array([.object(videoMetadata)]),
        ]

        if let seed = response.seed {
            falMetadata["seed"] = .number(seed)
        }

        if let timings = response.timings {
            var timingsObject: [String: JSONValue] = [:]
            if let inference = timings.inference {
                timingsObject["inference"] = .number(inference)
            }
            falMetadata["timings"] = .object(timingsObject)
        }

        if let nsfw = response.hasNSFWConcepts {
            falMetadata["has_nsfw_concepts"] = .array(nsfw.map(JSONValue.bool))
        }

        if let prompt = response.prompt {
            falMetadata["prompt"] = .string(prompt)
        }

        return VideoModelV3GenerateResult(
            videos: [
                .url(url: videoUrl, mediaType: mediaType)
            ],
            warnings: warnings,
            providerMetadata: [
                "fal": falMetadata
            ],
            response: VideoModelV3ResponseInfo(
                timestamp: now,
                modelId: modelIdentifier.rawValue,
                headers: responseHeaders
            )
        )
    }
}

// MARK: - Provider options

public struct FalVideoProviderOptions: Codable, Sendable {
    public var loop: Bool?
    public var motionStrength: Double?
    public var pollIntervalMs: Int?
    public var pollTimeoutMs: Int?
    public var resolution: String?
    public var negativePrompt: String?
    public var promptOptimizer: Bool?

    enum CodingKeys: String, CodingKey {
        case loop
        case motionStrength
        case pollIntervalMs
        case pollTimeoutMs
        case resolution
        case negativePrompt
        case promptOptimizer
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        loop = try container.decodeIfPresent(Bool.self, forKey: .loop)
        motionStrength = try container.decodeIfPresent(Double.self, forKey: .motionStrength)
        pollIntervalMs = try container.decodeIfPresent(Int.self, forKey: .pollIntervalMs)
        pollTimeoutMs = try container.decodeIfPresent(Int.self, forKey: .pollTimeoutMs)
        resolution = try container.decodeIfPresent(String.self, forKey: .resolution)
        negativePrompt = try container.decodeIfPresent(String.self, forKey: .negativePrompt)
        promptOptimizer = try container.decodeIfPresent(Bool.self, forKey: .promptOptimizer)

        if let motionStrength {
            guard (0.0...1.0).contains(motionStrength) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .motionStrength,
                    in: container,
                    debugDescription: "motionStrength must be between 0 and 1"
                )
            }
        }

        if let pollIntervalMs {
            guard pollIntervalMs > 0 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .pollIntervalMs,
                    in: container,
                    debugDescription: "pollIntervalMs must be positive"
                )
            }
        }

        if let pollTimeoutMs {
            guard pollTimeoutMs > 0 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .pollTimeoutMs,
                    in: container,
                    debugDescription: "pollTimeoutMs must be positive"
                )
            }
        }
    }

    public init() {}
}

private let falVideoProviderOptionsSchema = FlexibleSchema(
    Schema<FalVideoProviderOptions>.codable(
        FalVideoProviderOptions.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

// MARK: - API schemas

private struct FalJobResponse: Codable, Sendable {
    let requestId: String?
    let responseUrl: String?

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case responseUrl = "response_url"
    }
}

private let falJobResponseSchema = FlexibleSchema(
    Schema<FalJobResponse>.codable(
        FalJobResponse.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

private struct FalVideoStatusResponse: Codable, Sendable {
    struct Video: Codable, Sendable {
        let url: String
        let width: Double?
        let height: Double?
        let duration: Double?
        let fps: Double?
        let contentType: String?

        enum CodingKeys: String, CodingKey {
            case url
            case width
            case height
            case duration
            case fps
            case contentType = "content_type"
        }
    }

    struct Timings: Codable, Sendable {
        let inference: Double?
    }

    let video: Video?
    let seed: Double?
    let timings: Timings?
    let hasNSFWConcepts: [Bool]?
    let prompt: String?

    enum CodingKeys: String, CodingKey {
        case video
        case seed
        case timings
        case hasNSFWConcepts = "has_nsfw_concepts"
        case prompt
    }
}

private let falVideoStatusResponseSchema = FlexibleSchema(
    Schema<FalVideoStatusResponse>.codable(
        FalVideoStatusResponse.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

// MARK: - Polling

private enum FalVideoPollingConstants {
    static let inProgressDetail = "Request is still in progress"
}

private let falPollingFailedResponseHandler: ResponseHandler<APICallError> = { input in
    let response = input.response
    let headers = extractResponseHeaders(from: response.httpResponse)
    let bodyData = try await response.body.collectData()
    let bodyText = String(data: bodyData, encoding: .utf8) ?? ""

    if let data = bodyText.data(using: .utf8),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let detail = json["detail"] as? String,
       detail == FalVideoPollingConstants.inProgressDetail {
        return ResponseHandlerResult(
            value: APICallError(
                message: FalVideoPollingConstants.inProgressDetail,
                url: input.url,
                requestBodyValues: input.requestBodyValues,
                statusCode: response.statusCode,
                responseHeaders: headers,
                responseBody: bodyText
            ),
            rawValue: json,
            responseHeaders: headers
        )
    }

    return try await falFailedResponseHandler(input)
}

// MARK: - Helpers

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

private struct FalVideoModelError: AISDKError, Sendable {
    static let errorDomain = "fal.video.error"

    let name: String
    let message: String
    let cause: (any Error)? = nil
}
