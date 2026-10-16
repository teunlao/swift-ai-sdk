import Foundation
import AISDKProvider
import AISDKProviderUtils

struct BlackForestLabsVideoModelConfig: Sendable {
    let provider: String
    let baseURL: String
    let headers: @Sendable () throws -> [String: String?]
    let fetch: FetchFunction?
    var pollIntervalMillis: Int? = nil
    var pollTimeoutMillis: Int? = nil
    var currentDate: @Sendable () -> Date = { Date() }
}

private struct BFLVideoOperation: Decodable {
    let requestId: String
    let pollingUrl: String
    let cost: Double?
    let inputMegapixels: Double?
    let outputMegapixels: Double?
}

private struct BFLVideoResult: Decodable {
    let sample: String
    let seed: Double?
    let start_time: Double?
    let end_time: Double?
    let duration: Double?
    let draft_cache: String?
}

public final class BlackForestLabsVideoModel: VideoModelV4Operations, VideoModelV4Generator {
    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }
    public var maxVideosPerCall: VideoModelV4MaxVideosPerCall { .value(1) }
    private let modelIdentifier: BlackForestLabsVideoModelId
    private let config: BlackForestLabsVideoModelConfig

    init(modelId: BlackForestLabsVideoModelId, config: BlackForestLabsVideoModelConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    private func args(_ options: VideoModelV4CallOptions) async throws -> ([String: JSONValue], [SharedV4Warning]) {
        let providerOptions = try await bflVideoOptions(options.providerOptions)
        var warnings: [SharedV4Warning] = []
        if let cache = providerOptions["draftCache"] {
            let pinned: [(String, Bool)] = [
                ("prompt", !(options.prompt?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)),
                ("aspectRatio", options.aspectRatio != nil || providerOptions["aspectRatio"] != nil),
                ("resolution", options.resolution != nil || providerOptions["resolution"] != nil),
                ("duration", options.duration != nil), ("fps", options.fps != nil), ("seed", options.seed != nil),
                ("generateAudio", options.generateAudio != nil), ("image", options.image != nil),
                ("frameImages", !(options.frameImages?.isEmpty ?? true)), ("inputReferences", !(options.inputReferences?.isEmpty ?? true)),
                ("keyframes", providerOptions["keyframes"] != nil), ("version", providerOptions["version"] != nil)
            ]
            for (feature, isSet) in pinned where isSet {
                warnings.append(.unsupported(feature: feature, details: "FLUX 3 draft enhance replays the draft bundle as it was generated, so \"\(feature)\" was ignored. Set it on the original draft request instead."))
            }
            if providerOptions["draft"] != nil { warnings.append(.unsupported(feature: "draft", details: "FLUX 3 draft enhance always renders at full quality. The draft option was ignored.")) }
            if options.n > 1 { warnings.append(.unsupported(feature: "n", details: "FLUX 3 video generates a single video per call. Only 1 video will be generated.")) }
            var body: [String: JSONValue] = ["mode": .string("draft_enhance"), "draft_cache": cache]
            body["safety_tolerance"] = providerOptions["safetyTolerance"]
            return (body, warnings)
        }
        if options.fps != nil { warnings.append(.unsupported(feature: "fps", details: "FLUX 3 video does not support a custom frame rate.")) }
        if options.seed != nil { warnings.append(.unsupported(feature: "seed", details: "FLUX 3 video does not accept a seed.")) }
        if options.n > 1 { warnings.append(.unsupported(feature: "n", details: "FLUX 3 video generates a single video per call. Only 1 video will be generated.")) }
        var resolution = bflString(providerOptions["resolution"])
        if let requested = options.resolution {
            let resolved = resolveResolution(requested)
            if let resolution, resolved == nil {
                warnings.append(.unsupported(feature: "resolution", details: "Unrecognized resolution \"\(requested)\". FLUX 3 video supports \"hd\" and \"fhd\", so providerOptions.blackForestLabs.resolution (\"\(resolution)\") was used instead."))
            } else if resolution == nil {
                if let resolved {
                    resolution = resolved.tier
                    if resolved.derived { warnings.append(.compatibility(feature: "resolution", details: "FLUX 3 video renders at \"hd\" or \"fhd\"; the requested resolution \"\(requested)\" was mapped to \"\(resolved.tier)\".")) }
                } else { warnings.append(.unsupported(feature: "resolution", details: "Unrecognized resolution \"\(requested)\". FLUX 3 video supports \"hd\" and \"fhd\", or a {width}x{height} value to map onto one.")) }
            }
        }
        var aspect = bflString(providerOptions["aspectRatio"])
        if aspect == nil, let requested = options.aspectRatio {
            if bflVideoAspectRatios.contains(requested) { aspect = requested }
            else { warnings.append(.unsupported(feature: "aspectRatio", details: "FLUX 3 video does not support the aspect ratio \"\(requested)\". Using the provider default (auto).")) }
        }
        let firstEntry = options.frameImages?.first { $0.frameType == .firstFrame }?.image
        var first = firstEntry ?? options.image
        var last = options.frameImages?.first { $0.frameType == .lastFrame }?.image
        if let file = first, let mediaType = nonImageType(file) {
            warnings.append(.unsupported(feature: firstEntry != nil ? "frameImages" : "image", details: mediaType == "video" ? "FLUX 3 video does not accept a video as a keyframe. Pass it as an inputReference to continue from it instead." : "FLUX 3 video only accepts an image as a keyframe; the \"\(fileMediaType(file) ?? "")\" file was ignored."))
            first = nil
        }
        if let file = last {
            if first == nil {
                warnings.append(.unsupported(feature: "frameImages", details: "FLUX 3 video requires a first_frame when a last_frame is provided. The last_frame was ignored."))
                last = nil
            } else if let mediaType = nonImageType(file) {
                warnings.append(.unsupported(feature: "frameImages", details: mediaType == "video" ? "FLUX 3 video does not accept a video as a keyframe. The last_frame video was ignored." : "FLUX 3 video only accepts an image as a keyframe; the \"\(fileMediaType(file) ?? "")\" last_frame was ignored."))
                last = nil
            }
        }
        var keyframes: [JSONValue]?
        if case .array(let frames) = providerOptions["keyframes"], !frames.isEmpty {
            keyframes = frames
            if first != nil || last != nil { warnings.append(.unsupported(feature: options.frameImages != nil ? "frameImages" : "image", details: "FLUX 3 video takes a single keyframe list. providerOptions.blackForestLabs.keyframes was used and the top-level frame images were ignored.")) }
        } else if let first {
            keyframes = [.string(bflFile(first))]
            if let last { keyframes?.append(.string(bflFile(last))) }
        }
        var videoReferences: [VideoModelV4File] = []
        for file in options.inputReferences ?? [] {
            let mediaType = fileMediaType(file)?.components(separatedBy: "/").first
            switch mediaType {
            case "video": videoReferences.append(file)
            case nil:
                warnings.append(.compatibility(feature: "inputReferences", details: "FLUX 3 video only accepts a video reference, so the reference with no mediaType was treated as the video to continue from. Pass { url, mediaType: \"video/mp4\" } to be explicit."))
                videoReferences.append(file)
            case "image": warnings.append(.unsupported(feature: "inputReferences", details: "FLUX 3 video has no reference-image input. Pass images as `image`, `frameImages`, or providerOptions.blackForestLabs.keyframes instead. The reference was ignored."))
            default: warnings.append(.unsupported(feature: "inputReferences", details: "FLUX 3 video only accepts a video reference; the \"\(fileMediaType(file) ?? "")\" reference was ignored."))
            }
        }
        var startVideo: String?
        if let reference = videoReferences.first {
            if keyframes != nil { warnings.append(.unsupported(feature: "inputReferences", details: "FLUX 3 video cannot combine keyframes with a video to continue from. The video reference was ignored.")) }
            else {
                startVideo = bflFile(reference)
                if videoReferences.count > 1 { warnings.append(.unsupported(feature: "inputReferences", details: "FLUX 3 video continues from a single video. Only the first video reference was used.")) }
            }
        }
        var duration = options.duration
        if let requested = duration {
            if requested > 20 {
                duration = 20
                warnings.append(.unsupported(feature: "duration", details: "FLUX 3 video supports at most 20 seconds. The requested duration of \(requested) was clamped to 20."))
            } else if requested < 5 {
                duration = 5
                warnings.append(.unsupported(feature: "duration", details: "FLUX 3 video requires at least 5 seconds. The requested duration of \(requested) was clamped to 5."))
            }
        }
        if duration == nil, (keyframes ?? []).filter({ if case .string = $0 { return true }; return false }).count >= 3 {
            throw InvalidArgumentError(argument: "duration", message: "FLUX 3 video requires an explicit duration when 3 or more keyframes are sent without a timestamp.")
        }
        let mode = keyframes != nil ? "i2v" : startVideo != nil ? "v2v" : "t2v"
        var body: [String: JSONValue] = ["mode": .string(mode), "prompt": .string(options.prompt ?? "")]
        if let aspect { body["aspect_ratio"] = .string(aspect) }
        if let resolution { body["resolution"] = .string(resolution) }
        if let duration { body["duration"] = .number(Double(duration)) }
        if let value = options.generateAudio { body["generate_audio"] = .bool(value) }
        body["version"] = providerOptions["version"]
        body["draft"] = providerOptions["draft"]
        body["safety_tolerance"] = providerOptions["safetyTolerance"]
        if let keyframes { body["keyframes"] = .array(keyframes) }
        if let startVideo { body["start_video"] = .string(startVideo) }
        return (body, warnings)
    }

    public func doStart(options: VideoModelV4CallOptions, webhookUrl: String? = nil) async throws -> VideoModelV4OperationStartResult {
        let (body, warnings) = try await args(options)
        let timestamp = config.currentDate()
        let result = try await postJsonToAPI(
            url: "\(config.baseURL)/\(modelId)", headers: combineHeaders(try config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 }, body: JSONValue.object(body),
            failedResponseHandler: bflFailedResponseHandler, successfulResponseHandler: createJsonResponseHandler(responseSchema: bflSubmitSchema), isAborted: options.abortSignal, fetch: config.fetch
        )
        var operation: [String: JSONValue] = ["requestId": .string(result.value.id), "pollingUrl": .string(result.value.polling_url)]
        if let cost = result.value.cost { operation["cost"] = .number(cost) }
        if let value = result.value.input_mp { operation["inputMegapixels"] = .number(value) }
        if let value = result.value.output_mp { operation["outputMegapixels"] = .number(value) }
        return .init(operation: .object(operation), warnings: warnings, response: .init(timestamp: timestamp, modelId: modelId, headers: result.responseHeaders))
    }

    public func doStatus(options: VideoModelV4StatusCallOptions) async throws -> VideoModelV4OperationStatusResult {
        let timestamp = config.currentDate()
        let operation = try JSONDecoder().decode(BFLVideoOperation.self, from: JSONEncoder().encode(options.operation))
        let url = try bflPollingURL(operation.pollingUrl, id: operation.requestId)
        let headers = combineHeaders(try config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 }
        let result = try await getFromAPI(
            url: url, headers: bflTrustedURL(url, baseURL: config.baseURL) ? headers : nil,
            failedResponseHandler: bflFailedResponseHandler, successfulResponseHandler: createJsonResponseHandler(responseSchema: bflVideoPollSchema), isAborted: options.abortSignal, fetch: config.fetch, validateUrl: true, trustedOrigin: config.baseURL
        )
        let response = VideoModelV4ResponseInfo(timestamp: timestamp, modelId: modelId, headers: result.responseHeaders)
        let status = result.value.status
        if status == "Ready" {
            guard let raw = result.value.result,
                  let video = try? JSONDecoder().decode(BFLVideoResult.self, from: JSONEncoder().encode(raw)),
                  URL(string: video.sample)?.scheme != nil else {
                throw BFLVideoError(name: "BLACK_FOREST_LABS_VIDEO_GENERATION_ERROR", message: "Black Forest Labs reported the video as Ready but returned no result.sample URL. Request id: \(operation.requestId)")
            }
            var metadata: [String: JSONValue] = ["id": .string(operation.requestId), "videoUrl": .string(video.sample)]
            let numbers: [String: Double?] = ["seed": video.seed, "start_time": video.start_time, "end_time": video.end_time, "duration": video.duration, "cost": result.value.cost ?? operation.cost, "inputMegapixels": operation.inputMegapixels, "outputMegapixels": operation.outputMegapixels]
            for (key, value) in numbers { if let value { metadata[key] = .number(value) } }
            if let cache = video.draft_cache { metadata["draftCache"] = .string(cache) }
            return .completed(videos: [.url(url: video.sample, mediaType: "video/mp4")], warnings: [], providerMetadata: ["blackForestLabs": ["videos": .array([.object(metadata)])]], response: response)
        }
        if bflFailureStatuses.contains(status) {
            let detail = result.value.details.map { ": \(bflDescribe($0))" } ?? ""
            return .error(error: "Black Forest Labs video generation failed with status \"\(status)\"\(detail). Request id: \(operation.requestId)", providerMetadata: nil, response: response)
        }
        return .pending(warnings: nil, providerMetadata: nil, response: response)
    }

    public func doGenerate(options: VideoModelV4CallOptions) async throws -> VideoModelV4GenerateResult {
        let start = try await doStart(options: options)
        let interval = config.pollIntervalMillis ?? 2_000
        let timeout = config.pollTimeoutMillis ?? 600_000
        let began = Date()
        while true {
            try await delay(interval, abortSignal: options.abortSignal)
            if Date().timeIntervalSince(began) * 1_000 > Double(timeout) {
                let operation = try JSONDecoder().decode(BFLVideoOperation.self, from: JSONEncoder().encode(start.operation))
                throw BFLVideoError(name: "BLACK_FOREST_LABS_VIDEO_GENERATION_TIMEOUT", message: "Black Forest Labs video generation timed out after \(timeout)ms. Request id: \(operation.requestId)")
            }
            switch try await doStatus(options: .init(operation: start.operation, abortSignal: options.abortSignal, headers: options.headers)) {
            case .pending: continue
            case .error(let error, _, _): throw BFLVideoError(name: "BLACK_FOREST_LABS_VIDEO_GENERATION_FAILED", message: error)
            case .completed(let videos, let warnings, let metadata, let response):
                return .init(videos: videos, warnings: start.warnings + warnings, providerMetadata: metadata, response: response)
            }
        }
    }

    private func fileMediaType(_ file: VideoModelV4File) -> String? {
        switch file {
        case .url(_, let mediaType, _): return mediaType
        case .file(let mediaType, _, _): return mediaType
        }
    }
    private func nonImageType(_ file: VideoModelV4File) -> String? {
        guard let mediaType = fileMediaType(file)?.components(separatedBy: "/").first else { return nil }
        return mediaType == "image" ? nil : mediaType
    }
    private func resolveResolution(_ value: String) -> (tier: String, derived: Bool)? {
        let named = value.lowercased()
        if ["hd", "fhd"].contains(named) { return (named, false) }
        guard value.range(of: "^\\d+x\\d+$", options: .regularExpression) != nil else { return nil }
        let parts = value.components(separatedBy: "x").compactMap(Double.init)
        guard parts.count == 2 else { return nil }
        let shorter = min(parts[0], parts[1])
        return (shorter <= 720 ? "hd" : "fhd", shorter != 720 && shorter != 1080)
    }
}
