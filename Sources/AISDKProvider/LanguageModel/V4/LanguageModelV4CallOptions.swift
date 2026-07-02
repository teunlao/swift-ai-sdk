import Foundation

/**
 Call options for language model V4.

 Port of `@ai-sdk/provider/src/language-model/v4/language-model-v4-call-options.ts`.
 */
public struct LanguageModelV4CallOptions: Sendable {
    public let prompt: LanguageModelV4Prompt
    public let maxOutputTokens: Int?
    public let temperature: Double?
    public let stopSequences: [String]?
    public let topP: Double?
    public let topK: Int?
    public let presencePenalty: Double?
    public let frequencyPenalty: Double?
    public let responseFormat: LanguageModelV4ResponseFormat?
    public let seed: Int?
    public let tools: [LanguageModelV4Tool]?
    public let toolChoice: LanguageModelV4ToolChoice?
    public let includeRawChunks: Bool?
    public let abortSignal: (@Sendable () -> Bool)?
    public let headers: SharedV4Headers?
    public let reasoning: LanguageModelV4ReasoningEffort?
    public let providerOptions: SharedV4ProviderOptions?

    public init(
        prompt: LanguageModelV4Prompt,
        maxOutputTokens: Int? = nil,
        temperature: Double? = nil,
        stopSequences: [String]? = nil,
        topP: Double? = nil,
        topK: Int? = nil,
        presencePenalty: Double? = nil,
        frequencyPenalty: Double? = nil,
        responseFormat: LanguageModelV4ResponseFormat? = nil,
        seed: Int? = nil,
        tools: [LanguageModelV4Tool]? = nil,
        toolChoice: LanguageModelV4ToolChoice? = nil,
        includeRawChunks: Bool? = nil,
        abortSignal: (@Sendable () -> Bool)? = nil,
        headers: SharedV4Headers? = nil,
        reasoning: LanguageModelV4ReasoningEffort? = nil,
        providerOptions: SharedV4ProviderOptions? = nil
    ) {
        self.prompt = prompt
        self.maxOutputTokens = maxOutputTokens
        self.temperature = temperature
        self.stopSequences = stopSequences
        self.topP = topP
        self.topK = topK
        self.presencePenalty = presencePenalty
        self.frequencyPenalty = frequencyPenalty
        self.responseFormat = responseFormat
        self.seed = seed
        self.tools = tools
        self.toolChoice = toolChoice
        self.includeRawChunks = includeRawChunks
        self.abortSignal = abortSignal
        self.headers = headers
        self.reasoning = reasoning
        self.providerOptions = providerOptions
    }
}

public enum LanguageModelV4ReasoningEffort: String, Sendable, Codable, Equatable {
    case providerDefault = "provider-default"
    case none
    case minimal
    case low
    case medium
    case high
    case xhigh
}

public enum LanguageModelV4ResponseFormat: Sendable, Equatable, Codable {
    case text
    case json(schema: JSONValue?, name: String?, description: String?)

    private enum CodingKeys: String, CodingKey {
        case type
        case schema
        case name
        case description
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            self = .text
        case "json":
            self = .json(
                schema: try container.decodeIfPresent(JSONValue.self, forKey: .schema),
                name: try container.decodeIfPresent(String.self, forKey: .name),
                description: try container.decodeIfPresent(String.self, forKey: .description)
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown response format type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .text:
            try container.encode("text", forKey: .type)
        case let .json(schema, name, description):
            try container.encode("json", forKey: .type)
            try container.encodeIfPresent(schema, forKey: .schema)
            try container.encodeIfPresent(name, forKey: .name)
            try container.encodeIfPresent(description, forKey: .description)
        }
    }
}
