import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class OpenAIEmbeddingModel: EmbeddingModelV3 {
    public typealias VALUE = String
    private let modelIdentifier: OpenAIEmbeddingModelId
    private let config: OpenAIConfig

    public init(modelId: OpenAIEmbeddingModelId, config: OpenAIConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    public var maxEmbeddingsPerCall: Int? {
        get async throws { 2048 }
    }

    public var supportsParallelCalls: Bool {
        get async throws { true }
    }

    public func doEmbed(options: EmbeddingModelV3DoEmbedOptions<String>) async throws -> EmbeddingModelV3DoEmbedResult {
        if options.values.count > 2048 {
            throw TooManyEmbeddingValuesForCallError(
                provider: provider,
                modelId: modelId,
                maxEmbeddingsPerCall: 2048,
                values: options.values.map { $0 as Any }
            )
        }

        let openAIOptions = try await parseProviderOptions(
            provider: "openai",
            providerOptions: options.providerOptions,
            schema: openaiEmbeddingProviderOptionsSchema
        )

        let headers = combineHeaders(config.headers(), options.headers?.mapValues { Optional($0) })
        let normalizedHeaders = headers.compactMapValues { $0 }

        let body = OpenAIEmbeddingRequestBody(
            model: modelIdentifier.rawValue,
            input: options.values,
            dimensions: openAIOptions?.dimensions,
            user: openAIOptions?.user
        )

        let response = try await postJsonToAPI(
            url: config.url(.init(modelId: modelIdentifier.rawValue, path: "/embeddings")),
            headers: normalizedHeaders,
            body: body,
            failedResponseHandler: openAIFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: openaiEmbeddingResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let value = response.value

        let embeddings = value.data.map { $0.embedding }
        let usage = value.usage.map { EmbeddingModelV3Usage(tokens: $0.promptTokens) }
        let responseInfo = EmbeddingModelV3ResponseInfo(
            headers: response.responseHeaders,
            body: response.rawValue
        )

        return EmbeddingModelV3DoEmbedResult(
            embeddings: embeddings,
            usage: usage,
            providerMetadata: nil,
            response: responseInfo
        )
    }
}
