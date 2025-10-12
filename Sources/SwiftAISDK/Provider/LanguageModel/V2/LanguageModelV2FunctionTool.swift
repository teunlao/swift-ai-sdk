import Foundation

/**
 A tool has a name, a description, and a set of parameters.

 Note: this is **not** the user-facing tool definition. The AI SDK methods will
 map the user-facing tool definitions to this format.

 TypeScript equivalent:
 ```typescript
 export type LanguageModelV2FunctionTool = {
   type: 'function';
   name: string;
   description?: string;
   inputSchema: JSONSchema7;
   providerOptions?: SharedV2ProviderOptions;
 };
 ```
 */
public struct LanguageModelV2FunctionTool: Sendable, Equatable, Codable {
    /// The type of the tool (always 'function').
    public let type: String = "function"

    /// The name of the tool. Unique within this model call.
    public let name: String

    /// A description of the tool. The language model uses this to understand the
    /// tool's purpose and to provide better completion suggestions.
    public let description: String?

    /// The parameters that the tool expects. The language model uses this to
    /// understand the tool's input requirements and to provide matching suggestions.
    /// Represented as JSON Schema (JSONValue for now, can be more specific later).
    public let inputSchema: JSONValue

    /// The provider-specific options for the tool.
    public let providerOptions: SharedV2ProviderOptions?

    public init(
        name: String,
        inputSchema: JSONValue,
        description: String? = nil,
        providerOptions: SharedV2ProviderOptions? = nil
    ) {
        self.name = name
        self.inputSchema = inputSchema
        self.description = description
        self.providerOptions = providerOptions
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case name
        case description
        case inputSchema
        case providerOptions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        inputSchema = try container.decode(JSONValue.self, forKey: .inputSchema)
        providerOptions = try container.decodeIfPresent(SharedV2ProviderOptions.self, forKey: .providerOptions)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(inputSchema, forKey: .inputSchema)
        try container.encodeIfPresent(providerOptions, forKey: .providerOptions)
    }
}
