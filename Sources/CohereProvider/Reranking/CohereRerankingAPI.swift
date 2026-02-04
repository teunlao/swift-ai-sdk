import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/cohere/src/reranking/cohere-reranking-api.ts
// Upstream commit: f3a72bc2a
//===----------------------------------------------------------------------===//

private let genericJSONObjectSchema: JSONValue = .object(["type": .string("object")])

struct CohereRerankingResponse: Codable, Sendable {
    struct Result: Codable, Sendable {
        let index: Int
        let relevanceScore: Double

        private enum CodingKeys: String, CodingKey {
            case index
            case relevanceScore = "relevance_score"
        }
    }

    let id: String?
    let results: [Result]
    let meta: JSONValue
}

let cohereRerankingResponseSchema = FlexibleSchema(
    Schema.codable(
        CohereRerankingResponse.self,
        jsonSchema: genericJSONObjectSchema
    )
)

