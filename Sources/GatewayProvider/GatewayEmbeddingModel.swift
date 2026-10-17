import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class GatewayEmbeddingModel: EmbeddingModelV4 {
    private let modelIdentifier: GatewayEmbeddingModelId
    private let config: GatewayEmbeddingModelConfig

    init(modelId: GatewayEmbeddingModelId, config: GatewayEmbeddingModelConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }
    public var maxEmbeddingsPerCall: Int? { get async throws { 2048 } }
    public var supportsParallelCalls: Bool { get async throws { true } }

    public func doEmbed(options: EmbeddingModelV4CallOptions) async throws -> EmbeddingModelV4Result {
        let headers = try await config.headers()
        do {
            let body = GatewayEmbeddingRequest(values: options.values, dimensions: options.dimensions, providerOptions: options.providerOptions)
            let response = try await postJsonToAPI(
                url: "\(config.baseURL)/embedding-model",
                headers: combineHeaders(
                    headers,
                    options.headers?.mapValues { Optional($0) },
                    ["ai-embedding-model-specification-version": "4", "ai-model-id": modelId],
                    try await config.o11yHeaders()
                ).compactMapValues { $0 },
                body: try gatewayJSON(body),
                failedResponseHandler: makeGatewayFailedResponseHandler(),
                successfulResponseHandler: createJsonResponseHandler(responseSchema: gatewaySchema(GatewayEmbeddingResponse.self)),
                isAborted: options.abortSignal,
                fetch: config.fetch
            )
            return EmbeddingModelV4Result(
                embeddings: response.value.embeddings,
                usage: response.value.usage,
                providerMetadata: response.value.providerMetadata,
                response: .init(headers: response.responseHeaders, body: response.rawValue),
                warnings: response.value.warnings ?? []
            )
        } catch {
            throw asGatewayError(error, authMethod: parseAuthMethod(from: headers.compactMapValues { $0 }))
        }
    }
}

private struct GatewayEmbeddingRequest: Encodable {
    let values: [String]
    let dimensions: Int?
    let providerOptions: SharedV4ProviderOptions?
}

private struct GatewayEmbeddingResponse: Decodable, Sendable {
    let embeddings: [[Double]]
    let usage: EmbeddingModelV4Usage?
    let providerMetadata: SharedV4ProviderMetadata?
    let warnings: [SharedV4Warning]?
}
