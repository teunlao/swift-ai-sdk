import Foundation
import AISDKProvider
import AISDKProviderUtils

struct OpenAIChatAnnotation: Codable, Sendable {
    let type: String
    let startIndex: Int
    let endIndex: Int
    let url: String
    let title: String

    enum CodingKeys: String, CodingKey {
        case type
        case startIndex = "start_index"
        case endIndex = "end_index"
        case url
        case title
    }
}

struct OpenAIChatFunctionCall: Codable, Sendable {
    let name: String?
    let arguments: String?
}

struct OpenAIChatFunctionToolCall: Codable, Sendable {
    let id: String?
    let type: String?
    let function: OpenAIChatFunctionCall?
}

struct OpenAIChatChoiceMessage: Codable, Sendable {
    let role: String?
    let content: String?
    let toolCalls: [OpenAIChatFunctionToolCall]?
    let annotations: [OpenAIChatAnnotation]?

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case toolCalls = "tool_calls"
        case annotations
    }
}

struct OpenAIChatLogprobAlternative: Codable, Sendable {
    let token: String
    let logprob: Double

    enum CodingKeys: String, CodingKey {
        case token
        case logprob
    }
}

struct OpenAIChatLogprobItem: Codable, Sendable {
    let token: String
    let logprob: Double
    let topLogprobs: [OpenAIChatLogprobAlternative]?

    enum CodingKeys: String, CodingKey {
        case token
        case logprob
        case topLogprobs = "top_logprobs"
    }
}

struct OpenAIChatChoiceLogprobs: Codable, Sendable {
    let content: [OpenAIChatLogprobItem]?
}

struct OpenAIChatChoice: Codable, Sendable {
    let message: OpenAIChatChoiceMessage
    let index: Int
    let logprobs: OpenAIChatChoiceLogprobs?
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case message
        case index
        case logprobs
        case finishReason = "finish_reason"
    }
}

struct OpenAIChatUsageCompletionDetails: Codable, Sendable {
    let reasoningTokens: Int?
    let acceptedPredictionTokens: Int?
    let rejectedPredictionTokens: Int?

    enum CodingKeys: String, CodingKey {
        case reasoningTokens = "reasoning_tokens"
        case acceptedPredictionTokens = "accepted_prediction_tokens"
        case rejectedPredictionTokens = "rejected_prediction_tokens"
    }
}

struct OpenAIChatUsagePromptDetails: Codable, Sendable {
    let cachedTokens: Int?

    enum CodingKeys: String, CodingKey {
        case cachedTokens = "cached_tokens"
    }
}

struct OpenAIChatUsage: Codable, Sendable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?
    let promptTokensDetails: OpenAIChatUsagePromptDetails?
    let completionTokensDetails: OpenAIChatUsageCompletionDetails?

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
        case promptTokensDetails = "prompt_tokens_details"
        case completionTokensDetails = "completion_tokens_details"
    }
}

struct OpenAIChatResponse: Codable, Sendable {
    let id: String?
    let created: Double?
    let model: String?
    let choices: [OpenAIChatChoice]
    let usage: OpenAIChatUsage?
}

struct OpenAIChatChunkToolCallDelta: Codable, Sendable {
    let index: Int
    let id: String?
    let type: String?
    let function: OpenAIChatFunctionCall?

    enum CodingKeys: String, CodingKey {
        case index
        case id
        case type
        case function
    }
}

struct OpenAIChatChunkDelta: Codable, Sendable {
    let role: String?
    let content: String?
    let toolCalls: [OpenAIChatChunkToolCallDelta]?
    let annotations: [OpenAIChatAnnotation]?

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case toolCalls = "tool_calls"
        case annotations
    }
}

struct OpenAIChatChunkChoice: Codable, Sendable {
    let delta: OpenAIChatChunkDelta?
    let logprobs: OpenAIChatChoiceLogprobs?
    let finishReason: String?
    let index: Int

    enum CodingKeys: String, CodingKey {
        case delta
        case logprobs
        case finishReason = "finish_reason"
        case index
    }
}

struct OpenAIChatChunkData: Codable, Sendable {
    let id: String?
    let created: Double?
    let model: String?
    let choices: [OpenAIChatChunkChoice]
    let usage: OpenAIChatUsage?
}

enum OpenAIChatChunk: Codable, Sendable {
    case data(OpenAIChatChunkData)
    case error(OpenAIErrorData)

    init(from decoder: Decoder) throws {
        if let error = try? OpenAIErrorData(from: decoder) {
            self = .error(error)
            return
        }
        let data = try OpenAIChatChunkData(from: decoder)
        self = .data(data)
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .data(let value):
            try value.encode(to: encoder)
        case .error(let error):
            try error.encode(to: encoder)
        }
    }
}

let openAIChatResponseSchema = FlexibleSchema(
    Schema.codable(
        OpenAIChatResponse.self,
        jsonSchema: .object([
            "type": .string("object")
        ])
    )
)

let openAIChatChunkSchema = FlexibleSchema(
    Schema.codable(
        OpenAIChatChunk.self,
        jsonSchema: .object([
            "type": .string("object")
        ])
    )
)
