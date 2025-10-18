import Foundation
import AISDKProvider
import AISDKProviderUtils

struct OpenAICompletionUsage: Codable, Sendable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

struct OpenAICompletionLogprobs: Codable, Sendable {
    let tokens: [String]
    let tokenLogprobs: [Double]
    let topLogprobs: [[String: Double]]?

    enum CodingKeys: String, CodingKey {
        case tokens
        case tokenLogprobs = "token_logprobs"
        case topLogprobs = "top_logprobs"
    }
}

struct OpenAICompletionChoice: Codable, Sendable {
    let text: String
    let finishReason: String?
    let logprobs: OpenAICompletionLogprobs?

    enum CodingKeys: String, CodingKey {
        case text
        case finishReason = "finish_reason"
        case logprobs
    }
}

struct OpenAICompletionResponse: Codable, Sendable {
    let id: String?
    let created: Double?
    let model: String?
    let choices: [OpenAICompletionChoice]
    let usage: OpenAICompletionUsage?
}

struct OpenAICompletionChunkChoice: Codable, Sendable {
    let text: String?
    let finishReason: String?
    let index: Int
    let logprobs: OpenAICompletionLogprobs?

    enum CodingKeys: String, CodingKey {
        case text
        case finishReason = "finish_reason"
        case index
        case logprobs
    }
}

struct OpenAICompletionChunkData: Codable, Sendable {
    let id: String?
    let created: Double?
    let model: String?
    let choices: [OpenAICompletionChunkChoice]
    let usage: OpenAICompletionUsage?
}

enum OpenAICompletionChunk: Codable, Sendable {
    case data(OpenAICompletionChunkData)
    case error(OpenAIErrorData)

    init(from decoder: Decoder) throws {
        if let error = try? OpenAIErrorData(from: decoder) {
            self = .error(error)
            return
        }
        let data = try OpenAICompletionChunkData(from: decoder)
        self = .data(data)
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .data(let data):
            try data.encode(to: encoder)
        case .error(let error):
            try error.encode(to: encoder)
        }
    }
}

let openAICompletionResponseSchema = FlexibleSchema(
    Schema.codable(
        OpenAICompletionResponse.self,
        jsonSchema: .object([
            "type": .string("object")
        ])
    )
)

let openAICompletionChunkSchema = FlexibleSchema(
    Schema.codable(
        OpenAICompletionChunk.self,
        jsonSchema: .object([
            "type": .string("object")
        ])
    )
)
