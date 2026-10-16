import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct MoonshotAIErrorData: Codable, Sendable {
    public struct ErrorBody: Codable, Sendable {
        public let message: String
        public let type: String?
        public let code: String?
        private let hasType: Bool
        private let hasCode: Bool
        private enum CodingKeys: String, CodingKey { case message, type, code }
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            message = try container.decode(String.self, forKey: .message)
            type = try container.decodeIfPresent(String.self, forKey: .type)
            code = try container.decodeIfPresent(String.self, forKey: .code)
            hasType = container.contains(.type); hasCode = container.contains(.code)
        }
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(message, forKey: .message)
            if let type { try container.encode(type, forKey: .type) } else if hasType { try container.encodeNil(forKey: .type) }
            if let code { try container.encode(code, forKey: .code) } else if hasCode { try container.encodeNil(forKey: .code) }
        }
    }
    public let error: ErrorBody
}
let moonshotErrorSchema = FlexibleSchema(Schema<MoonshotAIErrorData>.codable(MoonshotAIErrorData.self, jsonSchema: .object(["type": .string("object")])))
let moonshotFailedResponseHandler = createJsonErrorResponseHandler(errorSchema: moonshotErrorSchema, errorToMessage: { $0.error.message })

struct MoonshotUsage: Decodable, Sendable {
    struct InputDetails: Decodable { let cached_tokens: Double? }
    struct OutputDetails: Decodable { let reasoning_tokens: Double? }
    let raw: JSONValue
    private enum CodingKeys: String, CodingKey { case prompt_tokens, completion_tokens, cached_tokens, total_tokens, prompt_tokens_details, completion_tokens_details }
    init(from decoder: Decoder) throws {
        raw = try JSONValue(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        for key in [CodingKeys.prompt_tokens, .completion_tokens, .cached_tokens, .total_tokens] { _ = try c.decodeIfPresent(Double.self, forKey: key) }
        _ = try c.decodeIfPresent(InputDetails.self, forKey: .prompt_tokens_details)
        _ = try c.decodeIfPresent(OutputDetails.self, forKey: .completion_tokens_details)
    }
}
struct MoonshotLogprob: Decodable, Sendable {
    struct Token: Decodable, Sendable {
        let token: String
        let logprob: Double
        let bytes: [Double]?
        enum CodingKeys: String, CodingKey { case token, logprob, bytes }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            token = try c.decode(String.self, forKey: .token); logprob = try c.decode(Double.self, forKey: .logprob)
            guard c.contains(.bytes) else { throw DecodingError.keyNotFound(CodingKeys.bytes, .init(codingPath: c.codingPath, debugDescription: "Missing bytes")) }
            bytes = try c.decodeIfPresent([Double].self, forKey: .bytes)
        }
        var json: JSONValue { .object(["token": .string(token), "logprob": .number(logprob), "bytes": bytes.map { .array($0.map(JSONValue.number)) } ?? .null]) }
    }
    let token: Token
    let top: [Token]
    enum CodingKeys: String, CodingKey { case top = "top_logprobs" }
    init(from decoder: Decoder) throws { token = try Token(from: decoder); top = try decoder.container(keyedBy: CodingKeys.self).decode([Token].self, forKey: .top) }
    var json: JSONValue {
        .object(["token": .string(token.token), "logprob": .number(token.logprob), "bytes": token.bytes.map { .array($0.map(JSONValue.number)) } ?? .null, "top_logprobs": .array(top.map(\.json))])
    }
}
struct MoonshotLogprobs: Decodable, Sendable {
    let content: [MoonshotLogprob]?
    let hasContent: Bool
    enum CodingKeys: String, CodingKey { case content }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self); content = try c.decodeIfPresent([MoonshotLogprob].self, forKey: .content); hasContent = c.contains(.content)
    }
    var json: JSONValue { .object(hasContent ? ["content": content.map { .array($0.map(\.json)) } ?? .null] : [:]) }
}

enum MoonshotRole: String, Decodable, Sendable { case assistant }
enum MoonshotFunctionType: String, Decodable, Sendable { case function }
struct MoonshotToolCall: Decodable, Sendable {
    struct Function: Decodable, Sendable { let name: String; let arguments: String }
    let id: String?
    let type: MoonshotFunctionType?
    let function: Function
}
struct MoonshotMessage: Decodable, Sendable {
    let role: MoonshotRole?
    let content: String?
    let reasoning_content: String?
    let tool_calls: [MoonshotToolCall]?
}
struct MoonshotResponse: Decodable, Sendable {
    enum Object: String, Decodable, Sendable { case completion = "chat.completion" }
    struct Choice: Decodable, Sendable {
        let index: Double?
        let message: MoonshotMessage
        let logprobs: MoonshotLogprobs?
        let finish_reason: String?
    }
    let id: String?
    let created: Double?
    let model: String?
    let object: Object?
    let choices: [Choice]
    let usage: MoonshotUsage?
}
struct MoonshotToolDelta: Decodable, Sendable {
    struct Function: Decodable, Sendable { let name: String?; let arguments: String? }
    let index: Int?
    let id: String?
    let type: MoonshotFunctionType?
    let function: Function
}
struct MoonshotDelta: Decodable, Sendable {
    let role: MoonshotRole?
    let content: String?
    let reasoning_content: String?
    let tool_calls: [MoonshotToolDelta]?
}
struct MoonshotChunkBody: Decodable, Sendable {
    enum Object: String, Decodable, Sendable { case chunk = "chat.completion.chunk" }
    struct Choice: Decodable, Sendable {
        let index: Double?
        let delta: MoonshotDelta?
        let logprobs: MoonshotLogprobs?
        let finish_reason: String?
        let usage: MoonshotUsage?
    }
    let id: String?
    let created: Double?
    let model: String?
    let object: Object?
    let choices: [Choice]
    let usage: MoonshotUsage?
}
enum MoonshotChunk: Decodable, Sendable {
    case body(MoonshotChunkBody), error(MoonshotAIErrorData)
    enum CodingKeys: String, CodingKey { case error }
    init(from decoder: Decoder) throws {
        if try decoder.container(keyedBy: CodingKeys.self).contains(.error) { self = .error(try MoonshotAIErrorData(from: decoder)) }
        else { self = .body(try MoonshotChunkBody(from: decoder)) }
    }
}

let moonshotResponseSchema = FlexibleSchema(Schema<MoonshotResponse>(jsonSchemaResolver: { .object(["type": .string("object")]) }, validator: { value in
    do { return .success(value: try JSONDecoder().decode(MoonshotResponse.self, from: JSONEncoder().encode(jsonValue(from: value)))) }
    catch { return .failure(error: TypeValidationError.wrap(value: value, cause: error)) }
}))
let moonshotChunkSchema = FlexibleSchema(Schema<MoonshotChunk>(jsonSchemaResolver: { .object(["type": .string("object")]) }, validator: { value in
    do { return .success(value: try JSONDecoder().decode(MoonshotChunk.self, from: JSONEncoder().encode(jsonValue(from: value)))) }
    catch { return .failure(error: TypeValidationError.wrap(value: value, cause: error)) }
}))

func mapMoonshotAIFinishReason(_ reason: String?) -> LanguageModelV4FinishReason.Unified {
    switch reason { case "stop": .stop; case "length": .length; case "content_filter": .contentFilter; case "function_call", "tool_calls": .toolCalls; default: .other }
}
