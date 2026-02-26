import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/xai/src/xai-video-model.ts
// Upstream commit: 73d5c59
//===----------------------------------------------------------------------===//

struct XAIVideoModelConfig: Sendable {
    let provider: String
    let baseURL: String?
    let headers: @Sendable () throws -> [String: String?]
    let fetch: FetchFunction?
    let currentDate: @Sendable () -> Date

    init(
        provider: String,
        baseURL: String?,
        headers: @escaping @Sendable () throws -> [String: String?],
        fetch: FetchFunction? = nil,
        currentDate: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.provider = provider
        self.baseURL = baseURL
        self.headers = headers
        self.fetch = fetch
        self.currentDate = currentDate
    }
}

private struct XAIVideoCreateResponse: Codable {
    let requestId: String?

    private enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
    }
}

private struct XAIVideoStatusResponse: Codable {
    struct Video: Codable {
        let url: String
        let duration: Double?
        let respectModeration: Bool?

        private enum CodingKeys: String, CodingKey {
            case url
            case duration
            case respectModeration = "respect_moderation"
        }
    }

    let status: String?
    let video: Video?
    let model: String?
}

private let genericJSONObjectSchema: JSONValue = .object(["type": .string("object")])

private let xaiCreateVideoResponseSchema = FlexibleSchema(
    Schema<XAIVideoCreateResponse>.codable(
        XAIVideoCreateResponse.self,
        jsonSchema: genericJSONObjectSchema
    )
)

private let xaiVideoStatusResponseSchema = FlexibleSchema(
    Schema<XAIVideoStatusResponse>.codable(
        XAIVideoStatusResponse.self,
        jsonSchema: genericJSONObjectSchema
    )
)

private let resolutionMap: [String: String] = [
    "1280x720": "720p",
    "854x480": "480p",
    "640x480": "480p",
]

public final class XAIVideoModel: VideoModelV3 {
    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }
    public var maxVideosPerCall: VideoModelV3MaxVideosPerCall { .value(1) }

    private let modelIdentifier: XAIVideoModelId
    private let config: XAIVideoModelConfig

    init(modelId: XAIVideoModelId, config: XAIVideoModelConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public func doGenerate(options: VideoModelV3CallOptions) async throws -> VideoModelV3GenerateResult {
        let currentDate = config.currentDate()
        var warnings: [SharedV3Warning] = []

        let xaiOptions = try await parseProviderOptions(
            provider: "xai",
            providerOptions: options.providerOptions,
            schema: xaiVideoModelOptionsSchema
        )

        let isEdit = xaiOptions?.videoUrl != nil

        if options.fps != nil {
            warnings.append(.unsupported(
                feature: "fps",
                details: "xAI video models do not support custom FPS."
            ))
        }

        if options.seed != nil {
            warnings.append(.unsupported(
                feature: "seed",
                details: "xAI video models do not support seed."
            ))
        }

        if options.n > 1 {
            warnings.append(.unsupported(
                feature: "n",
                details: "xAI video models do not support generating multiple videos per call. Only 1 video will be generated."
            ))
        }

        if isEdit, options.duration != nil {
            warnings.append(.unsupported(
                feature: "duration",
                details: "xAI video editing does not support custom duration."
            ))
        }

        if isEdit, options.aspectRatio != nil {
            warnings.append(.unsupported(
                feature: "aspectRatio",
                details: "xAI video editing does not support custom aspect ratio."
            ))
        }

        if isEdit, (xaiOptions?.resolution != nil || options.resolution != nil) {
            warnings.append(.unsupported(
                feature: "resolution",
                details: "xAI video editing does not support custom resolution."
            ))
        }

        var body: [String: JSONValue] = [
            "model": .string(modelIdentifier.rawValue),
        ]

        if let prompt = options.prompt {
            body["prompt"] = .string(prompt)
        }

        if !isEdit, let duration = options.duration {
            body["duration"] = .number(Double(duration))
        }

        if !isEdit, let aspectRatio = options.aspectRatio {
            body["aspect_ratio"] = .string(aspectRatio)
        }

        if !isEdit, let providerResolution = xaiOptions?.resolution {
            body["resolution"] = .string(providerResolution)
        } else if !isEdit, let resolution = options.resolution {
            if let mapped = resolutionMap[resolution] {
                body["resolution"] = .string(mapped)
            } else {
                warnings.append(.unsupported(
                    feature: "resolution",
                    details: "Unrecognized resolution \"\(resolution)\". Use providerOptions.xai.resolution with \"480p\" or \"720p\" instead."
                ))
            }
        }

        if let videoUrl = xaiOptions?.videoUrl {
            body["video"] = .object(["url": .string(videoUrl)])
        }

        if let image = options.image {
            switch image {
            case .url(let url, _):
                body["image"] = .object(["url": .string(url)])
            case .file(let mediaType, let data, _):
                let base64Data: String
                switch data {
                case .base64(let str):
                    base64Data = str
                case .binary(let bytes):
                    base64Data = convertToBase64(.data(bytes))
                }
                body["image"] = .object([
                    "url": .string("data:\(mediaType);base64,\(base64Data)")
                ])
            }
        }

        if let raw = xaiOptions?.raw {
            for (key, value) in raw {
                if ["pollIntervalMs", "pollTimeoutMs", "resolution", "videoUrl"].contains(key) {
                    continue
                }
                body[key] = value
            }
        }

        let baseURL = config.baseURL ?? "https://api.x.ai/v1"

        let createHeaders = combineHeaders(
            try config.headers(),
            options.headers?.mapValues { Optional($0) }
        ).compactMapValues { $0 }

        let createResponse = try await postJsonToAPI(
            url: "\(baseURL)/videos/\(isEdit ? "edits" : "generations")",
            headers: createHeaders,
            body: JSONValue.object(body),
            failedResponseHandler: xaiFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: xaiCreateVideoResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        guard let requestId = createResponse.value.requestId, !requestId.isEmpty else {
            throw XAIVideoModelError(
                name: "XAI_VIDEO_GENERATION_ERROR",
                message: "No request_id returned from xAI API. Response: \(encodeJSONString(createResponse.value))"
            )
        }

        let pollIntervalMs = xaiOptions?.pollIntervalMs ?? 5000
        let pollTimeoutMs = xaiOptions?.pollTimeoutMs ?? 600000
        let startTime = Date()
        var responseHeaders: [String: String]? = nil

        while true {
            try await delay(Int(pollIntervalMs.rounded(.towardZero)), abortSignal: options.abortSignal)

            let elapsedMs = Date().timeIntervalSince(startTime) * 1000
            if elapsedMs > pollTimeoutMs {
                throw XAIVideoModelError(
                    name: "XAI_VIDEO_GENERATION_TIMEOUT",
                    message: "Video generation timed out after \(pollTimeoutMs)ms"
                )
            }

            let statusHeaders = combineHeaders(
                try config.headers(),
                options.headers?.mapValues { Optional($0) }
            ).compactMapValues { $0 }

            let statusResponse = try await getFromAPI(
                url: "\(baseURL)/videos/\(requestId)",
                headers: statusHeaders,
                failedResponseHandler: xaiFailedResponseHandler,
                successfulResponseHandler: createJsonResponseHandler(responseSchema: xaiVideoStatusResponseSchema),
                isAborted: options.abortSignal,
                fetch: config.fetch
            )

            responseHeaders = statusResponse.responseHeaders

            let status = statusResponse.value.status
            let videoUrl = statusResponse.value.video?.url

            if status == "done" || (status == nil && videoUrl != nil) {
                guard let videoUrl else {
                    throw XAIVideoModelError(
                        name: "XAI_VIDEO_GENERATION_ERROR",
                        message: "Video generation completed but no video URL was returned."
                    )
                }

                var xaiMetadata: [String: JSONValue] = [
                    "requestId": .string(requestId),
                    "videoUrl": .string(videoUrl),
                ]

                if let duration = statusResponse.value.video?.duration {
                    xaiMetadata["duration"] = .number(duration)
                }

                return VideoModelV3GenerateResult(
                    videos: [
                        .url(url: videoUrl, mediaType: "video/mp4")
                    ],
                    warnings: warnings,
                    providerMetadata: [
                        "xai": xaiMetadata
                    ],
                    response: VideoModelV3ResponseInfo(
                        timestamp: currentDate,
                        modelId: modelIdentifier.rawValue,
                        headers: responseHeaders
                    )
                )
            }

            if status == "expired" {
                throw XAIVideoModelError(
                    name: "XAI_VIDEO_GENERATION_EXPIRED",
                    message: "Video generation request expired."
                )
            }

            // pending -> continue polling
        }
    }
}

private struct XAIVideoModelError: AISDKError, Sendable {
    static let errorDomain = "xai.video.error"

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
