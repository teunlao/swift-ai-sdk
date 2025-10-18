import Foundation
import AISDKProvider
import AISDKProviderUtils

public typealias OpenAIResponsesInput = [JSONValue]

public struct OpenAIResponsesResponse: Codable, Sendable {
    public struct OutputItem: Codable, Sendable {
        public let type: String
        public let text: String?
    }

    public struct Usage: Codable, Sendable {
        public let inputTokens: Int?
        public let outputTokens: Int?
        public let totalTokens: Int?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case totalTokens = "total_tokens"
        }
    }

    public let id: String?
    public let output: [OutputItem]
    public let usage: Usage?
    public let warnings: [LanguageModelV3CallWarningRecord]?
    public let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case id, output, usage, warnings
        case finishReason = "finish_reason"
    }
}

public struct LanguageModelV3CallWarningRecord: Codable, Sendable {
    public let type: String
    public let message: String?
    public let setting: String?

    public init(type: String, message: String? = nil, setting: String? = nil) {
        self.type = type
        self.message = message
        self.setting = setting
    }

    public func toWarning() -> LanguageModelV3CallWarning {
        switch type {
        case "unsupported-setting":
            return .unsupportedSetting(setting: setting ?? "unknown", details: message)
        default:
            return .other(message: message ?? "OpenAI warning")
        }
    }
}


public struct OpenAIResponsesChunk: Codable, Sendable {
    public let type: String?
    public let output: [OpenAIResponsesResponse.OutputItem]?
    public let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case type
        case output
        case finishReason = "finish_reason"
    }
}

public let openAIResponsesChunkSchema = FlexibleSchema(
    Schema.codable(
        OpenAIResponsesChunk.self,
        jsonSchema: .object([
            "type": .array([.string("object"), .string("null")]),
            "properties": .object([
                "type": .object(["type": .array([.string("string"), .string("null")])]),
                "output": .object([
                    "type": .array([.string("array"), .string("null")])
                ]),
                "finish_reason": .object(["type": .array([.string("string"), .string("null")])])
            ])
        ])
    )
)

public let openAIResponsesResponseSchema = FlexibleSchema(
    Schema.codable(
        OpenAIResponsesResponse.self,
        jsonSchema: .object([
            "type": .string("object"),
            "properties": .object([
                "id": .object(["type": .array([.string("string"), .string("null")])]),
                "output": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "type": .object(["type": .string("string")]),
                            "text": .object(["type": .array([.string("string"), .string("null")])])
                        ]),
                        "required": .array([.string("type")])
                    ])
                ]),
                "usage": .object(["type": .array([.string("object"), .string("null")])]),
                "warnings": .object([
                    "type": .array([.string("array"), .string("null")])
                ]),
                "finish_reason": .object(["type": .array([.string("string"), .string("null")])])
            ]),
            "required": .array([.string("output")])
        ])
    )
)
