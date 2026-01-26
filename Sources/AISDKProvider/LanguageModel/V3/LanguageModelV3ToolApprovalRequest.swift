import Foundation

/**
 Tool approval request emitted by a provider for a provider-executed tool call.

 This is used for flows where the provider executes the tool (e.g. MCP tools)
 but requires an explicit user approval before continuing.
 */
public struct LanguageModelV3ToolApprovalRequest: Sendable, Equatable, Codable {
    public let type: String = "tool-approval-request"

    /// ID of the approval request. This ID is referenced by the subsequent
    /// tool-approval-response (tool message) to approve or deny execution.
    public let approvalId: String

    /// The tool call ID that this approval request is for.
    public let toolCallId: String

    /// Additional provider-specific metadata for the approval request.
    public let providerMetadata: SharedV3ProviderMetadata?

    public init(
        approvalId: String,
        toolCallId: String,
        providerMetadata: SharedV3ProviderMetadata? = nil
    ) {
        self.approvalId = approvalId
        self.toolCallId = toolCallId
        self.providerMetadata = providerMetadata
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case approvalId
        case toolCallId
        case providerMetadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        approvalId = try container.decode(String.self, forKey: .approvalId)
        toolCallId = try container.decode(String.self, forKey: .toolCallId)
        providerMetadata = try container.decodeIfPresent(SharedV3ProviderMetadata.self, forKey: .providerMetadata)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(approvalId, forKey: .approvalId)
        try container.encode(toolCallId, forKey: .toolCallId)
        try container.encodeIfPresent(providerMetadata, forKey: .providerMetadata)
    }
}

