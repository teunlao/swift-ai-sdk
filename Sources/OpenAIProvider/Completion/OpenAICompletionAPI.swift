import Foundation
import AISDKProvider
import AISDKProviderUtils

struct OpenAICompletionUsage: Codable, Sendable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?
    let raw: JSONValue

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        promptTokens = Int(exactly: try container.decode(Double.self, forKey: .promptTokens))
        completionTokens = Int(exactly: try container.decode(Double.self, forKey: .completionTokens))
        totalTokens = Int(exactly: try container.decode(Double.self, forKey: .totalTokens))
        raw = try JSONValue(from: decoder)
    }
    func encode(to encoder: Encoder) throws { try raw.encode(to: encoder) }
}

struct OpenAICompletionLogprobs: Codable, Sendable {
    let tokens: [String]
    let tokenLogprobs: [Double]
    let topLogprobs: [[String: Double]]?
    let raw: JSONValue

    enum CodingKeys: String, CodingKey, CaseIterable {
        case tokens
        case tokenLogprobs = "token_logprobs"
        case topLogprobs = "top_logprobs"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tokens = try container.decode([String].self, forKey: .tokens)
        tokenLogprobs = try container.decode([Double].self, forKey: .tokenLogprobs)
        topLogprobs = try container.decodeIfPresent([[String: Double]].self, forKey: .topLogprobs)
        var value: [String: JSONValue] = [:]
        for key in CodingKeys.allCases where container.contains(key) {
            value[key.rawValue] = try container.decode(JSONValue.self, forKey: key)
        }
        raw = .object(value)
    }

    func encode(to encoder: Encoder) throws { try raw.encode(to: encoder) }
}

struct OpenAICompletionChoice: Codable, Sendable {
    let text: String
    let finishReason: String
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
    let text: String
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
    case error(JSONValue)

    private enum ErrorKey: String, CodingKey { case error }

    init(from decoder: Decoder) throws {
        if let data = try? OpenAICompletionChunkData(from: decoder) {
            self = .data(data)
        } else {
            self = .error(try OpenAIErrorData(from: decoder).error.jsonValue)
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .data(let data):
            try data.encode(to: encoder)
        case .error(let error):
            var container = encoder.container(keyedBy: ErrorKey.self)
            try container.encode(error, forKey: .error)
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
