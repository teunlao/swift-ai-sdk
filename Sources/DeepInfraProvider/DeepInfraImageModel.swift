import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/deepinfra/src/deepinfra-image-model.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct DeepInfraImageModelConfig: Sendable {
    public let provider: String
    public let baseURL: String
    public let headers: @Sendable () -> [String: String?]
    public let fetch: FetchFunction?
    public let currentDate: @Sendable () -> Date

    public init(
        provider: String,
        baseURL: String,
        headers: @escaping @Sendable () -> [String: String?],
        fetch: FetchFunction?,
        currentDate: @escaping @Sendable () -> Date
    ) {
        self.provider = provider
        self.baseURL = baseURL
        self.headers = headers
        self.fetch = fetch
        self.currentDate = currentDate
    }
}

public final class DeepInfraImageModel: ImageModelV3 {
    public let specificationVersion: String = "v3"
    public let modelId: String
    public var maxImagesPerCall: ImageModelV3MaxImagesPerCall { .value(1) }

    private let modelIdentifier: DeepInfraImageModelId
    private let config: DeepInfraImageModelConfig

    public init(modelId: DeepInfraImageModelId, config: DeepInfraImageModelConfig) {
        self.modelIdentifier = modelId
        self.modelId = modelId.rawValue
        self.config = config
    }

    public var provider: String { config.provider }

    public func doGenerate(options: ImageModelV3CallOptions) async throws -> ImageModelV3GenerateResult {
        var payload: [String: JSONValue] = [
            "prompt": .string(options.prompt)
        ]

        payload["num_images"] = .number(Double(options.n))

        if let aspectRatio = options.aspectRatio {
            payload["aspect_ratio"] = .string(aspectRatio)
        }

        if let size = options.size {
            let parts = size.split(separator: "x", omittingEmptySubsequences: true)
            if parts.count == 2 {
                payload["width"] = .string(String(parts[0]))
                payload["height"] = .string(String(parts[1]))
            }
        }

        if let seed = options.seed {
            payload["seed"] = .number(Double(seed))
        }

        if let providerOptions = options.providerOptions?["deepinfra"] {
            for (key, value) in providerOptions {
                payload[key] = value
            }
        }

        let headers = combineHeaders(config.headers(), options.headers?.mapValues { Optional($0) })
        let currentDate = config.currentDate()

        let response = try await postJsonToAPI(
            url: "\(config.baseURL)/\(modelIdentifier.rawValue)",
            headers: headers.compactMapValues { $0 },
            body: JSONValue.object(payload),
            failedResponseHandler: deepInfraFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: deepInfraImageResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let sanitizedImages = response.value.images.map { image -> String in
            image.replacingOccurrences(of: "^data:image/\\w+;base64,", with: "", options: [.regularExpression])
        }

        return ImageModelV3GenerateResult(
            images: .base64(sanitizedImages),
            warnings: [],
            response: ImageModelV3ResponseInfo(
                timestamp: currentDate,
                modelId: modelIdentifier.rawValue,
                headers: response.responseHeaders
            )
        )
    }
}

// MARK: - Response Handling

private struct DeepInfraImageError: Codable, Sendable {
    struct Detail: Codable, Sendable {
        let error: String
    }

    let detail: Detail
}

private let deepInfraFailedResponseHandler = createJsonErrorResponseHandler(
    errorSchema: FlexibleSchema(
        Schema<DeepInfraImageError>.codable(
            DeepInfraImageError.self,
            jsonSchema: .object(["type": .string("object")])
        )
    ),
    errorToMessage: { $0.detail.error }
)

private struct DeepInfraImageResponse: Codable, Sendable {
    let images: [String]
}

private let deepInfraImageResponseSchema = FlexibleSchema(
    Schema<DeepInfraImageResponse>.codable(
        DeepInfraImageResponse.self,
        jsonSchema: .object(["type": .string("object")])
    )
)
