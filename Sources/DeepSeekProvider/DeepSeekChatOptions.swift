import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct DeepSeekLanguageModelChatOptions: Codable, Sendable, Equatable {
    public struct Thinking: Codable, Sendable, Equatable {
        public let type: String?
        public init(type: String? = nil) { self.type = type }
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Key.self)
            type = try container.decodeIfPresent(String.self, forKey: .type)
            if let type, !["adaptive", "enabled", "disabled"].contains(type) {
                throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Invalid DeepSeek thinking type")
            }
        }
        private enum Key: String, CodingKey { case type }
    }
    public var logprobs: Bool?
    public var topLogprobs: Int?
    public var userId: String?
    public var thinking: Thinking?
    public var reasoningEffort: String?
    public var strictJsonSchema: Bool?
    public init(logprobs: Bool? = nil, topLogprobs: Int? = nil, userId: String? = nil,
                thinking: Thinking? = nil, reasoningEffort: String? = nil, strictJsonSchema: Bool? = nil) {
        self.logprobs = logprobs; self.topLogprobs = topLogprobs; self.userId = userId
        self.thinking = thinking; self.reasoningEffort = reasoningEffort; self.strictJsonSchema = strictJsonSchema
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        logprobs = try c.decodeIfPresent(Bool.self, forKey: .logprobs)
        topLogprobs = try c.decodeIfPresent(Int.self, forKey: .topLogprobs)
        userId = try c.decodeIfPresent(String.self, forKey: .userId)
        thinking = try c.decodeIfPresent(Thinking.self, forKey: .thinking)
        reasoningEffort = try c.decodeIfPresent(String.self, forKey: .reasoningEffort)
        strictJsonSchema = try c.decodeIfPresent(Bool.self, forKey: .strictJsonSchema)
        if let value = topLogprobs, !(0...20).contains(value) {
            throw DecodingError.dataCorruptedError(forKey: .topLogprobs, in: c, debugDescription: "topLogprobs must be between 0 and 20")
        }
        if let value = userId, value.count > 512 || value.range(of: "^[a-zA-Z0-9_-]+$", options: .regularExpression) == nil {
            throw DecodingError.dataCorruptedError(forKey: .userId, in: c, debugDescription: "Invalid DeepSeek userId")
        }
        if let value = reasoningEffort, !["low", "medium", "high", "xhigh", "max"].contains(value) {
            throw DecodingError.dataCorruptedError(forKey: .reasoningEffort, in: c, debugDescription: "Invalid DeepSeek reasoning effort")
        }
    }
}

public struct DeepSeekMessageProviderOptions: Codable, Sendable, Equatable {
    public var name: String?
    public init(name: String? = nil) { self.name = name }
}

public struct DeepSeekAssistantMessageProviderOptions: Codable, Sendable, Equatable {
    public var name: String?
    public var prefix: Bool?
    public init(name: String? = nil, prefix: Bool? = nil) { self.name = name; self.prefix = prefix }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        prefix = try c.decodeIfPresent(Bool.self, forKey: .prefix)
        if prefix == false { throw DecodingError.dataCorruptedError(forKey: .prefix, in: c, debugDescription: "prefix must be true") }
    }
}

public struct DeepSeekFilePartProviderOptions: Codable, Sendable, Equatable {
    public var imageDetail: String?
    public var fileData: Bool?
    public init(imageDetail: String? = nil, fileData: Bool? = nil) { self.imageDetail = imageDetail; self.fileData = fileData }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        imageDetail = try c.decodeIfPresent(String.self, forKey: .imageDetail)
        fileData = try c.decodeIfPresent(Bool.self, forKey: .fileData)
        if let imageDetail, !["low", "high", "original", "auto"].contains(imageDetail) {
            throw DecodingError.dataCorruptedError(forKey: .imageDetail, in: c, debugDescription: "Invalid DeepSeek image detail")
        }
        if fileData == false { throw DecodingError.dataCorruptedError(forKey: .fileData, in: c, debugDescription: "fileData must be true") }
    }
}

let deepSeekLanguageModelChatOptionsSchema = FlexibleSchema(Schema<DeepSeekLanguageModelChatOptions>.codable(DeepSeekLanguageModelChatOptions.self, jsonSchema: ["type": "object"]))
let deepSeekMessageOptionsSchema = FlexibleSchema(Schema<DeepSeekAssistantMessageProviderOptions>.codable(DeepSeekAssistantMessageProviderOptions.self, jsonSchema: ["type": "object"]))
let deepSeekFilePartOptionsSchema = FlexibleSchema(Schema<DeepSeekFilePartProviderOptions>.codable(DeepSeekFilePartProviderOptions.self, jsonSchema: ["type": "object"]))

func prepareDeepSeekTools(_ tools: [LanguageModelV4Tool]?, choice: LanguageModelV4ToolChoice?, supportsStrict: Bool?) throws -> (tools: [JSONValue]?, choice: JSONValue?, warnings: [SharedV4Warning]) {
    guard let tools, !tools.isEmpty else { return (nil, nil, []) }
    let functions = tools.compactMap { tool -> LanguageModelV4FunctionTool? in
        guard case .function(let function) = tool else { return nil }
        return function
    }
    let strict = functions.contains { $0.strict == true }
    if strict, supportsStrict == false {
        throw UnsupportedFunctionalityError(functionality: "DeepSeek strict tool calls", message: "DeepSeek strict tool calls require a beta base URL ending in `/beta`.")
    }
    if strict, supportsStrict == true, functions.contains(where: { $0.strict != true }) {
        throw UnsupportedFunctionalityError(functionality: "mixed DeepSeek strict and non-strict tool calls", message: "DeepSeek strict mode requires every function tool in the request to set `strict: true`.")
    }
    var warnings: [SharedV4Warning] = []
    var result: [JSONValue] = []
    for tool in tools {
        switch tool {
        case .provider(let value): warnings.append(.unsupported(feature: "provider-defined tool \(value.id)", details: nil))
        case .function(let value):
            var function: [String: JSONValue] = ["name": .string(value.name), "parameters": value.inputSchema]
            if let description = value.description { function["description"] = .string(description) }
            if let strict = value.strict { function["strict"] = .bool(strict) }
            result.append(["type": "function", "function": .object(function)])
        }
    }
    let toolChoice: JSONValue?
    switch choice {
    case .some(.auto): toolChoice = "auto"
    case .some(.none): toolChoice = "none"
    case .some(.required): toolChoice = "required"
    case .some(.tool(let name)): toolChoice = ["type": "function", "function": ["name": .string(name)]]
    case nil: toolChoice = nil
    }
    return (result, toolChoice, warnings)
}
