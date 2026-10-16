import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct FireworksImageModelConfig: Sendable {
    public let provider: String
    public let baseURL: String
    public let headers: @Sendable () throws -> [String: String]
    public let fetch: FetchFunction?
    public let pollIntervalMillis: Int
    public let pollTimeoutMillis: Int
    public let currentDate: @Sendable () -> Date
    public init(provider: String, baseURL: String, headers: @escaping @Sendable () throws -> [String: String] = { [:] },
                fetch: FetchFunction? = nil, pollIntervalMillis: Int = 500, pollTimeoutMillis: Int = 120000,
                currentDate: @escaping @Sendable () -> Date = { Date() }) {
        self.provider = provider; self.baseURL = baseURL; self.headers = headers; self.fetch = fetch
        self.pollIntervalMillis = pollIntervalMillis; self.pollTimeoutMillis = pollTimeoutMillis; self.currentDate = currentDate
    }
}

private let fireworksSizeModels: Set<String> = [
    "accounts/fireworks/models/playground-v2-5-1024px-aesthetic", "accounts/fireworks/models/japanese-stable-diffusion-xl",
    "accounts/fireworks/models/playground-v2-1024px-aesthetic", "accounts/fireworks/models/stable-diffusion-xl-1024-v1-0", "accounts/fireworks/models/SSD-1B"
]
private let fireworksSyncWorkflowModels: Set<String> = ["accounts/fireworks/models/flux-1-dev-fp8", "accounts/fireworks/models/flux-1-schnell-fp8"]
private let fireworksEditingModels: Set<String> = ["accounts/fireworks/models/flux-kontext-pro", "accounts/fireworks/models/flux-kontext-max"]

public final class FireworksImageModel: ImageModelV4 {
    public let specificationVersion = "v4"
    public let modelId: String
    public var provider: String { config.provider }
    public var maxImagesPerCall: ImageModelV4MaxImagesPerCall { .value(1) }
    public var supportsFileInputs: Bool? {
        get async throws {
            if fireworksEditingModels.contains(modelId) { return true }
            return fireworksSizeModels.contains(modelId) || fireworksSyncWorkflowModels.contains(modelId) ? false : nil
        }
    }
    public var supportsMaskInputs: Bool? { get async throws { try await supportsFileInputs == nil ? nil : false } }
    private let config: FireworksImageModelConfig
    public init(modelId: FireworksImageModelId, config: FireworksImageModelConfig) { self.modelId = modelId.rawValue; self.config = config }

    public func doGenerate(options: ImageModelV4CallOptions) async throws -> ImageModelV4GenerateResult {
        var warnings: [SharedV4Warning] = []
        let supportsSize = fireworksSizeModels.contains(modelId)
        if !supportsSize, options.size != nil { warnings.append(.unsupported(feature: "size", details: "This model does not support the `size` option. Use `aspectRatio` instead.")) }
        if supportsSize, options.aspectRatio != nil { warnings.append(.unsupported(feature: "aspectRatio", details: "This model does not support the `aspectRatio` option.")) }
        var body: [String: JSONValue] = ["samples": .number(Double(options.n))]
        if let first = options.files?.first {
            let input = convertImageModelFileToDataURI(first)
            if !input.isEmpty { body["input_image"] = .string(input) }
            if (options.files?.count ?? 0) > 1 { warnings.append(.other(message: "Fireworks only supports a single input image. Additional images are ignored.")) }
        }
        if options.mask != nil { warnings.append(.unsupported(feature: "mask", details: "Fireworks Kontext models do not support explicit masks. Use the prompt to describe the areas to edit.")) }
        if let prompt = options.prompt { body["prompt"] = .string(prompt) }
        if let ratio = options.aspectRatio { body["aspect_ratio"] = .string(ratio) }
        if let seed = options.seed { body["seed"] = .number(Double(seed)) }
        if let size = options.size {
            let parts = size.components(separatedBy: "x")
            body["width"] = .string(parts[0])
            if parts.count > 1 { body["height"] = .string(parts[1]) }
        }
        let timestamp = config.currentDate()
        let headers = combineHeaders(try config.headers().mapValues(Optional.some), options.headers?.mapValues(Optional.some)).compactMapValues { $0 }
        let fireworksOptions = try await parseProviderOptions(provider: "fireworks", providerOptions: options.providerOptions, schema: fireworksImageModelOptionsSchema) ?? .init()
        let fields = try JSONDecoder().decode(JSONObject.self, from: JSONEncoder().encode(fireworksOptions))
        body.merge(fields) { _, new in new }
        let base = config.baseURL
        let endpoint = fireworksSizeModels.contains(modelId) ? "\(base)/image_generation/\(modelId)" : "\(base)/workflows/\(modelId)"
        if fireworksEditingModels.contains(modelId) {
            let response = try await postJsonToAPI(url: endpoint, headers: headers, body: JSONValue.object(body),
                                                   failedResponseHandler: createStatusCodeErrorResponseHandler(),
                                                   successfulResponseHandler: createJsonResponseHandler(responseSchema: fireworksSubmitSchema),
                                                   isAborted: options.abortSignal, fetch: config.fetch)
            let imageURL = try await poll(requestId: response.value.requestId, headers: headers, abortSignal: options.abortSignal)
            let image = try await getFromAPI(url: imageURL, headers: headers.filter { $0.key.lowercased() == "user-agent" },
                                             failedResponseHandler: createStatusCodeErrorResponseHandler(), successfulResponseHandler: createBinaryResponseHandler(),
                                             isAborted: options.abortSignal, fetch: config.fetch, validateUrl: true, trustedOrigin: base)
            return .init(images: .binary([image.value]), warnings: warnings, response: .init(timestamp: timestamp, modelId: modelId, headers: image.responseHeaders))
        }
        let url = fireworksSizeModels.contains(modelId) ? endpoint : endpoint + "/text_to_image"
        let response = try await postJsonToAPI(url: url, headers: headers, body: JSONValue.object(body),
                                               failedResponseHandler: createStatusCodeErrorResponseHandler(), successfulResponseHandler: createBinaryResponseHandler(),
                                               isAborted: options.abortSignal, fetch: config.fetch)
        return .init(images: .binary([response.value]), warnings: warnings, response: .init(timestamp: timestamp, modelId: modelId, headers: response.responseHeaders))
    }
    private func poll(requestId: String, headers: [String: String], abortSignal: (@Sendable () -> Bool)?) async throws -> String {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(Double(config.pollTimeoutMillis) / 1000))
        let abort: @Sendable () -> Bool = { abortSignal?() == true || clock.now >= deadline }
        do {
            while true {
                let response = try await postJsonToAPI(url: "\(config.baseURL)/workflows/\(modelId)/get_result", headers: headers,
                                                       body: JSONValue.object(["id": .string(requestId)]),
                                                       failedResponseHandler: createStatusCodeErrorResponseHandler(),
                                                       successfulResponseHandler: createJsonResponseHandler(responseSchema: fireworksPollSchema),
                                                       isAborted: abort, fetch: config.fetch).value
                if response.status == "Ready" {
                    guard let sample = response.result?.sample else { throw FireworksImageError.missingSample }
                    return sample
                }
                if response.status == "Error" || response.status == "Failed" {
                    throw FireworksImageError.generationFailed(status: response.status)
                }
                try await delay(config.pollIntervalMillis, abortSignal: abort)
            }
        } catch {
            if clock.now >= deadline { throw FireworksImageError.timedOut(milliseconds: config.pollTimeoutMillis) }
            throw error
        }
    }
}
public enum FireworksImageError: AISDKError, LocalizedError, Sendable, Equatable {
    case missingSample
    case generationFailed(status: String)
    case timedOut(milliseconds: Int)
    public static let errorDomain = "AI_FireworksImageError"
    public var name: String { Self.errorDomain }
    public var cause: (any Error)? { nil }
    public var message: String {
        switch self {
        case .missingSample: "Fireworks poll response is Ready but missing result.sample"
        case .generationFailed(let status): "Fireworks image generation failed with status: \(status)"
        case .timedOut(let milliseconds): "Fireworks image generation timed out after \(milliseconds)ms"
        }
    }
    public var errorDescription: String? { message }
}
private struct FireworksSubmit: Decodable, Sendable {
    let requestId: String
    enum CodingKeys: String, CodingKey { case requestId = "request_id" }
}
private struct FireworksPoll: Decodable, Sendable {
    struct Result: Decodable, Sendable {
        let sample: String?
        private enum CodingKeys: String, CodingKey { case sample }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            sample = container.contains(.sample) ? try container.decode(String.self, forKey: .sample) : nil
        }
    }
    let id: String
    let status: String
    let result: Result?
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        id = try c.decode(String.self, forKey: .id)
        status = try c.decode(String.self, forKey: .status)
        result = try c.decode(Result?.self, forKey: .result)
    }
    private enum Key: String, CodingKey { case id, status, result }
}
private let fireworksSubmitSchema = FlexibleSchema(Schema<FireworksSubmit>.codable(FireworksSubmit.self, jsonSchema: ["type": "object"]))
private let fireworksPollSchema = FlexibleSchema(Schema<FireworksPoll>.codable(FireworksPoll.self, jsonSchema: ["type": "object"]))
