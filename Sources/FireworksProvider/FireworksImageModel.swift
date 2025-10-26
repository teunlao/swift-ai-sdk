import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/fireworks/src/fireworks-image-model.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

private enum FireworksImageModelURLFormat {
    case workflows
    case imageGeneration
}

private struct FireworksImageModelBackendConfig {
    let urlFormat: FireworksImageModelURLFormat
    let supportsSize: Bool
}

private let fireworksImageModelBackendConfig: [FireworksImageModelId: FireworksImageModelBackendConfig] = [
    .flux1DevFP8: FireworksImageModelBackendConfig(urlFormat: .workflows, supportsSize: false),
    .flux1SchnellFP8: FireworksImageModelBackendConfig(urlFormat: .workflows, supportsSize: false),
    .playgroundV25_1024pxAesthetic: FireworksImageModelBackendConfig(urlFormat: .imageGeneration, supportsSize: true),
    .japaneseStableDiffusionXL: FireworksImageModelBackendConfig(urlFormat: .imageGeneration, supportsSize: true),
    .playgroundV2_1024pxAesthetic: FireworksImageModelBackendConfig(urlFormat: .imageGeneration, supportsSize: true),
    .stableDiffusionXL1024v10: FireworksImageModelBackendConfig(urlFormat: .imageGeneration, supportsSize: true),
    .ssd1b: FireworksImageModelBackendConfig(urlFormat: .imageGeneration, supportsSize: true)
]

private func fireworksImageURL(baseURL: String, modelId: FireworksImageModelId) -> String {
    if let backend = fireworksImageModelBackendConfig[modelId] {
        switch backend.urlFormat {
        case .imageGeneration:
            return "\(baseURL)/image_generation/\(modelId.rawValue)"
        case .workflows:
            return "\(baseURL)/workflows/\(modelId.rawValue)/text_to_image"
        }
    }

    return "\(baseURL)/workflows/\(modelId.rawValue)/text_to_image"
}

struct FireworksImageModelConfig: Sendable {
    let provider: String
    let baseURL: String
    let headers: @Sendable () -> [String: String]
    let fetch: FetchFunction?
    let currentDate: @Sendable () -> Date

    init(
        provider: String,
        baseURL: String,
        headers: @escaping @Sendable () -> [String: String],
        fetch: FetchFunction?,
        currentDate: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.provider = provider
        self.baseURL = baseURL
        self.headers = headers
        self.fetch = fetch
        self.currentDate = currentDate
    }
}

public final class FireworksImageModel: ImageModelV3 {
    public var specificationVersion: String { "v3" }
    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }
    public var maxImagesPerCall: ImageModelV3MaxImagesPerCall { .value(1) }

    private let modelIdentifier: FireworksImageModelId
    private let config: FireworksImageModelConfig

    init(modelId: FireworksImageModelId, config: FireworksImageModelConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public func doGenerate(options: ImageModelV3CallOptions) async throws -> ImageModelV3GenerateResult {
        var warnings: [ImageModelV3CallWarning] = []
        let backendConfig = fireworksImageModelBackendConfig[modelIdentifier]

        if backendConfig?.supportsSize != true, options.size != nil {
            warnings.append(.unsupportedSetting(
                setting: "size",
                details: "This model does not support the `size` option. Use `aspectRatio` instead."
            ))
        }

        if backendConfig?.supportsSize == true, options.aspectRatio != nil {
            warnings.append(.unsupportedSetting(
                setting: "aspectRatio",
                details: "This model does not support the `aspectRatio` option."
            ))
        }

        var body: [String: JSONValue] = [
            "prompt": .string(options.prompt),
            "samples": .number(Double(options.n))
        ]

        if let aspectRatio = options.aspectRatio {
            body["aspect_ratio"] = .string(aspectRatio)
        }

        if let seed = options.seed {
            body["seed"] = .number(Double(seed))
        }

        if let size = options.size {
            let parts = size.split(separator: "x", omittingEmptySubsequences: true)
            if parts.count == 2 {
                body["width"] = .string(String(parts[0]))
                body["height"] = .string(String(parts[1]))
            }
        }

        if let fireworksOptions = options.providerOptions?["fireworks"] {
            for (key, value) in fireworksOptions {
                body[key] = value
            }
        }

        let headers = combineHeaders(
            config.headers().mapValues { Optional($0) },
            options.headers?.mapValues { Optional($0) }
        ).compactMapValues { $0 }

        let response = try await postJsonToAPI(
            url: fireworksImageURL(baseURL: config.baseURL, modelId: modelIdentifier),
            headers: headers,
            body: JSONValue.object(body),
            failedResponseHandler: createStatusCodeErrorResponseHandler(),
            successfulResponseHandler: createBinaryResponseHandler(),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        return ImageModelV3GenerateResult(
            images: .binary([response.value]),
            warnings: warnings,
            providerMetadata: nil,
            response: ImageModelV3ResponseInfo(
                timestamp: config.currentDate(),
                modelId: modelIdentifier.rawValue,
                headers: response.responseHeaders
            )
        )
    }
}
