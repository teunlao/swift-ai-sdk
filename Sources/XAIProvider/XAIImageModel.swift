import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/xai/src/xai-image-model.ts
// Upstream commit: 73d5c59
//===----------------------------------------------------------------------===//

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
        let url: String
        let revisedPrompt: String?

        enum CodingKeys: String, CodingKey {
            case url
            case revisedPrompt = "revised_prompt"
        }
    }

    let data: [Item]
}

private let xaiImageResponseSchema = FlexibleSchema(
    Schema<XAIImageResponse>.codable(
        XAIImageResponse.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

public final class XAIImageModel: ImageModelV3 {
    public let specificationVersion: String = "v3"
    public var maxImagesPerCall: ImageModelV3MaxImagesPerCall { .value(1) }

    private let modelIdentifier: XAIImageModelId
    private let config: XAIImageModelConfig

    init(modelId: XAIImageModelId, config: XAIImageModelConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    public func doGenerate(options: ImageModelV3CallOptions) async throws -> ImageModelV3GenerateResult {
        var warnings: [SharedV3Warning] = []

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

        var imageURL: String? = nil
        if hasFiles {
            imageURL = convertImageModelFileToDataURI(files[0])

            if files.count > 1 {
                warnings.append(.other(
                    message: "xAI only supports a single input image. Additional images are ignored."
                ))
            }
        }

        let endpoint = hasFiles ? "/images/edits" : "/images/generations"

        var body: [String: JSONValue] = [
            "model": .string(modelIdentifier.rawValue),
            "n": .number(Double(options.n)),
            "response_format": .string("url")
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

        if let imageURL {
            body["image"] = .object([
                "url": .string(imageURL),
                "type": .string("image_url")
            ])
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

        let downloadedImages = try await downloadImages(response.value.data, abortSignal: options.abortSignal)

        let metadataImages = response.value.data.map { item -> JSONValue in
            var object: [String: JSONValue] = [:]
            if let revised = item.revisedPrompt {
                object["revisedPrompt"] = .string(revised)
            }
            return .object(object)
        }

        let providerMetadata: ImageModelV3ProviderMetadata = [
            "xai": ImageModelV3ProviderMetadataValue(images: metadataImages)
        ]

        return ImageModelV3GenerateResult(
            images: .binary(downloadedImages),
            warnings: warnings,
            providerMetadata: providerMetadata,
            response: ImageModelV3ResponseInfo(
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
                    let data = try await getFromAPI(
                        url: item.url,
                        failedResponseHandler: createStatusCodeErrorResponseHandler(),
                        successfulResponseHandler: createBinaryResponseHandler(),
                        isAborted: abortSignal,
                        fetch: config.fetch
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

