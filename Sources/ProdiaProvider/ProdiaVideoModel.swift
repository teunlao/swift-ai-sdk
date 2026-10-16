import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class ProdiaVideoModel: VideoModelV4Generator {
    public var specificationVersion: String { "v4" }
    public var maxVideosPerCall: VideoModelV4MaxVideosPerCall { .value(1) }
    public var provider: String { config.provider }
    public var modelId: String { identifier.rawValue }
    private let identifier: ProdiaVideoModelId
    private let config: ProdiaModelConfig

    init(modelId: ProdiaVideoModelId, config: ProdiaModelConfig) {
        self.identifier = modelId
        self.config = config
    }

    public func doGenerate(options: VideoModelV4CallOptions) async throws -> VideoModelV4GenerateResult {
        let parsed = try await parseProviderOptions(provider: "prodia", providerOptions: options.providerOptions,
                                                   schema: prodiaVideoModelOptionsSchema)
        var jobConfig: JSONObject = [:]
        if let prompt = options.prompt { jobConfig["prompt"] = .string(prompt) }
        if let seed = options.seed { jobConfig["seed"] = .number(Double(seed)) }
        if let resolution = parsed?.resolution { jobConfig["resolution"] = .string(resolution) }
        let job: JSONValue = .object(["type": .string(modelId), "config": .object(jobConfig)])
        let now = config.currentDate()
        let headers = combineHeaders(try await config.headers(), options.headers?.mapValues { Optional($0) },
                                     ["Accept": "multipart/form-data; video/mp4"]).compactMapValues { $0 }
        let response: ResponseHandlerResult<ProdiaVideoResponse>
        if let image = options.image {
            let data: Data
            let mediaType: String
            switch image {
            case .file(let type, let bytes, _):
                mediaType = type
                switch bytes {
                case .binary(let value): data = value
                case .base64(let value): data = try convertBase64ToData(value)
                }
            case .url(let url, _, _):
                let blob = try await downloadBlob(url: url, isAborted: options.abortSignal, fetch: config.fetch)
                data = blob.data
                mediaType = blob.mediaType.flatMap { $0.isEmpty ? nil : $0 } ?? "application/octet-stream"
            }
            var form = MultipartFormDataBuilder()
            form.appendFile(name: "job", filename: "job.json", contentType: "application/json", data: try JSONEncoder().encode(job))
            let extensions = ["image/png": ".png", "image/jpeg": ".jpg", "image/webp": ".webp", "video/mp4": ".mp4", "video/webm": ".webm"]
            form.appendFile(name: "input", filename: "input" + (extensions[mediaType] ?? ""), contentType: mediaType, data: data)
            response = try await postToAPI(
                url: "\(config.baseURL)/job?price=true", headers: headers,
                body: .init(content: .multipartFormData(form), values: job),
                failedResponseHandler: prodiaFailedResponseHandler, successfulResponseHandler: prodiaVideoResponseHandler,
                isAborted: options.abortSignal, fetch: config.fetch
            )
        } else {
            response = try await postJsonToAPI(
                url: "\(config.baseURL)/job?price=true",
                headers: combineHeaders(headers.mapValues { Optional($0) }, ["Content-Type": "application/json"]).compactMapValues { $0 }, body: job,
                failedResponseHandler: prodiaFailedResponseHandler, successfulResponseHandler: prodiaVideoResponseHandler,
                isAborted: options.abortSignal, fetch: config.fetch
            )
        }
        return .init(videos: [.binary(data: response.value.data, mediaType: response.value.mediaType)], warnings: [],
                     providerMetadata: ["prodia": ["videos": .array([.object(response.value.job.metadata)])]],
                     response: .init(timestamp: now, modelId: modelId, headers: response.responseHeaders))
    }
}

private struct ProdiaVideoResponse: Sendable {
    let job: ProdiaJobResult
    let data: Data
    let mediaType: String
}

private let prodiaVideoResponseHandler: ResponseHandler<ProdiaVideoResponse> = { input in
    let multipart = try await prodiaMultipartResponseHandler(input)
    var bytes: Data?
    var mediaType = "video/mp4"
    for part in multipart.value.parts {
        if part.disposition.contains("name=\"job\"") { continue }
        if part.disposition.contains("name=\"output\"") {
            bytes = part.body
            if part.mediaType.hasPrefix("video/") { mediaType = part.mediaType }
        } else if part.mediaType.hasPrefix("video/") {
            bytes = part.body
            mediaType = part.mediaType
        }
    }
    guard let bytes else {
        throw InvalidResponseDataError(data: nil, message: "Prodia multipart response missing output video")
    }
    return .init(value: .init(job: multipart.value.job, data: bytes, mediaType: mediaType), responseHeaders: multipart.responseHeaders)
}
