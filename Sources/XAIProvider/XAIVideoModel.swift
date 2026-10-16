import Foundation
import AISDKProvider
import AISDKProviderUtils

struct XAIVideoModelConfig: Sendable {
    let provider: String
    let baseURL: String?
    let headers: @Sendable () throws -> [String: String?]
    let fetch: FetchFunction?
    let currentDate: @Sendable () -> Date
    init(provider: String, baseURL: String?, headers: @escaping @Sendable () throws -> [String: String?], fetch: FetchFunction? = nil, currentDate: @escaping @Sendable () -> Date = { Date() }) {
        self.provider = provider; self.baseURL = baseURL; self.headers = headers; self.fetch = fetch; self.currentDate = currentDate
    }
}

private struct XAIVideoCreateResponse: Codable, Sendable {
    let requestId: String?
    enum CodingKeys: String, CodingKey { case requestId = "request_id" }
}

private struct XAIVideoStatusResponse: Codable, Sendable {
    struct Video: Codable, Sendable {
        struct FileOutput: Codable, Sendable {
            let fileId: String
            let filename: String
            let expiresAt: Double?
            let publicUrl: String?
            let publicUrlError: String?
            let publicUrlExpiresAt: Double?
            enum CodingKeys: String, CodingKey {
                case fileId = "file_id", filename, expiresAt = "expires_at", publicUrl = "public_url", publicUrlError = "public_url_error", publicUrlExpiresAt = "public_url_expires_at"
            }
        }
        let url: String?
        let duration: Double?
        let respectModeration: Bool?
        let fileOutput: FileOutput?
        let storageError: String?
        enum CodingKeys: String, CodingKey { case url, duration, respectModeration = "respect_moderation", fileOutput = "file_output", storageError = "storage_error" }
    }
    struct Usage: Codable, Sendable { let costInUsdTicks: Double?; enum CodingKeys: String, CodingKey { case costInUsdTicks = "cost_in_usd_ticks" } }
    struct Failure: Codable, Sendable { let code: String?; let message: String? }
    let status: String?
    let video: Video?
    let model: String?
    let usage: Usage?
    let progress: Double?
    let error: Failure?
}

private let xaiCreateVideoSchema = FlexibleSchema(Schema<XAIVideoCreateResponse>.codable(XAIVideoCreateResponse.self, jsonSchema: .object(["type": .string("object")])))
private let xaiStatusVideoSchema = FlexibleSchema(Schema<XAIVideoStatusResponse>.codable(XAIVideoStatusResponse.self, jsonSchema: .object(["type": .string("object")])))

private let xaiVideoStatusResponseHandler: ResponseHandler<XAIVideoStatusResponse> = { input in
    if input.response.statusCode != 202 { return try await createJsonResponseHandler(responseSchema: xaiStatusVideoSchema)(input) }
    var data = Data()
    for try await chunk in input.response.body.makeStream() {
        data.append(chunk)
        if data.count > 1_048_576 {
            throw APICallError(message: "xAI video status response exceeded 1048576 bytes", url: input.url, requestBodyValues: input.requestBodyValues, statusCode: 202, responseHeaders: extractResponseHeaders(from: input.response.httpResponse))
        }
    }
    let pending = XAIVideoStatusResponse(status: "pending", video: nil, model: nil, usage: nil, progress: nil, error: nil)
    return .init(value: (try? JSONDecoder().decode(XAIVideoStatusResponse.self, from: data)) ?? pending, responseHeaders: extractResponseHeaders(from: input.response.httpResponse))
}

public final class XAIVideoModel: VideoModelV4Operations {
    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }
    public var maxVideosPerCall: VideoModelV4MaxVideosPerCall { .value(1) }
    private let modelIdentifier: XAIVideoModelId
    private let config: XAIVideoModelConfig
    init(modelId: XAIVideoModelId, config: XAIVideoModelConfig) { self.modelIdentifier = modelId; self.config = config }

    private func prepare(_ options: VideoModelV4CallOptions) async throws -> (body: [String: JSONValue], warnings: [SharedV4Warning], mode: XAIVideoMode?) {
        let parsed = try await parseProviderOptions(provider: "xai", providerOptions: options.providerOptions, schema: xaiVideoModelOptionsSchema)
        let xai = parsed?.options ?? .init()
        let references = options.inputReferences ?? []
        let images = references.filter { mediaType($0) == nil || mediaType($0)?.hasPrefix("image/") == true }
        let audios = references.filter { mediaType($0)?.hasPrefix("audio/") == true }
        let mode = xai.mode ?? (xai.videoUrl != nil ? .editVideo : !images.isEmpty || !audios.isEmpty || xai.referenceImageUrls?.isEmpty == false ? .referenceToVideo : nil)
        let edit = mode == .editVideo
        let extend = mode == .extendVideo
        let reference = mode == .referenceToVideo
        var warnings: [SharedV4Warning] = []
        func warn(_ feature: String, _ details: String) { warnings.append(.unsupported(feature: feature, details: details)) }
        if options.fps != nil { warn("fps", "xAI video models do not support custom FPS.") }
        if options.seed != nil { warn("seed", "xAI video models do not support seed.") }
        if options.n > 1 { warn("n", "xAI video models do not support generating multiple videos per call. Only 1 video will be generated.") }
        if edit && options.duration != nil { warn("duration", "xAI video editing does not support custom duration.") }
        if (edit || extend) && options.aspectRatio != nil { warn("aspectRatio", "xAI video \(edit ? "editing" : "extension") does not support custom aspect ratio.") }
        if (edit || extend) && (xai.resolution != nil || options.resolution != nil) { warn("resolution", "xAI video \(edit ? "editing" : "extension") does not support custom resolution.") }
        var body: [String: JSONValue] = ["model": .string(modelId)]
        if let prompt = options.prompt { body["prompt"] = .string(prompt) }
        if !edit, let duration = options.duration { body["duration"] = .number(Double(duration)) }
        if !edit && !extend {
            if let ratio = options.aspectRatio { body["aspect_ratio"] = .string(ratio) }
            if let resolution = xai.resolution { body["resolution"] = .string(resolution) }
            else if let resolution = options.resolution {
                if let mapped = ["1920x1080": "1080p", "1280x720": "720p", "854x480": "480p", "640x480": "480p"][resolution] { body["resolution"] = .string(mapped) }
                else { warn("resolution", "Unrecognized resolution \"\(resolution)\". Use providerOptions.xai.resolution with \"480p\", \"720p\", or \"1080p\" instead.") }
            }
        }
        if let audio = options.generateAudio {
            if edit || extend { warn("generateAudio", "xAI video \(edit ? "editing" : "extension") does not support generateAudio.") }
            else { body["generate_audio"] = .bool(audio) }
        }
        if let storage = xai.storageOptions {
            var value: [String: JSONValue] = ["filename": .string(storage.filename)]
            if let expires = storage.expiresAfter { value["expires_after"] = .number(Double(expires)) }
            if let publicURL = storage.publicUrl {
                switch publicURL {
                case .enabled(let enabled): value["public_url"] = .bool(enabled)
                case .expiring(let expires): value["public_url"] = .object(expires.map { ["expires_after": .number(Double($0))] } ?? [:])
                }
            }
            body["storage_options"] = .object(value)
        }
        if let keyframes = xai.keyframes, !keyframes.isEmpty {
            if modelId != "grok-imagine-video-1.5" || edit || extend {
                warn("keyframes", modelId != "grok-imagine-video-1.5" ? "xAI only supports keyframes with \"grok-imagine-video-1.5\"." : "xAI video \(edit ? "editing" : "extension") does not support keyframes.")
            } else { body["keyframes"] = .array(keyframes.map { .object(["image": .object(["url": .string($0.imageUrl)]), "timestamp_s": .number($0.timestampSeconds)]) }) }
        }
        if edit || extend { body["video"] = .object(xai.videoUrl.map { ["url": .string($0)] } ?? [:]) }
        let firstFrame = options.frameImages?.first { $0.frameType == .firstFrame }?.image
        if let image = firstFrame ?? options.image {
            if mediaType(image)?.hasPrefix("video/") == true {
                warn(firstFrame == nil ? "image" : "frameImages", "xAI does not accept a video as a start/frame image. The video was ignored. Use providerOptions.xai.mode \"extend-video\" to continue from a video instead.")
            } else { body["image"] = .object(["url": .string(fileURL(image))]) }
        }
        if let image = options.frameImages?.first(where: { $0.frameType == .lastFrame })?.image {
            if modelId != "grok-imagine-video-1.5" || edit || extend || mediaType(image)?.hasPrefix("video/") == true {
                warn("frameImages", modelId != "grok-imagine-video-1.5" ? "xAI only supports last_frame with \"grok-imagine-video-1.5\". The last frame was ignored." : "xAI only accepts an image last_frame for video generation. The last frame was ignored.")
            } else { body["last_frame"] = .object(["url": .string(fileURL(image))]) }
        }
        if reference {
            for file in references where mediaType(file)?.hasPrefix("video/") == true { warn("inputReferences", "xAI reference-to-video does not accept video references. The video reference was ignored. Use providerOptions.xai.mode \"extend-video\" to continue from a video.") }
            let imageURLs = !references.isEmpty ? images.map(fileURL) : (xai.referenceImageUrls ?? [])
            if !imageURLs.isEmpty { body["reference_images"] = .array(imageURLs.map { .object(["url": .string($0)]) }) }
            else if audios.isEmpty { warn("referenceImages", "xAI reference-to-video requires at least one image reference. The video will be generated without reference images.") }
            let audioInputs = audios.map { JSONValue.object(["url": .string(fileURL($0))]) } + (xai.referenceVoiceIds ?? []).map { .object(["voice_id": .string($0)]) }
            if !audioInputs.isEmpty {
                if audioInputs.count > 3 { warn("inputReferences", "xAI reference-to-video supports at most 3 audio references. Only the first 3 were used.") }
                body["reference_audios"] = .array(Array(audioInputs.prefix(3)))
            }
            if body["resolution"] == .string("1080p") {
                warn("resolution", "xAI reference-to-video is limited to 720p. The request was downgraded from 1080p to 720p.")
                body["resolution"] = .string("720p")
            }
        }
        if body["resolution"] == .string("1080p") && modelId == "grok-imagine-video" { warn("resolution", "xAI model \"grok-imagine-video\" does not support 1080p. Use \"grok-imagine-video-1.5\" for 1080p, or a lower resolution. The request was sent with 1080p.") }
        if !references.isEmpty && !reference { warn("inputReferences", !images.isEmpty || !audios.isEmpty ? "xAI only supports inputReferences for reference-to-video generation. The references were ignored." : "xAI reference-to-video requires at least one image or audio reference. The references were ignored.") }
        if xai.referenceVoiceIds?.isEmpty == false && !reference { warn("referenceVoiceIds", "xAI only supports reference voices for reference-to-video generation. The reference voices were ignored.") }
        if !extend, let user = xai.user { body["user"] = .string(user) }
        body.merge(parsed?.extra ?? [:]) { _, new in new }
        return (body, warnings, mode)
    }

    public func doStart(options: VideoModelV4CallOptions, webhookUrl: String? = nil) async throws -> VideoModelV4OperationStartResult {
        let timestamp = config.currentDate()
        let prepared = try await prepare(options)
        let endpoint = prepared.mode == .editVideo ? "edits" : prepared.mode == .extendVideo ? "extensions" : "generations"
        let response = try await postJsonToAPI(url: "\(config.baseURL ?? "https://api.x.ai/v1")/videos/\(endpoint)", headers: combineHeaders(try config.headers(), options.headers?.mapValues(Optional.some)).compactMapValues { $0 }, body: JSONValue.object(prepared.body), failedResponseHandler: xaiFailedResponseHandler, successfulResponseHandler: createJsonResponseHandler(responseSchema: xaiCreateVideoSchema), isAborted: options.abortSignal, fetch: config.fetch)
        guard let id = response.value.requestId, !id.isEmpty else { throw XAIVideoModelError(name: "XAI_VIDEO_GENERATION_ERROR", message: "No request_id returned from xAI API.") }
        return .init(operation: .object(["requestId": .string(id)]), warnings: prepared.warnings, response: .init(timestamp: timestamp, modelId: modelId, headers: response.responseHeaders))
    }

    public func doStatus(options: VideoModelV4StatusCallOptions) async throws -> VideoModelV4OperationStatusResult {
        guard case .object(let operation) = options.operation, case .string(let requestId) = operation["requestId"] else { throw InvalidArgumentError(argument: "operation", message: "Expected an xAI requestId") }
        let timestamp = config.currentDate()
        let response = try await getFromAPI(url: "\(config.baseURL ?? "https://api.x.ai/v1")/videos/\(xaiPathSegment(requestId))", headers: combineHeaders(try config.headers(), options.headers?.mapValues(Optional.some)).compactMapValues { $0 }, failedResponseHandler: xaiFailedResponseHandler, successfulResponseHandler: xaiVideoStatusResponseHandler, isAborted: options.abortSignal, fetch: config.fetch)
        let status = response.value
        let info = VideoModelV4ResponseInfo(timestamp: timestamp, modelId: modelId, headers: response.responseHeaders)
        if status.status == "expired" { return .error(error: "Video generation request expired.", providerMetadata: nil, response: info) }
        if status.status == "failed" {
            let detail = status.error?.message ?? status.error?.code
            return .error(error: detail.map { "Video generation failed: \($0)" } ?? "Video generation failed.", providerMetadata: nil, response: info)
        }
        if status.status == "done" || (status.status == nil && status.video?.url?.isEmpty == false) {
            if status.video?.respectModeration == false { return .error(error: "Video generation was blocked due to a content policy violation.", providerMetadata: nil, response: info) }
            guard let url = status.video?.url ?? status.video?.fileOutput?.publicUrl, !url.isEmpty else { return .error(error: "Video generation completed but no video URL was returned.", providerMetadata: nil, response: info) }
            var metadata: [String: JSONValue] = ["requestId": .string(requestId), "videoUrl": .string(url)]
            if let value = status.video?.duration { metadata["duration"] = .number(value) }
            if let value = status.usage?.costInUsdTicks { metadata["costInUsdTicks"] = .number(value) }
            if let value = status.progress { metadata["progress"] = .number(value) }
            if let output = status.video?.fileOutput {
                var file: [String: JSONValue] = ["fileId": .string(output.fileId), "filename": .string(output.filename)]
                if let value = output.expiresAt { file["expiresAt"] = .number(value) }
                if let value = output.publicUrl { file["publicUrl"] = .string(value) }
                if let value = output.publicUrlError { file["publicUrlError"] = .string(value) }
                if let value = output.publicUrlExpiresAt { file["publicUrlExpiresAt"] = .number(value) }
                metadata["fileOutput"] = .object(file)
            }
            if let error = status.video?.storageError { metadata["storageError"] = .string(error) }
            return .completed(videos: [.url(url: url, mediaType: "video/mp4")], warnings: [], providerMetadata: ["xai": metadata], response: info)
        }
        return .pending(warnings: nil, providerMetadata: nil, response: info)
    }
}

private struct XAIVideoModelError: AISDKError, Sendable {
    static let errorDomain = "xai.video.error"
    let name: String
    let message: String
    let cause: (any Error)? = nil
}

private func mediaType(_ file: VideoModelV4File) -> String? {
    switch file { case .url(_, let type, _): return type; case .file(let type, _, _): return type }
}

private func fileURL(_ file: VideoModelV4File) -> String {
    switch file {
    case .url(let url, _, _): return url
    case .file(let type, let data, _):
        switch data { case .base64(let value): return "data:\(type);base64,\(value)"; case .binary(let value): return "data:\(type);base64,\(value.base64EncodedString())" }
    }
}

func xaiPathSegment(_ value: String) -> String {
    if value == "." { return "%252E" }
    if value == ".." { return "%252E%252E" }
    return value.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()"))!
}
