import Foundation

public typealias LanguageModelV4Prompt = [LanguageModelV4Message]

public enum LanguageModelV4Message: Sendable, Equatable, Codable {
    case system(content: String, providerOptions: SharedV4ProviderOptions?)
    case user(content: [LanguageModelV4UserMessagePart], providerOptions: SharedV4ProviderOptions?)
    case assistant(content: [LanguageModelV4MessagePart], providerOptions: SharedV4ProviderOptions?)
    case tool(content: [LanguageModelV4ToolMessagePart], providerOptions: SharedV4ProviderOptions?)

    private enum CodingKeys: String, CodingKey { case role, content, providerOptions }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let role = try container.decode(String.self, forKey: .role)
        let providerOptions = try container.decodeIfPresent(SharedV4ProviderOptions.self, forKey: .providerOptions)

        switch role {
        case "system":
            self = .system(content: try container.decode(String.self, forKey: .content), providerOptions: providerOptions)
        case "user":
            self = .user(content: try container.decode([LanguageModelV4UserMessagePart].self, forKey: .content), providerOptions: providerOptions)
        case "assistant":
            self = .assistant(content: try container.decode([LanguageModelV4MessagePart].self, forKey: .content), providerOptions: providerOptions)
        case "tool":
            self = .tool(content: try container.decode([LanguageModelV4ToolMessagePart].self, forKey: .content), providerOptions: providerOptions)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .role,
                in: container,
                debugDescription: "Unknown role: \(role)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .system(content, providerOptions):
            try container.encode("system", forKey: .role)
            try container.encode(content, forKey: .content)
            try container.encodeIfPresent(providerOptions, forKey: .providerOptions)
        case let .user(content, providerOptions):
            try container.encode("user", forKey: .role)
            try container.encode(content, forKey: .content)
            try container.encodeIfPresent(providerOptions, forKey: .providerOptions)
        case let .assistant(content, providerOptions):
            try container.encode("assistant", forKey: .role)
            try container.encode(content, forKey: .content)
            try container.encodeIfPresent(providerOptions, forKey: .providerOptions)
        case let .tool(content, providerOptions):
            try container.encode("tool", forKey: .role)
            try container.encode(content, forKey: .content)
            try container.encodeIfPresent(providerOptions, forKey: .providerOptions)
        }
    }
}

public enum LanguageModelV4MessagePart: Sendable, Equatable, Codable {
    case text(LanguageModelV4TextPart)
    case file(LanguageModelV4FilePart)
    case custom(LanguageModelV4CustomPart)
    case reasoning(LanguageModelV4ReasoningPart)
    case reasoningFile(LanguageModelV4ReasoningFilePart)
    case toolCall(LanguageModelV4ToolCallPart)
    case toolResult(LanguageModelV4ToolResultPart)

    private enum TypeKey: String, CodingKey { case type }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            self = .text(try LanguageModelV4TextPart(from: decoder))
        case "file":
            self = .file(try LanguageModelV4FilePart(from: decoder))
        case "custom":
            self = .custom(try LanguageModelV4CustomPart(from: decoder))
        case "reasoning":
            self = .reasoning(try LanguageModelV4ReasoningPart(from: decoder))
        case "reasoning-file":
            self = .reasoningFile(try LanguageModelV4ReasoningFilePart(from: decoder))
        case "tool-call":
            self = .toolCall(try LanguageModelV4ToolCallPart(from: decoder))
        case "tool-result":
            self = .toolResult(try LanguageModelV4ToolResultPart(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown message part type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let part):
            try part.encode(to: encoder)
        case .file(let part):
            try part.encode(to: encoder)
        case .custom(let part):
            try part.encode(to: encoder)
        case .reasoning(let part):
            try part.encode(to: encoder)
        case .reasoningFile(let part):
            try part.encode(to: encoder)
        case .toolCall(let part):
            try part.encode(to: encoder)
        case .toolResult(let part):
            try part.encode(to: encoder)
        }
    }
}

public enum LanguageModelV4UserMessagePart: Sendable, Equatable, Codable {
    case text(LanguageModelV4TextPart)
    case file(LanguageModelV4FilePart)

    private enum TypeKey: String, CodingKey { case type }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            self = .text(try LanguageModelV4TextPart(from: decoder))
        case "file":
            self = .file(try LanguageModelV4FilePart(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "User messages support only text and file parts, received: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let part):
            try part.encode(to: encoder)
        case .file(let part):
            try part.encode(to: encoder)
        }
    }
}

public enum LanguageModelV4ToolMessagePart: Sendable, Equatable, Codable {
    case toolResult(LanguageModelV4ToolResultPart)
    case toolApprovalResponse(LanguageModelV4ToolApprovalResponsePart)

    private enum TypeKey: String, CodingKey { case type }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "tool-result":
            self = .toolResult(try LanguageModelV4ToolResultPart(from: decoder))
        case "tool-approval-response":
            self = .toolApprovalResponse(try LanguageModelV4ToolApprovalResponsePart(from: decoder))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown tool message part type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .toolResult(let part):
            try part.encode(to: encoder)
        case .toolApprovalResponse(let part):
            try part.encode(to: encoder)
        }
    }
}

public struct LanguageModelV4TextPart: Sendable, Equatable, Codable {
    public let type: String = "text"
    public let text: String
    public let providerOptions: SharedV4ProviderOptions?

    public init(text: String, providerOptions: SharedV4ProviderOptions? = nil) {
        self.text = text
        self.providerOptions = providerOptions
    }

    private enum CodingKeys: String, CodingKey { case type, text, providerOptions }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        providerOptions = try container.decodeIfPresent(SharedV4ProviderOptions.self, forKey: .providerOptions)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(providerOptions, forKey: .providerOptions)
    }
}

public struct LanguageModelV4ReasoningPart: Sendable, Equatable, Codable {
    public let type: String = "reasoning"
    public let text: String
    public let providerOptions: SharedV4ProviderOptions?

    public init(text: String, providerOptions: SharedV4ProviderOptions? = nil) {
        self.text = text
        self.providerOptions = providerOptions
    }

    private enum CodingKeys: String, CodingKey { case type, text, providerOptions }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        providerOptions = try container.decodeIfPresent(SharedV4ProviderOptions.self, forKey: .providerOptions)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(providerOptions, forKey: .providerOptions)
    }
}

public struct LanguageModelV4ReasoningFilePart: Sendable, Equatable, Codable {
    public let type: String = "reasoning-file"
    public let data: LanguageModelV4FileData
    public let mediaType: String
    public let providerOptions: SharedV4ProviderOptions?

    public init(
        data: LanguageModelV4FileData,
        mediaType: String,
        providerOptions: SharedV4ProviderOptions? = nil
    ) {
        self.data = data
        self.mediaType = mediaType
        self.providerOptions = providerOptions
    }

    private enum CodingKeys: String, CodingKey { case type, data, mediaType, providerOptions }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try container.decode(LanguageModelV4FileData.self, forKey: .data)
        mediaType = try container.decode(String.self, forKey: .mediaType)
        providerOptions = try container.decodeIfPresent(SharedV4ProviderOptions.self, forKey: .providerOptions)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(data, forKey: .data)
        try container.encode(mediaType, forKey: .mediaType)
        try container.encodeIfPresent(providerOptions, forKey: .providerOptions)
    }
}

public struct LanguageModelV4CustomPart: Sendable, Equatable, Codable {
    public let type: String = "custom"
    public let kind: String
    public let providerOptions: SharedV4ProviderOptions?

    public init(kind: String, providerOptions: SharedV4ProviderOptions? = nil) {
        self.kind = kind
        self.providerOptions = providerOptions
    }

    private enum CodingKeys: String, CodingKey { case type, kind, providerOptions }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(String.self, forKey: .kind)
        providerOptions = try container.decodeIfPresent(SharedV4ProviderOptions.self, forKey: .providerOptions)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(providerOptions, forKey: .providerOptions)
    }
}

public struct LanguageModelV4FilePart: Sendable, Equatable, Codable {
    public let type: String = "file"
    public let filename: String?
    public let data: SharedV4FileData
    public let mediaType: String
    public let providerOptions: SharedV4ProviderOptions?

    public init(
        data: SharedV4FileData,
        mediaType: String,
        filename: String? = nil,
        providerOptions: SharedV4ProviderOptions? = nil
    ) {
        self.data = data
        self.mediaType = mediaType
        self.filename = filename
        self.providerOptions = providerOptions
    }

    private enum CodingKeys: String, CodingKey { case type, filename, data, mediaType, providerOptions }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        filename = try container.decodeIfPresent(String.self, forKey: .filename)
        data = try container.decode(SharedV4FileData.self, forKey: .data)
        mediaType = try container.decode(String.self, forKey: .mediaType)
        providerOptions = try container.decodeIfPresent(SharedV4ProviderOptions.self, forKey: .providerOptions)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(filename, forKey: .filename)
        try container.encode(data, forKey: .data)
        try container.encode(mediaType, forKey: .mediaType)
        try container.encodeIfPresent(providerOptions, forKey: .providerOptions)
    }
}

public struct LanguageModelV4ToolCallPart: Sendable, Equatable, Codable {
    public let type: String = "tool-call"
    public let toolCallId: String
    public let toolName: String
    public let input: JSONValue
    public let providerExecuted: Bool?
    public let providerOptions: SharedV4ProviderOptions?

    public init(
        toolCallId: String,
        toolName: String,
        input: JSONValue,
        providerExecuted: Bool? = nil,
        providerOptions: SharedV4ProviderOptions? = nil
    ) {
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.input = input
        self.providerExecuted = providerExecuted
        self.providerOptions = providerOptions
    }

    private enum CodingKeys: String, CodingKey { case type, toolCallId, toolName, input, providerExecuted, providerOptions }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        toolCallId = try container.decode(String.self, forKey: .toolCallId)
        toolName = try container.decode(String.self, forKey: .toolName)
        input = try container.decode(JSONValue.self, forKey: .input)
        providerExecuted = try container.decodeIfPresent(Bool.self, forKey: .providerExecuted)
        providerOptions = try container.decodeIfPresent(SharedV4ProviderOptions.self, forKey: .providerOptions)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(toolCallId, forKey: .toolCallId)
        try container.encode(toolName, forKey: .toolName)
        try container.encode(input, forKey: .input)
        try container.encodeIfPresent(providerExecuted, forKey: .providerExecuted)
        try container.encodeIfPresent(providerOptions, forKey: .providerOptions)
    }
}

public struct LanguageModelV4ToolResultPart: Sendable, Equatable, Codable {
    public let type: String = "tool-result"
    public let toolCallId: String
    public let toolName: String
    public let output: LanguageModelV4ToolResultOutput
    public let providerOptions: SharedV4ProviderOptions?

    public init(
        toolCallId: String,
        toolName: String,
        output: LanguageModelV4ToolResultOutput,
        providerOptions: SharedV4ProviderOptions? = nil
    ) {
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.output = output
        self.providerOptions = providerOptions
    }

    private enum CodingKeys: String, CodingKey { case type, toolCallId, toolName, output, providerOptions }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        toolCallId = try container.decode(String.self, forKey: .toolCallId)
        toolName = try container.decode(String.self, forKey: .toolName)
        output = try container.decode(LanguageModelV4ToolResultOutput.self, forKey: .output)
        providerOptions = try container.decodeIfPresent(SharedV4ProviderOptions.self, forKey: .providerOptions)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(toolCallId, forKey: .toolCallId)
        try container.encode(toolName, forKey: .toolName)
        try container.encode(output, forKey: .output)
        try container.encodeIfPresent(providerOptions, forKey: .providerOptions)
    }
}

public struct LanguageModelV4ToolApprovalResponsePart: Sendable, Equatable, Codable {
    public let type: String = "tool-approval-response"
    public let approvalId: String
    public let approved: Bool
    public let reason: String?
    public let providerOptions: SharedV4ProviderOptions?

    public init(
        approvalId: String,
        approved: Bool,
        reason: String? = nil,
        providerOptions: SharedV4ProviderOptions? = nil
    ) {
        self.approvalId = approvalId
        self.approved = approved
        self.reason = reason
        self.providerOptions = providerOptions
    }

    private enum CodingKeys: String, CodingKey { case type, approvalId, approved, reason, providerOptions }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        approvalId = try container.decode(String.self, forKey: .approvalId)
        approved = try container.decode(Bool.self, forKey: .approved)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        providerOptions = try container.decodeIfPresent(SharedV4ProviderOptions.self, forKey: .providerOptions)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(approvalId, forKey: .approvalId)
        try container.encode(approved, forKey: .approved)
        try container.encodeIfPresent(reason, forKey: .reason)
        try container.encodeIfPresent(providerOptions, forKey: .providerOptions)
    }
}

public enum LanguageModelV4ToolResultOutput: Sendable, Equatable, Codable {
    case text(value: String, providerOptions: SharedV4ProviderOptions? = nil)
    case json(value: JSONValue, providerOptions: SharedV4ProviderOptions? = nil)
    case executionDenied(reason: String?, providerOptions: SharedV4ProviderOptions? = nil)
    case errorText(value: String, providerOptions: SharedV4ProviderOptions? = nil)
    case errorJson(value: JSONValue, providerOptions: SharedV4ProviderOptions? = nil)
    case content(value: [LanguageModelV4ToolResultContentPart])

    private enum CodingKeys: String, CodingKey { case type, value, reason, providerOptions }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let providerOptions = try container.decodeIfPresent(SharedV4ProviderOptions.self, forKey: .providerOptions)

        switch type {
        case "text":
            self = .text(value: try container.decode(String.self, forKey: .value), providerOptions: providerOptions)
        case "json":
            self = .json(value: try container.decode(JSONValue.self, forKey: .value), providerOptions: providerOptions)
        case "execution-denied":
            self = .executionDenied(reason: try container.decodeIfPresent(String.self, forKey: .reason), providerOptions: providerOptions)
        case "error-text":
            self = .errorText(value: try container.decode(String.self, forKey: .value), providerOptions: providerOptions)
        case "error-json":
            self = .errorJson(value: try container.decode(JSONValue.self, forKey: .value), providerOptions: providerOptions)
        case "content":
            self = .content(value: try container.decode([LanguageModelV4ToolResultContentPart].self, forKey: .value))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown tool result output type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .text(value, providerOptions):
            try container.encode("text", forKey: .type)
            try container.encode(value, forKey: .value)
            try container.encodeIfPresent(providerOptions, forKey: .providerOptions)
        case let .json(value, providerOptions):
            try container.encode("json", forKey: .type)
            try container.encode(value, forKey: .value)
            try container.encodeIfPresent(providerOptions, forKey: .providerOptions)
        case let .executionDenied(reason, providerOptions):
            try container.encode("execution-denied", forKey: .type)
            try container.encodeIfPresent(reason, forKey: .reason)
            try container.encodeIfPresent(providerOptions, forKey: .providerOptions)
        case let .errorText(value, providerOptions):
            try container.encode("error-text", forKey: .type)
            try container.encode(value, forKey: .value)
            try container.encodeIfPresent(providerOptions, forKey: .providerOptions)
        case let .errorJson(value, providerOptions):
            try container.encode("error-json", forKey: .type)
            try container.encode(value, forKey: .value)
            try container.encodeIfPresent(providerOptions, forKey: .providerOptions)
        case .content(let value):
            try container.encode("content", forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }
}

public enum LanguageModelV4ToolResultContentPart: Sendable, Equatable, Codable {
    case text(text: String, providerOptions: SharedV4ProviderOptions?)
    case file(data: SharedV4FileData, mediaType: String, filename: String?, providerOptions: SharedV4ProviderOptions?)
    case custom(providerOptions: SharedV4ProviderOptions?)

    private enum CodingKeys: String, CodingKey { case type, text, data, mediaType, filename, providerOptions }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let providerOptions = try container.decodeIfPresent(SharedV4ProviderOptions.self, forKey: .providerOptions)

        switch type {
        case "text":
            self = .text(text: try container.decode(String.self, forKey: .text), providerOptions: providerOptions)
        case "file":
            self = .file(
                data: try container.decode(SharedV4FileData.self, forKey: .data),
                mediaType: try container.decode(String.self, forKey: .mediaType),
                filename: try container.decodeIfPresent(String.self, forKey: .filename),
                providerOptions: providerOptions
            )
        case "custom":
            self = .custom(providerOptions: providerOptions)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown tool result content part type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .text(text, providerOptions):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
            try container.encodeIfPresent(providerOptions, forKey: .providerOptions)
        case let .file(data, mediaType, filename, providerOptions):
            try container.encode("file", forKey: .type)
            try container.encode(data, forKey: .data)
            try container.encode(mediaType, forKey: .mediaType)
            try container.encodeIfPresent(filename, forKey: .filename)
            try container.encodeIfPresent(providerOptions, forKey: .providerOptions)
        case .custom(let providerOptions):
            try container.encode("custom", forKey: .type)
            try container.encodeIfPresent(providerOptions, forKey: .providerOptions)
        }
    }
}
