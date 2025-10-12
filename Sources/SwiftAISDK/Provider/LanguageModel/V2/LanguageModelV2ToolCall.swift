import Foundation

/**
 Tool calls that the model has generated.

 TypeScript equivalent:
 ```typescript
 export type LanguageModelV2ToolCall = {
   type: 'tool-call';
   toolCallId: string;
   toolName: string;
   input: string;
   providerExecuted?: boolean;
   providerMetadata?: SharedV2ProviderMetadata;
 };
 ```
 */
public struct LanguageModelV2ToolCall: Sendable, Equatable, Codable {
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

    /// Additional provider-specific metadata for the tool call.
    public let providerMetadata: SharedV2ProviderMetadata?

    public init(
        toolCallId: String,
        toolName: String,
        input: String,
        providerExecuted: Bool? = nil,
        providerMetadata: SharedV2ProviderMetadata? = nil
    ) {
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.input = input
        self.providerExecuted = providerExecuted
        self.providerMetadata = providerMetadata
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case toolCallId
        case toolName
        case input
        case providerExecuted
        case providerMetadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        toolCallId = try container.decode(String.self, forKey: .toolCallId)
        toolName = try container.decode(String.self, forKey: .toolName)
        input = try container.decode(String.self, forKey: .input)
        providerExecuted = try container.decodeIfPresent(Bool.self, forKey: .providerExecuted)
        providerMetadata = try container.decodeIfPresent(SharedV2ProviderMetadata.self, forKey: .providerMetadata)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(toolCallId, forKey: .toolCallId)
        try container.encode(toolName, forKey: .toolName)
        try container.encode(input, forKey: .input)
        try container.encodeIfPresent(providerExecuted, forKey: .providerExecuted)
        try container.encodeIfPresent(providerMetadata, forKey: .providerMetadata)
    }
}
