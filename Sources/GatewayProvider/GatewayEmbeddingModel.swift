import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/gateway/src/gateway-embedding-model.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public final class GatewayEmbeddingModel: EmbeddingModelV3 {
    public typealias VALUE = String

    private let modelIdentifier: GatewayEmbeddingModelId
    private let config: GatewayEmbeddingModelConfig

    init(modelId: GatewayEmbeddingModelId, config: GatewayEmbeddingModelConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var specificationVersion: String { "v3" }
    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    public var maxEmbeddingsPerCall: Int? {
        get async throws { 2048 }
    }

    public var supportsParallelCalls: Bool {
        get async throws { true }
    }

    public func doEmbed(options: EmbeddingModelV3DoEmbedOptions<String>) async throws -> EmbeddingModelV3DoEmbedResult {
        let values = options.values
        guard !values.isEmpty else {
            return EmbeddingModelV3DoEmbedResult(embeddings: [], usage: nil, providerMetadata: nil, response: nil)
        }

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
            "input": values.count == 1 ? .string(values[0]) : .array(values.map { .string($0) })
        ]

        if let providerOptions = options.providerOptions {
            body["providerOptions"] = .object(providerOptions.mapValues { .object($0) })
        }

        do {
            let response = try await postJsonToAPI(
                url: getUrl(),
                headers: requestHeaders,
                body: JSONValue.object(body),
                failedResponseHandler: makeGatewayFailedResponseHandler(),
                successfulResponseHandler: createJsonResponseHandler(responseSchema: gatewayEmbeddingResponseSchema),
                isAborted: options.abortSignal,
                fetch: config.fetch
            )

            let responseInfo = EmbeddingModelV3ResponseInfo(
                headers: response.responseHeaders,
                body: response.rawValue
            )

            return EmbeddingModelV3DoEmbedResult(
                embeddings: response.value.embeddings,
                usage: response.value.usage,
                providerMetadata: response.value.providerMetadata,
                response: responseInfo
            )
        } catch {
            throw asGatewayError(error, authMethod: authMethod)
        }
    }

    private func getUrl() -> String {
        "\(config.baseURL)/embedding-model"
    }

    private func getModelConfigHeaders() -> [String: String?] {
        [
            "ai-embedding-model-specification-version": "2",
            "ai-model-id": modelIdentifier.rawValue
        ]
    }
}

private struct GatewayEmbeddingResponse: Decodable, Sendable {
    let embeddings: [[Double]]
    let usage: EmbeddingModelV3Usage?
    let providerMetadata: SharedV3ProviderMetadata?

    private enum CodingKeys: String, CodingKey {
        case embeddings
        case usage
        case providerMetadata = "provider_metadata"
    }

    private enum UsageCodingKeys: String, CodingKey {
        case tokens
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        embeddings = try container.decode([[Double]].self, forKey: .embeddings)

        if container.contains(.usage) {
            if try container.decodeNil(forKey: .usage) {
                usage = nil
            } else if let usageContainer = try? container.nestedContainer(keyedBy: UsageCodingKeys.self, forKey: .usage) {
                let tokens = try usageContainer.decode(Int.self, forKey: .tokens)
                usage = EmbeddingModelV3Usage(tokens: tokens)
            } else if let tokens = try? container.decode(Int.self, forKey: .usage) {
                usage = EmbeddingModelV3Usage(tokens: tokens)
            } else {
                usage = nil
            }
        } else {
            usage = nil
        }

        providerMetadata = try container.decodeIfPresent(SharedV3ProviderMetadata.self, forKey: .providerMetadata)
    }
}

private let gatewayEmbeddingResponseSchema = FlexibleSchema(
    Schema<GatewayEmbeddingResponse>.codable(
        GatewayEmbeddingResponse.self,
        jsonSchema: .object(["type": .string("object")]),
        configureDecoder: { decoder in
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return decoder
        }
    )
)
