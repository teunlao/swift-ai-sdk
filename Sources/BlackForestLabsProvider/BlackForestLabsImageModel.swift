import Foundation
import AISDKProvider
import AISDKProviderUtils

struct BlackForestLabsImageModelConfig: Sendable {
    let provider: String
    let baseURL: String
    var headers: (@Sendable () throws -> [String: String?])? = nil
    var fetch: FetchFunction? = nil
    var pollIntervalMillis: Int? = nil
    var pollTimeoutMillis: Int? = nil
    var currentDate: @Sendable () -> Date = { Date() }
}

private struct BFLImageResult: Decodable, Sendable {
    let sample: String
    let seed: Double?
    let start_time: Double?
    let end_time: Double?
    let duration: Double?
}

private struct BFLImagePoll: Decodable, Sendable {
    let status: String
    let result: BFLImageResult?
    private enum CodingKeys: String, CodingKey { case status, state, result }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        status = try values.decodeIfPresent(String.self, forKey: .status) ?? values.decode(String.self, forKey: .state)
        guard ["Content Moderated", "Generating", "Pending", "Reasoning", "Ready", "Error", "Failed", "Request Moderated", "Task not found"].contains(status) else {
            throw DecodingError.dataCorruptedError(forKey: .status, in: values, debugDescription: "Invalid Black Forest Labs status")
        }
        result = try values.decodeIfPresent(BFLImageResult.self, forKey: .result)
        if let result, URL(string: result.sample)?.scheme == nil {
            throw DecodingError.dataCorruptedError(forKey: .result, in: values, debugDescription: "Invalid result.sample URL")
        }
    }
}

private let bflImagePollSchema = FlexibleSchema(Schema<BFLImagePoll>.codable(BFLImagePoll.self, jsonSchema: .object(["type": .string("object")])))

public final class BlackForestLabsImageModel: ImageModelV4 {
    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }
    public var maxImagesPerCall: ImageModelV4MaxImagesPerCall { .value(1) }
    private var modelAPI: BFLImageAPI {
        if modelId == "flux-pro" || modelId == "flux-dev" || modelId.hasPrefix("flux-pro-") || modelId.hasPrefix("flux-kontext-") || modelId.range(of: "^flux-[12](?:[.-]|$)", options: .regularExpression) != nil { return .legacy }
        return modelId == "flux-3-image" ? .flux3 : .latest
    }
    public var supportsFileInputs: Bool? {
        if modelAPI != .legacy || ["flux-kontext-pro", "flux-kontext-max", "flux-pro-1.0-fill"].contains(modelId) { return true }
        if ["flux-pro-1.1-ultra", "flux-pro-1.1"].contains(modelId) { return false }
        return nil
    }
    public var supportsMaskInputs: Bool? { modelId == "flux-pro-1.0-fill" ? true : supportsFileInputs == nil ? nil : false }
    private let modelIdentifier: BlackForestLabsImageModelId
    private let config: BlackForestLabsImageModelConfig

    init(modelId: BlackForestLabsImageModelId, config: BlackForestLabsImageModelConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public func doGenerate(options: ImageModelV4CallOptions) async throws -> ImageModelV4GenerateResult {
        let api = modelAPI
        let providerOptions = try await bflImageOptions(options.providerOptions, api: api, size: options.size)
        var warnings: [SharedV4Warning] = []
        let aspect = options.aspectRatio ?? options.size.flatMap(bflAspectRatio)
        if let size = options.size, !size.isEmpty, api != .latest {
            let details: String
            if options.aspectRatio == nil || options.aspectRatio == "" {
                details = api == .flux3 ? "Deriving aspect_ratio from size. FLUX 3 uses the resolution provider option to select output resolution." : "Deriving aspect_ratio from size. Use the width and height provider options to specify dimensions for models that support them."
            } else {
                details = api == .flux3 ? "FLUX 3 ignores size when aspectRatio is provided. Use the resolution provider option to select output resolution." : "Black Forest Labs ignores size when aspectRatio is provided. Use the width and height provider options to specify dimensions for models that support them"
            }
            warnings.append(.unsupported(feature: "size", details: details))
        }
        let images = (options.files ?? []).map(bflFile)
        if images.count > 10 { throw InvalidArgumentError(argument: "files", message: "Black Forest Labs supports up to 10 input images.") }
        var body: [String: JSONValue] = [:]
        if let prompt = options.prompt { body["prompt"] = .string(prompt) }
        if api == .legacy {
            if let seed = options.seed { body["seed"] = .number(Double(seed)) }
            if let aspect { body["aspect_ratio"] = .string(aspect) }
            if let size = options.size {
                let parts = size.components(separatedBy: "x")
                if let width = parts.first.flatMap(Double.init), width.isFinite { body["width"] = .number(width) } else { body["width"] = .null }
                if parts.count > 1, let height = Double(parts[1]), height.isFinite { body["height"] = .number(height) } else { body["height"] = .null }
            }
            let field = modelId == "flux-pro-1.0-fill" ? "image" : "input_image"
            for (index, image) in images.enumerated() { body[index == 0 ? field : "\(field)_\(index + 1)"] = .string(image) }
            if let mask = options.mask { body["mask"] = .string(bflFile(mask)) }
            let mapping = ["width": "width", "height": "height", "steps": "steps", "guidance": "guidance", "imagePromptStrength": "image_prompt_strength", "imagePrompt": "image_prompt", "outputFormat": "output_format", "promptUpsampling": "prompt_upsampling", "raw": "raw", "safetyTolerance": "safety_tolerance", "webhookSecret": "webhook_secret", "webhookUrl": "webhook_url"]
            for (key, field) in mapping { if let value = providerOptions[key] { body[field] = value } }
        } else {
            if options.mask != nil { throw UnsupportedFunctionalityError(functionality: "FLUX 3 image masks") }
            let hasDimensions = api == .latest && providerOptions["width"] != nil
            var ratio = hasDimensions ? nil : aspect == "7:3" ? "21:9" : aspect == "3:7" ? "9:21" : aspect
            if let value = ratio, !["21:9", "2:1", "16:9", "3:2", "7:5", "4:3", "5:4", "1:1", "4:5", "3:4", "5:7", "2:3", "9:16", "1:2", "9:21"].contains(value) {
                warnings.append(.unsupported(feature: "aspectRatio", details: "FLUX 3 does not support aspect ratio \(aspect ?? ""). Using the endpoint's default auto aspect ratio."))
                ratio = nil
            }
            if let ratio { body["aspect_ratio"] = .string(ratio) }
            if !images.isEmpty { body["images"] = .array(images.map(JSONValue.string)) }
            if !hasDimensions { body["resolution"] = providerOptions["resolution"] }
            body["safety_tolerance"] = providerOptions["safetyTolerance"]
            let supported: Set<String>
            if api == .latest {
                supported = ["height", "outputFormat", "pollIntervalMillis", "pollTimeoutMillis", "resolution", "safetyTolerance", "steps", "width"]
                for key in ["width", "height", "steps"] { body[key] = providerOptions[key] }
                body["output_format"] = providerOptions["outputFormat"]
                if let seed = options.seed { body["seed"] = .number(Double(seed)) }
            } else {
                supported = ["grounding", "pollIntervalMillis", "pollTimeoutMillis", "resolution", "safetyTolerance", "version"]
                body["grounding"] = providerOptions["grounding"]
                body["version"] = providerOptions["version"]
                if options.seed != nil { warnings.append(.unsupported(feature: "seed", details: nil)) }
            }
            for key in providerOptions.keys.sorted() where !supported.contains(key) { warnings.append(.unsupported(feature: "blackForestLabs.\(key)", details: nil)) }
        }
        let timestamp = config.currentDate()
        let headers = combineHeaders(try config.headers?(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 }
        let submit = try await postJsonToAPI(
            url: "\(config.baseURL)/\(modelId)", headers: headers, body: JSONValue.object(body),
            failedResponseHandler: bflFailedResponseHandler, successfulResponseHandler: createJsonResponseHandler(responseSchema: bflSubmitSchema),
            isAborted: options.abortSignal, fetch: config.fetch
        )
        let url = try bflPollingURL(submit.value.polling_url, id: submit.value.id)
        let interval = Int(bflNumber(providerOptions["pollIntervalMillis"]) ?? Double(config.pollIntervalMillis ?? 500))
        let timeout = Int(bflNumber(providerOptions["pollTimeoutMillis"]) ?? Double(config.pollTimeoutMillis ?? 60_000))
        let result = try await poll(url: url, headers: headers, interval: interval, timeout: timeout, abortSignal: options.abortSignal)
        let image = try await getFromAPI(
            url: result.sample,
            headers: headers.filter { $0.key.lowercased() == "user-agent" },
            failedResponseHandler: createStatusCodeErrorResponseHandler(), successfulResponseHandler: createBinaryResponseHandler(),
            isAborted: options.abortSignal, fetch: config.fetch, validateUrl: true, trustedOrigin: config.baseURL
        )
        var metadata: [String: JSONValue] = [:]
        let values: [String: Double?] = ["seed": result.seed, "start_time": result.start_time, "end_time": result.end_time, "duration": result.duration, "cost": submit.value.cost, "inputMegapixels": submit.value.input_mp, "outputMegapixels": submit.value.output_mp]
        for (key, value) in values { if let value { metadata[key] = .number(value) } }
        return .init(images: .binary([image.value]), warnings: warnings, providerMetadata: ["blackForestLabs": .init(images: [.object(metadata)])], response: .init(timestamp: timestamp, modelId: modelId, headers: image.responseHeaders))
    }

    private func poll(url: String, headers: [String: String], interval: Int, timeout: Int, abortSignal: (@Sendable () -> Bool)?) async throws -> BFLImageResult {
        try await withThrowingTaskGroup(of: BFLImageResult.self) { group in
            group.addTask {
                try await delay(timeout)
                throw InvalidResponseDataError(data: url, message: "Black Forest Labs generation timed out.")
            }
            group.addTask {
                while true {
                    try Task.checkCancellation()
                    let result = try await getFromAPI(
                        url: url, headers: bflTrustedURL(url, baseURL: self.config.baseURL) ? headers : nil,
                        failedResponseHandler: bflFailedResponseHandler, successfulResponseHandler: createJsonResponseHandler(responseSchema: bflImagePollSchema),
                        isAborted: abortSignal, fetch: self.config.fetch, validateUrl: true, trustedOrigin: self.config.baseURL
                    ).value
                    if result.status == "Ready" {
                        guard let image = result.result else { throw InvalidResponseDataError(data: result, message: "Black Forest Labs poll response is Ready but missing result.sample") }
                        return image
                    }
                    if bflFailureStatuses.contains(result.status) {
                        let message = ["Error", "Failed"].contains(result.status) ? "Black Forest Labs generation failed." : "Black Forest Labs generation failed: \(result.status)."
                        throw InvalidResponseDataError(data: result, message: message)
                    }
                    try await delay(interval, abortSignal: abortSignal)
                }
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }
}

private func bflAspectRatio(_ size: String) -> String? {
    let parts = size.components(separatedBy: "x")
    guard parts.count >= 2, let width = Double(parts[0]), let height = Double(parts[1]), width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }
    var x = abs(width), y = abs(height)
    while y != 0 { let remainder = x.truncatingRemainder(dividingBy: y); x = y; y = remainder }
    return "\(String(format: "%.0f", (width / x).rounded())):\(String(format: "%.0f", (height / x).rounded()))"
}
