import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/amazon-bedrock/src/reranking/bedrock-reranking-model.ts
// Upstream commit: f3a72bc2a
//===----------------------------------------------------------------------===//

public final class BedrockRerankingModel: RerankingModelV3 {
    struct Config: Sendable {
        let baseURL: @Sendable () -> String
        let region: String
        let headers: @Sendable () -> [String: String?]
        let fetch: FetchFunction?
    }

    private let modelIdentifier: BedrockRerankingModelId
    private let config: Config

    init(modelId: BedrockRerankingModelId, config: Config) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var provider: String { "amazon-bedrock" }
    public var modelId: String { modelIdentifier.rawValue }

    public func doRerank(options: RerankingModelV3CallOptions) async throws -> RerankingModelV3DoRerankResult {
        let bedrockOptions = try await parseProviderOptions(
            provider: "bedrock",
            providerOptions: options.providerOptions,
            schema: bedrockRerankingOptionsSchema
        )

        let modelArn = "arn:aws:bedrock:\(config.region)::foundation-model/\(modelIdentifier.rawValue)"

        var modelConfiguration: [String: JSONValue] = [
            "modelArn": .string(modelArn)
        ]

        if let additional = bedrockOptions?.additionalModelRequestFields {
            modelConfiguration["additionalModelRequestFields"] = .object(additional)
        }

        var bedrockRerankingConfiguration: [String: JSONValue] = [
            "modelConfiguration": .object(modelConfiguration)
        ]

        if let topN = options.topN {
            bedrockRerankingConfiguration["numberOfResults"] = .number(Double(topN))
        }

        let rerankingConfiguration: JSONValue = .object([
            "bedrockRerankingConfiguration": .object(bedrockRerankingConfiguration),
            "type": .string("BEDROCK_RERANKING_MODEL"),
        ])

        let queries: JSONValue = .array([
            .object([
                "textQuery": .object(["text": .string(options.query)]),
                "type": .string("TEXT"),
            ])
        ])

        let sources: [JSONValue] = makeSources(from: options.documents)

        var body: [String: JSONValue] = [
            "queries": queries,
            "rerankingConfiguration": rerankingConfiguration,
            "sources": .array(sources),
        ]

        if let nextToken = bedrockOptions?.nextToken {
            body["nextToken"] = .string(nextToken)
        }

        let headers = combineHeaders(
            config.headers(),
            options.headers?.mapValues { Optional($0) }
        ).compactMapValues { $0 }

        let response = try await postJsonToAPI(
            url: "\(config.baseURL())/rerank",
            headers: headers,
            body: JSONValue.object(body),
            failedResponseHandler: bedrockFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: bedrockRerankingResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        return RerankingModelV3DoRerankResult(
            ranking: response.value.results.map { result in
                RerankingModelV3Ranking(index: result.index, relevanceScore: result.relevanceScore)
            },
            response: RerankingModelV3ResponseInfo(
                headers: response.responseHeaders,
                body: response.rawValue
            )
        )
    }
}

private func makeSources(from documents: RerankingModelV3CallOptions.Documents) -> [JSONValue] {
    switch documents {
    case .text(let values):
        return values.map { value in
            .object([
                "type": .string("INLINE"),
                "inlineDocumentSource": .object([
                    "type": .string("TEXT"),
                    "textDocument": .object(["text": .string(value)]),
                ]),
            ])
        }
    case .object(let values):
        return values.map { value in
            .object([
                "type": .string("INLINE"),
                "inlineDocumentSource": .object([
                    "type": .string("JSON"),
                    "jsonDocument": .object(value),
                ]),
            ])
        }
    }
}
