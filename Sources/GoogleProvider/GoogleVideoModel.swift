import Foundation
import AISDKProvider
import AISDKProviderUtils

struct GoogleVideoModelConfig: Sendable {
    let provider: String
    let baseURL: String
    let headers: @Sendable () throws -> [String: String?]
    let fetch: FetchFunction?
    let generateId: @Sendable () -> String
    let currentDate: @Sendable () -> Date
    init(provider: String, baseURL: String, headers: @escaping @Sendable () throws -> [String: String?], fetch: FetchFunction?, generateId: @escaping @Sendable () -> String = generateID, currentDate: @escaping @Sendable () -> Date = { Date() }) {
        self.provider = provider; self.baseURL = baseURL; self.headers = headers; self.fetch = fetch; self.generateId = generateId; self.currentDate = currentDate
    }
}

public struct GoogleVideoReferenceImage: Sendable, Equatable, Codable {
    public var bytesBase64Encoded: String?
    public var gcsUri: String?
    public init(bytesBase64Encoded: String? = nil, gcsUri: String? = nil) { self.bytesBase64Encoded = bytesBase64Encoded; self.gcsUri = gcsUri }
}
public struct GoogleVideoModelOptions: Sendable, Equatable, Codable {
    public var pollIntervalMs: Double?
    public var pollTimeoutMs: Double?
    public var personGeneration: GooglePersonGeneration?
    public var negativePrompt: String?
    public var referenceImages: [GoogleVideoReferenceImage]?
    public init(pollIntervalMs: Double? = nil, pollTimeoutMs: Double? = nil, personGeneration: GooglePersonGeneration? = nil, negativePrompt: String? = nil, referenceImages: [GoogleVideoReferenceImage]? = nil) {
        self.pollIntervalMs = pollIntervalMs; self.pollTimeoutMs = pollTimeoutMs; self.personGeneration = personGeneration; self.negativePrompt = negativePrompt; self.referenceImages = referenceImages
    }
}
private let googleVideoOptionsSchema = FlexibleSchema(Schema<GoogleVideoModelOptions>(jsonSchemaResolver: { .object(["type": .string("object")]) }, validator: { value in
    do {
        let data = try JSONEncoder().encode(jsonValue(from: value))
        let options = try JSONDecoder().decode(GoogleVideoModelOptions.self, from: data)
        if let interval = options.pollIntervalMs, interval <= 0 { throw InvalidArgumentError(argument: "pollIntervalMs", message: "pollIntervalMs must be positive") }
        if let timeout = options.pollTimeoutMs, timeout <= 0 { throw InvalidArgumentError(argument: "pollTimeoutMs", message: "pollTimeoutMs must be positive") }
        return .success(value: options)
    } catch { return .failure(error: TypeValidationError.wrap(value: value, cause: error)) }
}))

private struct GoogleVideoOperation: Codable, Sendable {
    struct Failure: Codable, Sendable { let code: Double?; let message: String; let status: String? }
    struct Response: Codable, Sendable {
        struct Generation: Codable, Sendable {
            struct Sample: Codable, Sendable { struct Video: Codable, Sendable { let uri: String? }; let video: Video? }
            let generatedSamples: [Sample]?
        }
        let generateVideoResponse: Generation?
    }
    let name: String?
    let done: Bool?
    let error: Failure?
    let response: Response?
}
private let googleVideoOperationSchema = FlexibleSchema(Schema<GoogleVideoOperation>.codable(GoogleVideoOperation.self, jsonSchema: .object(["type": .string("object")])))

public final class GoogleVideoModel: VideoModelV4Operations {
    private let config: GoogleVideoModelConfig
    public let modelId: String
    public var provider: String { config.provider }
    public var maxVideosPerCall: VideoModelV4MaxVideosPerCall { .value(4) }
    init(modelId: GoogleVideoModelId, config: GoogleVideoModelConfig) { self.modelId = modelId.rawValue; self.config = config }

    public func doStart(options: VideoModelV4CallOptions, webhookUrl: String? = nil) async throws -> VideoModelV4OperationStartResult {
        let timestamp = config.currentDate()
        let google = try await parseProviderOptions(provider: "google", providerOptions: options.providerOptions, schema: googleVideoOptionsSchema)
        var warnings: [SharedV4Warning] = []
        func image(_ file: VideoModelV4File) -> JSONValue? {
            switch file {
            case .url(let url, _, _):
                if url.hasPrefix("gs://") { return .object(["gcsUri": .string(url), "mimeType": .string("image/png")]) }
                warnings.append(.unsupported(feature: "URL-based image input", details: "Google Generative AI video models require base64-encoded images or GCS URIs. URL will be ignored."))
                return nil
            case .file(let type, let data, _):
                let bytes: String
                switch data { case .base64(let string): bytes = string; case .binary(let bytesValue): bytes = bytesValue.base64EncodedString() }
                return .object(["bytesBase64Encoded": .string(bytes), "mimeType": .string(type.isEmpty ? "image/png" : type)])
            }
        }
        var instance: [String: JSONValue] = [:]
        if let prompt = options.prompt { instance["prompt"] = .string(prompt) }
        let first = options.frameImages?.first { $0.frameType == .firstFrame }?.image ?? options.image
        if let first, let value = image(first) { instance["image"] = value }
        if let last = options.frameImages?.first(where: { $0.frameType == .lastFrame })?.image, let value = image(last) { instance["lastFrame"] = value }
        if options.frameImages?.isEmpty != false, let references = options.inputReferences, !references.isEmpty {
            instance["referenceImages"] = .array(references.compactMap { reference in image(reference).map { .object(["image": $0, "referenceType": .string("asset")]) } })
        } else if let references = google?.referenceImages {
            instance["referenceImages"] = .array(references.map { reference in
                var image: [String: JSONValue] = ["mimeType": .string("image/png")]
                if let bytes = reference.bytesBase64Encoded, !bytes.isEmpty { image["bytesBase64Encoded"] = .string(bytes) }
                else if let uri = reference.gcsUri, !uri.isEmpty { image["gcsUri"] = .string(uri) }
                else {
                    var value: [String: JSONValue] = [:]
                    if let bytes = reference.bytesBase64Encoded { value["bytesBase64Encoded"] = .string(bytes) }
                    if let uri = reference.gcsUri { value["gcsUri"] = .string(uri) }
                    return .object(value)
                }
                return .object(["image": .object(image), "referenceType": .string("asset")])
            })
        }
        var parameters: [String: JSONValue] = ["sampleCount": .number(Double(options.n))]
        if let ratio = options.aspectRatio, !ratio.isEmpty { parameters["aspectRatio"] = .string(ratio) }
        if let resolution = options.resolution, !resolution.isEmpty { parameters["resolution"] = .string(["1280x720": "720p", "1920x1080": "1080p", "3840x2160": "4k"][resolution] ?? resolution) }
        if let duration = options.duration, duration != 0 { parameters["durationSeconds"] = .number(Double(duration)) }
        if let seed = options.seed, seed != 0 { parameters["seed"] = .number(Double(seed)) }
        if let person = google?.personGeneration { parameters["personGeneration"] = .string(person.rawValue) }
        if let negative = google?.negativePrompt { parameters["negativePrompt"] = .string(negative) }
        for (key, value) in options.providerOptions?["google"] ?? [:] where !["pollIntervalMs", "pollTimeoutMs", "personGeneration", "negativePrompt", "referenceImages"].contains(key) { parameters[key] = value }
        let response = try await postJsonToAPI(url: "\(config.baseURL)/models/\(modelId):predictLongRunning", headers: combineHeaders(try config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 }, body: JSONValue.object(["instances": .array([.object(instance)]), "parameters": .object(parameters)]), failedResponseHandler: googleFailedResponseHandler, successfulResponseHandler: createJsonResponseHandler(responseSchema: googleVideoOperationSchema), isAborted: options.abortSignal, fetch: config.fetch)
        guard let name = response.value.name, !name.isEmpty else { throw GoogleVideoModelError(message: "No operation name returned from API") }
        return .init(operation: .object(["operationName": .string(name)]), warnings: warnings, response: .init(timestamp: timestamp, modelId: modelId, headers: response.responseHeaders))
    }

    public func doStatus(options: VideoModelV4StatusCallOptions) async throws -> VideoModelV4OperationStatusResult {
        let timestamp = config.currentDate()
        guard case .object(let operation) = options.operation, case .string(let name) = operation["operationName"] else { throw InvalidArgumentError(argument: "operation", message: "operationName is required") }
        let response = try await getFromAPI(url: "\(config.baseURL)/\(name)", headers: combineHeaders(try config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 }, failedResponseHandler: googleFailedResponseHandler, successfulResponseHandler: createJsonResponseHandler(responseSchema: googleVideoOperationSchema), isAborted: options.abortSignal, fetch: config.fetch)
        let info = VideoModelV4ResponseInfo(timestamp: timestamp, modelId: modelId, headers: response.responseHeaders)
        guard response.value.done == true else { return .pending(warnings: nil, providerMetadata: nil, response: info) }
        if let failure = response.value.error { return .error(error: "Video generation failed: \(failure.message)", providerMetadata: nil, response: info) }
        guard let samples = response.value.response?.generateVideoResponse?.generatedSamples, !samples.isEmpty else {
            let raw = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(response.value))
            throw GoogleVideoModelError(message: "No videos in response. Response: \(try googleJSONString(raw))")
        }
        let key = try config.headers()["x-goog-api-key"] ?? nil
        var videos: [VideoModelV4VideoData] = []
        var metadata: [JSONValue] = []
        for sample in samples {
            guard let uri = sample.video?.uri, !uri.isEmpty else { continue }
            var url = uri
            if let key, !key.isEmpty, let a = URL(string: uri), let b = URL(string: config.baseURL), a.scheme == b.scheme, a.host == b.host, a.port == b.port {
                url += (uri.contains("?") ? "&" : "?") + "key=\(key)"
            }
            videos.append(.url(url: url, mediaType: "video/mp4"))
            metadata.append(.object(["uri": .string(uri)]))
        }
        if videos.isEmpty { throw GoogleVideoModelError(message: "No valid videos in response") }
        return .completed(videos: videos, warnings: [], providerMetadata: ["google": ["videos": .array(metadata)]], response: info)
    }
}

private struct GoogleVideoModelError: AISDKError, Sendable {
    static let errorDomain = "google.video.error"
    let name = "GOOGLE_VIDEO_GENERATION_ERROR"
    let message: String
    let cause: (any Error)? = nil
}
