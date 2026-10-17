import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct PerplexityLanguageModelOptions: Codable, Sendable, Equatable {
    public struct Reasoning: Codable, Sendable, Equatable {
        public enum Effort: String, Codable, Sendable { case minimal, low, medium, high, xhigh }
        public var effort: Effort?
        public var additionalProperties: JSONObject
        public init(effort: Effort? = nil, additionalProperties: JSONObject = [:]) {
            self.effort = effort
            self.additionalProperties = additionalProperties
        }
        public init(from decoder: Decoder) throws {
            let value = try PerplexityObject(decoder)
            effort = try value.optional(Effort.self, "effort")
            additionalProperties = value.fields.filter { $0.key != "effort" }
        }
        var fields: JSONObject {
            var value = additionalProperties
            if let effort { value["effort"] = .string(effort.rawValue) }
            return value
        }
        public func encode(to encoder: Encoder) throws { try fields.encode(to: encoder) }
    }

    public struct NativeTool: Codable, Sendable, Equatable {
        public enum Kind: String, Codable, Sendable {
            case webSearch = "web_search", fetchURL = "fetch_url", peopleSearch = "people_search"
            case financeSearch = "finance_search", sandbox, mcp, connector
        }
        public let type: Kind
        public let configuration: JSONObject
        public init(type: Kind, configuration: JSONObject = [:]) {
            self.type = type
            self.configuration = configuration
        }
        public init(from decoder: Decoder) throws {
            let value = try PerplexityObject(decoder)
            type = try value.required(Kind.self, "type")
            configuration = value.fields.filter { $0.key != "type" }
            switch type {
            case .webSearch:
                _ = try value.optional(WebSearchFilters.self, "filters")
                if let count = try value.optional(Int.self, "max_results") { try perplexitySafeCount(count, minimum: 1, decoder: decoder) }
                _ = try value.optional(Double.self, "max_tokens")
                _ = try value.optional(Double.self, "max_tokens_per_page")
                _ = try value.optional(SearchContext.self, "search_context_size")
                _ = try value.optional(UserLocation.self, "user_location")
            case .fetchURL: _ = try value.optional(Double.self, "max_urls")
            case .mcp:
                _ = try value.required(String.self, "server_label")
                _ = try value.required(String.self, "server_url")
                _ = try value.optional([String].self, "allowed_tools")
                _ = try value.optional(String.self, "authorization")
                _ = try value.optional(Bool.self, "defer_loading")
                _ = try value.optional([String: String].self, "headers")
            case .connector:
                _ = try value.required(String.self, "id")
                _ = try value.required(String.self, "server_label")
                _ = try value.optional(String.self, "server_description")
                _ = try value.optional([String].self, "allowed_tools")
            case .peopleSearch, .financeSearch, .sandbox: break
            }
        }
        var fields: JSONObject {
            var value = configuration
            value["type"] = .string(type.rawValue)
            return value
        }
        public func encode(to encoder: Encoder) throws { try fields.encode(to: encoder) }
    }

    public struct Skill: Codable, Sendable, Equatable {
        public enum Kind: String, Codable, Sendable { case builtin, inline }
        public enum BuiltinName: String, Codable, Sendable {
            case office, docx = "office/docx", pdf = "office/pdf", pptx = "office/pptx", xlsx = "office/xlsx"
        }
        public let type: Kind
        public let configuration: JSONObject
        public init(type: Kind, configuration: JSONObject) { self.type = type; self.configuration = configuration }
        public init(from decoder: Decoder) throws {
            let value = try PerplexityObject(decoder)
            type = try value.required(Kind.self, "type")
            configuration = value.fields.filter { $0.key != "type" }
            switch type {
            case .builtin: _ = try value.required(BuiltinName.self, "name")
            case .inline:
                _ = try value.required(String.self, "name")
                _ = try value.required(String.self, "description")
                _ = try value.required(String.self, "instructions")
            }
        }
        var fields: JSONObject {
            var value = configuration
            value["type"] = .string(type.rawValue)
            return value
        }
        public func encode(to encoder: Encoder) throws { try fields.encode(to: encoder) }
    }

    public var instructions: String?
    public var tools: [NativeTool]?
    public var models: [String]?
    public var maxSteps: Int?
    public var maxToolCalls: Int?
    public var previousResponseId: String?
    public var store: Bool?
    public var languagePreference: String?
    public var reasoning: Reasoning?
    public var skills: [Skill]?
    public var additionalProperties: JSONObject

    public init(instructions: String? = nil, tools: [NativeTool]? = nil, models: [String]? = nil,
                maxSteps: Int? = nil, maxToolCalls: Int? = nil, previousResponseId: String? = nil,
                store: Bool? = nil, languagePreference: String? = nil, reasoning: Reasoning? = nil,
                skills: [Skill]? = nil, additionalProperties: JSONObject = [:]) {
        self.instructions = instructions
        self.tools = tools
        self.models = models
        self.maxSteps = maxSteps
        self.maxToolCalls = maxToolCalls
        self.previousResponseId = previousResponseId
        self.store = store
        self.languagePreference = languagePreference
        self.reasoning = reasoning
        self.skills = skills
        self.additionalProperties = additionalProperties
    }

    public init(from decoder: Decoder) throws {
        let value = try PerplexityObject(decoder)
        instructions = try value.optional(String.self, "instructions")
        tools = try value.optional([NativeTool].self, "tools")
        models = try value.optional([String].self, "models")
        maxSteps = try value.optional(Int.self, "max_steps")
        maxToolCalls = try value.optional(Int.self, "max_tool_calls")
        previousResponseId = try value.optional(String.self, "previous_response_id")
        store = try value.optional(Bool.self, "store")
        languagePreference = try value.optional(String.self, "language_preference")
        reasoning = try value.optional(Reasoning.self, "reasoning")
        skills = try value.optional([Skill].self, "skills")
        if let maxSteps { try perplexitySafeCount(maxSteps, minimum: 1, decoder: decoder) }
        if let maxToolCalls { try perplexitySafeCount(maxToolCalls, minimum: 0, decoder: decoder) }
        let known: Set<String> = ["instructions", "tools", "models", "max_steps", "max_tool_calls", "previous_response_id", "store", "language_preference", "reasoning", "skills"]
        additionalProperties = value.fields.filter { !known.contains($0.key) }
    }

    var fields: JSONObject {
        var value = additionalProperties
        if let instructions { value["instructions"] = .string(instructions) }
        if let tools { value["tools"] = .array(tools.map { .object($0.fields) }) }
        if let models { value["models"] = .array(models.map(JSONValue.string)) }
        if let maxSteps { value["max_steps"] = .number(Double(maxSteps)) }
        if let maxToolCalls { value["max_tool_calls"] = .number(Double(maxToolCalls)) }
        if let previousResponseId { value["previous_response_id"] = .string(previousResponseId) }
        if let store { value["store"] = .bool(store) }
        if let languagePreference { value["language_preference"] = .string(languagePreference) }
        if let reasoning { value["reasoning"] = .object(reasoning.fields) }
        if let skills { value["skills"] = .array(skills.map { .object($0.fields) }) }
        return value
    }
    public func encode(to encoder: Encoder) throws { try fields.encode(to: encoder) }
}

private enum SearchContext: String, Decodable { case low, medium, high }
private struct WebSearchFilters: Decodable {
    enum Recency: String, Decodable { case hour, day, week, month, year }
    init(from decoder: Decoder) throws {
        let value = try PerplexityObject(decoder)
        _ = try value.optional([String].self, "search_domain_filter")
        _ = try value.optional(Recency.self, "search_recency_filter")
        for key in ["search_after_date_filter", "search_before_date_filter", "last_updated_after_filter", "last_updated_before_filter"] {
            _ = try value.optional(String.self, key)
        }
    }
}
private struct UserLocation: Decodable {
    init(from decoder: Decoder) throws {
        let value = try PerplexityObject(decoder)
        _ = try value.optional(Double.self, "latitude")
        _ = try value.optional(Double.self, "longitude")
        for key in ["country", "city", "region"] { _ = try value.optional(String.self, key) }
    }
}
private func perplexitySafeCount(_ value: Int, minimum: Int, decoder: Decoder) throws {
    guard value >= minimum, value <= 9_007_199_254_740_991 else {
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Expected a safe integer of at least \(minimum)"))
    }
}

let perplexityLanguageModelOptions = FlexibleSchema(Schema<PerplexityLanguageModelOptions>.codable(PerplexityLanguageModelOptions.self, jsonSchema: ["type": "object"]))
