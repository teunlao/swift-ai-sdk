import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/cohere/src/cohere-embedding-model.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public final class CohereEmbeddingModel: EmbeddingModelV3 {
    public typealias VALUE = String

    struct Config: Sendable {
        let provider: String
        let baseURL: String
        let headers: @Sendable () -> [String: String?]
        let fetch: FetchFunction?
    }

    private let modelIdentifier: CohereEmbeddingModelId
    private let config: Config

    init(modelId: CohereEmbeddingModelId, config: Config) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    public var maxEmbeddingsPerCall: Int? {
        get async throws { 96 }
    }

    public var supportsParallelCalls: Bool {
        get async throws { true }
    }

    public func doEmbed(options: EmbeddingModelV3DoEmbedOptions<String>) async throws -> EmbeddingModelV3DoEmbedResult {
        let values = options.values

        if let limit = try await maxEmbeddingsPerCall, values.count > limit {
            throw TooManyEmbeddingValuesForCallError(
                provider: provider,
                modelId: modelIdentifier.rawValue,
                maxEmbeddingsPerCall: limit,
                values: values
            )
        }

        let embeddingOptions = try await parseProviderOptions(
            provider: "cohere",
            providerOptions: options.providerOptions,
            schema: cohereEmbeddingOptionsSchema
        )

        var body: [String: JSONValue] = [
            "model": .string(modelIdentifier.rawValue),
            "embedding_types": .array([.string("float")]),
            "texts": .array(values.map { .string($0) }),
            "input_type": .string(embeddingOptions?.inputType?.rawValue ?? "search_query")
        ]

        if let truncate = embeddingOptions?.truncate {
            body["truncate"] = .string(truncate.rawValue)
        }

        let headers = combineHeaders(config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 }

        let response = try await postJsonToAPI(
            url: "\(config.baseURL)/embed",
            headers: headers,
            body: JSONValue.object(body),
            failedResponseHandler: cohereFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: cohereEmbeddingResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let embeddings = response.value.embeddings.float
        let usage = EmbeddingModelV3Usage(tokens: response.value.meta.billedUnits.inputTokens)

        return EmbeddingModelV3DoEmbedResult(
            embeddings: embeddings,
            usage: usage,
            providerMetadata: nil,
            response: EmbeddingModelV3ResponseInfo(headers: response.responseHeaders, body: response.rawValue)
        )
    }
}

private let genericJSONObjectSchema: JSONValue = .object(["type": .string("object")])

private struct CohereEmbeddingResponse: Codable {
    struct Embeddings: Codable {
        let float: [[Double]]
    }

    struct Meta: Codable {
        struct BilledUnits: Codable {
            let inputTokens: Int

            private enum CodingKeys: String, CodingKey {
                case inputTokens = "input_tokens"
            }
        }

        let billedUnits: BilledUnits

        private enum CodingKeys: String, CodingKey {
            case billedUnits = "billed_units"
        }
    }

    let embeddings: Embeddings
    let meta: Meta
}

private let cohereEmbeddingResponseSchema = FlexibleSchema(
    Schema<CohereEmbeddingResponse>.codable(
        CohereEmbeddingResponse.self,
        jsonSchema: genericJSONObjectSchema
    )
)
