import Foundation

/**
 A prompt is a list of messages.

 Note: Not all models and prompt formats support multi-modal inputs and
 tool calls. The validation happens at runtime.

 Note: This is not a user-facing prompt. The AI SDK methods will map the
 user-facing prompt types such as chat or instruction prompts to this format.

 TypeScript equivalent:
 ```typescript
 export type LanguageModelV3Prompt = Array<LanguageModelV3Message>;
 ```
 */
public typealias LanguageModelV3Prompt = [LanguageModelV3Message]

/**
 A message in the prompt with role-based content.

 TypeScript equivalent (discriminated union):
 ```typescript
 export type LanguageModelV3Message =
   | { role: 'system'; content: string; providerOptions?: SharedV3ProviderOptions }
   | { role: 'user'; content: Array<...>; providerOptions?: SharedV3ProviderOptions }
   | { role: 'assistant'; content: Array<...>; providerOptions?: SharedV3ProviderOptions }
   | { role: 'tool'; content: Array<...>; providerOptions?: SharedV3ProviderOptions };
 ```
 */
public enum LanguageModelV3Message: Sendable, Equatable, Codable {
    case system(content: String, providerOptions: SharedV3ProviderOptions?)
    case user(content: [LanguageModelV3UserMessagePart], providerOptions: SharedV3ProviderOptions?)
    case assistant(content: [LanguageModelV3MessagePart], providerOptions: SharedV3ProviderOptions?)
    case tool(content: [LanguageModelV3ToolResultPart], providerOptions: SharedV3ProviderOptions?)

    private enum CodingKeys: String, CodingKey {
        case role
        case content
        case providerOptions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let role = try container.decode(String.self, forKey: .role)
        let providerOptions = try container.decodeIfPresent(SharedV3ProviderOptions.self, forKey: .providerOptions)

        switch role {
        case "system":
            let content = try container.decode(String.self, forKey: .content)
            self = .system(content: content, providerOptions: providerOptions)
        case "user":
            let content = try container.decode([LanguageModelV3UserMessagePart].self, forKey: .content)
            self = .user(content: content, providerOptions: providerOptions)
        case "assistant":
            let content = try container.decode([LanguageModelV3MessagePart].self, forKey: .content)
            self = .assistant(content: content, providerOptions: providerOptions)
        case "tool":
            let content = try container.decode([LanguageModelV3ToolResultPart].self, forKey: .content)
            self = .tool(content: content, providerOptions: providerOptions)
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

/**
 Assistant message part (for assistant role content).
 Discriminated union of text/file/reasoning/tool-call/tool-result parts.
 */
public enum LanguageModelV3MessagePart: Sendable, Equatable, Codable {
    case text(LanguageModelV3TextPart)
    case file(LanguageModelV3FilePart)
    case reasoning(LanguageModelV3ReasoningPart)
    case toolCall(LanguageModelV3ToolCallPart)
    case toolResult(LanguageModelV3ToolResultPart)

    private enum TypeKey: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            self = .text(try LanguageModelV3TextPart(from: decoder))
        case "file":
            self = .file(try LanguageModelV3FilePart(from: decoder))
        case "reasoning":
            self = .reasoning(try LanguageModelV3ReasoningPart(from: decoder))
        case "tool-call":
            self = .toolCall(try LanguageModelV3ToolCallPart(from: decoder))
        case "tool-result":
            self = .toolResult(try LanguageModelV3ToolResultPart(from: decoder))
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
        case .reasoning(let part):
            try part.encode(to: encoder)
        case .toolCall(let part):
            try part.encode(to: encoder)
        case .toolResult(let part):
            try part.encode(to: encoder)
        }
    }
}

/**
 User message part restricted to text/file to mirror TypeScript union.
 */
public enum LanguageModelV3UserMessagePart: Sendable, Equatable, Codable {
    case text(LanguageModelV3TextPart)
    case file(LanguageModelV3FilePart)

    private enum TypeKey: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            self = .text(try LanguageModelV3TextPart(from: decoder))
        case "file":
            self = .file(try LanguageModelV3FilePart(from: decoder))
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

// MARK: - Message Parts (prompt input)

/// Text content part of a prompt. It contains a string of text.
public struct LanguageModelV3TextPart: Sendable, Equatable, Codable {
    public let type: String = "text"
    public let text: String
    public let providerOptions: SharedV3ProviderOptions?

    public init(text: String, providerOptions: SharedV3ProviderOptions? = nil) {
        self.text = text
        self.providerOptions = providerOptions
    }

    private enum CodingKeys: String, CodingKey {
        case type, text, providerOptions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        providerOptions = try container.decodeIfPresent(SharedV3ProviderOptions.self, forKey: .providerOptions)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(providerOptions, forKey: .providerOptions)
    }
}

/// Reasoning content part of a prompt. It contains a string of reasoning text.
public struct LanguageModelV3ReasoningPart: Sendable, Equatable, Codable {
    public let type: String = "reasoning"
    public let text: String
    public let providerOptions: SharedV3ProviderOptions?

    public init(text: String, providerOptions: SharedV3ProviderOptions? = nil) {
        self.text = text
        self.providerOptions = providerOptions
    }

    private enum CodingKeys: String, CodingKey {
        case type, text, providerOptions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        providerOptions = try container.decodeIfPresent(SharedV3ProviderOptions.self, forKey: .providerOptions)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(providerOptions, forKey: .providerOptions)
    }
}

/// File content part of a prompt. It contains a file.
public struct LanguageModelV3FilePart: Sendable, Equatable, Codable {
    public let type: String = "file"
    public let filename: String?
    public let data: LanguageModelV3DataContent
    public let mediaType: String
    public let providerOptions: SharedV3ProviderOptions?

    public init(
        data: LanguageModelV3DataContent,
        mediaType: String,
        filename: String? = nil,
        providerOptions: SharedV3ProviderOptions? = nil
    ) {
        self.data = data
        self.mediaType = mediaType
        self.filename = filename
        self.providerOptions = providerOptions
    }

    private enum CodingKeys: String, CodingKey {
        case type, filename, data, mediaType, providerOptions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        filename = try container.decodeIfPresent(String.self, forKey: .filename)
        data = try container.decode(LanguageModelV3DataContent.self, forKey: .data)
        mediaType = try container.decode(String.self, forKey: .mediaType)
        providerOptions = try container.decodeIfPresent(SharedV3ProviderOptions.self, forKey: .providerOptions)
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

/// Tool call content part of a prompt (usually generated by the AI model).
public struct LanguageModelV3ToolCallPart: Sendable, Equatable, Codable {
    public let type: String = "tool-call"
    public let toolCallId: String
    public let toolName: String
    public let input: JSONValue
    public let providerExecuted: Bool?
    public let providerOptions: SharedV3ProviderOptions?

    public init(
        toolCallId: String,
        toolName: String,
        input: JSONValue,
        providerExecuted: Bool? = nil,
        providerOptions: SharedV3ProviderOptions? = nil
    ) {
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.input = input
        self.providerExecuted = providerExecuted
        self.providerOptions = providerOptions
    }

    private enum CodingKeys: String, CodingKey {
        case type, toolCallId, toolName, input, providerExecuted, providerOptions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        toolCallId = try container.decode(String.self, forKey: .toolCallId)
        toolName = try container.decode(String.self, forKey: .toolName)
        input = try container.decode(JSONValue.self, forKey: .input)
        providerExecuted = try container.decodeIfPresent(Bool.self, forKey: .providerExecuted)
        providerOptions = try container.decodeIfPresent(SharedV3ProviderOptions.self, forKey: .providerOptions)
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

/// Tool result content part of a prompt. Contains the result of a tool call.
public struct LanguageModelV3ToolResultPart: Sendable, Equatable, Codable {
    public let type: String = "tool-result"
    public let toolCallId: String
    public let toolName: String
    public let output: LanguageModelV3ToolResultOutput
    public let providerOptions: SharedV3ProviderOptions?

    public init(
        toolCallId: String,
        toolName: String,
        output: LanguageModelV3ToolResultOutput,
        providerOptions: SharedV3ProviderOptions? = nil
    ) {
        self.toolCallId = toolCallId
        self.toolName = toolName
        self.output = output
        self.providerOptions = providerOptions
    }

    private enum CodingKeys: String, CodingKey {
        case type, toolCallId, toolName, output, providerOptions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        toolCallId = try container.decode(String.self, forKey: .toolCallId)
        toolName = try container.decode(String.self, forKey: .toolName)
        output = try container.decode(LanguageModelV3ToolResultOutput.self, forKey: .output)
        providerOptions = try container.decodeIfPresent(SharedV3ProviderOptions.self, forKey: .providerOptions)
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

/// Tool result output (discriminated union)
public enum LanguageModelV3ToolResultOutput: Sendable, Equatable, Codable {
    case text(value: String)
    case json(value: JSONValue)
    case executionDenied(reason: String?)
    case errorText(value: String)
    case errorJson(value: JSONValue)
    case content(value: [LanguageModelV3ToolResultContentPart])

    private enum CodingKeys: String, CodingKey {
        case type
        case value
        case reason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            let value = try container.decode(String.self, forKey: .value)
            self = .text(value: value)
        case "json":
            let value = try container.decode(JSONValue.self, forKey: .value)
            self = .json(value: value)
        case "execution-denied":
            let reason = try container.decodeIfPresent(String.self, forKey: .reason)
            self = .executionDenied(reason: reason)
        case "error-text":
            let value = try container.decode(String.self, forKey: .value)
            self = .errorText(value: value)
        case "error-json":
            let value = try container.decode(JSONValue.self, forKey: .value)
            self = .errorJson(value: value)
        case "content":
            let value = try container.decode([LanguageModelV3ToolResultContentPart].self, forKey: .value)
            self = .content(value: value)
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
        case .text(let value):
            try container.encode("text", forKey: .type)
            try container.encode(value, forKey: .value)
        case .json(let value):
            try container.encode("json", forKey: .type)
            try container.encode(value, forKey: .value)
        case .executionDenied(let reason):
            try container.encode("execution-denied", forKey: .type)
            try container.encodeIfPresent(reason, forKey: .reason)
        case .errorText(let value):
            try container.encode("error-text", forKey: .type)
            try container.encode(value, forKey: .value)
        case .errorJson(let value):
            try container.encode("error-json", forKey: .type)
            try container.encode(value, forKey: .value)
        case .content(let value):
            try container.encode("content", forKey: .type)
            try container.encode(value, forKey: .value)
        }
    }
}

/// Tool result content part (text or media)
public enum LanguageModelV3ToolResultContentPart: Sendable, Equatable, Codable {
    case text(text: String)
    case media(data: String, mediaType: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case data
        case mediaType
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "text":
            let text = try container.decode(String.self, forKey: .text)
            self = .text(text: text)
        case "media":
            let data = try container.decode(String.self, forKey: .data)
            let mediaType = try container.decode(String.self, forKey: .mediaType)
            self = .media(data: data, mediaType: mediaType)
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
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .media(let data, let mediaType):
            try container.encode("media", forKey: .type)
            try container.encode(data, forKey: .data)
            try container.encode(mediaType, forKey: .mediaType)
        }
    }
}
