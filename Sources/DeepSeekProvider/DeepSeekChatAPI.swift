import Foundation
import AISDKProvider
import AISDKProviderUtils

func deepSeekObject(_ value: JSONValue?) -> [String: JSONValue] {
    guard case .object(let object) = value else { return [:] }
    return object
}

struct DeepSeekTokenUsage: Decodable, Sendable {
    let raw: JSONValue
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        for key in [Key.promptTokens, .completionTokens, .totalTokens, .cacheHit, .cacheMiss] {
            _ = try c.decodeIfPresent(Double.self, forKey: key)
        }
        _ = try c.decodeIfPresent(PromptDetails.self, forKey: .promptDetails)
        _ = try c.decodeIfPresent(CompletionDetails.self, forKey: .completionDetails)
        raw = try JSONValue(from: decoder)
    }
    private struct PromptDetails: Decodable { let cached_tokens: Double? }
    private struct CompletionDetails: Decodable { let reasoning_tokens: Double? }
    private enum Key: String, CodingKey {
        case promptTokens = "prompt_tokens", completionTokens = "completion_tokens", totalTokens = "total_tokens"
        case cacheHit = "prompt_cache_hit_tokens", cacheMiss = "prompt_cache_miss_tokens"
        case promptDetails = "prompt_tokens_details", completionDetails = "completion_tokens_details"
    }
}

struct DeepSeekLogprobs: Decodable, Sendable {
    let raw: JSONValue
    private struct Token: Decodable {
        struct Alternative: Decodable {
            let token: String
            let logprob: Double
            let bytes: [Double]?
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: Key.self)
                token = try c.decode(String.self, forKey: .token)
                logprob = try c.decode(Double.self, forKey: .logprob)
                bytes = try c.decode([Double]?.self, forKey: .bytes)
            }
            private enum Key: String, CodingKey { case token, logprob, bytes }
        }
        let token: String
        let logprob: Double
        let bytes: [Double]?
        let top_logprobs: [Alternative]
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Key.self)
            token = try c.decode(String.self, forKey: .token)
            logprob = try c.decode(Double.self, forKey: .logprob)
            bytes = try c.decode([Double]?.self, forKey: .bytes)
            top_logprobs = try c.decode([Alternative].self, forKey: .topLogprobs)
        }
        private enum Key: String, CodingKey { case token, logprob, bytes; case topLogprobs = "top_logprobs" }
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        _ = try c.decodeIfPresent([Token].self, forKey: .content)
        _ = try c.decodeIfPresent([Token].self, forKey: .reasoning)
        let object = deepSeekObject(try JSONValue(from: decoder))
        var parsed: [String: JSONValue] = [:]
        for key in ["content", "reasoning_content"] {
            guard let value = object[key] else { continue }
            if case .array(let tokens) = value {
                parsed[key] = .array(tokens.map { value in
                    var token = deepSeekObject(value).filter { ["token", "logprob", "bytes", "top_logprobs"].contains($0.key) }
                    if case .array(let alternatives) = token["top_logprobs"] {
                        token["top_logprobs"] = .array(alternatives.map { .object(deepSeekObject($0).filter { ["token", "logprob", "bytes"].contains($0.key) }) })
                    }
                    return .object(token)
                })
            } else { parsed[key] = value }
        }
        raw = .object(parsed)
    }
    private enum Key: String, CodingKey { case content; case reasoning = "reasoning_content" }
}

enum DeepSeekAssistantRole: String, Decodable, Sendable { case assistant }
enum DeepSeekToolType: String, Decodable, Sendable { case function }
enum DeepSeekResponseObject: String, Decodable, Sendable { case completion = "chat.completion" }
enum DeepSeekChunkObject: String, Decodable, Sendable { case chunk = "chat.completion.chunk" }

struct DeepSeekResponse: Decodable, Sendable {
    struct ToolCall: Decodable, Sendable {
        struct Function: Decodable, Sendable { let name: String; let arguments: String }
        let id: String?
        let type: DeepSeekToolType?
        let function: Function
    }
    struct Message: Decodable, Sendable {
        let role: DeepSeekAssistantRole?
        let content: String?
        let reasoningContent: String?
        let toolCalls: [ToolCall]?
        enum CodingKeys: String, CodingKey {
            case role, content
            case reasoningContent = "reasoning_content"
            case toolCalls = "tool_calls"
        }
    }
    struct Choice: Decodable, Sendable {
        let index: Double?
        let message: Message
        let logprobs: DeepSeekLogprobs?
        let finishReason: String?
        enum CodingKeys: String, CodingKey { case index, message, logprobs; case finishReason = "finish_reason" }
    }
    let id: String?
    let created: Double?
    let model: String?
    let object: DeepSeekResponseObject?
    let systemFingerprint: String?
    let choices: [Choice]
    let usage: DeepSeekTokenUsage?
    enum CodingKeys: String, CodingKey { case id, created, model, object, choices, usage; case systemFingerprint = "system_fingerprint" }
}

struct DeepSeekChunk: Decodable, Sendable {
    struct ToolCall: Decodable, Sendable {
        struct Function: Decodable, Sendable { let name: String?; let arguments: String? }
        let index: Int
        let id: String?
        let type: DeepSeekToolType?
        let function: Function
    }
    struct Delta: Decodable, Sendable {
        let role: DeepSeekAssistantRole?
        let content: String?
        let reasoningContent: String?
        let toolCalls: [ToolCall]?
        enum CodingKeys: String, CodingKey {
            case role, content
            case reasoningContent = "reasoning_content"
            case toolCalls = "tool_calls"
        }
    }
    struct Choice: Decodable, Sendable {
        let index: Double?
        let delta: Delta?
        let logprobs: DeepSeekLogprobs?
        let finishReason: String?
        enum CodingKeys: String, CodingKey { case index, delta, logprobs; case finishReason = "finish_reason" }
    }
    let id: String?
    let created: Double?
    let model: String?
    let object: DeepSeekChunkObject?
    let systemFingerprint: String?
    let choices: [Choice]
    let usage: DeepSeekTokenUsage?
    enum CodingKeys: String, CodingKey { case id, created, model, object, choices, usage; case systemFingerprint = "system_fingerprint" }
}

public struct DeepSeekErrorData: Decodable, Sendable {
    public struct Detail: Decodable, Sendable {
        public let message: String
        public let type: String?
        public let param: JSONValue?
        public let code: ProviderStreamError.Code?
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Key.self)
            message = try container.decode(String.self, forKey: .message)
            type = try container.decodeIfPresent(String.self, forKey: .type)
            param = try container.decodeIfPresent(JSONValue.self, forKey: .param)
            switch try container.decodeIfPresent(JSONValue.self, forKey: .code) {
            case .string(let value): code = .string(value)
            case .number(let value): code = .number(value)
            case nil, .null: code = nil
            default: throw DecodingError.dataCorruptedError(forKey: .code, in: container, debugDescription: "Expected string or number error code")
            }
        }
        private enum Key: String, CodingKey { case message, type, param, code }
    }
    public let error: Detail
}

let deepSeekErrorSchema = FlexibleSchema(Schema<DeepSeekErrorData>.codable(DeepSeekErrorData.self, jsonSchema: ["type": "object"]))
let deepSeekFailedResponseHandler = createJsonErrorResponseHandler(errorSchema: deepSeekErrorSchema, errorToMessage: { $0.error.message })
let deepSeekResponseSchema = FlexibleSchema(Schema<DeepSeekResponse>.codable(DeepSeekResponse.self, jsonSchema: ["type": "object"]))

enum DeepSeekStreamEvent: Decodable, Sendable {
    case data(DeepSeekChunk)
    case error(DeepSeekErrorData.Detail)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        if container.contains(.error) { self = .error(try container.decode(DeepSeekErrorData.Detail.self, forKey: .error)) }
        else { self = .data(try DeepSeekChunk(from: decoder)) }
    }
    enum Key: String, CodingKey { case error }
}
let deepSeekChunkSchema = FlexibleSchema(Schema<DeepSeekStreamEvent>.codable(DeepSeekStreamEvent.self, jsonSchema: ["type": "object"]))

func deepSeekStreamError(_ error: DeepSeekErrorData.Detail, raw: JSONValue) -> ProviderStreamError {
    let code: ProviderStreamError.Code?
    let codeText: String?
    switch error.code {
    case .string(let value): code = .string(value); codeText = value
    case .number(let value): code = .number(value); codeText = Int(exactly: value).map(String.init) ?? String(value)
    default: code = nil; codeText = nil
    }
    var status: Int?
    var retryable: Bool?
    if codeText == "insufficient_quota" || error.type == "insufficient_quota" {
        status = 429; retryable = false
    } else if let number = codeText.flatMap(Int.init), (400...599).contains(number) {
        status = number; retryable = [408, 409, 429].contains(number) || number >= 500
    } else {
        for value in [codeText, error.type].compactMap({ $0 }) {
            switch value {
            case "rate_limit_exceeded", "rate_limit_error": status = 429
            case "server_error", "api_error", "internal_server_error": status = 500
            case "overloaded_error", "service_unavailable": status = 503
            case "timeout", "timeout_error": status = 504
            case "authentication_error", "invalid_api_key": status = 401
            case "permission_error": status = 403
            case "not_found_error", "model_not_found": status = 404
            case "bad_request", "context_length_exceeded", "invalid_request_error": status = 400
            default: continue
            }
            retryable = status == 429 || (status ?? 0) >= 500
            break
        }
    }
    return createProviderStreamError(message: error.message, type: error.type, code: code,
                                     statusCode: status, isRetryable: retryable, data: raw)
}
