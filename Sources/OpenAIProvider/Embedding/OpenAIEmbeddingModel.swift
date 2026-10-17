import AISDKProvider
import AISDKProviderUtils

public final class OpenAIEmbeddingModel: EmbeddingModelV4, EmbeddingModelMaxInputBytesPerCall {
    private let modelIdentifier: OpenAIEmbeddingModelId
    private let config: OpenAIConfig

    public init(modelId: OpenAIEmbeddingModelId, config: OpenAIConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }
    public var maxEmbeddingsPerCall: Int? { get async throws { 2048 } }
    public var maxInputBytesPerCall: Int? { get async throws { 300_000 } }
    public var supportsParallelCalls: Bool { get async throws { true } }

    public func doEmbed(options: EmbeddingModelV4CallOptions) async throws -> EmbeddingModelV4Result {
        guard options.values.count <= 2048 else {
            throw TooManyEmbeddingValuesForCallError(
                provider: provider, modelId: modelId, maxEmbeddingsPerCall: 2048,
                values: options.values.map { $0 as Any }
            )
        }
        let openAIOptions = try await parseProviderOptions(
            provider: "openai", providerOptions: options.providerOptions,
            schema: openaiEmbeddingProviderOptionsSchema
        )
        let response = try await postJsonToAPI(
            url: try config.url(.init(modelId: modelId, path: "/embeddings")),
            headers: combineHeaders(try config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 },
            body: OpenAIEmbeddingRequestBody(
                model: modelId, input: options.values,
                dimensions: openAIOptions?.dimensions ?? options.dimensions,
                user: openAIOptions?.user
            ),
            failedResponseHandler: openAIFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: openaiEmbeddingResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )
        return EmbeddingModelV4Result(
            embeddings: response.value.data.map { $0.embedding },
            usage: (response.value.usage?.promptTokens).map { EmbeddingModelV4Usage(tokens: $0) },
            response: EmbeddingModelV4ResponseInfo(headers: response.responseHeaders, body: response.rawValue),
            warnings: []
        )
    }
}
