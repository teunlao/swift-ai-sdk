import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct OpenAICompatibleImageModelConfig: Sendable {
    public let provider: String
    public let headers: @Sendable () -> [String: String]
    public let url: @Sendable (OpenAICompatibleURLOptions) -> String
    public let fetch: FetchFunction?
    public let errorConfiguration: OpenAICompatibleErrorConfiguration
    public let currentDate: @Sendable () -> Date

    public init(
        provider: String,
        headers: @escaping @Sendable () -> [String: String],
        url: @escaping @Sendable (OpenAICompatibleURLOptions) -> String,
        fetch: FetchFunction? = nil,
        errorConfiguration: OpenAICompatibleErrorConfiguration = defaultOpenAICompatibleErrorConfiguration,
        currentDate: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.provider = provider
        self.headers = headers
        self.url = url
        self.fetch = fetch
        self.errorConfiguration = errorConfiguration
        self.currentDate = currentDate
    }
}

public final class OpenAICompatibleImageModel: ImageModelV3 {
    public let specificationVersion: String = "v3"
    public let modelIdentifier: OpenAICompatibleImageModelId
    private let config: OpenAICompatibleImageModelConfig

    public init(modelId: OpenAICompatibleImageModelId, config: OpenAICompatibleImageModelConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    public var maxImagesPerCall: ImageModelV3MaxImagesPerCall { .value(10) }

    public func doGenerate(options: ImageModelV3CallOptions) async throws -> ImageModelV3GenerateResult {
        var warnings: [ImageModelV3CallWarning] = []

        if options.aspectRatio != nil {
            warnings.append(.unsupportedSetting(setting: "aspectRatio", details: "This model does not support aspect ratio. Use `size` instead."))
        }

        if options.seed != nil {
            warnings.append(.unsupportedSetting(setting: "seed", details: nil))
        }

        let defaultHeaders = config.headers().mapValues { Optional($0) }
        let requestHeaders = options.headers?.mapValues { Optional($0) }
        let headers = combineHeaders(defaultHeaders, requestHeaders).compactMapValues { $0 }

        // Use hardcoded "openai" to match upstream TypeScript behavior (line 79 in upstream)
        let providerSpecific = options.providerOptions?["openai"] ?? [:]
        var body: [String: JSONValue] = [
            "model": .string(modelIdentifier.rawValue),
            "n": .number(Double(options.n)),
            "response_format": .string("b64_json")
        ]

        if let prompt = options.prompt {
            body["prompt"] = .string(prompt)
        }

        if let size = options.size {
            body["size"] = .string(size)
        }

        for (key, value) in providerSpecific {
            body[key] = value
        }

        let response = try await postJsonToAPI(
            url: config.url(.init(modelId: modelIdentifier.rawValue, path: "/images/generations")),
            headers: headers,
            body: JSONValue.object(body),
            failedResponseHandler: config.errorConfiguration.failedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: openAICompatibleImageResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let images = response.value.data.map { $0.b64JSON }
        let result = ImageModelV3GenerateResult(
            images: .base64(images),
            warnings: warnings,
            providerMetadata: nil,
            response: ImageModelV3ResponseInfo(
                timestamp: config.currentDate(),
                modelId: modelIdentifier.rawValue,
                headers: response.responseHeaders
            )
        )

        return result
    }
}

private let genericJSONObjectSchema: JSONValue = .object(["type": .string("object")])

private struct OpenAICompatibleImageResponse: Codable {
    struct DataItem: Codable {
        let b64JSON: String

        private enum CodingKeys: String, CodingKey {
            case b64JSON = "b64_json"
        }
    }

    let data: [DataItem]
}

private let openAICompatibleImageResponseSchema = FlexibleSchema(
    Schema<OpenAICompatibleImageResponse>.codable(
        OpenAICompatibleImageResponse.self,
        jsonSchema: genericJSONObjectSchema
    )
)
