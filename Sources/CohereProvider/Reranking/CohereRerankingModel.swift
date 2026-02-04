import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/cohere/src/reranking/cohere-reranking-model.ts
// Upstream commit: f3a72bc2a
//===----------------------------------------------------------------------===//

public final class CohereRerankingModel: RerankingModelV3 {
    struct Config: Sendable {
        let provider: String
        let baseURL: String
        let headers: @Sendable () -> [String: String?]
        let fetch: FetchFunction?
    }

    private let modelIdentifier: CohereRerankingModelId
    private let config: Config

    init(modelId: CohereRerankingModelId, config: Config) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    // Current implementation is based on v2 of the Cohere API:
    // https://docs.cohere.com/v2/reference/rerank
    public func doRerank(options: RerankingModelV3CallOptions) async throws -> RerankingModelV3DoRerankResult {
        let rerankingOptions = try await parseProviderOptions(
            provider: "cohere",
            providerOptions: options.providerOptions,
            schema: cohereRerankingOptionsSchema
        )

        var warnings: [SharedV3Warning] = []

        let documentStrings: [String]
        switch options.documents {
        case .text(let values):
            documentStrings = values
        case .object(let values):
            warnings.append(
                .compatibility(
                    feature: "object documents",
                    details: "Object documents are converted to strings."
                )
            )
            documentStrings = try values.map { try jsonStringify($0) }
        }

        var body: [String: JSONValue] = [
            "model": .string(modelIdentifier.rawValue),
            "query": .string(options.query),
            "documents": .array(documentStrings.map { .string($0) }),
        ]

        if let topN = options.topN {
            body["top_n"] = .number(Double(topN))
        }

        if let maxTokensPerDoc = rerankingOptions?.maxTokensPerDoc {
            body["max_tokens_per_doc"] = .number(Double(maxTokensPerDoc))
        }

        if let priority = rerankingOptions?.priority {
            body["priority"] = .number(Double(priority))
        }

        let headers = combineHeaders(
            config.headers(),
            options.headers?.mapValues { Optional($0) }
        ).compactMapValues { $0 }

        let response = try await postJsonToAPI(
            url: "\(config.baseURL)/rerank",
            headers: headers,
            body: JSONValue.object(body),
            failedResponseHandler: cohereFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: cohereRerankingResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        return RerankingModelV3DoRerankResult(
            ranking: response.value.results.map { result in
                RerankingModelV3Ranking(index: result.index, relevanceScore: result.relevanceScore)
            },
            warnings: warnings,
            response: RerankingModelV3ResponseInfo(
                id: response.value.id,
                headers: response.responseHeaders,
                body: response.rawValue
            )
        )
    }
}

private func jsonStringify(_ object: JSONObject) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(object)
    guard let string = String(data: data, encoding: .utf8) else {
        throw EncodingError.invalidValue(
            object,
            EncodingError.Context(codingPath: [], debugDescription: "Failed to encode JSON string")
        )
    }
    return string
}
