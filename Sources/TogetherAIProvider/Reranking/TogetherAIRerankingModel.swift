import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/togetherai/src/reranking/togetherai-reranking-model.ts
// Upstream commit: f3a72bc2a
//===----------------------------------------------------------------------===//

public final class TogetherAIRerankingModel: RerankingModelV3 {
    public struct Config: Sendable {
        let provider: String
        let baseURL: String
        let headers: @Sendable () -> [String: String?]
        let fetch: FetchFunction?

        public init(
            provider: String,
            baseURL: String,
            headers: @escaping @Sendable () -> [String: String?],
            fetch: FetchFunction? = nil
        ) {
            self.provider = provider
            self.baseURL = baseURL
            self.headers = headers
            self.fetch = fetch
        }
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    private let modelIdentifier: TogetherAIRerankingModelId
    private let config: Config

    init(modelId: TogetherAIRerankingModelId, config: Config) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public func doRerank(options: RerankingModelV3CallOptions) async throws -> RerankingModelV3DoRerankResult {
        let rerankingOptions = try await parseProviderOptions(
            provider: "togetherai",
            providerOptions: options.providerOptions,
            schema: togetheraiRerankingOptionsSchema
        )

        var body: [String: JSONValue] = [
            "model": .string(modelIdentifier.rawValue),
            "documents": encodeDocuments(options.documents),
            "query": .string(options.query),
            "return_documents": .bool(false),
        ]

        if let topN = options.topN {
            body["top_n"] = .number(Double(topN))
        }

        if let rankFields = rerankingOptions?.rankFields {
            body["rank_fields"] = .array(rankFields.map(JSONValue.string))
        }

        let headers = combineHeaders(
            config.headers(),
            options.headers?.mapValues { Optional($0) }
        ).compactMapValues { $0 }

        let response = try await postJsonToAPI(
            url: "\(config.baseURL)/rerank",
            headers: headers,
            body: JSONValue.object(body),
            failedResponseHandler: createJsonErrorResponseHandler(
                errorSchema: togetheraiRerankingErrorSchema,
                errorToMessage: { $0.error.message }
            ),
            successfulResponseHandler: createJsonResponseHandler(responseSchema: togetheraiRerankingResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        return RerankingModelV3DoRerankResult(
            ranking: response.value.results.map { result in
                RerankingModelV3Ranking(index: result.index, relevanceScore: result.relevanceScore)
            },
            response: RerankingModelV3ResponseInfo(
                id: response.value.id,
                modelId: response.value.model,
                headers: response.responseHeaders,
                body: response.rawValue
            )
        )
    }
}

private func encodeDocuments(_ documents: RerankingModelV3CallOptions.Documents) -> JSONValue {
    switch documents {
    case .text(let values):
        return .array(values.map(JSONValue.string))
    case .object(let values):
        return .array(values.map { .object($0) })
    }
}

