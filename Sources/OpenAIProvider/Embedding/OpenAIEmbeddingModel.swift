import Foundation
import AISDKProvider
import AISDKProviderUtils

private struct OpenAIEmbeddingModelCore: Sendable {
    private let modelIdentifier: OpenAIEmbeddingModelId
    private let config: OpenAIConfig

    init(modelId: OpenAIEmbeddingModelId, config: OpenAIConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    var provider: String { config.provider }
    var modelId: String { modelIdentifier.rawValue }

    func doEmbed(
        values: [String],
        abortSignal: (@Sendable () -> Bool)?,
        providerOptions: SharedV4ProviderOptions?,
        headers: SharedV4Headers?
    ) async throws -> OpenAIEmbeddingCoreResult {
        if values.count > 2048 {
            throw TooManyEmbeddingValuesForCallError(
                provider: provider,
                modelId: modelId,
                maxEmbeddingsPerCall: 2048,
                values: values.map { $0 as Any }
            )
        }

        let openAIOptions = try await parseProviderOptions(
            provider: "openai",
            providerOptions: providerOptions,
            schema: openaiEmbeddingProviderOptionsSchema
        )

        let combinedHeaders = combineHeaders(try config.headers(), headers?.mapValues { Optional($0) })
        let normalizedHeaders = combinedHeaders.compactMapValues { $0 }

        let body = OpenAIEmbeddingRequestBody(
            model: modelIdentifier.rawValue,
            input: values,
            dimensions: openAIOptions?.dimensions,
            user: openAIOptions?.user
        )

        let response = try await postJsonToAPI(
            url: config.url(.init(modelId: modelIdentifier.rawValue, path: "/embeddings")),
            headers: normalizedHeaders,
            body: body,
            failedResponseHandler: openAIFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: openaiEmbeddingResponseSchema),
            isAborted: abortSignal,
            fetch: config.fetch
        )

        return OpenAIEmbeddingCoreResult(
            embeddings: response.value.data.map { $0.embedding },
            tokens: response.value.usage?.promptTokens,
            responseHeaders: response.responseHeaders,
            responseBody: response.rawValue
        )
    }
}

private struct OpenAIEmbeddingCoreResult: @unchecked Sendable {
    let embeddings: [[Double]]
    let tokens: Int?
    let responseHeaders: SharedV4Headers?
    let responseBody: Any?
}

public final class OpenAIEmbeddingModel: EmbeddingModelV3 {
    public typealias VALUE = String
    private let core: OpenAIEmbeddingModelCore

    public init(modelId: OpenAIEmbeddingModelId, config: OpenAIConfig) {
        self.core = OpenAIEmbeddingModelCore(modelId: modelId, config: config)
    }

    public var provider: String { core.provider }
    public var modelId: String { core.modelId }

    public var maxEmbeddingsPerCall: Int? {
        get async throws { 2048 }
    }

    public var supportsParallelCalls: Bool {
        get async throws { true }
    }

    public func doEmbed(options: EmbeddingModelV3DoEmbedOptions<String>) async throws -> EmbeddingModelV3DoEmbedResult {
        let result = try await core.doEmbed(
            values: options.values,
            abortSignal: options.abortSignal,
            providerOptions: options.providerOptions,
            headers: options.headers
        )

        return EmbeddingModelV3DoEmbedResult(
            embeddings: result.embeddings,
            usage: result.tokens.map(EmbeddingModelV3Usage.init(tokens:)),
            providerMetadata: nil,
            response: EmbeddingModelV3ResponseInfo(
                headers: result.responseHeaders,
                body: result.responseBody
            )
        )
    }

    func asV4() -> OpenAIEmbeddingModelV4 {
        OpenAIEmbeddingModelV4(core: core)
    }
}

public final class OpenAIEmbeddingModelV4: EmbeddingModelV4 {
    private let core: OpenAIEmbeddingModelCore

    public init(modelId: OpenAIEmbeddingModelId, config: OpenAIConfig) {
        self.core = OpenAIEmbeddingModelCore(modelId: modelId, config: config)
    }

    fileprivate init(core: OpenAIEmbeddingModelCore) {
        self.core = core
    }

    public var provider: String { core.provider }
    public var modelId: String { core.modelId }

    public var maxEmbeddingsPerCall: Int? {
        get async throws { 2048 }
    }

    public var supportsParallelCalls: Bool {
        get async throws { true }
    }

    public func doEmbed(options: EmbeddingModelV4CallOptions) async throws -> EmbeddingModelV4Result {
        let result = try await core.doEmbed(
            values: options.values,
            abortSignal: options.abortSignal,
            providerOptions: options.providerOptions,
            headers: options.headers
        )

        return EmbeddingModelV4Result(
            embeddings: result.embeddings,
            usage: result.tokens.map(EmbeddingModelV4Usage.init(tokens:)),
            providerMetadata: nil,
            response: EmbeddingModelV4ResponseInfo(
                headers: result.responseHeaders,
                body: result.responseBody
            )
        )
    }
}
