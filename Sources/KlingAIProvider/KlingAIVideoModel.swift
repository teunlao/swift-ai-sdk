import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/klingai/src/klingai-video-model.ts
// Upstream commit: 73d5c59
//===----------------------------------------------------------------------===//

public struct KlingAIVideoProviderOptions: Sendable, Equatable {
    public enum QualityMode: String, Sendable, Equatable {
        case std = "std"
        case pro = "pro"
    }

    public enum Sound: String, Sendable, Equatable {
        case on = "on"
        case off = "off"
    }

    public enum ShotType: String, Sendable, Equatable {
        case customize = "customize"
        case intelligence = "intelligence"
    }

    public enum CharacterOrientation: String, Sendable, Equatable {
        case image = "image"
        case video = "video"
    }

    public enum KeepOriginalSound: String, Sendable, Equatable {
        case yes = "yes"
        case no = "no"
    }

    public var mode: QualityMode?
    public var pollIntervalMs: Double?
    public var pollTimeoutMs: Double?
    public var negativePrompt: String?
    public var sound: Sound?
    public var cfgScale: Double?
    public var cameraControl: JSONValue?
    public var imageTail: String?
    public var staticMask: String?
    public var dynamicMasks: JSONValue?
    public var multiShot: Bool?
    public var shotType: ShotType?
    public var multiPrompt: JSONValue?
    public var elementList: JSONValue?
    public var voiceList: JSONValue?
    public var videoUrl: String?
    public var characterOrientation: CharacterOrientation?
    public var keepOriginalSound: KeepOriginalSound?
    public var watermarkEnabled: Bool?

    public init(
        mode: QualityMode? = nil,
        pollIntervalMs: Double? = nil,
        pollTimeoutMs: Double? = nil,
        negativePrompt: String? = nil,
        sound: Sound? = nil,
        cfgScale: Double? = nil,
        cameraControl: JSONValue? = nil,
        imageTail: String? = nil,
        staticMask: String? = nil,
        dynamicMasks: JSONValue? = nil,
        multiShot: Bool? = nil,
        shotType: ShotType? = nil,
        multiPrompt: JSONValue? = nil,
        elementList: JSONValue? = nil,
        voiceList: JSONValue? = nil,
        videoUrl: String? = nil,
        characterOrientation: CharacterOrientation? = nil,
        keepOriginalSound: KeepOriginalSound? = nil,
        watermarkEnabled: Bool? = nil
    ) {
        self.mode = mode
        self.pollIntervalMs = pollIntervalMs
        self.pollTimeoutMs = pollTimeoutMs
        self.negativePrompt = negativePrompt
        self.sound = sound
        self.cfgScale = cfgScale
        self.cameraControl = cameraControl
        self.imageTail = imageTail
        self.staticMask = staticMask
        self.dynamicMasks = dynamicMasks
        self.multiShot = multiShot
        self.shotType = shotType
        self.multiPrompt = multiPrompt
        self.elementList = elementList
        self.voiceList = voiceList
        self.videoUrl = videoUrl
        self.characterOrientation = characterOrientation
        self.keepOriginalSound = keepOriginalSound
        self.watermarkEnabled = watermarkEnabled
    }
}

private enum KlingAIVideoEndpointMode: String, Sendable {
    case t2v
    case i2v
    case motionControl = "motion-control"
}

private func detectMode(modelId: String) throws -> KlingAIVideoEndpointMode {
    if modelId.hasSuffix("-t2v") { return .t2v }
    if modelId.hasSuffix("-i2v") { return .i2v }
    if modelId.hasSuffix("-motion-control") { return .motionControl }
    throw NoSuchModelError(modelId: modelId, modelType: .videoModel)
}

private let modeEndpointMap: [KlingAIVideoEndpointMode: String] = [
    .t2v: "/v1/videos/text2video",
    .i2v: "/v1/videos/image2video",
    .motionControl: "/v1/videos/motion-control",
]

private func getApiModelName(modelId: String, mode: KlingAIVideoEndpointMode) -> String {
    let suffix: String
    switch mode {
    case .motionControl:
        suffix = "-motion-control"
    case .t2v:
        suffix = "-t2v"
    case .i2v:
        suffix = "-i2v"
    }

    let baseName = String(modelId.dropLast(suffix.count))
    let withoutDotZero: String
    if baseName.hasSuffix(".0") {
        withoutDotZero = String(baseName.dropLast(2))
    } else {
        withoutDotZero = baseName
    }

    return withoutDotZero.replacingOccurrences(of: ".", with: "-")
}

private let handledProviderOptionKeys: Set<String> = [
    "mode",
    "pollIntervalMs",
    "pollTimeoutMs",
    "negativePrompt",
    "sound",
    "cfgScale",
    "cameraControl",
    "multiShot",
    "shotType",
    "multiPrompt",
    "elementList",
    "voiceList",
    "imageTail",
    "staticMask",
    "dynamicMasks",
    "videoUrl",
    "characterOrientation",
    "keepOriginalSound",
    "watermarkEnabled",
]

private let klingaiVideoProviderOptionsSchema = FlexibleSchema(
    Schema<KlingAIVideoProviderOptions>(
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
                    let error = SchemaValidationIssuesError(vendor: "klingai", issues: "provider options must be an object")
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                func boolOrNullish(_ key: String) -> Result<Bool?, TypeValidationError> {
                    guard let raw = dict[key], raw != .null else { return .success(nil) }
                    guard case .bool(let value) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "klingai", issues: "\(key) must be a boolean")
                        return .failure(TypeValidationError.wrap(value: raw, cause: error))
                    }
                    return .success(value)
                }

                func stringOrNullish(_ key: String) -> Result<String?, TypeValidationError> {
                    guard let raw = dict[key], raw != .null else { return .success(nil) }
                    guard case .string(let value) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "klingai", issues: "\(key) must be a string")
                        return .failure(TypeValidationError.wrap(value: raw, cause: error))
                    }
                    return .success(value)
                }

                func numberOrNullish(_ key: String) -> Result<Double?, TypeValidationError> {
                    guard let raw = dict[key], raw != .null else { return .success(nil) }
                    guard case .number(let value) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "klingai", issues: "\(key) must be a number")
                        return .failure(TypeValidationError.wrap(value: raw, cause: error))
                    }
                    return .success(value)
                }

                func positiveNumberOrNullish(_ key: String) -> Result<Double?, TypeValidationError> {
                    switch numberOrNullish(key) {
                    case .success(let value):
                        guard let value else { return .success(nil) }
                        guard value > 0 else {
                            let error = SchemaValidationIssuesError(vendor: "klingai", issues: "\(key) must be a positive number")
                            return .failure(TypeValidationError.wrap(value: dict[key] as Any, cause: error))
                        }
                        return .success(value)
                    case .failure(let error):
                        return .failure(error)
                    }
                }

                func enumOrNullish<T: RawRepresentable>(
                    _ key: String,
                    _ type: T.Type
                ) -> Result<T?, TypeValidationError> where T.RawValue == String {
                    switch stringOrNullish(key) {
                    case .success(let value):
                        guard let value else { return .success(nil) }
                        guard let parsed = T(rawValue: value) else {
                            let error = SchemaValidationIssuesError(vendor: "klingai", issues: "\(key) has an invalid value")
                            return .failure(TypeValidationError.wrap(value: dict[key] as Any, cause: error))
                        }
                        return .success(parsed)
                    case .failure(let error):
                        return .failure(error)
                    }
                }

                func cameraControlOrNullish(_ key: String) -> Result<JSONValue?, TypeValidationError> {
                    guard let raw = dict[key], raw != .null else { return .success(nil) }
                    guard case .object(let obj) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "klingai", issues: "\(key) must be an object")
                        return .failure(TypeValidationError.wrap(value: raw, cause: error))
                    }

                    if let typeValue = obj["type"], typeValue != .null {
                        guard case .string(let value) = typeValue else {
                            let error = SchemaValidationIssuesError(vendor: "klingai", issues: "cameraControl.type must be a string")
                            return .failure(TypeValidationError.wrap(value: typeValue, cause: error))
                        }
                        let allowed: Set<String> = ["simple", "down_back", "forward_up", "right_turn_forward", "left_turn_forward"]
                        guard allowed.contains(value) else {
                            let error = SchemaValidationIssuesError(vendor: "klingai", issues: "cameraControl.type has an invalid value")
                            return .failure(TypeValidationError.wrap(value: typeValue, cause: error))
                        }
                    }

                    if let configValue = obj["config"], configValue != .null {
                        guard case .object(let configObj) = configValue else {
                            let error = SchemaValidationIssuesError(vendor: "klingai", issues: "cameraControl.config must be an object")
                            return .failure(TypeValidationError.wrap(value: configValue, cause: error))
                        }
                        for (_, value) in configObj {
                            if value == .null { continue }
                            guard case .number = value else {
                                let error = SchemaValidationIssuesError(vendor: "klingai", issues: "cameraControl.config values must be numbers")
                                return .failure(TypeValidationError.wrap(value: value, cause: error))
                            }
                        }
                    }

                    return .success(raw)
                }

                func objectArrayOrNullish(
                    _ key: String,
                    elementValidator: (JSONValue) -> Result<Void, TypeValidationError>
                ) -> Result<JSONValue?, TypeValidationError> {
                    guard let raw = dict[key], raw != .null else { return .success(nil) }
                    guard case .array(let values) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "klingai", issues: "\(key) must be an array")
                        return .failure(TypeValidationError.wrap(value: raw, cause: error))
                    }
                    for entry in values {
                        switch elementValidator(entry) {
                        case .success:
                            continue
                        case .failure(let error):
                            return .failure(error)
                        }
                    }
                    return .success(raw)
                }

                func validateMultiPrompt(_ value: JSONValue) -> Result<Void, TypeValidationError> {
                    guard case .object(let obj) = value else {
                        let error = SchemaValidationIssuesError(vendor: "klingai", issues: "multiPrompt entries must be objects")
                        return .failure(TypeValidationError.wrap(value: value, cause: error))
                    }
                    guard case .number? = obj["index"] else {
                        let error = SchemaValidationIssuesError(vendor: "klingai", issues: "multiPrompt.index must be a number")
                        return .failure(TypeValidationError.wrap(value: value, cause: error))
                    }
                    guard case .string? = obj["prompt"] else {
                        let error = SchemaValidationIssuesError(vendor: "klingai", issues: "multiPrompt.prompt must be a string")
                        return .failure(TypeValidationError.wrap(value: value, cause: error))
                    }
                    guard case .string? = obj["duration"] else {
                        let error = SchemaValidationIssuesError(vendor: "klingai", issues: "multiPrompt.duration must be a string")
                        return .failure(TypeValidationError.wrap(value: value, cause: error))
                    }
                    return .success(())
                }

                func validateElement(_ value: JSONValue) -> Result<Void, TypeValidationError> {
                    guard case .object(let obj) = value else {
                        let error = SchemaValidationIssuesError(vendor: "klingai", issues: "elementList entries must be objects")
                        return .failure(TypeValidationError.wrap(value: value, cause: error))
                    }
                    guard case .number? = obj["element_id"] else {
                        let error = SchemaValidationIssuesError(vendor: "klingai", issues: "elementList.element_id must be a number")
                        return .failure(TypeValidationError.wrap(value: value, cause: error))
                    }
                    return .success(())
                }

                func validateVoice(_ value: JSONValue) -> Result<Void, TypeValidationError> {
                    guard case .object(let obj) = value else {
                        let error = SchemaValidationIssuesError(vendor: "klingai", issues: "voiceList entries must be objects")
                        return .failure(TypeValidationError.wrap(value: value, cause: error))
                    }
                    guard case .string? = obj["voice_id"] else {
                        let error = SchemaValidationIssuesError(vendor: "klingai", issues: "voiceList.voice_id must be a string")
                        return .failure(TypeValidationError.wrap(value: value, cause: error))
                    }
                    return .success(())
                }

                func validateDynamicMask(_ value: JSONValue) -> Result<Void, TypeValidationError> {
                    guard case .object(let obj) = value else {
                        let error = SchemaValidationIssuesError(vendor: "klingai", issues: "dynamicMasks entries must be objects")
                        return .failure(TypeValidationError.wrap(value: value, cause: error))
                    }
                    guard case .string? = obj["mask"] else {
                        let error = SchemaValidationIssuesError(vendor: "klingai", issues: "dynamicMasks.mask must be a string")
                        return .failure(TypeValidationError.wrap(value: value, cause: error))
                    }
                    guard case .array(let trajectories)? = obj["trajectories"] else {
                        let error = SchemaValidationIssuesError(vendor: "klingai", issues: "dynamicMasks.trajectories must be an array")
                        return .failure(TypeValidationError.wrap(value: value, cause: error))
                    }
                    for t in trajectories {
                        guard case .object(let p) = t else {
                            let error = SchemaValidationIssuesError(vendor: "klingai", issues: "dynamicMasks.trajectories entries must be objects")
                            return .failure(TypeValidationError.wrap(value: t, cause: error))
                        }
                        guard case .number? = p["x"], case .number? = p["y"] else {
                            let error = SchemaValidationIssuesError(vendor: "klingai", issues: "dynamicMasks.trajectories entries must have x and y numbers")
                            return .failure(TypeValidationError.wrap(value: t, cause: error))
                        }
                    }
                    return .success(())
                }

                let mode: KlingAIVideoProviderOptions.QualityMode?
                switch enumOrNullish("mode", KlingAIVideoProviderOptions.QualityMode.self) {
                case .success(let value): mode = value
                case .failure(let error): return .failure(error: error)
                }

                let pollIntervalMs: Double?
                switch positiveNumberOrNullish("pollIntervalMs") {
                case .success(let value): pollIntervalMs = value
                case .failure(let error): return .failure(error: error)
                }

                let pollTimeoutMs: Double?
                switch positiveNumberOrNullish("pollTimeoutMs") {
                case .success(let value): pollTimeoutMs = value
                case .failure(let error): return .failure(error: error)
                }

                let negativePrompt: String?
                switch stringOrNullish("negativePrompt") {
                case .success(let value): negativePrompt = value
                case .failure(let error): return .failure(error: error)
                }

                let sound: KlingAIVideoProviderOptions.Sound?
                switch enumOrNullish("sound", KlingAIVideoProviderOptions.Sound.self) {
                case .success(let value): sound = value
                case .failure(let error): return .failure(error: error)
                }

                let cfgScale: Double?
                switch numberOrNullish("cfgScale") {
                case .success(let value): cfgScale = value
                case .failure(let error): return .failure(error: error)
                }

                let cameraControl: JSONValue?
                switch cameraControlOrNullish("cameraControl") {
                case .success(let value): cameraControl = value
                case .failure(let error): return .failure(error: error)
                }

                let multiShot: Bool?
                switch boolOrNullish("multiShot") {
                case .success(let value): multiShot = value
                case .failure(let error): return .failure(error: error)
                }

                let shotType: KlingAIVideoProviderOptions.ShotType?
                switch enumOrNullish("shotType", KlingAIVideoProviderOptions.ShotType.self) {
                case .success(let value): shotType = value
                case .failure(let error): return .failure(error: error)
                }

                let multiPrompt: JSONValue?
                switch objectArrayOrNullish("multiPrompt", elementValidator: validateMultiPrompt) {
                case .success(let value): multiPrompt = value
                case .failure(let error): return .failure(error: error)
                }

                let elementList: JSONValue?
                switch objectArrayOrNullish("elementList", elementValidator: validateElement) {
                case .success(let value): elementList = value
                case .failure(let error): return .failure(error: error)
                }

                let voiceList: JSONValue?
                switch objectArrayOrNullish("voiceList", elementValidator: validateVoice) {
                case .success(let value): voiceList = value
                case .failure(let error): return .failure(error: error)
                }

                let imageTail: String?
                switch stringOrNullish("imageTail") {
                case .success(let value): imageTail = value
                case .failure(let error): return .failure(error: error)
                }

                let staticMask: String?
                switch stringOrNullish("staticMask") {
                case .success(let value): staticMask = value
                case .failure(let error): return .failure(error: error)
                }

                let dynamicMasks: JSONValue?
                switch objectArrayOrNullish("dynamicMasks", elementValidator: validateDynamicMask) {
                case .success(let value): dynamicMasks = value
                case .failure(let error): return .failure(error: error)
                }

                let videoUrl: String?
                switch stringOrNullish("videoUrl") {
                case .success(let value): videoUrl = value
                case .failure(let error): return .failure(error: error)
                }

                let characterOrientation: KlingAIVideoProviderOptions.CharacterOrientation?
                switch enumOrNullish("characterOrientation", KlingAIVideoProviderOptions.CharacterOrientation.self) {
                case .success(let value): characterOrientation = value
                case .failure(let error): return .failure(error: error)
                }

                let keepOriginalSound: KlingAIVideoProviderOptions.KeepOriginalSound?
                switch enumOrNullish("keepOriginalSound", KlingAIVideoProviderOptions.KeepOriginalSound.self) {
                case .success(let value): keepOriginalSound = value
                case .failure(let error): return .failure(error: error)
                }

                let watermarkEnabled: Bool?
                switch boolOrNullish("watermarkEnabled") {
                case .success(let value): watermarkEnabled = value
                case .failure(let error): return .failure(error: error)
                }

                return .success(
                    value: KlingAIVideoProviderOptions(
                        mode: mode,
                        pollIntervalMs: pollIntervalMs,
                        pollTimeoutMs: pollTimeoutMs,
                        negativePrompt: negativePrompt,
                        sound: sound,
                        cfgScale: cfgScale,
                        cameraControl: cameraControl,
                        imageTail: imageTail,
                        staticMask: staticMask,
                        dynamicMasks: dynamicMasks,
                        multiShot: multiShot,
                        shotType: shotType,
                        multiPrompt: multiPrompt,
                        elementList: elementList,
                        voiceList: voiceList,
                        videoUrl: videoUrl,
                        characterOrientation: characterOrientation,
                        keepOriginalSound: keepOriginalSound,
                        watermarkEnabled: watermarkEnabled
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

struct KlingAIVideoModelConfig: Sendable {
    let provider: String
    let baseURL: String
    let headers: @Sendable () async throws -> [String: String?]
    let fetch: FetchFunction?
    let currentDate: @Sendable () -> Date

    init(
        provider: String,
        baseURL: String,
        headers: @escaping @Sendable () async throws -> [String: String?],
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

public final class KlingAIVideoModel: VideoModelV3 {
    public var specificationVersion: String { "v3" }
    public var maxVideosPerCall: VideoModelV3MaxVideosPerCall { .value(1) }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    private let modelIdentifier: KlingAIVideoModelId
    private let config: KlingAIVideoModelConfig

    init(modelId: KlingAIVideoModelId, config: KlingAIVideoModelConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public func doGenerate(options: VideoModelV3CallOptions) async throws -> VideoModelV3GenerateResult {
        let currentDate = config.currentDate()
        var warnings: [SharedV3Warning] = []

        let endpointMode = try detectMode(modelId: modelIdentifier.rawValue)

        let klingaiOptions = try await parseProviderOptions(
            provider: "klingai",
            providerOptions: options.providerOptions,
            schema: klingaiVideoProviderOptionsSchema
        )

        let rawProviderOptions = options.providerOptions?["klingai"]

        let body: [String: JSONValue]
        switch endpointMode {
        case .motionControl:
            body = try buildMotionControlBody(options: options, providerOptions: klingaiOptions, rawProviderOptions: rawProviderOptions, warnings: &warnings)
        case .t2v:
            body = buildT2VBody(options: options, providerOptions: klingaiOptions, rawProviderOptions: rawProviderOptions, warnings: &warnings)
        case .i2v:
            body = buildI2VBody(options: options, providerOptions: klingaiOptions, rawProviderOptions: rawProviderOptions, warnings: &warnings)
        }

        // Warn about universally unsupported standard options.
        if options.resolution != nil {
            warnings.append(.unsupported(
                feature: "resolution",
                details: "KlingAI video models do not support the resolution option."
            ))
        }

        if options.seed != nil {
            warnings.append(.unsupported(
                feature: "seed",
                details: "KlingAI video models do not support seed for deterministic generation."
            ))
        }

        if options.fps != nil {
            warnings.append(.unsupported(
                feature: "fps",
                details: "KlingAI video models do not support custom FPS."
            ))
        }

        if options.n > 1 {
            warnings.append(.unsupported(
                feature: "n",
                details: "KlingAI video models do not support generating multiple videos per call. Only 1 video will be generated."
            ))
        }

        let endpointPath = modeEndpointMap[endpointMode]!

        // Step 1: Create the task.
        let createURL = "\(config.baseURL)\(endpointPath)"
        let createHeaders = combineHeaders(
            try await config.headers(),
            options.headers?.mapValues { Optional($0) }
        ).compactMapValues { $0 }

        let createResult = try await postJsonToAPI(
            url: createURL,
            headers: createHeaders,
            body: JSONValue.object(body),
            failedResponseHandler: klingaiFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: klingaiCreateTaskResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let taskId = createResult.value.data?.taskId
        guard let taskId, !taskId.isEmpty else {
            throw KlingAIVideoModelError(
                name: "KLINGAI_VIDEO_GENERATION_ERROR",
                message: "No task_id returned from KlingAI API. Response: \(klingaiJSONString(from: createResult.value))"
            )
        }

        // Step 2: Poll for task completion.
        let pollIntervalMs = klingaiOptions?.pollIntervalMs ?? 5000
        let pollTimeoutMs = klingaiOptions?.pollTimeoutMs ?? 600_000
        let startTime = Date()

        var finalResponse: KlingAITaskStatusResponse?
        var responseHeaders: [String: String]? = createResult.responseHeaders

        while true {
            try await delay(Int(pollIntervalMs.rounded(.towardZero)), abortSignal: options.abortSignal)

            let elapsedMs = Date().timeIntervalSince(startTime) * 1000
            if elapsedMs > pollTimeoutMs {
                throw KlingAIVideoModelError(
                    name: "KLINGAI_VIDEO_GENERATION_TIMEOUT",
                    message: "Video generation timed out after \(pollTimeoutMs)ms"
                )
            }

            let statusURL = "\(config.baseURL)\(endpointPath)/\(taskId)"
            let statusHeaders = combineHeaders(
                try await config.headers(),
                options.headers?.mapValues { Optional($0) }
            ).compactMapValues { $0 }

            let statusResult = try await getFromAPI(
                url: statusURL,
                headers: statusHeaders,
                failedResponseHandler: klingaiFailedResponseHandler,
                successfulResponseHandler: createJsonResponseHandler(responseSchema: klingaiTaskStatusResponseSchema),
                isAborted: options.abortSignal,
                fetch: config.fetch
            )

            responseHeaders = statusResult.responseHeaders
            let taskStatus = statusResult.value.data?.taskStatus

            if taskStatus == "succeed" {
                finalResponse = statusResult.value
                break
            }

            if taskStatus == "failed" {
                throw KlingAIVideoModelError(
                    name: "KLINGAI_VIDEO_GENERATION_FAILED",
                    message: "Video generation failed: \(statusResult.value.data?.taskStatusMsg ?? "Unknown error")"
                )
            }
        }

        guard let finalResponse else {
            throw KlingAIVideoModelError(
                name: "KLINGAI_VIDEO_GENERATION_ERROR",
                message: "No videos in response. Response: null"
            )
        }

        let responseVideos = finalResponse.data?.taskResult?.videos
        if responseVideos?.isEmpty != false {
            throw KlingAIVideoModelError(
                name: "KLINGAI_VIDEO_GENERATION_ERROR",
                message: "No videos in response. Response: \(klingaiJSONString(from: finalResponse))"
            )
        }

        var videos: [VideoModelV3VideoData] = []
        var videoMetadata: [JSONValue] = []

        for video in responseVideos ?? [] {
            guard let url = video.url, !url.isEmpty else {
                continue
            }

            videos.append(.url(url: url, mediaType: "video/mp4"))

            var meta: [String: JSONValue] = [
                "id": .string(video.id ?? ""),
                "url": .string(url),
            ]
            if let watermarkUrl = video.watermarkUrl, !watermarkUrl.isEmpty {
                meta["watermarkUrl"] = .string(watermarkUrl)
            }
            if let duration = video.duration, !duration.isEmpty {
                meta["duration"] = .string(duration)
            }

            videoMetadata.append(.object(meta))
        }

        if videos.isEmpty {
            throw KlingAIVideoModelError(
                name: "KLINGAI_VIDEO_GENERATION_ERROR",
                message: "No valid video URLs in response"
            )
        }

        return VideoModelV3GenerateResult(
            videos: videos,
            warnings: warnings,
            providerMetadata: [
                "klingai": [
                    "taskId": .string(taskId),
                    "videos": .array(videoMetadata),
                ]
            ],
            response: VideoModelV3ResponseInfo(
                timestamp: currentDate,
                modelId: modelIdentifier.rawValue,
                headers: responseHeaders
            )
        )
    }

    private func buildT2VBody(
        options: VideoModelV3CallOptions,
        providerOptions: KlingAIVideoProviderOptions?,
        rawProviderOptions: [String: JSONValue]?,
        warnings: inout [SharedV3Warning]
    ) -> [String: JSONValue] {
        var body: [String: JSONValue] = [
            "model_name": .string(getApiModelName(modelId: modelIdentifier.rawValue, mode: .t2v))
        ]

        if let prompt = options.prompt {
            body["prompt"] = .string(prompt)
        }

        if let negativePrompt = providerOptions?.negativePrompt {
            body["negative_prompt"] = .string(negativePrompt)
        }

        if let sound = providerOptions?.sound {
            body["sound"] = .string(sound.rawValue)
        }

        if let cfgScale = providerOptions?.cfgScale {
            body["cfg_scale"] = .number(cfgScale)
        }

        if let mode = providerOptions?.mode {
            body["mode"] = .string(mode.rawValue)
        }

        if let cameraControl = providerOptions?.cameraControl {
            body["camera_control"] = cameraControl
        }

        if let aspectRatio = options.aspectRatio {
            body["aspect_ratio"] = .string(aspectRatio)
        }

        if let duration = options.duration {
            body["duration"] = .string(String(duration))
        }

        if let multiShot = providerOptions?.multiShot {
            body["multi_shot"] = .bool(multiShot)
        }

        if let shotType = providerOptions?.shotType {
            body["shot_type"] = .string(shotType.rawValue)
        }

        if let multiPrompt = providerOptions?.multiPrompt {
            body["multi_prompt"] = multiPrompt
        }

        if let voiceList = providerOptions?.voiceList {
            body["voice_list"] = voiceList
        }

        if options.image != nil {
            warnings.append(.unsupported(
                feature: "image",
                details: "KlingAI text-to-video does not support image input. Use an image-to-video model instead."
            ))
        }

        addPassthroughOptions(&body, rawProviderOptions: rawProviderOptions)
        return body
    }

    private func buildI2VBody(
        options: VideoModelV3CallOptions,
        providerOptions: KlingAIVideoProviderOptions?,
        rawProviderOptions: [String: JSONValue]?,
        warnings: inout [SharedV3Warning]
    ) -> [String: JSONValue] {
        var body: [String: JSONValue] = [
            "model_name": .string(getApiModelName(modelId: modelIdentifier.rawValue, mode: .i2v))
        ]

        if let prompt = options.prompt {
            body["prompt"] = .string(prompt)
        }

        if let image = options.image {
            body["image"] = .string(convertVideoModelFileToRawBase64(image))
        }

        if let imageTail = providerOptions?.imageTail {
            body["image_tail"] = .string(imageTail)
        }

        if let negativePrompt = providerOptions?.negativePrompt {
            body["negative_prompt"] = .string(negativePrompt)
        }

        if let sound = providerOptions?.sound {
            body["sound"] = .string(sound.rawValue)
        }

        if let cfgScale = providerOptions?.cfgScale {
            body["cfg_scale"] = .number(cfgScale)
        }

        if let mode = providerOptions?.mode {
            body["mode"] = .string(mode.rawValue)
        }

        if let cameraControl = providerOptions?.cameraControl {
            body["camera_control"] = cameraControl
        }

        if let staticMask = providerOptions?.staticMask {
            body["static_mask"] = .string(staticMask)
        }

        if let dynamicMasks = providerOptions?.dynamicMasks {
            body["dynamic_masks"] = dynamicMasks
        }

        if let multiShot = providerOptions?.multiShot {
            body["multi_shot"] = .bool(multiShot)
        }

        if let shotType = providerOptions?.shotType {
            body["shot_type"] = .string(shotType.rawValue)
        }

        if let multiPrompt = providerOptions?.multiPrompt {
            body["multi_prompt"] = multiPrompt
        }

        if let elementList = providerOptions?.elementList {
            body["element_list"] = elementList
        }

        if let voiceList = providerOptions?.voiceList {
            body["voice_list"] = voiceList
        }

        if let duration = options.duration {
            body["duration"] = .string(String(duration))
        }

        if options.aspectRatio != nil {
            warnings.append(.unsupported(
                feature: "aspectRatio",
                details: "KlingAI image-to-video does not support aspectRatio. The output dimensions are determined by the input image."
            ))
        }

        addPassthroughOptions(&body, rawProviderOptions: rawProviderOptions)
        return body
    }

    private func buildMotionControlBody(
        options: VideoModelV3CallOptions,
        providerOptions: KlingAIVideoProviderOptions?,
        rawProviderOptions: [String: JSONValue]?,
        warnings: inout [SharedV3Warning]
    ) throws -> [String: JSONValue] {
        guard let providerOptions,
              let videoUrl = providerOptions.videoUrl,
              let characterOrientation = providerOptions.characterOrientation,
              let mode = providerOptions.mode else {
            throw KlingAIVideoModelError(
                name: "KLINGAI_VIDEO_MISSING_OPTIONS",
                message: "KlingAI Motion Control requires providerOptions.klingai with videoUrl, characterOrientation, and mode."
            )
        }

        var body: [String: JSONValue] = [
            "video_url": .string(videoUrl),
            "character_orientation": .string(characterOrientation.rawValue),
            "mode": .string(mode.rawValue),
        ]

        if let prompt = options.prompt {
            body["prompt"] = .string(prompt)
        }

        if let image = options.image {
            body["image_url"] = .string(convertVideoModelFileToRawBase64(image))
        }

        if let keepOriginalSound = providerOptions.keepOriginalSound {
            body["keep_original_sound"] = .string(keepOriginalSound.rawValue)
        }

        if let watermarkEnabled = providerOptions.watermarkEnabled {
            body["watermark_info"] = .object([
                "enabled": .bool(watermarkEnabled)
            ])
        }

        if options.aspectRatio != nil {
            warnings.append(.unsupported(
                feature: "aspectRatio",
                details: "KlingAI Motion Control does not support aspectRatio. The output dimensions are determined by the reference image/video."
            ))
        }

        if options.duration != nil {
            warnings.append(.unsupported(
                feature: "duration",
                details: "KlingAI Motion Control does not support custom duration. The output duration matches the reference video duration."
            ))
        }

        addPassthroughOptions(&body, rawProviderOptions: rawProviderOptions)
        return body
    }

    private func addPassthroughOptions(_ body: inout [String: JSONValue], rawProviderOptions: [String: JSONValue]?) {
        guard let rawProviderOptions else { return }
        for (key, value) in rawProviderOptions {
            guard !handledProviderOptionKeys.contains(key) else { continue }
            body[key] = value
        }
    }
}

// MARK: - API Schemas

private struct KlingAITaskInfo: Codable, Sendable {
    let externalTaskId: String?

    enum CodingKeys: String, CodingKey {
        case externalTaskId = "external_task_id"
    }
}

private struct KlingAICreateTaskData: Codable, Sendable {
    let taskId: String
    let taskStatus: String?
    let taskInfo: KlingAITaskInfo?
    let createdAt: Double?
    let updatedAt: Double?

    enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case taskStatus = "task_status"
        case taskInfo = "task_info"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

private struct KlingAICreateTaskResponse: Codable, Sendable {
    let code: Double
    let message: String
    let requestId: String?
    let data: KlingAICreateTaskData?

    enum CodingKeys: String, CodingKey {
        case code
        case message
        case requestId = "request_id"
        case data
    }
}

private let klingaiCreateTaskResponseSchema = FlexibleSchema(
    Schema<KlingAICreateTaskResponse>.codable(
        KlingAICreateTaskResponse.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

private struct KlingAITaskVideo: Codable, Sendable {
    let id: String?
    let url: String?
    let watermarkUrl: String?
    let duration: String?

    enum CodingKeys: String, CodingKey {
        case id
        case url
        case watermarkUrl = "watermark_url"
        case duration
    }
}

private struct KlingAITaskResult: Codable, Sendable {
    let videos: [KlingAITaskVideo]?
}

private struct KlingAITaskStatusData: Codable, Sendable {
    let taskId: String
    let taskStatus: String
    let taskStatusMsg: String?
    let taskInfo: KlingAITaskInfo?
    let taskResult: KlingAITaskResult?

    enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case taskStatus = "task_status"
        case taskStatusMsg = "task_status_msg"
        case taskInfo = "task_info"
        case taskResult = "task_result"
    }
}

private struct KlingAITaskStatusResponse: Codable, Sendable {
    let code: Double
    let message: String
    let requestId: String?
    let data: KlingAITaskStatusData?

    enum CodingKeys: String, CodingKey {
        case code
        case message
        case requestId = "request_id"
        case data
    }
}

private let klingaiTaskStatusResponseSchema = FlexibleSchema(
    Schema<KlingAITaskStatusResponse>.codable(
        KlingAITaskStatusResponse.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

// MARK: - Helpers

private func convertVideoModelFileToRawBase64(_ file: VideoModelV3File) -> String {
    switch file {
    case let .url(url, _):
        return url
    case let .file(_, data, _):
        switch data {
        case .base64(let value):
            return value
        case .binary(let value):
            return convertDataToBase64(value)
        }
    }
}

private func klingaiJSONString<T: Encodable>(from value: T) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    do {
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    } catch {
        return "{}"
    }
}

private struct KlingAIVideoModelError: AISDKError, Sendable {
    static let errorDomain = "klingai.video.error"

    let name: String
    let message: String
    let cause: (any Error)?

    init(name: String, message: String, cause: (any Error)? = nil) {
        self.name = name
        self.message = message
        self.cause = cause
    }
}

