import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class ByteDanceImageModel: ImageModelV4 {
    public var specificationVersion: String { "v4" }
    public var maxImagesPerCall: ImageModelV4MaxImagesPerCall { .value(1) }
    public var provider: String { config.provider }
    public var modelId: String { identifier.rawValue }
    public var supportsFileInputs: Bool? {
        ["dola-seedream-5-0-pro-260628", "seedream-5-0-260128", "seedream-5-0-lite-260128",
         "seedream-4-5-251128", "seedream-4-0-250828"].contains(modelId) ? true : nil
    }
    public var supportsMaskInputs: Bool? { supportsFileInputs == true ? false : nil }

    private let identifier: ByteDanceImageModelId
    private let config: ByteDanceConfig

    public init(modelId: ByteDanceImageModelId, config: ByteDanceConfig) {
        self.identifier = modelId
        self.config = config
    }

    public func doGenerate(options: ImageModelV4CallOptions) async throws -> ImageModelV4GenerateResult {
        var warnings: [SharedV4Warning] = []
        if options.aspectRatio != nil {
            warnings.append(.unsupported(feature: "aspectRatio", details: "ByteDance does not support aspectRatio. Use `size` (e.g. \"2048x2048\" or a resolution level like \"2K\" via providerOptions) instead."))
        }
        if options.seed != nil { warnings.append(.unsupported(feature: "seed", details: nil)) }
        if options.mask != nil {
            warnings.append(.unsupported(feature: "mask", details: "ByteDance Seedream does not support a separate mask. Provide edit instructions in the prompt, optionally with markings on the input image."))
        }
        let now = config.currentDate()
        let parsed = try await parseProviderOptions(provider: "bytedance", providerOptions: options.providerOptions,
                                                  schema: byteDanceImageModelOptionsSchema)
        var body: JSONObject = ["model": .string(modelId)]
        if let prompt = options.prompt { body["prompt"] = .string(prompt) }
        if let files = options.files, !files.isEmpty {
            body["image"] = files.count == 1 ? .string(dataURI(files[0])) : .array(files.map { .string(dataURI($0)) })
        }
        if let size = options.size { body["size"] = .string(size) }
        if let watermark = parsed?.watermark { body["watermark"] = .bool(watermark) }
        if let outputFormat = parsed?.outputFormat { body["output_format"] = .string(outputFormat.rawValue) }
        if let size = parsed?.size { body["size"] = .string(size) }
        if let sequential = parsed?.sequentialImageGeneration { body["sequential_image_generation"] = .string(sequential.rawValue) }
        if let maxImages = parsed?.maxImages { body["sequential_image_generation_options"] = .object(["max_images": .number(Double(maxImages))]) }
        if let mode = parsed?.optimizePromptMode { body["optimize_prompt_options"] = .object(["mode": .string(mode.rawValue)]) }
        for (key, value) in parsed?.additionalOptions ?? [:] { body[key] = value }
        body["response_format"] = .string("b64_json")
        let response = try await postJsonToAPI(
            url: "\(config.baseURL)/images/generations",
            headers: combineHeaders(try await config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 },
            body: JSONValue.object(body),
            failedResponseHandler: byteDanceFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: byteDanceImageResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )
        return .init(
            images: .base64(response.value.data.map(\.b64_json)), warnings: warnings,
            response: .init(timestamp: now, modelId: modelId, headers: response.responseHeaders),
            usage: response.value.usage.map { .init(outputTokens: $0.outputTokens, totalTokens: $0.totalTokens) }
        )
    }
}

private func dataURI(_ file: ImageModelV4File) -> String {
    switch file {
    case .url(let url, _): return url
    case .file(let mediaType, let data, _):
        let base64: String
        switch data {
        case .base64(let value): base64 = value
        case .binary(let value): base64 = value.base64EncodedString()
        }
        return "data:\(mediaType);base64,\(base64)"
    }
}

private struct ByteDanceImageResponse: Decodable, Sendable {
    struct Image: Decodable, Sendable { let b64_json: String }
    struct Usage: Decodable, Sendable {
        let outputTokens: Int?
        let totalTokens: Int?
        enum CodingKeys: String, CodingKey { case outputTokens = "output_tokens", totalTokens = "total_tokens" }
    }
    let data: [Image]
    let usage: Usage?
}

private let byteDanceImageResponseSchema = FlexibleSchema(
    Schema<ByteDanceImageResponse>.codable(ByteDanceImageResponse.self, jsonSchema: .object(["type": .string("object")]))
)
