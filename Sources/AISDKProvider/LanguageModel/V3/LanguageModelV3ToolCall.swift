import Foundation

/**
 Tool calls that the model has generated.

 TypeScript equivalent:
 ```typescript
 export type LanguageModelV3ToolCall = {
   type: 'tool-call';
   toolCallId: string;
   toolName: string;
   input: string;
   providerExecuted?: boolean;
   dynamic?: boolean;
   providerMetadata?: SharedV3ProviderMetadata;
 };
 ```
 */
public struct LanguageModelV3ToolCall: Sendable, Equatable, Codable {
    public let type: String = "tool-call"

    /// The identifier of the tool call. It must be unique across all tool calls.
    public let toolCallId: String

    /// The name of the tool that should be called.
    public let toolName: String

    /// Stringified JSON object with the tool call arguments. Must match the
    /// parameters schema of the tool.
    public let input: String

    /// Whether the tool call will be executed by the provider.
    /// If this flag is not set or is false, the tool call will be executed by the client.
    public let providerExecuted: Bool?

    /// Whether the tool is dynamic, i.e. defined at runtime.
    /// For example, MCP (Model Context Protocol) tools that are executed by the provider.
    public let dynamic: Bool?

    /// Additional provider-specific metadata for the tool call.
    public let providerMetadata: SharedV3ProviderMetadata?

    public init(
        toolCallId: String,
        toolName: String,
        input: String,
        providerExecuted: Bool? = nil,
        dynamic: Bool? = nil,
        providerMetadata: SharedV3ProviderMetadata? = nil
    ) {
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.input = input
        self.providerExecuted = providerExecuted
        self.dynamic = dynamic
        self.providerMetadata = providerMetadata
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case toolCallId
        case toolName
        case input
        case providerExecuted
        case dynamic
        case providerMetadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        toolCallId = try container.decode(String.self, forKey: .toolCallId)
        toolName = try container.decode(String.self, forKey: .toolName)
        input = try container.decode(String.self, forKey: .input)
        providerExecuted = try container.decodeIfPresent(Bool.self, forKey: .providerExecuted)
        dynamic = try container.decodeIfPresent(Bool.self, forKey: .dynamic)
        providerMetadata = try container.decodeIfPresent(SharedV3ProviderMetadata.self, forKey: .providerMetadata)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(toolCallId, forKey: .toolCallId)
        try container.encode(toolName, forKey: .toolName)
        try container.encode(input, forKey: .input)
        try container.encodeIfPresent(providerExecuted, forKey: .providerExecuted)
        try container.encodeIfPresent(dynamic, forKey: .dynamic)
        try container.encodeIfPresent(providerMetadata, forKey: .providerMetadata)
    }
}
