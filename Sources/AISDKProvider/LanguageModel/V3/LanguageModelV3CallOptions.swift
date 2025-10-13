import Foundation

/**
 Call options for language model V3.

 TypeScript equivalent:
 ```typescript
 export type LanguageModelV3CallOptions = {
   prompt: LanguageModelV3Prompt;
   maxOutputTokens?: number;
   temperature?: number;
   stopSequences?: string[];
   topP?: number;
   topK?: number;
   presencePenalty?: number;
   frequencyPenalty?: number;
   responseFormat?: { type: 'text' } | { type: 'json'; schema?: JSONSchema7; name?: string; description?: string };
   seed?: number;
   tools?: Array<LanguageModelV3FunctionTool | LanguageModelV3ProviderDefinedTool>;
   toolChoice?: LanguageModelV3ToolChoice;
   includeRawChunks?: boolean;
   abortSignal?: AbortSignal;
   headers?: Record<string, string | undefined>;
   providerOptions?: SharedV3ProviderOptions;
 };
 ```
 */
public struct LanguageModelV3CallOptions: Sendable {
    /// A language model prompt is a standardized prompt type.
    /// Note: This is **not** the user-facing prompt.
    public let prompt: LanguageModelV3Prompt

    /// Maximum number of tokens to generate.
    public let maxOutputTokens: Int?

    /// Temperature setting. The range depends on the provider and model.
    public let temperature: Double?

    /// Stop sequences.
    /// If set, the model will stop generating text when one of the stop sequences is generated.
    public let stopSequences: [String]?

    /// Nucleus sampling.
    public let topP: Double?

    /// Only sample from the top K options for each subsequent token.
    public let topK: Int?

    /// Presence penalty setting.
    public let presencePenalty: Double?

    /// Frequency penalty setting.
    public let frequencyPenalty: Double?

    /// Response format. The output can either be text or JSON.
    public let responseFormat: LanguageModelV3ResponseFormat?

    /// The seed (integer) to use for random sampling.
    public let seed: Int?

    /// The tools that are available for the model.
    public let tools: [LanguageModelV3Tool]?

    /// Specifies how the tool should be selected. Defaults to 'auto'.
    public let toolChoice: LanguageModelV3ToolChoice?

    /// Include raw chunks in the stream. Only applicable for streaming calls.
    public let includeRawChunks: Bool?

    /// Abort signal for cancelling the operation (Task cancellation in Swift).
    public let abortSignal: (@Sendable () -> Bool)?

    /// Additional HTTP headers to be sent with the request.
    public let headers: [String: String]?

    /// Additional provider-specific options.
    public let providerOptions: SharedV3ProviderOptions?

    public init(
        prompt: LanguageModelV3Prompt,
        maxOutputTokens: Int? = nil,
        temperature: Double? = nil,
        stopSequences: [String]? = nil,
        topP: Double? = nil,
        topK: Int? = nil,
        presencePenalty: Double? = nil,
        frequencyPenalty: Double? = nil,
        responseFormat: LanguageModelV3ResponseFormat? = nil,
        seed: Int? = nil,
        tools: [LanguageModelV3Tool]? = nil,
        toolChoice: LanguageModelV3ToolChoice? = nil,
        includeRawChunks: Bool? = nil,
        abortSignal: (@Sendable () -> Bool)? = nil,
        headers: [String: String]? = nil,
        providerOptions: SharedV3ProviderOptions? = nil
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
        self.providerOptions = providerOptions
    }
}

/// Response format (text or JSON with optional schema)
public enum LanguageModelV3ResponseFormat: Sendable, Equatable, Codable {
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
            let schema = try container.decodeIfPresent(JSONValue.self, forKey: .schema)
            let name = try container.decodeIfPresent(String.self, forKey: .name)
            let description = try container.decodeIfPresent(String.self, forKey: .description)
            self = .json(schema: schema, name: name, description: description)
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
