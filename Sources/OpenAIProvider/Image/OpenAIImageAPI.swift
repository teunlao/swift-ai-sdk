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

    public struct Usage: Codable, Sendable {
        public struct InputTokensDetails: Codable, Sendable {
            public let imageTokens: Int?
            public let textTokens: Int?

            enum CodingKeys: String, CodingKey {
                case imageTokens = "image_tokens"
                case textTokens = "text_tokens"
            }
        }

        public let inputTokens: Int?
        public let outputTokens: Int?
        public let totalTokens: Int?
        public let inputTokensDetails: InputTokensDetails?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case totalTokens = "total_tokens"
            case inputTokensDetails = "input_tokens_details"
        }
    }

    public let created: Double?
    public let data: [Item]
    public let background: String?
    public let outputFormat: String?
    public let size: String?
    public let quality: String?
    public let usage: Usage?

    enum CodingKeys: String, CodingKey {
        case created
        case data
        case background
        case outputFormat = "output_format"
        case size
        case quality
        case usage
    }
}

public let openaiImageResponseSchema = FlexibleSchema(
    Schema.codable(
        OpenAIImageResponse.self,
        jsonSchema: [
            "type": "object", "required": ["data"],
            "properties": [
                "created": ["type": ["number", "null"]],
                "data": ["type": "array", "items": ["type": "object", "required": ["b64_json"],
                    "properties": ["b64_json": ["type": "string"], "revised_prompt": ["type": ["string", "null"]]]]],
                "background": ["type": ["string", "null"]],
                "output_format": ["type": ["string", "null"]],
                "size": ["type": ["string", "null"]],
                "quality": ["type": ["string", "null"]],
                "usage": ["type": ["object", "null"], "properties": [
                    "input_tokens": ["type": ["number", "null"]],
                    "output_tokens": ["type": ["number", "null"]],
                    "total_tokens": ["type": ["number", "null"]],
                    "input_tokens_details": ["type": ["object", "null"], "properties": [
                        "image_tokens": ["type": ["number", "null"]], "text_tokens": ["type": ["number", "null"]]
                    ]]
                ]]
            ]
        ]
    )
)
