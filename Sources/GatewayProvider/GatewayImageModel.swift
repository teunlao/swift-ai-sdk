import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class GatewayImageModel: ImageModelV4 {
    private let modelIdentifier: GatewayImageModelId
    private let config: GatewayImageModelConfig

    init(modelId: GatewayImageModelId, config: GatewayImageModelConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var specificationVersion: String { "v4" }
    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    // Set a very large number to prevent client-side splitting of requests
    public var maxImagesPerCall: ImageModelV4MaxImagesPerCall { .value(Int.max) }

    public func doGenerate(options: ImageModelV4CallOptions) async throws -> ImageModelV4GenerateResult {
        let resolvedHeaders = try await resolve(config.headers)
        let authMethod = parseAuthMethod(from: resolvedHeaders.compactMapValues { $0 })

        let o11yHeaders = try await resolve(config.o11yHeaders)
        let requestHeaders = combineHeaders(
            resolvedHeaders,
            options.headers?.mapValues { Optional($0) },
            getModelConfigHeaders(),
            o11yHeaders
        ).compactMapValues { $0 }

        var body: [String: JSONValue] = [
            "n": .number(Double(options.n))
        ]

        if let prompt = options.prompt {
            body["prompt"] = .string(prompt)
        }

        if let size = options.size {
            body["size"] = .string(size)
        }

        if let aspectRatio = options.aspectRatio {
            body["aspectRatio"] = .string(aspectRatio)
        }

        if let seed = options.seed, seed != 0 {
            body["seed"] = .number(Double(seed))
        }

        if let providerOptions = options.providerOptions {
            body["providerOptions"] = .object(providerOptions.mapValues { .object($0) })
        }

        if let files = options.files {
            body["files"] = .array(files.map { encodeImageFile($0) })
        }

        if let mask = options.mask {
            body["mask"] = encodeImageFile(mask)
        }

        do {
            let response = try await postJsonToAPI(
                url: getUrl(),
                headers: requestHeaders,
                body: JSONValue.object(body),
                failedResponseHandler: makeGatewayFailedResponseHandler(),
                successfulResponseHandler: createJsonResponseHandler(responseSchema: gatewayImageResponseSchema),
                isAborted: options.abortSignal,
                fetch: config.fetch
            )

            return ImageModelV4GenerateResult(
                images: .base64(response.value.images),
                isRetryable: response.value.isRetryable,
                warnings: response.value.warnings ?? [],
                providerMetadata: convertProviderMetadata(response.value.providerMetadata),
                response: ImageModelV4ResponseInfo(
                    timestamp: Date(),
                    modelId: modelIdentifier.rawValue,
                    headers: response.responseHeaders
                ),
                usage: response.value.usage
            )
        } catch {
            throw asGatewayError(error, authMethod: authMethod)
        }
    }

    private func getUrl() -> String {
        "\(config.baseURL)/image-model"
    }

    private func getModelConfigHeaders() -> [String: String?] {
        [
            "ai-image-model-specification-version": "4",
            "ai-model-id": modelIdentifier.rawValue
        ]
    }
}

private struct GatewayImageResponse: Decodable, Sendable {
    let images: [String]
    let isRetryable: Bool?
    let warnings: [SharedV4Warning]?
    let providerMetadata: [String: [String: JSONValue]]?
    let usage: ImageModelV4Usage?

    private enum CodingKeys: String, CodingKey {
        case images
        case isRetryable
        case warnings
        case providerMetadata
        case usage
    }
}

private let gatewayImageResponseSchema = gatewaySchema(GatewayImageResponse.self)

private func encodeImageFile(_ file: ImageModelV4File) -> JSONValue {
    switch file {
    case let .file(mediaType, data, providerOptions):
        var payload: [String: JSONValue] = [
            "type": .string("file"),
            "mediaType": .string(mediaType),
            "data": .string(encodedFileData(data))
        ]

        if let providerOptions {
            payload["providerOptions"] = .object(providerOptions.mapValues { .object($0) })
        }

        return .object(payload)

    case let .url(url, providerOptions):
        var payload: [String: JSONValue] = [
            "type": .string("url"),
            "url": .string(url)
        ]

        if let providerOptions {
            payload["providerOptions"] = .object(providerOptions.mapValues { .object($0) })
        }

        return .object(payload)
    }
}

private func encodedFileData(_ data: ImageModelV4FileData) -> String {
    switch data {
    case .base64(let string):
        return string
    case .binary(let binary):
        return binary.base64EncodedString()
    }
}

private func convertProviderMetadata(_ providerMetadata: [String: [String: JSONValue]]?) -> ImageModelV4ProviderMetadata? {
    guard let providerMetadata else { return nil }

    var result: ImageModelV4ProviderMetadata = [:]
    result.reserveCapacity(providerMetadata.count)

    for (provider, entry) in providerMetadata {
        let images: [JSONValue]
        if case .array(let rawImages)? = entry["images"] {
            images = rawImages
        } else {
            images = []
        }

        var additional = entry
        additional.removeValue(forKey: "images")
        let additionalData: JSONValue? = additional.isEmpty ? nil : .object(additional)

        result[provider] = ImageModelV4ProviderMetadataValue(
            images: images,
            additionalData: additionalData
        )
    }

    return result
}

