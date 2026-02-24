import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/google-vertex/src/google-vertex-video-model.ts
// Ported from packages/google-vertex/src/google-vertex-video-settings.ts
// Upstream commit: c0fff03
//===----------------------------------------------------------------------===//

struct GoogleVertexVideoModelConfig: Sendable {
    let provider: String
    let baseURL: String
    let headers: @Sendable () -> [String: String?]
    let fetch: FetchFunction?
    let generateId: @Sendable () -> String
    let currentDate: @Sendable () -> Date

    init(
        provider: String,
        baseURL: String,
        headers: @escaping @Sendable () -> [String: String?],
        fetch: FetchFunction?,
        generateId: @escaping @Sendable () -> String,
        currentDate: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.provider = provider
        self.baseURL = baseURL
        self.headers = headers
        self.fetch = fetch
        self.generateId = generateId
        self.currentDate = currentDate
    }
}

public enum GoogleVertexVideoPersonGeneration: String, Sendable, Equatable {
    case dontAllow = "dont_allow"
    case allowAdult = "allow_adult"
    case allowAll = "allow_all"
}

public struct GoogleVertexVideoReferenceImage: Sendable, Equatable {
    public var bytesBase64Encoded: String?
    public var gcsUri: String?

    public init(bytesBase64Encoded: String? = nil, gcsUri: String? = nil) {
        self.bytesBase64Encoded = bytesBase64Encoded
        self.gcsUri = gcsUri
    }
}

public struct GoogleVertexVideoModelOptions: Sendable, Equatable {
    public var pollIntervalMs: Double?
    public var pollTimeoutMs: Double?
    public var personGeneration: GoogleVertexVideoPersonGeneration?
    public var negativePrompt: String?
    public var generateAudio: Bool?
    public var gcsOutputDirectory: String?
    public var referenceImages: [GoogleVertexVideoReferenceImage]?

    public init(
        pollIntervalMs: Double? = nil,
        pollTimeoutMs: Double? = nil,
        personGeneration: GoogleVertexVideoPersonGeneration? = nil,
        negativePrompt: String? = nil,
        generateAudio: Bool? = nil,
        gcsOutputDirectory: String? = nil,
        referenceImages: [GoogleVertexVideoReferenceImage]? = nil
    ) {
        self.pollIntervalMs = pollIntervalMs
        self.pollTimeoutMs = pollTimeoutMs
        self.personGeneration = personGeneration
        self.negativePrompt = negativePrompt
        self.generateAudio = generateAudio
        self.gcsOutputDirectory = gcsOutputDirectory
        self.referenceImages = referenceImages
    }
}

private let googleVertexVideoModelOptionsSchema = FlexibleSchema(
    Schema<GoogleVertexVideoModelOptions>(
        jsonSchemaResolver: {
            .object([
                "type": .string("object"),
                "additionalProperties": .bool(true)
            ])
        },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(
                        vendor: "vertex",
                        issues: "provider options must be an object"
                    )
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                func positiveNumber(_ key: String) -> Result<Double?, TypeValidationError> {
                    guard let rawValue = dict[key], rawValue != .null else {
                        return .success(nil)
                    }

                    guard case .number(let number) = rawValue else {
                        let error = SchemaValidationIssuesError(
                            vendor: "vertex",
                            issues: "\(key) must be a positive number"
                        )
                        return .failure(TypeValidationError.wrap(value: rawValue, cause: error))
                    }

                    guard number > 0 else {
                        let error = SchemaValidationIssuesError(
                            vendor: "vertex",
                            issues: "\(key) must be a positive number"
                        )
                        return .failure(TypeValidationError.wrap(value: rawValue, cause: error))
                    }

                    return .success(number)
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

                var personGeneration: GoogleVertexVideoPersonGeneration?
                if let value = dict["personGeneration"], value != .null {
                    guard case .string(let rawValue) = value,
                          let parsed = GoogleVertexVideoPersonGeneration(rawValue: rawValue) else {
                        let error = SchemaValidationIssuesError(
                            vendor: "vertex",
                            issues: "personGeneration must be one of 'dont_allow', 'allow_adult', 'allow_all'"
                        )
                        return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                    }
                    personGeneration = parsed
                }

                var negativePrompt: String?
                if let value = dict["negativePrompt"], value != .null {
                    guard case .string(let stringValue) = value else {
                        let error = SchemaValidationIssuesError(
                            vendor: "vertex",
                            issues: "negativePrompt must be a string"
                        )
                        return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                    }
                    negativePrompt = stringValue
                }

                var generateAudio: Bool?
                if let value = dict["generateAudio"], value != .null {
                    guard case .bool(let boolValue) = value else {
                        let error = SchemaValidationIssuesError(
                            vendor: "vertex",
                            issues: "generateAudio must be a boolean"
                        )
                        return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                    }
                    generateAudio = boolValue
                }

                var gcsOutputDirectory: String?
                if let value = dict["gcsOutputDirectory"], value != .null {
                    guard case .string(let stringValue) = value else {
                        let error = SchemaValidationIssuesError(
                            vendor: "vertex",
                            issues: "gcsOutputDirectory must be a string"
                        )
                        return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                    }
                    gcsOutputDirectory = stringValue
                }

                var referenceImages: [GoogleVertexVideoReferenceImage]?
                if let value = dict["referenceImages"], value != .null {
                    guard case .array(let array) = value else {
                        let error = SchemaValidationIssuesError(
                            vendor: "vertex",
                            issues: "referenceImages must be an array"
                        )
                        return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                    }

                    var parsedImages: [GoogleVertexVideoReferenceImage] = []
                    for item in array {
                        guard case .object(let object) = item else {
                            let error = SchemaValidationIssuesError(
                                vendor: "vertex",
                                issues: "referenceImages entries must be objects"
                            )
                            return .failure(error: TypeValidationError.wrap(value: item, cause: error))
                        }

                        var bytesBase64Encoded: String?
                        if let bytes = object["bytesBase64Encoded"], bytes != .null {
                            guard case .string(let bytesValue) = bytes else {
                                let error = SchemaValidationIssuesError(
                                    vendor: "vertex",
                                    issues: "referenceImages[].bytesBase64Encoded must be a string"
                                )
                                return .failure(error: TypeValidationError.wrap(value: bytes, cause: error))
                            }
                            bytesBase64Encoded = bytesValue
                        }

                        var gcsUri: String?
                        if let gcs = object["gcsUri"], gcs != .null {
                            guard case .string(let gcsValue) = gcs else {
                                let error = SchemaValidationIssuesError(
                                    vendor: "vertex",
                                    issues: "referenceImages[].gcsUri must be a string"
                                )
                                return .failure(error: TypeValidationError.wrap(value: gcs, cause: error))
                            }
                            gcsUri = gcsValue
                        }

                        parsedImages.append(
                            GoogleVertexVideoReferenceImage(
                                bytesBase64Encoded: bytesBase64Encoded,
                                gcsUri: gcsUri
                            )
                        )
                    }

                    referenceImages = parsedImages
                }

                return .success(
                    value: GoogleVertexVideoModelOptions(
                        pollIntervalMs: pollIntervalMs,
                        pollTimeoutMs: pollTimeoutMs,
                        personGeneration: personGeneration,
                        negativePrompt: negativePrompt,
                        generateAudio: generateAudio,
                        gcsOutputDirectory: gcsOutputDirectory,
                        referenceImages: referenceImages
                    )
                )
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)

private struct GoogleVertexVideoOperation: Codable, Sendable {
    struct OperationError: Codable, Sendable {
        let code: Int?
        let message: String
        let status: String?
    }

    struct OperationResponse: Codable, Sendable {
        struct Video: Codable, Sendable {
            let bytesBase64Encoded: String?
            let gcsUri: String?
            let mimeType: String?
        }

        let videos: [Video]?
        let raiMediaFilteredCount: Int?
    }

    let name: String?
    let done: Bool?
    let error: OperationError?
    let response: OperationResponse?
}

private let googleVertexVideoOperationSchema = FlexibleSchema(
    Schema.codable(
        GoogleVertexVideoOperation.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

public final class GoogleVertexVideoModel: VideoModelV3 {
    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }
    public var maxVideosPerCall: VideoModelV3MaxVideosPerCall { .value(4) }

    private let modelIdentifier: GoogleVertexVideoModelId
    private let config: GoogleVertexVideoModelConfig

    init(modelId: GoogleVertexVideoModelId, config: GoogleVertexVideoModelConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public func doGenerate(options: VideoModelV3CallOptions) async throws -> VideoModelV3GenerateResult {
        let currentDate = config.currentDate()
        var warnings: [SharedV3Warning] = []

        let vertexOptions = try await parseProviderOptions(
            provider: "vertex",
            providerOptions: options.providerOptions,
            schema: googleVertexVideoModelOptionsSchema
        )

        let rawVertexOptions = options.providerOptions?["vertex"] ?? [:]

        var instance: [String: JSONValue] = [:]
        if let prompt = options.prompt {
            instance["prompt"] = .string(prompt)
        }

        if let image = options.image {
            switch image {
            case .url:
                warnings.append(
                    .unsupported(
                        feature: "URL-based image input",
                        details: "Vertex AI video models require base64-encoded images or GCS URIs. URL will be ignored."
                    )
                )

            case .file(let mediaType, let data, _):
                let base64Data: String
                switch data {
                case .base64(let value):
                    base64Data = value
                case .binary(let value):
                    base64Data = convertDataToBase64(value)
                }

                var imagePayload: [String: JSONValue] = [
                    "bytesBase64Encoded": .string(base64Data)
                ]
                if !mediaType.isEmpty {
                    imagePayload["mimeType"] = .string(mediaType)
                }
                instance["image"] = .object(imagePayload)
            }
        }

        if let referenceImages = vertexOptions?.referenceImages {
            instance["referenceImages"] = .array(
                referenceImages.map { image in
                    var object: [String: JSONValue] = [:]
                    if let bytes = image.bytesBase64Encoded {
                        object["bytesBase64Encoded"] = .string(bytes)
                    }
                    if let gcsUri = image.gcsUri {
                        object["gcsUri"] = .string(gcsUri)
                    }
                    return .object(object)
                }
            )
        }

        var parameters: [String: JSONValue] = [
            "sampleCount": .number(Double(options.n))
        ]

        if let aspectRatio = options.aspectRatio {
            parameters["aspectRatio"] = .string(aspectRatio)
        }

        if let resolution = options.resolution {
            let mappedResolution: String
            switch resolution {
            case "1280x720":
                mappedResolution = "720p"
            case "1920x1080":
                mappedResolution = "1080p"
            case "3840x2160":
                mappedResolution = "4k"
            default:
                mappedResolution = resolution
            }
            parameters["resolution"] = .string(mappedResolution)
        }

        if let duration = options.duration {
            parameters["durationSeconds"] = .number(Double(duration))
        }

        if let seed = options.seed {
            parameters["seed"] = .number(Double(seed))
        }

        if let personGeneration = vertexOptions?.personGeneration {
            parameters["personGeneration"] = .string(personGeneration.rawValue)
        }

        if let negativePrompt = vertexOptions?.negativePrompt {
            parameters["negativePrompt"] = .string(negativePrompt)
        }

        if let generateAudio = vertexOptions?.generateAudio {
            parameters["generateAudio"] = .bool(generateAudio)
        }

        if let gcsOutputDirectory = vertexOptions?.gcsOutputDirectory {
            parameters["gcsOutputDirectory"] = .string(gcsOutputDirectory)
        }

        let excludedPassthroughKeys: Set<String> = [
            "pollIntervalMs",
            "pollTimeoutMs",
            "personGeneration",
            "negativePrompt",
            "generateAudio",
            "gcsOutputDirectory",
            "referenceImages"
        ]

        for (key, value) in rawVertexOptions where !excludedPassthroughKeys.contains(key) {
            parameters[key] = value
        }

        let requestHeaders: @Sendable () -> [String: String] = { [self] in
            combineHeaders(self.config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 }
        }

        let operation = try await postJsonToAPI(
            url: "\(config.baseURL)/models/\(modelIdentifier.rawValue):predictLongRunning",
            headers: requestHeaders(),
            body: JSONValue.object([
                "instances": .array([.object(instance)]),
                "parameters": .object(parameters)
            ]),
            failedResponseHandler: googleVertexFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: googleVertexVideoOperationSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        guard let operationName = operation.value.name, !operationName.isEmpty else {
            throw GoogleVertexVideoModelError(
                name: "VERTEX_VIDEO_GENERATION_ERROR",
                message: "No operation name returned from API"
            )
        }

        let pollIntervalMs = vertexOptions?.pollIntervalMs ?? 10_000
        let pollTimeoutMs = vertexOptions?.pollTimeoutMs ?? 600_000

        let startTime = Date()
        var finalOperation = operation.value
        var responseHeaders: [String: String]?

        while finalOperation.done != true {
            let elapsedMs = Date().timeIntervalSince(startTime) * 1000
            if elapsedMs > pollTimeoutMs {
                throw GoogleVertexVideoModelError(
                    name: "VERTEX_VIDEO_GENERATION_TIMEOUT",
                    message: "Video generation timed out after \(formatVertexMilliseconds(pollTimeoutMs))ms"
                )
            }

            let pollDelay = max(0, Int(pollIntervalMs.rounded(.towardZero)))
            try await delay(pollDelay)

            if options.abortSignal?() == true {
                throw GoogleVertexVideoModelError(
                    name: "VERTEX_VIDEO_GENERATION_ABORTED",
                    message: "Video generation request was aborted"
                )
            }

            let statusOperation = try await postJsonToAPI(
                url: "\(config.baseURL)/models/\(modelIdentifier.rawValue):fetchPredictOperation",
                headers: requestHeaders(),
                body: JSONValue.object([
                    "operationName": .string(operationName)
                ]),
                failedResponseHandler: googleVertexFailedResponseHandler,
                successfulResponseHandler: createJsonResponseHandler(responseSchema: googleVertexVideoOperationSchema),
                isAborted: options.abortSignal,
                fetch: config.fetch
            )

            finalOperation = statusOperation.value
            responseHeaders = statusOperation.responseHeaders
        }

        if let operationError = finalOperation.error {
            throw GoogleVertexVideoModelError(
                name: "VERTEX_VIDEO_GENERATION_FAILED",
                message: "Video generation failed: \(operationError.message)"
            )
        }

        guard let responseVideos = finalOperation.response?.videos,
              !responseVideos.isEmpty else {
            throw GoogleVertexVideoModelError(
                name: "VERTEX_VIDEO_GENERATION_ERROR",
                message: "No videos in response. Response: \(googleVertexVideoJSONString(from: finalOperation))"
            )
        }

        var videos: [VideoModelV3VideoData] = []
        var videoMetadata: [JSONValue] = []

        for video in responseVideos {
            let resolvedMimeType = video.mimeType?.isEmpty == false ? video.mimeType! : "video/mp4"

            if let bytesBase64Encoded = video.bytesBase64Encoded, !bytesBase64Encoded.isEmpty {
                videos.append(.base64(data: bytesBase64Encoded, mediaType: resolvedMimeType))

                var metadata: [String: JSONValue] = [:]
                if let mimeType = video.mimeType {
                    metadata["mimeType"] = .string(mimeType)
                }
                videoMetadata.append(.object(metadata))
                continue
            }

            if let gcsUri = video.gcsUri, !gcsUri.isEmpty {
                videos.append(.url(url: gcsUri, mediaType: resolvedMimeType))

                var metadata: [String: JSONValue] = [
                    "gcsUri": .string(gcsUri)
                ]
                if let mimeType = video.mimeType {
                    metadata["mimeType"] = .string(mimeType)
                }
                videoMetadata.append(.object(metadata))
            }
        }

        if videos.isEmpty {
            throw GoogleVertexVideoModelError(
                name: "VERTEX_VIDEO_GENERATION_ERROR",
                message: "No valid videos in response"
            )
        }

        return VideoModelV3GenerateResult(
            videos: videos,
            warnings: warnings,
            providerMetadata: [
                "google-vertex": [
                    "videos": .array(videoMetadata)
                ]
            ],
            response: VideoModelV3ResponseInfo(
                timestamp: currentDate,
                modelId: modelIdentifier.rawValue,
                headers: responseHeaders
            )
        )
    }
}

private func googleVertexVideoJSONString(from operation: GoogleVertexVideoOperation) -> String {
    do {
        let data = try JSONEncoder().encode(operation)
        return String(data: data, encoding: .utf8) ?? String(describing: operation)
    } catch {
        return String(describing: operation)
    }
}

private func formatVertexMilliseconds(_ value: Double) -> String {
    if value.rounded(.towardZero) == value {
        return String(Int(value))
    }
    return String(value)
}

private struct GoogleVertexVideoModelError: AISDKError, Sendable {
    static let errorDomain = "google.vertex.video.error"

    let name: String
    let message: String
    let cause: (any Error)? = nil
}
