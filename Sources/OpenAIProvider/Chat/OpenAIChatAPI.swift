import Foundation
import AISDKProvider
import AISDKProviderUtils

enum OpenAIChatRole: String, Codable, Sendable { case assistant }
enum OpenAIChatToolType: String, Codable, Sendable { case function }
enum OpenAIChatAnnotationType: String, Codable, Sendable { case urlCitation = "url_citation" }

struct OpenAIChatAnnotation: Codable, Sendable {
    let type: OpenAIChatAnnotationType
    let urlCitation: URLCitation
    struct URLCitation: Codable, Sendable {
        let startIndex: Int
        let endIndex: Int
        let url: String
        let title: String
        enum CodingKeys: String, CodingKey {
            case startIndex = "start_index", endIndex = "end_index", url, title
        }
    }
    enum CodingKeys: String, CodingKey { case type, urlCitation = "url_citation" }
}

struct OpenAIChatFunctionCall: Codable, Sendable {
    let name: String?
    let arguments: String?
}

struct OpenAIChatFunctionToolCall: Codable, Sendable {
    let id: String?
    let type: OpenAIChatToolType
    let function: Function
    struct Function: Codable, Sendable {
        let name: String
        let arguments: String
    }
}

struct OpenAIChatChoiceMessage: Codable, Sendable {
    let role: OpenAIChatRole?
    let content: String?
    let toolCalls: [OpenAIChatFunctionToolCall]?
    let annotations: [OpenAIChatAnnotation]?
    let audio: Audio?
    struct Audio: Codable, Sendable { let transcript: String? }
    enum CodingKeys: String, CodingKey { case role, content, toolCalls = "tool_calls", annotations, audio }
}

struct OpenAIChatLogprobAlternative: Codable, Sendable {
    let token: String
    let logprob: Double
}
struct OpenAIChatLogprobItem: Codable, Sendable {
    let token: String
    let logprob: Double
    let topLogprobs: [OpenAIChatLogprobAlternative]
    enum CodingKeys: String, CodingKey { case token, logprob, topLogprobs = "top_logprobs" }
}
struct OpenAIChatChoiceLogprobs: Codable, Sendable { let content: [OpenAIChatLogprobItem]? }
struct OpenAIChatChoice: Codable, Sendable {
    let message: OpenAIChatChoiceMessage
    let index: Int
    let logprobs: OpenAIChatChoiceLogprobs?
    let finishReason: String?
    enum CodingKeys: String, CodingKey { case message, index, logprobs, finishReason = "finish_reason" }
}

struct OpenAIChatUsageCompletionDetails: Codable, Sendable {
    let reasoningTokens: Int?
    let acceptedPredictionTokens: Int?
    let rejectedPredictionTokens: Int?
    enum CodingKeys: String, CodingKey {
        case reasoningTokens = "reasoning_tokens", acceptedPredictionTokens = "accepted_prediction_tokens", rejectedPredictionTokens = "rejected_prediction_tokens"
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reasoningTokens = try container.decodeIfPresent(Double.self, forKey: .reasoningTokens).flatMap(Int.init(exactly:))
        acceptedPredictionTokens = try container.decodeIfPresent(Double.self, forKey: .acceptedPredictionTokens).flatMap(Int.init(exactly:))
        rejectedPredictionTokens = try container.decodeIfPresent(Double.self, forKey: .rejectedPredictionTokens).flatMap(Int.init(exactly:))
    }
}
struct OpenAIChatUsagePromptDetails: Codable, Sendable {
    let cachedTokens: Int?
    let cacheWriteTokens: Int?
    enum CodingKeys: String, CodingKey { case cachedTokens = "cached_tokens", cacheWriteTokens = "cache_write_tokens" }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cachedTokens = try container.decodeIfPresent(Double.self, forKey: .cachedTokens).flatMap(Int.init(exactly:))
        cacheWriteTokens = try container.decodeIfPresent(Double.self, forKey: .cacheWriteTokens).flatMap(Int.init(exactly:))
    }
}
struct OpenAIChatUsage: Codable, Sendable {
    let promptTokens: Int?
    let completionTokens: Int?
    let totalTokens: Int?
    let promptTokensDetails: OpenAIChatUsagePromptDetails?
    let completionTokensDetails: OpenAIChatUsageCompletionDetails?
    let raw: JSONValue
    enum CodingKeys: String, CodingKey, CaseIterable {
        case promptTokens = "prompt_tokens", completionTokens = "completion_tokens", totalTokens = "total_tokens"
        case promptTokensDetails = "prompt_tokens_details", completionTokensDetails = "completion_tokens_details"
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        promptTokens = try container.decodeIfPresent(Double.self, forKey: .promptTokens).flatMap(Int.init(exactly:))
        completionTokens = try container.decodeIfPresent(Double.self, forKey: .completionTokens).flatMap(Int.init(exactly:))
        totalTokens = try container.decodeIfPresent(Double.self, forKey: .totalTokens).flatMap(Int.init(exactly:))
        promptTokensDetails = try container.decodeIfPresent(OpenAIChatUsagePromptDetails.self, forKey: .promptTokensDetails)
        completionTokensDetails = try container.decodeIfPresent(OpenAIChatUsageCompletionDetails.self, forKey: .completionTokensDetails)
        raw = try JSONValue(from: decoder)
    }
    func encode(to encoder: Encoder) throws { try raw.encode(to: encoder) }
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
    let type: OpenAIChatToolType?
    let function: OpenAIChatFunctionCall
}
struct OpenAIChatChunkDelta: Codable, Sendable {
    let role: OpenAIChatRole?
    let content: String?
    let toolCalls: [OpenAIChatChunkToolCallDelta]?
    let annotations: [OpenAIChatAnnotation]?
    enum CodingKeys: String, CodingKey { case role, content, toolCalls = "tool_calls", annotations }
}
struct OpenAIChatChunkChoice: Codable, Sendable {
    let delta: OpenAIChatChunkDelta?
    let logprobs: OpenAIChatChoiceLogprobs?
    let finishReason: String?
    let index: Int
    enum CodingKeys: String, CodingKey { case delta, logprobs, finishReason = "finish_reason", index }
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
    case error(JSONValue)
    private enum ErrorKey: String, CodingKey { case error }
    init(from decoder: Decoder) throws {
        if let data = try? OpenAIChatChunkData(from: decoder) {
            self = .data(data)
        } else {
            self = .error(try OpenAIErrorData(from: decoder).error.jsonValue)
        }
    }
    func encode(to encoder: Encoder) throws {
        switch self {
        case .data(let value): try value.encode(to: encoder)
        case .error(let value):
            var container = encoder.container(keyedBy: ErrorKey.self)
            try container.encode(value, forKey: .error)
        }
    }
}

let openAIChatResponseSchema = FlexibleSchema(Schema.codable(OpenAIChatResponse.self, jsonSchema: .object(["type": .string("object")])))
let openAIChatChunkSchema = FlexibleSchema(Schema.codable(OpenAIChatChunk.self, jsonSchema: .object(["type": .string("object")])))
