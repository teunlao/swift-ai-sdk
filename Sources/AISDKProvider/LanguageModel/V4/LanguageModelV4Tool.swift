import Foundation

public enum LanguageModelV4Tool: Sendable, Equatable, Codable {
    case function(LanguageModelV4FunctionTool)
    case provider(LanguageModelV4ProviderTool)

    private enum TypeKey: String, CodingKey { case type }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "function":
            self = .function(try LanguageModelV4FunctionTool(from: decoder))
        case "provider":
            self = .provider(try LanguageModelV4ProviderTool(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown tool type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .function(let tool):
            try tool.encode(to: encoder)
        case .provider(let tool):
            try tool.encode(to: encoder)
        }
    }
}

public struct LanguageModelV4ToolInputExample: Sendable, Equatable, Codable {
    public let input: JSONObject

    public init(input: JSONObject) {
        self.input = input
    }
}

public struct LanguageModelV4FunctionTool: Sendable, Equatable, Codable {
    public let type: String = "function"
    public let name: String
    public let description: String?
    public let inputSchema: JSONValue
    public let inputExamples: [LanguageModelV4ToolInputExample]?
    public let strict: Bool?
    public let providerOptions: SharedV4ProviderOptions?

    public init(
        name: String,
        inputSchema: JSONValue,
        inputExamples: [LanguageModelV4ToolInputExample]? = nil,
        description: String? = nil,
        strict: Bool? = nil,
        providerOptions: SharedV4ProviderOptions? = nil
    ) {
        self.name = name
        self.inputSchema = inputSchema
        self.inputExamples = inputExamples
        self.description = description
        self.strict = strict
        self.providerOptions = providerOptions
    }

    private enum CodingKeys: String, CodingKey {
        case type, name, description, inputSchema, inputExamples, strict, providerOptions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        inputSchema = try container.decode(JSONValue.self, forKey: .inputSchema)
        inputExamples = try container.decodeIfPresent([LanguageModelV4ToolInputExample].self, forKey: .inputExamples)
        strict = try container.decodeIfPresent(Bool.self, forKey: .strict)
        providerOptions = try container.decodeIfPresent(SharedV4ProviderOptions.self, forKey: .providerOptions)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(inputSchema, forKey: .inputSchema)
        try container.encodeIfPresent(inputExamples, forKey: .inputExamples)
        try container.encodeIfPresent(strict, forKey: .strict)
        try container.encodeIfPresent(providerOptions, forKey: .providerOptions)
    }
}

public struct LanguageModelV4ProviderTool: Sendable, Equatable, Codable {
    public let type: String = "provider"
    public let id: String
    public let name: String
    public let args: [String: JSONValue]

    public init(id: String, name: String, args: [String: JSONValue]) {
        self.id = id
        self.name = name
        self.args = args
    }

    private enum CodingKeys: String, CodingKey { case type, id, name, args }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        args = try container.decode([String: JSONValue].self, forKey: .args)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(args, forKey: .args)
    }
}

public enum LanguageModelV4ToolChoice: Sendable, Equatable, Codable {
    case auto
    case none
    case required
    case tool(toolName: String)

    private enum CodingKeys: String, CodingKey { case type, toolName }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "auto":
            self = .auto
        case "none":
            self = .none
        case "required":
            self = .required
        case "tool":
            self = .tool(toolName: try container.decode(String.self, forKey: .toolName))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown tool choice type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .auto:
            try container.encode("auto", forKey: .type)
        case .none:
            try container.encode("none", forKey: .type)
        case .required:
            try container.encode("required", forKey: .type)
        case .tool(let toolName):
            try container.encode("tool", forKey: .type)
            try container.encode(toolName, forKey: .toolName)
        }
    }
}
