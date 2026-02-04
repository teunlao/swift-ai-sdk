import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/amazon-bedrock/src/reranking/bedrock-reranking-api.ts
// Upstream commit: f3a72bc2a
//===----------------------------------------------------------------------===//

private let genericJSONObjectSchema: JSONValue = .object(["type": .string("object")])

struct BedrockRerankingResponse: Codable, Sendable {
    struct Result: Codable, Sendable {
        let index: Int
        let relevanceScore: Double
    }

    let results: [Result]
    let nextToken: String?
}

let bedrockRerankingResponseSchema = FlexibleSchema(
    Schema.codable(
        BedrockRerankingResponse.self,
        jsonSchema: genericJSONObjectSchema
    )
)

