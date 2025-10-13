import Foundation

/**
 The configuration of a tool that is defined by the provider.

 TypeScript equivalent:
 ```typescript
 export type LanguageModelV3ProviderDefinedTool = {
   type: 'provider-defined';
   id: `${string}.${string}`;
   name: string;
   args: Record<string, unknown>;
 };
 ```
 */
public struct LanguageModelV3ProviderDefinedTool: Sendable, Equatable, Codable {
    /// The type of the tool (always 'provider-defined').
    public let type: String = "provider-defined"

    /// The ID of the tool. Should follow the format `<provider-name>.<unique-tool-name>`.
    public let id: String

    /// The name of the tool that the user must use in the tool set.
    public let name: String

    /// The arguments for configuring the tool. Must match the expected arguments
    /// defined by the provider for this tool.
    public let args: [String: JSONValue]

    public init(
        id: String,
        name: String,
        args: [String: JSONValue]
    ) {
        self.id = id
        self.name = name
        self.args = args
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case id
        case name
        case args
    }

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
