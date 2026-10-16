import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct MoonshotAILanguageModelOptions: Codable, Sendable, Equatable {
    public enum ReasoningEffort: String, Codable, Sendable { case low, high, max }
    public enum ReasoningHistory: String, Codable, Sendable { case disabled, interleaved, preserved }
    public struct Thinking: Codable, Sendable, Equatable {
        public enum Mode: String, Codable, Sendable { case enabled, disabled }
        public var type: Mode?
        public var budgetTokens: Int?
        public init(type: Mode? = nil, budgetTokens: Int? = nil) { self.type = type; self.budgetTokens = budgetTokens }
    }
    public struct Prediction: Codable, Sendable, Equatable {
        public enum Content: Codable, Sendable, Equatable {
            case text(String), parts([TextPart])
            public init(from decoder: Decoder) throws {
                let c = try decoder.singleValueContainer()
                if let text = try? c.decode(String.self) { self = .text(text) } else { self = .parts(try c.decode([TextPart].self)) }
            }
            public func encode(to encoder: Encoder) throws {
                var c = encoder.singleValueContainer()
                switch self { case .text(let value): try c.encode(value); case .parts(let value): try c.encode(value) }
            }
        }
        public struct TextPart: Codable, Sendable, Equatable {
            public enum Kind: String, Codable, Sendable { case text }
            public var type: Kind = .text
            public var text: String
            public init(text: String) { self.text = text }
        }
        public enum Kind: String, Codable, Sendable { case content }
        public var type: Kind = .content
        public var content: Content
        public init(content: Content) { self.content = content }
    }
    public var strictJsonSchema: Bool?
    public var logprobs: Bool?
    public var topLogprobs: Int?
    public var reasoningEffort: ReasoningEffort?
    public var prediction: Prediction?
    public var thinking: Thinking?
    public var reasoningHistory: ReasoningHistory?
    public var promptCacheKey: String?
    public var safetyIdentifier: String?
    public init(strictJsonSchema: Bool? = nil, logprobs: Bool? = nil, topLogprobs: Int? = nil, reasoningEffort: ReasoningEffort? = nil, prediction: Prediction? = nil, thinking: Thinking? = nil, reasoningHistory: ReasoningHistory? = nil, promptCacheKey: String? = nil, safetyIdentifier: String? = nil) {
        self.strictJsonSchema = strictJsonSchema; self.logprobs = logprobs; self.topLogprobs = topLogprobs; self.reasoningEffort = reasoningEffort; self.prediction = prediction; self.thinking = thinking; self.reasoningHistory = reasoningHistory; self.promptCacheKey = promptCacheKey; self.safetyIdentifier = safetyIdentifier
    }
}

public struct MoonshotAIDynamicTool: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable { case function }
    public var type: Kind = .function
    public var name: String
    public var description: String?
    public var inputSchema: JSONObject
    public var strict: Bool?
    public init(name: String, description: String? = nil, inputSchema: JSONObject, strict: Bool? = nil) { self.name = name; self.description = description; self.inputSchema = inputSchema; self.strict = strict }
}

public struct MoonshotAIMessageProviderOptions: Codable, Sendable, Equatable {
    public var name: String?
    public init(name: String? = nil) { self.name = name }
}
public struct MoonshotAIAssistantMessageProviderOptions: Codable, Sendable, Equatable {
    public var name: String?
    public var partial: Bool?
    public init(name: String? = nil, partial: Bool? = nil) { self.name = name; self.partial = partial }
}
public struct MoonshotAISystemMessageProviderOptions: Codable, Sendable, Equatable {
    public var name: String?
    public var tools: [MoonshotAIDynamicTool]?
    public init(name: String? = nil, tools: [MoonshotAIDynamicTool]? = nil) { self.name = name; self.tools = tools }
}
struct MoonshotMessageOptions: Codable, Sendable {
    var name: String?
    var partial: Bool?
    var tools: [MoonshotAIDynamicTool]?
}

enum MoonshotModelFamily: String { case k25, k26, k27, k3, v1, unknown }
func moonshotModelFamily(_ id: String) -> MoonshotModelFamily {
    switch id {
    case "kimi-k2.5": .k25
    case "kimi-k2.6": .k26
    case "kimi-k2.7-code", "kimi-k2.7-code-highspeed": .k27
    case "kimi-k3": .k3
    default: id.hasPrefix("moonshot-v1-") ? .v1 : .unknown
    }
}

let moonshotLanguageOptionsSchema = FlexibleSchema(Schema<MoonshotAILanguageModelOptions>(jsonSchemaResolver: { .object(["type": .string("object")]) }, validator: { value in
    do {
        let json = try jsonValue(from: value)
        try rejectMoonshotNulls(json, keys: ["strictJsonSchema", "logprobs", "topLogprobs", "reasoningEffort", "prediction", "thinking", "reasoningHistory", "promptCacheKey", "safetyIdentifier"])
        if case .object(let object) = json, let thinking = object["thinking"] { try rejectMoonshotNulls(thinking, keys: ["type", "budgetTokens"]) }
        let parsed = try JSONDecoder().decode(MoonshotAILanguageModelOptions.self, from: JSONEncoder().encode(json))
        if let value = parsed.topLogprobs, !(0...20).contains(value) { throw InvalidArgumentError(argument: "topLogprobs", message: "Expected an integer between 0 and 20") }
        if let value = parsed.thinking?.budgetTokens, value < 1024 { throw InvalidArgumentError(argument: "budgetTokens", message: "Expected an integer of at least 1024") }
        return .success(value: parsed)
    } catch { return .failure(error: TypeValidationError.wrap(value: value, cause: error)) }
}))

let moonshotMessageOptionsSchema = FlexibleSchema(Schema<MoonshotMessageOptions>(jsonSchemaResolver: { .object(["type": .string("object")]) }, validator: { value in
    do {
        let json = try jsonValue(from: value)
        try rejectMoonshotNulls(json, keys: ["name", "partial", "tools"])
        let parsed = try JSONDecoder().decode(MoonshotMessageOptions.self, from: JSONEncoder().encode(json))
        if let partial = parsed.partial, !partial { throw InvalidArgumentError(argument: "partial", message: "Expected true") }
        if case .object(let object) = json, case .array(let tools) = object["tools"] { for tool in tools { try rejectMoonshotNulls(tool, keys: ["description", "strict"]) } }
        return .success(value: parsed)
    } catch { return .failure(error: TypeValidationError.wrap(value: value, cause: error)) }
}))

private func rejectMoonshotNulls(_ json: JSONValue, keys: [String]) throws {
    guard case .object(let object) = json else { throw InvalidArgumentError(argument: "providerOptions", message: "Expected an object") }
    for key in keys where object[key] == .null { throw InvalidArgumentError(argument: key, message: "Expected a non-null option") }
}

func moonshotJSONString<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}
func moonshotJSONValue<T: Encodable>(_ value: T) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value)) }
