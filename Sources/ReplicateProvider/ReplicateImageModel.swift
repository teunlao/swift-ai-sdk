import Foundation
import AISDKProvider
import AISDKProviderUtils

struct ReplicateImageModelConfig: Sendable {
    let provider: String
    let baseURL: String
    let headers: @Sendable () throws -> [String: String?]
    let fetch: FetchFunction?
    var currentDate: @Sendable () -> Date = { Date() }
}

private struct ReplicateImagePrediction: Decodable, Sendable {
    enum Status: String, Decodable, Sendable {
        case starting, processing, succeeded, failed, canceled
    }
    struct URLs: Decodable, Sendable { let get: String }
    enum Output: Decodable, Sendable {
        case urls([String])
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let urls = try? container.decode([String].self) { self = .urls(urls) }
            else { self = .urls([try container.decode(String.self)]) }
        }
        var urls: [String] { switch self { case .urls(let urls): urls } }
    }
    let status: Status
    let output: Output?
    let error: String?
    let urls: URLs
}

private let replicateImageResponseSchema = FlexibleSchema(
    Schema<ReplicateImagePrediction>.codable(
        ReplicateImagePrediction.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

public struct ReplicateImageModelOptions: Sendable, Codable, Equatable {
    public var maxWaitTimeInSeconds: Double?
    public var pollIntervalMillis: Int?
    public var maxPollAttempts: Int?
    public var guidance_scale: Double?
    public var num_inference_steps: Double?
    public var negative_prompt: String?
    public var output_format: String?
    public var output_quality: Double?
    public var strength: Double?

    public init() {}
}

private let replicateImageOptionsSchema = FlexibleSchema(jsonSchema(.object([
    "type": .string("object"),
    "additionalProperties": .bool(true),
    "properties": .object([
        "maxWaitTimeInSeconds": .object(["type": .array([.string("number"), .string("null")]), "exclusiveMinimum": .number(0)]),
        "pollIntervalMillis": .object(["type": .array([.string("integer"), .string("null")]), "exclusiveMinimum": .number(0)]),
        "maxPollAttempts": .object(["type": .array([.string("integer"), .string("null")]), "exclusiveMinimum": .number(0)]),
        "guidance_scale": .object(["type": .array([.string("number"), .string("null")])]),
        "num_inference_steps": .object(["type": .array([.string("number"), .string("null")])]),
        "negative_prompt": .object(["type": .array([.string("string"), .string("null")])]),
        "output_format": .object(["enum": .array([.string("png"), .string("jpg"), .string("webp"), .null])]),
        "output_quality": .object(["type": .array([.string("number"), .string("null")]), "minimum": .number(1), "maximum": .number(100)]),
        "strength": .object(["type": .array([.string("number"), .string("null")]), "minimum": .number(0), "maximum": .number(1)])
    ])
])))

public final class ReplicateImageModel: ImageModelV4 {
    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }
    public var maxImagesPerCall: ImageModelV4MaxImagesPerCall { .value(isFlux2 ? 8 : 1) }
    public var supportsFileInputs: Bool? {
        ["black-forest-labs/flux-2-pro", "black-forest-labs/flux-2-dev", "black-forest-labs/flux-fill-pro", "black-forest-labs/flux-fill-dev"].contains(modelId) ? true : nil
    }
    public var supportsMaskInputs: Bool? {
        if ["black-forest-labs/flux-fill-pro", "black-forest-labs/flux-fill-dev"].contains(modelId) { return true }
        return supportsFileInputs == true ? false : nil
    }
    private var isFlux2: Bool { modelId.hasPrefix("black-forest-labs/flux-2-") }
    private let modelIdentifier: ReplicateImageModelId
    private let config: ReplicateImageModelConfig

    init(_ modelId: ReplicateImageModelId, config: ReplicateImageModelConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public func doGenerate(options: ImageModelV4CallOptions) async throws -> ImageModelV4GenerateResult {
        let timestamp = config.currentDate()
        var warnings: [SharedV4Warning] = []
        let parsed = try await parseProviderOptions(provider: "replicate", providerOptions: options.providerOptions, schema: replicateImageOptionsSchema)
        var inputOptions: [String: JSONValue] = [:]
        if case .object(let value) = parsed { inputOptions = value }
        let wait = inputOptions.removeValue(forKey: "maxWaitTimeInSeconds")
        guard let interval = Int(exactly: replicateNumber(inputOptions.removeValue(forKey: "pollIntervalMillis")) ?? 500),
              let attempts = Int(exactly: replicateNumber(inputOptions.removeValue(forKey: "maxPollAttempts")) ?? 240) else {
            throw InvalidArgumentError(argument: "providerOptions", message: "Replicate polling values must be representable integers.")
        }
        let prefer = replicateNumber(wait).map { "wait=\(replicateNumberString($0))" } ?? "wait"
        let resolvedHeaders = try config.headers()
        let headers = combineHeaders(resolvedHeaders, options.headers?.mapValues { Optional($0) })
        let parts = modelId.split(separator: ":", omittingEmptySubsequences: false)
        var input: [String: JSONValue] = ["num_outputs": .number(Double(options.n))]
        if let prompt = options.prompt { input["prompt"] = .string(prompt) }
        if let aspect = options.aspectRatio { input["aspect_ratio"] = .string(aspect) }
        if let size = options.size { input["size"] = .string(size) }
        if let seed = options.seed { input["seed"] = .number(Double(seed)) }
        if let files = options.files, !files.isEmpty {
            if isFlux2 {
                for (index, file) in files.prefix(8).enumerated() {
                    input[index == 0 ? "input_image" : "input_image_\(index + 1)"] = .string(replicateImageDataURI(file))
                }
                if files.count > 8 { warnings.append(.other(message: "Flux-2 models support up to 8 input images. Additional images are ignored.")) }
            } else {
                input["image"] = .string(replicateImageDataURI(files[0]))
                if files.count > 1 { warnings.append(.other(message: "This Replicate model only supports a single input image. Additional images are ignored.")) }
            }
        }
        if let mask = options.mask {
            if isFlux2 { warnings.append(.other(message: "Flux-2 models do not support mask input. The mask will be ignored.")) }
            else { input["mask"] = .string(replicateImageDataURI(mask)) }
        }
        input.merge(inputOptions) { _, value in value }
        var body: [String: JSONValue] = ["input": .object(input)]
        if parts.count > 1 { body["version"] = .string(String(parts[1])) }
        let url = parts.count > 1 ? "\(config.baseURL)/predictions" : "\(config.baseURL)/models/\(parts[0])/predictions"
        let response = try await postJsonToAPI(
            url: url,
            headers: combineHeaders(headers, ["prefer": prefer]).compactMapValues { $0 },
            body: JSONValue.object(body),
            failedResponseHandler: replicateFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: replicateImageResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )
        var prediction = response.value
        func completed(_ prediction: ReplicateImagePrediction) throws -> Bool {
            if prediction.status == .failed || prediction.status == .canceled {
                throw InvalidResponseDataError(data: prediction, message: "Replicate image generation \(prediction.status.rawValue): \(prediction.error ?? "Unknown error")")
            }
            return prediction.output != nil || prediction.status == .succeeded
        }
        for index in 0..<attempts {
            if try completed(prediction) { break }
            let result = try await getFromAPI(
                url: prediction.urls.get,
                headers: headers.compactMapValues { $0 },
                failedResponseHandler: replicateFailedResponseHandler,
                successfulResponseHandler: createJsonResponseHandler(responseSchema: replicateImageResponseSchema),
                isAborted: options.abortSignal,
                fetch: config.fetch,
                validateUrl: true,
                credentialedOrigin: config.baseURL,
                trustedOrigin: config.baseURL
            )
            prediction = result.value
            if index < attempts - 1 { try await delay(interval, abortSignal: options.abortSignal) }
        }
        guard try completed(prediction) else {
            throw InvalidResponseDataError(data: prediction, message: "Replicate image generation did not complete after \(attempts) polling attempts.")
        }
        guard let output = prediction.output else {
            throw InvalidResponseDataError(data: prediction, message: "Replicate image generation completed without output.")
        }
        let urls = output.urls
        let images = try await withThrowingTaskGroup(of: (Int, Data).self) { group in
            for (index, url) in urls.enumerated() {
                group.addTask { [config] in
                    let result = try await getFromAPI(
                        url: url,
                        failedResponseHandler: replicateFailedResponseHandler,
                        successfulResponseHandler: createBinaryResponseHandler(),
                        isAborted: options.abortSignal,
                        fetch: config.fetch,
                        validateUrl: true,
                        trustedOrigin: config.baseURL
                    )
                    return (index, result.value)
                }
            }
            var images = Array(repeating: Data(), count: urls.count)
            for try await (index, data) in group { images[index] = data }
            return images
        }
        return .init(images: .binary(images), warnings: warnings, response: .init(timestamp: timestamp, modelId: modelId, headers: response.responseHeaders))
    }
}

private func replicateImageDataURI(_ file: ImageModelV4File) -> String {
    switch file {
    case .url(let url, _): return url
    case .file(let mediaType, let data, _):
        switch data {
        case .base64(let value): return "data:\(mediaType);base64,\(value)"
        case .binary(let value): return "data:\(mediaType);base64,\(value.base64EncodedString())"
        }
    }
}

private func replicateNumber(_ value: JSONValue?) -> Double? {
    if case .number(let number) = value { return number }
    return nil
}

func replicateNumberString(_ value: Double) -> String {
    value.isFinite && value.rounded(.towardZero) == value ? String(format: "%.0f", value) : String(value)
}
