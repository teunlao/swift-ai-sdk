import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct OpenAIEmbeddingResponse: Codable, Sendable {
    public struct Item: Codable, Sendable {
        public let embedding: [Double]
    }

    public struct Usage: Codable, Sendable {
        public let promptTokens: Int

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
        }
    }

    public let data: [Item]
    public let usage: Usage?
}

public let openaiEmbeddingResponseSchema = FlexibleSchema(
    Schema.codable(
        OpenAIEmbeddingResponse.self,
        jsonSchema: .object([
            "type": .string("object")
        ])
    )
)
