import Foundation

public struct LanguageModelV4ToolCall: Sendable, Equatable, Codable {
    public let type: String = "tool-call"
    public let toolCallId: String
    public let toolName: String
    public let input: String
    public let providerExecuted: Bool?
    public let dynamic: Bool?
    public let providerMetadata: SharedV4ProviderMetadata?

    public init(
        toolCallId: String,
        toolName: String,
        input: String,
        providerExecuted: Bool? = nil,
        dynamic: Bool? = nil,
        providerMetadata: SharedV4ProviderMetadata? = nil
    ) {
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.input = input
        self.providerExecuted = providerExecuted
        self.dynamic = dynamic
        self.providerMetadata = providerMetadata
    }

    private enum CodingKeys: String, CodingKey {
        case type, toolCallId, toolName, input, providerExecuted, dynamic, providerMetadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        toolCallId = try container.decode(String.self, forKey: .toolCallId)
        toolName = try container.decode(String.self, forKey: .toolName)
        input = try container.decode(String.self, forKey: .input)
        providerExecuted = try container.decodeIfPresent(Bool.self, forKey: .providerExecuted)
        dynamic = try container.decodeIfPresent(Bool.self, forKey: .dynamic)
        providerMetadata = try container.decodeIfPresent(SharedV4ProviderMetadata.self, forKey: .providerMetadata)
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

public struct LanguageModelV4ToolResult: Sendable, Equatable, Codable {
    public let type: String = "tool-result"
    public let toolCallId: String
    public let toolName: String
    public let result: JSONValue
    public let isError: Bool?
    public let preliminary: Bool?
    public let dynamic: Bool?
    public let providerMetadata: SharedV4ProviderMetadata?

    public init(
        toolCallId: String,
        toolName: String,
        result: JSONValue,
        isError: Bool? = nil,
        preliminary: Bool? = nil,
        dynamic: Bool? = nil,
        providerMetadata: SharedV4ProviderMetadata? = nil
    ) {
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.result = result
        self.isError = isError
        self.preliminary = preliminary
        self.dynamic = dynamic
        self.providerMetadata = providerMetadata
    }

    private enum CodingKeys: String, CodingKey {
        case type, toolCallId, toolName, result, isError, preliminary, dynamic, providerMetadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        toolCallId = try container.decode(String.self, forKey: .toolCallId)
        toolName = try container.decode(String.self, forKey: .toolName)
        result = try container.decode(JSONValue.self, forKey: .result)
        isError = try container.decodeIfPresent(Bool.self, forKey: .isError)
        preliminary = try container.decodeIfPresent(Bool.self, forKey: .preliminary)
        dynamic = try container.decodeIfPresent(Bool.self, forKey: .dynamic)
        providerMetadata = try container.decodeIfPresent(SharedV4ProviderMetadata.self, forKey: .providerMetadata)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(toolCallId, forKey: .toolCallId)
        try container.encode(toolName, forKey: .toolName)
        try container.encode(result, forKey: .result)
        try container.encodeIfPresent(isError, forKey: .isError)
        try container.encodeIfPresent(preliminary, forKey: .preliminary)
        try container.encodeIfPresent(dynamic, forKey: .dynamic)
        try container.encodeIfPresent(providerMetadata, forKey: .providerMetadata)
    }
}

public struct LanguageModelV4ToolApprovalRequest: Sendable, Equatable, Codable {
    public let type: String = "tool-approval-request"
    public let approvalId: String
    public let toolCallId: String
    public let providerMetadata: SharedV4ProviderMetadata?

    public init(
        approvalId: String,
        toolCallId: String,
        providerMetadata: SharedV4ProviderMetadata? = nil
    ) {
        self.approvalId = approvalId
        self.toolCallId = toolCallId
        self.providerMetadata = providerMetadata
    }

    private enum CodingKeys: String, CodingKey { case type, approvalId, toolCallId, providerMetadata }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        approvalId = try container.decode(String.self, forKey: .approvalId)
        toolCallId = try container.decode(String.self, forKey: .toolCallId)
        providerMetadata = try container.decodeIfPresent(SharedV4ProviderMetadata.self, forKey: .providerMetadata)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(approvalId, forKey: .approvalId)
        try container.encode(toolCallId, forKey: .toolCallId)
        try container.encodeIfPresent(providerMetadata, forKey: .providerMetadata)
    }
}
