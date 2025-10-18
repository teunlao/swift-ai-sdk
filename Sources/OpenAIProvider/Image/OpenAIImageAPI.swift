import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct OpenAIImageResponse: Codable, Sendable {
    public struct Item: Codable, Sendable {
        public let b64JSON: String
        public let revisedPrompt: String?

        enum CodingKeys: String, CodingKey {
            case b64JSON = "b64_json"
            case revisedPrompt = "revised_prompt"
        }
    }

    public let data: [Item]
}

public let openaiImageResponseSchema = FlexibleSchema(
    Schema.codable(
        OpenAIImageResponse.self,
        jsonSchema: .object([
            "type": .string("object")
        ])
    )
)
