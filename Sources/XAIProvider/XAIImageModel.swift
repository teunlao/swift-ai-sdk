import Foundation
import AISDKProvider
import AISDKProviderUtils

struct XAIImageModelConfig: Sendable {
    let provider: String
    let baseURL: String?
    let headers: @Sendable () throws -> [String: String?]
    let fetch: FetchFunction?
    let currentDate: @Sendable () -> Date

    init(
        provider: String,
        baseURL: String? = nil,
        headers: @escaping @Sendable () throws -> [String: String?],
        fetch: FetchFunction? = nil,
        currentDate: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.provider = provider
        self.baseURL = baseURL
        self.headers = headers
        self.fetch = fetch
        self.currentDate = currentDate
    }
}

private struct XAIImageResponse: Codable, Sendable {
    struct Item: Codable, Sendable {
        let url: String?
        let base64: String?
        let revisedPrompt: String?
        let respectModeration: Bool?

        enum CodingKeys: String, CodingKey {
            case url
            case base64 = "b64_json"
            case revisedPrompt = "revised_prompt"
            case respectModeration = "respect_moderation"
        }
    }

    struct Usage: Codable, Sendable {
        let costInUsdTicks: Double?
        enum CodingKeys: String, CodingKey { case costInUsdTicks = "cost_in_usd_ticks" }
    }
    let data: [Item]
    let usage: Usage?
}

private let xaiImageResponseSchema = FlexibleSchema(
    Schema<XAIImageResponse>.codable(
        XAIImageResponse.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

public final class XAIImageModel: ImageModelV4 {
    public let specificationVersion: String = "v4"
    public var maxImagesPerCall: ImageModelV4MaxImagesPerCall { .value(3) }
    public var supportsFileInputs: Bool? {
        get async throws { ["grok-imagine-image", "grok-imagine-image-2.0", "grok-imagine-image-pro"].contains(modelId) ? true : nil }
    }
    public var supportsMaskInputs: Bool? {
        get async throws { try await supportsFileInputs == true ? false : nil }
    }

    private let modelIdentifier: XAIImageModelId
    private let config: XAIImageModelConfig

    init(modelId: XAIImageModelId, config: XAIImageModelConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    public func doGenerate(options: ImageModelV4CallOptions) async throws -> ImageModelV4GenerateResult {
        var warnings: [SharedV4Warning] = []

        if options.size != nil {
            warnings.append(.unsupported(
                feature: "size",
                details: "This model does not support the `size` option. Use `aspectRatio` instead."
            ))
        }

        if options.seed != nil {
            warnings.append(.unsupported(feature: "seed", details: nil))
        }

        if options.mask != nil {
            warnings.append(.unsupported(feature: "mask", details: nil))
        }

        let xaiOptions = try await parseProviderOptions(
            provider: "xai",
            providerOptions: options.providerOptions,
            schema: xaiImageModelOptionsSchema
        )

        let files = options.files ?? []
        let hasFiles = !files.isEmpty

        let imageURLs = files.map(convertImageModelFileToDataURI)

        let endpoint = hasFiles ? "/images/edits" : "/images/generations"

        var body: [String: JSONValue] = [
            "model": .string(modelIdentifier.rawValue),
            "n": .number(Double(options.n)),
            "response_format": .string("b64_json")
        ]

        if let prompt = options.prompt {
            body["prompt"] = .string(prompt)
        }

        if let aspectRatio = options.aspectRatio {
            body["aspect_ratio"] = .string(aspectRatio)
        }

        if let outputFormat = xaiOptions?.outputFormat {
            body["output_format"] = .string(outputFormat)
        }

        if let syncMode = xaiOptions?.syncMode {
            body["sync_mode"] = .bool(syncMode)
        }

        if let providerAspectRatio = xaiOptions?.aspectRatio, options.aspectRatio == nil {
            body["aspect_ratio"] = .string(providerAspectRatio)
        }

        if let value = xaiOptions?.resolution { body["resolution"] = .string(value) }
        if let value = xaiOptions?.quality { body["quality"] = .string(value) }
        if let value = xaiOptions?.user { body["user"] = .string(value) }
        if imageURLs.count == 1 {
            body["image"] = .object(["url": .string(imageURLs[0]), "type": .string("image_url")])
        } else if imageURLs.count > 1 {
            body["images"] = .array(imageURLs.map { .object(["url": .string($0), "type": .string("image_url")]) })
        }

        let baseURL = config.baseURL ?? "https://api.x.ai/v1"
        let timestamp = config.currentDate()

        let headers = combineHeaders(
            try config.headers(),
            options.headers?.mapValues { Optional($0) }
        ).compactMapValues { $0 }

        let response = try await postJsonToAPI(
            url: "\(baseURL)\(endpoint)",
            headers: headers,
            body: JSONValue.object(body),
            failedResponseHandler: xaiFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: xaiImageResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        if response.value.data.contains(where: { $0.respectModeration == false }) {
            throw InvalidResponseDataError(data: response.rawValue, message: "Image generation was blocked due to a content policy violation.")
        }
        let images: ImageModelV4GeneratedImages
        if response.value.data.allSatisfy({ $0.base64 != nil }) {
            images = .base64(response.value.data.compactMap(\.base64))
        } else {
            images = .binary(try await downloadImages(response.value.data, abortSignal: options.abortSignal))
        }

        let metadataImages = response.value.data.map { item -> JSONValue in
            var object: [String: JSONValue] = [:]
            if let revised = item.revisedPrompt {
                object["revisedPrompt"] = .string(revised)
            }
            return .object(object)
        }

        let providerMetadata: ImageModelV4ProviderMetadata = [
            "xai": ImageModelV4ProviderMetadataValue(images: metadataImages, additionalData: response.value.usage?.costInUsdTicks.map { .object(["costInUsdTicks": .number($0)]) })
        ]

        return ImageModelV4GenerateResult(
            images: images,
            warnings: warnings,
            providerMetadata: providerMetadata,
            response: ImageModelV4ResponseInfo(
                timestamp: timestamp,
                modelId: modelIdentifier.rawValue,
                headers: response.responseHeaders
            )
        )
    }

    private func downloadImages(
        _ items: [XAIImageResponse.Item],
        abortSignal: (@Sendable () -> Bool)?
    ) async throws -> [Data] {
        var storage = Array<Data?>(repeating: nil, count: items.count)

        try await withThrowingTaskGroup(of: (Int, Data).self) { group in
            for (index, item) in items.enumerated() {
                group.addTask { [config] in
                    guard let url = item.url else { throw InvalidResponseDataError(data: item.base64, message: "Generated image URL is missing") }
                    let data = try await getFromAPI(
                        url: url,
                        failedResponseHandler: createStatusCodeErrorResponseHandler(),
                        successfulResponseHandler: createBinaryResponseHandler(),
                        isAborted: abortSignal,
                        fetch: config.fetch,
                        validateUrl: true,
                        trustedOrigin: config.baseURL
                    ).value
                    return (index, data)
                }
            }

            for try await (index, data) in group {
                storage[index] = data
            }
        }

        return storage.compactMap { $0 }
    }
}

