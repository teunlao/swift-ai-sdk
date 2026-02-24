import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/google/src/google-generative-ai-video-model.ts
// Ported from packages/google/src/google-generative-ai-video-settings.ts
// Upstream commit: c0fff03
//===----------------------------------------------------------------------===//

struct GoogleGenerativeAIVideoModelConfig: Sendable {
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

public struct GoogleVideoReferenceImage: Sendable, Equatable {
    public var bytesBase64Encoded: String?
    public var gcsUri: String?

    public init(bytesBase64Encoded: String? = nil, gcsUri: String? = nil) {
        self.bytesBase64Encoded = bytesBase64Encoded
        self.gcsUri = gcsUri
    }
}

public struct GoogleVideoModelOptions: Sendable, Equatable {
    public var pollIntervalMs: Double?
    public var pollTimeoutMs: Double?
    public var personGeneration: GoogleGenerativeAIPersonGeneration?
    public var negativePrompt: String?
    public var referenceImages: [GoogleVideoReferenceImage]?

    public init(
        pollIntervalMs: Double? = nil,
        pollTimeoutMs: Double? = nil,
        personGeneration: GoogleGenerativeAIPersonGeneration? = nil,
        negativePrompt: String? = nil,
        referenceImages: [GoogleVideoReferenceImage]? = nil
    ) {
        self.pollIntervalMs = pollIntervalMs
        self.pollTimeoutMs = pollTimeoutMs
        self.personGeneration = personGeneration
        self.negativePrompt = negativePrompt
        self.referenceImages = referenceImages
    }
}

private let googleVideoModelOptionsSchema = FlexibleSchema(
    Schema<GoogleVideoModelOptions>(
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
                        vendor: "google",
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
                            vendor: "google",
                            issues: "\(key) must be a positive number"
                        )
                        return .failure(TypeValidationError.wrap(value: rawValue, cause: error))
                    }

                    guard number > 0 else {
                        let error = SchemaValidationIssuesError(
                            vendor: "google",
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

                var personGeneration: GoogleGenerativeAIPersonGeneration?
                if let value = dict["personGeneration"], value != .null {
                    guard case .string(let rawValue) = value,
                          let parsed = GoogleGenerativeAIPersonGeneration(rawValue: rawValue) else {
                        let error = SchemaValidationIssuesError(
                            vendor: "google",
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
                            vendor: "google",
                            issues: "negativePrompt must be a string"
                        )
                        return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                    }
                    negativePrompt = stringValue
                }

                var referenceImages: [GoogleVideoReferenceImage]?
                if let value = dict["referenceImages"], value != .null {
                    guard case .array(let array) = value else {
                        let error = SchemaValidationIssuesError(
                            vendor: "google",
                            issues: "referenceImages must be an array"
                        )
                        return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                    }

                    var parsedImages: [GoogleVideoReferenceImage] = []
                    for item in array {
                        guard case .object(let object) = item else {
                            let error = SchemaValidationIssuesError(
                                vendor: "google",
                                issues: "referenceImages entries must be objects"
                            )
                            return .failure(error: TypeValidationError.wrap(value: item, cause: error))
                        }

                        var bytesBase64Encoded: String?
                        if let bytes = object["bytesBase64Encoded"], bytes != .null {
                            guard case .string(let bytesValue) = bytes else {
                                let error = SchemaValidationIssuesError(
                                    vendor: "google",
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
                                    vendor: "google",
                                    issues: "referenceImages[].gcsUri must be a string"
                                )
                                return .failure(error: TypeValidationError.wrap(value: gcs, cause: error))
                            }
                            gcsUri = gcsValue
                        }

                        parsedImages.append(
                            GoogleVideoReferenceImage(
                                bytesBase64Encoded: bytesBase64Encoded,
                                gcsUri: gcsUri
                            )
                        )
                    }

                    referenceImages = parsedImages
                }

                return .success(
                    value: GoogleVideoModelOptions(
                        pollIntervalMs: pollIntervalMs,
                        pollTimeoutMs: pollTimeoutMs,
                        personGeneration: personGeneration,
                        negativePrompt: negativePrompt,
                        referenceImages: referenceImages
                    )
                )
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)

private struct GoogleVideoOperation: Codable, Sendable {
    struct OperationError: Codable, Sendable {
        let code: Int?
        let message: String
        let status: String?
    }

    struct OperationResponse: Codable, Sendable {
        struct GenerateVideoResponse: Codable, Sendable {
            struct GeneratedSample: Codable, Sendable {
                struct Video: Codable, Sendable {
                    let uri: String?
                }

                let video: Video?
            }

            let generatedSamples: [GeneratedSample]?
        }

        let generateVideoResponse: GenerateVideoResponse?
    }

    let name: String?
    let done: Bool?
    let error: OperationError?
    let response: OperationResponse?
}

private let googleVideoOperationSchema = FlexibleSchema(
    Schema.codable(
        GoogleVideoOperation.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

public final class GoogleGenerativeAIVideoModel: VideoModelV3 {
    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }
    public var maxVideosPerCall: VideoModelV3MaxVideosPerCall { .value(4) }

    private let modelIdentifier: GoogleGenerativeAIVideoModelId
    private let config: GoogleGenerativeAIVideoModelConfig

    init(modelId: GoogleGenerativeAIVideoModelId, config: GoogleGenerativeAIVideoModelConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public func doGenerate(options: VideoModelV3CallOptions) async throws -> VideoModelV3GenerateResult {
        let currentDate = config.currentDate()
        var warnings: [SharedV3Warning] = []

        let googleOptions = try await parseProviderOptions(
            provider: "google",
            providerOptions: options.providerOptions,
            schema: googleVideoModelOptionsSchema
        )

        let rawGoogleOptions = options.providerOptions?["google"] ?? [:]

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
                        details: "Google Generative AI video models require base64-encoded images. URL will be ignored."
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

                let resolvedMediaType = mediaType.isEmpty ? "image/png" : mediaType
                instance["image"] = .object([
                    "inlineData": .object([
                        "mimeType": .string(resolvedMediaType),
                        "data": .string(base64Data)
                    ])
                ])
            }
        }

        if let referenceImages = googleOptions?.referenceImages {
            instance["referenceImages"] = .array(
                referenceImages.map { image in
                    if let bytes = image.bytesBase64Encoded, !bytes.isEmpty {
                        return .object([
                            "inlineData": .object([
                                "mimeType": .string("image/png"),
                                "data": .string(bytes)
                            ])
                        ])
                    }

                    if let gcsUri = image.gcsUri, !gcsUri.isEmpty {
                        return .object([
                            "gcsUri": .string(gcsUri)
                        ])
                    }

                    var passthrough: [String: JSONValue] = [:]
                    if let bytes = image.bytesBase64Encoded {
                        passthrough["bytesBase64Encoded"] = .string(bytes)
                    }
                    if let gcsUri = image.gcsUri {
                        passthrough["gcsUri"] = .string(gcsUri)
                    }
                    return .object(passthrough)
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

        if let personGeneration = googleOptions?.personGeneration {
            parameters["personGeneration"] = .string(personGeneration.rawValue)
        }

        if let negativePrompt = googleOptions?.negativePrompt {
            parameters["negativePrompt"] = .string(negativePrompt)
        }

        let excludedPassthroughKeys: Set<String> = [
            "pollIntervalMs",
            "pollTimeoutMs",
            "personGeneration",
            "negativePrompt",
            "referenceImages"
        ]

        for (key, value) in rawGoogleOptions where !excludedPassthroughKeys.contains(key) {
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
            failedResponseHandler: googleFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: googleVideoOperationSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        guard let operationName = operation.value.name, !operationName.isEmpty else {
            throw GoogleVideoModelError(
                name: "GOOGLE_VIDEO_GENERATION_ERROR",
                message: "No operation name returned from API"
            )
        }

        let pollIntervalMs = googleOptions?.pollIntervalMs ?? 10_000
        let pollTimeoutMs = googleOptions?.pollTimeoutMs ?? 600_000

        let startTime = Date()
        var finalOperation = operation.value
        var responseHeaders: [String: String]?

        while finalOperation.done != true {
            let elapsedMs = Date().timeIntervalSince(startTime) * 1000
            if elapsedMs > pollTimeoutMs {
                throw GoogleVideoModelError(
                    name: "GOOGLE_VIDEO_GENERATION_TIMEOUT",
                    message: "Video generation timed out after \(formatMilliseconds(pollTimeoutMs))ms"
                )
            }

            let pollDelay = max(0, Int(pollIntervalMs.rounded(.towardZero)))
            try await delay(pollDelay)

            if options.abortSignal?() == true {
                throw GoogleVideoModelError(
                    name: "GOOGLE_VIDEO_GENERATION_ABORTED",
                    message: "Video generation request was aborted"
                )
            }

            let statusOperation = try await getFromAPI(
                url: "\(config.baseURL)/\(operationName)",
                headers: requestHeaders(),
                failedResponseHandler: googleFailedResponseHandler,
                successfulResponseHandler: createJsonResponseHandler(responseSchema: googleVideoOperationSchema),
                isAborted: options.abortSignal,
                fetch: config.fetch
            )

            finalOperation = statusOperation.value
            responseHeaders = statusOperation.responseHeaders
        }

        if let operationError = finalOperation.error {
            throw GoogleVideoModelError(
                name: "GOOGLE_VIDEO_GENERATION_FAILED",
                message: "Video generation failed: \(operationError.message)"
            )
        }

        guard let samples = finalOperation.response?.generateVideoResponse?.generatedSamples,
              !samples.isEmpty else {
            throw GoogleVideoModelError(
                name: "GOOGLE_VIDEO_GENERATION_ERROR",
                message: "No videos in response. Response: \(googleVideoJSONString(from: finalOperation))"
            )
        }

        let resolvedHeaders = config.headers()
        let apiKey = resolvedHeaders.first { $0.key.lowercased() == "x-goog-api-key" }?.value ?? nil

        var videos: [VideoModelV3VideoData] = []
        var videoMetadata: [JSONValue] = []

        for sample in samples {
            guard let uri = sample.video?.uri, !uri.isEmpty else { continue }

            let videoURL: String
            if let apiKey, !apiKey.isEmpty {
                let separator = uri.contains("?") ? "&" : "?"
                videoURL = "\(uri)\(separator)key=\(apiKey)"
            } else {
                videoURL = uri
            }

            videos.append(.url(url: videoURL, mediaType: "video/mp4"))
            videoMetadata.append(.object(["uri": .string(uri)]))
        }

        if videos.isEmpty {
            throw GoogleVideoModelError(
                name: "GOOGLE_VIDEO_GENERATION_ERROR",
                message: "No valid videos in response"
            )
        }

        return VideoModelV3GenerateResult(
            videos: videos,
            warnings: warnings,
            providerMetadata: [
                "google": [
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

private func googleVideoJSONString(from operation: GoogleVideoOperation) -> String {
    do {
        let data = try JSONEncoder().encode(operation)
        return String(data: data, encoding: .utf8) ?? String(describing: operation)
    } catch {
        return String(describing: operation)
    }
}

private func formatMilliseconds(_ value: Double) -> String {
    if value.rounded(.towardZero) == value {
        return String(Int(value))
    }
    return String(value)
}

private struct GoogleVideoModelError: AISDKError, Sendable {
    static let errorDomain = "google.video.error"

    let name: String
    let message: String
    let cause: (any Error)? = nil
}
