import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct OpenAICompatibleEmbeddingConfig: Sendable {
    public let provider: String
    public let url: @Sendable (OpenAICompatibleURLOptions) -> String
    public let headers: @Sendable () -> [String: String]
    public let fetch: FetchFunction?
    public let errorConfiguration: OpenAICompatibleErrorConfiguration
    public let maxEmbeddingsPerCallOverride: Int?
    public let supportsParallelCallsOverride: Bool?

    public init(
        provider: String,
        url: @escaping @Sendable (OpenAICompatibleURLOptions) -> String,
        headers: @escaping @Sendable () -> [String: String],
        fetch: FetchFunction? = nil,
        errorConfiguration: OpenAICompatibleErrorConfiguration = defaultOpenAICompatibleErrorConfiguration,
        maxEmbeddingsPerCall: Int? = nil,
        supportsParallelCalls: Bool? = nil
    ) {
        self.provider = provider
        self.url = url
        self.headers = headers
        self.fetch = fetch
        self.errorConfiguration = errorConfiguration
        self.maxEmbeddingsPerCallOverride = maxEmbeddingsPerCall
        self.supportsParallelCallsOverride = supportsParallelCalls
    }
}

public final class OpenAICompatibleEmbeddingModel: EmbeddingModelV3 {
    public typealias VALUE = String

    public let specificationVersion: String = "v3"
    public let modelIdentifier: OpenAICompatibleEmbeddingModelId
    private let config: OpenAICompatibleEmbeddingConfig

    public init(modelId: OpenAICompatibleEmbeddingModelId, config: OpenAICompatibleEmbeddingConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    public var maxEmbeddingsPerCall: Int? {
        get async throws { config.maxEmbeddingsPerCallOverride ?? 2048 }
    }

    public var supportsParallelCalls: Bool {
        get async throws { config.supportsParallelCallsOverride ?? true }
    }

    public func doEmbed(options: EmbeddingModelV3DoEmbedOptions<String>) async throws -> EmbeddingModelV3DoEmbedResult {
        if let limit = try await maxEmbeddingsPerCall, options.values.count > limit {
            throw TooManyEmbeddingValuesForCallError(
                provider: provider,
                modelId: modelId,
                maxEmbeddingsPerCall: limit,
                values: options.values
            )
        }

        let defaultHeaders = config.headers().mapValues { Optional($0) }
        let requestHeaders = options.headers?.mapValues { Optional($0) }
        let headers = combineHeaders(defaultHeaders, requestHeaders).compactMapValues { $0 }

        let baseOptions = try await parseProviderOptions(
            provider: "openai-compatible",
            providerOptions: options.providerOptions,
            schema: openAICompatibleEmbeddingProviderOptionsSchema
        ) ?? OpenAICompatibleEmbeddingProviderOptions()

        let providerSpecificOptions = try await parseProviderOptions(
            provider: config.provider.split(separator: ".").first.map(String.init) ?? "openai-compatible",
            providerOptions: options.providerOptions,
            schema: openAICompatibleEmbeddingProviderOptionsSchema
        ) ?? OpenAICompatibleEmbeddingProviderOptions()

        var mergedOptions = baseOptions
        if let dimensions = providerSpecificOptions.dimensions {
            mergedOptions.dimensions = dimensions
        }
        if let user = providerSpecificOptions.user {
            mergedOptions.user = user
        }

        let response = try await postJsonToAPI(
            url: config.url(.init(modelId: modelIdentifier.rawValue, path: "/embeddings")),
            headers: headers,
            body: JSONValue.object([
                "model": .string(modelIdentifier.rawValue),
                "input": .array(options.values.map(JSONValue.string)),
                "encoding_format": .string("float"),
                "dimensions": mergedOptions.dimensions.map { .number(Double($0)) } ?? .null,
                "user": mergedOptions.user.map(JSONValue.string) ?? .null
            ].compactMapValues { value in
                if case .null = value { return nil }
                return value
            }),
            failedResponseHandler: config.errorConfiguration.failedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: openAICompatibleEmbeddingResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let embeddings = response.value.data.map { item -> [Double] in
            item.embedding
        }

        let providerMetadata = response.value.providerMetadata?.isEmpty == false ? response.value.providerMetadata : nil

        return EmbeddingModelV3DoEmbedResult(
            embeddings: embeddings,
            usage: response.value.usage?.promptTokens.map { EmbeddingModelV3Usage(tokens: $0) },
            providerMetadata: providerMetadata,
            response: EmbeddingModelV3ResponseInfo(headers: response.responseHeaders, body: response.rawValue)
        )
    }
}

private let genericJSONObjectSchema: JSONValue = .object(["type": .string("object")])

private struct OpenAICompatibleEmbeddingResponse: Codable {
    struct DataItem: Codable {
        let embedding: [Double]
    }

    struct Usage: Codable {
        let promptTokens: Int?

        private enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
        }
    }

    let data: [DataItem]
    let usage: Usage?
    let providerMetadata: SharedV3ProviderMetadata?
}

private let openAICompatibleEmbeddingResponseSchema = FlexibleSchema(
    Schema<OpenAICompatibleEmbeddingResponse>.codable(
        OpenAICompatibleEmbeddingResponse.self,
        jsonSchema: genericJSONObjectSchema
    )
)
