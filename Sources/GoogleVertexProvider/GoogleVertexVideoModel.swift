import Foundation
import AISDKProvider
import AISDKProviderUtils

struct GoogleVertexVideoModelConfig: Sendable {
    let provider: String
    let baseURL: @Sendable () throws -> String
    let headers: @Sendable () throws -> [String: String?]
    let fetch: FetchFunction?
    let generateId: @Sendable () -> String
    let currentDate: @Sendable () -> Date

    init(provider: String, baseURL: @escaping @Sendable () throws -> String, headers: @escaping @Sendable () throws -> [String: String?], fetch: FetchFunction?, generateId: @escaping @Sendable () -> String, currentDate: @escaping @Sendable () -> Date = { Date() }) {
        self.provider = provider
        self.baseURL = baseURL
        self.headers = headers
        self.fetch = fetch
        self.generateId = generateId
        self.currentDate = currentDate
    }
}

public enum GoogleVertexVideoPersonGeneration: String, Sendable, Equatable, Codable {
    case dontAllow = "dont_allow", allowAdult = "allow_adult", allowAll = "allow_all"
}

public struct GoogleVertexVideoReferenceImage: Sendable, Equatable, Codable {
    public var bytesBase64Encoded: String?
    public var gcsUri: String?
    public init(bytesBase64Encoded: String? = nil, gcsUri: String? = nil) {
        self.bytesBase64Encoded = bytesBase64Encoded
        self.gcsUri = gcsUri
    }
}

public struct GoogleVertexVideoModelOptions: Sendable, Equatable, Codable {
    public var pollIntervalMs: Double?
    public var pollTimeoutMs: Double?
    public var personGeneration: GoogleVertexVideoPersonGeneration?
    public var negativePrompt: String?
    public var generateAudio: Bool?
    public var gcsOutputDirectory: String?
    public var referenceImages: [GoogleVertexVideoReferenceImage]?

    public init(pollIntervalMs: Double? = nil, pollTimeoutMs: Double? = nil, personGeneration: GoogleVertexVideoPersonGeneration? = nil, negativePrompt: String? = nil, generateAudio: Bool? = nil, gcsOutputDirectory: String? = nil, referenceImages: [GoogleVertexVideoReferenceImage]? = nil) {
        self.pollIntervalMs = pollIntervalMs
        self.pollTimeoutMs = pollTimeoutMs
        self.personGeneration = personGeneration
        self.negativePrompt = negativePrompt
        self.generateAudio = generateAudio
        self.gcsOutputDirectory = gcsOutputDirectory
        self.referenceImages = referenceImages
    }
}

private let googleVertexVideoModelOptionsSchema = FlexibleSchema(Schema<GoogleVertexVideoModelOptions>(
    jsonSchemaResolver: { .object(["type": .string("object")]) },
    validator: { value in
        do {
            let json = try jsonValue(from: value)
            let parsed = try JSONDecoder().decode(GoogleVertexVideoModelOptions.self, from: JSONEncoder().encode(json))
            if let interval = parsed.pollIntervalMs, interval <= 0 {
                throw InvalidArgumentError(argument: "pollIntervalMs", message: "pollIntervalMs must be positive")
            }
            if let timeout = parsed.pollTimeoutMs, timeout <= 0 {
                throw InvalidArgumentError(argument: "pollTimeoutMs", message: "pollTimeoutMs must be positive")
            }
            return .success(value: parsed)
        } catch { return .failure(error: TypeValidationError.wrap(value: value, cause: error)) }
    }
))

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

private let googleVertexVideoOperationSchema = FlexibleSchema(Schema.codable(
    GoogleVertexVideoOperation.self, jsonSchema: .object(["type": .string("object")])
))

public final class GoogleVertexVideoModel: VideoModelV4Operations {
    private let modelIdentifier: GoogleVertexVideoModelId
    private let config: GoogleVertexVideoModelConfig
    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }
    public var maxVideosPerCall: VideoModelV4MaxVideosPerCall { .value(4) }

    init(modelId: GoogleVertexVideoModelId, config: GoogleVertexVideoModelConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public func doStart(options: VideoModelV4CallOptions, webhookUrl: String? = nil) async throws -> VideoModelV4OperationStartResult {
        let timestamp = config.currentDate()
        let parsed = try await parseVertexOptions(options.providerOptions, schema: googleVertexVideoModelOptionsSchema)
        let raw = options.providerOptions?["googleVertex"] ?? options.providerOptions?["vertex"] ?? [:]
        var warnings: [SharedV4Warning] = []
        var instance: JSONObject = [:]
        if let prompt = options.prompt { instance["prompt"] = .string(prompt) }
        let firstFrame = options.frameImages?.first { $0.frameType == .firstFrame }?.image
        if let file = firstFrame ?? options.image, let image = convertImage(file, warnings: &warnings) {
            instance["image"] = .object(image)
        }
        if let file = options.frameImages?.first(where: { $0.frameType == .lastFrame })?.image,
           let image = convertImage(file, warnings: &warnings) {
            instance["lastFrame"] = .object(image)
        }
        if options.frameImages?.isEmpty != false, let references = options.inputReferences, !references.isEmpty {
            instance["referenceImages"] = .array(references.compactMap { file in
                guard let image = convertImage(file, warnings: &warnings) else { return nil }
                return .object(["image": .object(image), "referenceType": .string("asset")])
            })
        } else if parsed?.referenceImages != nil {
            instance["referenceImages"] = raw["referenceImages"]
        }
        var parameters: JSONObject = ["sampleCount": .number(Double(options.n))]
        if let ratio = options.aspectRatio, !ratio.isEmpty { parameters["aspectRatio"] = .string(ratio) }
        if let resolution = options.resolution, !resolution.isEmpty {
            let map = ["1280x720": "720p", "1920x1080": "1080p", "3840x2160": "4k"]
            parameters["resolution"] = .string(map[resolution] ?? resolution)
        }
        if let duration = options.duration, duration != 0 { parameters["durationSeconds"] = .number(Double(duration)) }
        if let seed = options.seed, seed != 0 { parameters["seed"] = .number(Double(seed)) }
        if let audio = options.generateAudio ?? parsed?.generateAudio { parameters["generateAudio"] = .bool(audio) }
        if let person = parsed?.personGeneration { parameters["personGeneration"] = .string(person.rawValue) }
        if let prompt = parsed?.negativePrompt { parameters["negativePrompt"] = .string(prompt) }
        if let directory = parsed?.gcsOutputDirectory { parameters["gcsOutputDirectory"] = .string(directory) }
        let excluded: Set<String> = ["pollIntervalMs", "pollTimeoutMs", "personGeneration", "negativePrompt", "generateAudio", "gcsOutputDirectory", "referenceImages"]
        for (key, value) in raw where !excluded.contains(key) { parameters[key] = value }
        let response = try await postJsonToAPI(
            url: "\(try config.baseURL())/models/\(modelId):predictLongRunning",
            headers: combineHeaders(try config.headers(), options.headers).compactMapValues { $0 },
            body: JSONValue.object(["instances": .array([.object(instance)]), "parameters": .object(parameters)]),
            failedResponseHandler: googleVertexFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: googleVertexVideoOperationSchema),
            isAborted: options.abortSignal, fetch: config.fetch
        )
        guard let name = response.value.name, !name.isEmpty else {
            throw GoogleVertexVideoModelError(name: "VERTEX_VIDEO_GENERATION_ERROR", message: "No operation name returned from API")
        }
        return .init(operation: .object(["operationName": .string(name)]), warnings: warnings,
                     response: .init(timestamp: timestamp, modelId: modelId, headers: response.responseHeaders))
    }

    public func doStatus(options: VideoModelV4StatusCallOptions) async throws -> VideoModelV4OperationStatusResult {
        let timestamp = config.currentDate()
        var body: JSONObject = [:]
        if case .object(let operation) = options.operation { body["operationName"] = operation["operationName"] }
        let response = try await postJsonToAPI(
            url: "\(try config.baseURL())/models/\(modelId):fetchPredictOperation",
            headers: combineHeaders(try config.headers(), options.headers).compactMapValues { $0 },
            body: JSONValue.object(body), failedResponseHandler: googleVertexFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: googleVertexVideoOperationSchema),
            isAborted: options.abortSignal, fetch: config.fetch
        )
        let info = VideoModelV4ResponseInfo(timestamp: timestamp, modelId: modelId, headers: response.responseHeaders)
        let operation = response.value
        if operation.done != true { return .pending(warnings: nil, providerMetadata: nil, response: info) }
        if let error = operation.error {
            return .error(error: "Video generation failed: \(error.message)", providerMetadata: nil, response: info)
        }
        guard let responseVideos = operation.response?.videos, !responseVideos.isEmpty else {
            let data = try JSONEncoder().encode(operation)
            throw GoogleVertexVideoModelError(name: "VERTEX_VIDEO_GENERATION_ERROR", message: "No videos in response. Response: \(String(decoding: data, as: UTF8.self))")
        }
        var videos: [VideoModelV4VideoData] = []
        var metadata: [JSONValue] = []
        for video in responseVideos {
            let type = video.mimeType.flatMap { $0.isEmpty ? nil : $0 } ?? "video/mp4"
            var entry: JSONObject = [:]
            if let mime = video.mimeType { entry["mimeType"] = .string(mime) }
            if let bytes = video.bytesBase64Encoded, !bytes.isEmpty {
                videos.append(.base64(data: bytes, mediaType: type))
            } else if let uri = video.gcsUri, !uri.isEmpty {
                videos.append(.url(url: uri, mediaType: type))
                entry["gcsUri"] = .string(uri)
            } else { continue }
            metadata.append(.object(entry))
        }
        guard !videos.isEmpty else {
            throw GoogleVertexVideoModelError(name: "VERTEX_VIDEO_GENERATION_ERROR", message: "No valid videos in response")
        }
        let payload: JSONObject = ["videos": .array(metadata)]
        return .completed(videos: videos, warnings: [], providerMetadata: ["googleVertex": payload, "vertex": payload, "google-vertex": payload], response: info)
    }

    private func convertImage(_ file: VideoModelV4File, warnings: inout [SharedV4Warning]) -> JSONObject? {
        switch file {
        case .url(let url, _, _):
            if url.hasPrefix("gs://") { return ["gcsUri": .string(url), "mimeType": .string("image/png")] }
            warnings.append(.unsupported(feature: "URL-based image input", details: "Vertex AI video models require base64-encoded images or GCS URIs. URL will be ignored."))
            return nil
        case .file(let type, let data, _):
            let bytes: String
            switch data {
            case .base64(let value): bytes = value
            case .binary(let value): bytes = value.base64EncodedString()
            }
            return ["bytesBase64Encoded": .string(bytes), "mimeType": .string(type.isEmpty ? "image/png" : type)]
        }
    }
}

private struct GoogleVertexVideoModelError: AISDKError, Sendable {
    static let errorDomain = "google.vertex.video.error"
    let name: String
    let message: String
    let cause: (any Error)? = nil
}
