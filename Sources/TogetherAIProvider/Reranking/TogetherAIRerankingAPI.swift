import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/togetherai/src/reranking/togetherai-reranking-api.ts
// Upstream commit: f3a72bc2a
//===----------------------------------------------------------------------===//

private let genericJSONObjectSchema: JSONValue = .object(["type": .string("object")])

struct TogetherAIRerankingErrorEnvelope: Codable, Sendable {
    struct ErrorInfo: Codable, Sendable {
        let message: String
    }

    let error: ErrorInfo
}

let togetheraiRerankingErrorSchema = FlexibleSchema(
    Schema.codable(
        TogetherAIRerankingErrorEnvelope.self,
        jsonSchema: genericJSONObjectSchema
    )
)

struct TogetherAIRerankingResponse: Codable, Sendable {
    struct Result: Codable, Sendable {
        let index: Int
        let relevanceScore: Double

        private enum CodingKeys: String, CodingKey {
            case index
            case relevanceScore = "relevance_score"
        }
    }

    struct Usage: Codable, Sendable {
        let promptTokens: Int
        let completionTokens: Int
        let totalTokens: Int

        private enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }

    let id: String?
    let model: String?
    let results: [Result]
    let usage: Usage
}

let togetheraiRerankingResponseSchema = FlexibleSchema(
    Schema.codable(
        TogetherAIRerankingResponse.self,
        jsonSchema: genericJSONObjectSchema
    )
)
